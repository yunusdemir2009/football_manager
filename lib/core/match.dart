import 'dart:math';

import 'engine.dart';

/// Taktik, diziliş ve dakika dakika canlı maç motoru (UI'dan bağımsız).

class Rating {
  final double att, def;
  const Rating(this.att, this.def);
}

const double kBaseGoals = 1.34;
const double kHomeBoost = 1.12;
const double kAwayBoost = 0.90;
const double kSpread = 5.0;
const double kFatigue = 0.12; // 90. dakikada, kondisyonu 0 olan oyuncunun CA kaybi orani ust siniri
const int kMaxSubs = 5;
const int kBenchSize = 7;

/// Bir sutun golle sonuclanma olasiligi. Gol olasiligi (1 - exp(-lambda)) korunur,
/// sut sayisi buna gore turetilir: sut/dk = (1 - exp(-lambda)) / kConversion.
const double kConversion = 0.11;
const double kSaveGivenNoGoal = 0.27; // golle bitmeyen sutlarin kurtarilma orani
const double kYellowPerMinute = 0.022; // takim basi dakika basi sari kart olasiligi
const double kRedPerMinute = 0.0002; // direkt kirmizi
const double kInjuryPerMinute = 0.0006;
const double kManDownPenalty = 1.2; // eksik oyuncu basina hucum ve savunma kaybi (CA puani)

class Formation {
  final String name;
  final int d, m, f;
  final double attMod, defMod;
  const Formation(this.name, this.d, this.m, this.f, this.attMod, this.defMod);
}

const List<Formation> kFormations = [
  Formation('4-4-2', 4, 4, 2, 0.0, 0.0),
  Formation('4-3-3', 4, 3, 3, 1.0, -0.5),
  Formation('4-2-3-1', 4, 5, 1, 0.3, 0.3),
  Formation('3-5-2', 3, 5, 2, 0.5, -0.8),
  Formation('5-3-2', 5, 3, 2, -0.8, 1.0),
  Formation('4-5-1', 4, 5, 1, -0.5, 0.5),
];

Formation formationByName(String n) =>
    kFormations.firstWhere((f) => f.name == n, orElse: () => kFormations.first);

enum Mentality { defensive, balanced, attacking }

extension MentalityX on Mentality {
  String get label {
    switch (this) {
      case Mentality.defensive:
        return 'Defansif';
      case Mentality.balanced:
        return 'Dengeli';
      case Mentality.attacking:
        return 'Hücum';
    }
  }

  double get attMod => this == Mentality.attacking ? 1.5 : this == Mentality.defensive ? -1.5 : 0.0;
  double get defMod => this == Mentality.attacking ? -1.8 : this == Mentality.defensive ? 1.5 : 0.0;
  double get tiring => this == Mentality.attacking ? 1.3 : this == Mentality.defensive ? 0.8 : 1.0;
}

/// Savunma anlayisi: ne kadar yukarida baski yapilir.
enum Pressing { low, normal, high }

extension PressingX on Pressing {
  String get label {
    switch (this) {
      case Pressing.low:
        return 'Düşük blok';
      case Pressing.normal:
        return 'Normal';
      case Pressing.high:
        return 'Yüksek baskı';
    }
  }

  double get attMod => this == Pressing.high ? 0.6 : this == Pressing.low ? -0.5 : 0.0;
  double get defMod => this == Pressing.high ? -0.3 : this == Pressing.low ? 0.5 : 0.0;
  double get tiring => this == Pressing.high ? 1.25 : this == Pressing.low ? 0.85 : 1.0;
  double get fouls => this == Pressing.high ? 1.3 : this == Pressing.low ? 0.85 : 1.0;
}

// ---------------- Kadro secimi ----------------

int _byAvailabilityThenCa(Player a, Player b) {
  final c = (b.available ? 1 : 0).compareTo(a.available ? 1 : 0);
  return c != 0 ? c : b.ca.compareTo(a.ca);
}

List<Player> _top(List<Player> squad, String grp, int n) {
  final l = squad.where((p) => p.grp == grp).toList()..sort(_byAvailabilityThenCa);
  return l.take(n).toList();
}

/// Dizilise gore en iyi ilk 11 (1 GK + D + M + F). Musait oyuncular once secilir.
List<Player> autoXI(List<Player> squad, Formation f) =>
    [..._top(squad, 'GK', 1), ..._top(squad, 'DEF', f.d), ..._top(squad, 'MID', f.m), ..._top(squad, 'FWD', f.f)];

/// Yedekler: 1 kaleci + en iyi 6 diger (sakat/cezali olmayan) oyuncu.
List<Player> autoBench(List<Player> squad, List<Player> xi) {
  final ids = xi.map((p) => p.id).toSet();
  final rest = squad.where((p) => !ids.contains(p.id) && p.available).toList()
    ..sort((a, b) => b.ca.compareTo(a.ca));
  final bench = <Player>[];
  for (final p in rest) {
    if (p.grp == 'GK') {
      bench.add(p);
      break;
    }
  }
  for (final p in rest) {
    if (bench.length >= kBenchSize) break;
    if (!bench.contains(p)) bench.add(p);
  }
  return bench;
}

/// xi, dizilisin gerektirdigi sayilara uyuyor mu?
bool lineupValid(List<Player> xi, Formation f) {
  if (xi.length != 11) return false;
  int c(String g) => xi.where((p) => p.grp == g).length;
  return c('GK') == 1 && c('DEF') == f.d && c('MID') == f.m && c('FWD') == f.f;
}

// ---------------- Puanlama ----------------

Rating _rating(List<Player> xi, Formation f, Mentality m, Pressing pr, double Function(Player) eff) {
  double mean(String g, double dflt) {
    final l = xi.where((p) => p.grp == g).toList();
    if (l.isEmpty) return dflt;
    return l.fold<double>(0, (a, p) => a + eff(p)) / l.length;
  }

  final missing = max(0, 11 - xi.length);
  final penalty = missing * kManDownPenalty;
  final gk = mean('GK', 30);
  final d = mean('DEF', 30);
  final mid = mean('MID', 30);
  final fw = mean('FWD', mid - 5);
  return Rating(
    (2 * fw + mid) / 3 + f.attMod + m.attMod + pr.attMod - penalty,
    (2 * d + gk) / 3 + f.defMod + m.defMod + pr.defMod - penalty,
  );
}

/// Lig ortalamasina normalize etmek icin: 4-4-2, dengeli, normal baski, yorgunluksuz puan.
Rating baselineRating(List<Player> squad) {
  final f = kFormations.first;
  return _rating(autoXI(squad, f), f, Mentality.balanced, Pressing.normal, (p) => p.ca.toDouble());
}

// ---------------- Canli mac ----------------

class MatchSide {
  final int teamId;
  final String teamName;
  final bool isUser;
  Formation formation;
  Mentality mentality;
  Pressing pressing;
  List<Player> xi;
  List<Player> bench;
  int subsUsed = 0;

  // Mac istatistikleri
  int shots = 0;
  int onTarget = 0;
  int yellows = 0;
  int reds = 0;

  MatchSide({
    required this.teamId,
    required this.teamName,
    required this.isUser,
    required this.formation,
    required this.mentality,
    required this.xi,
    required this.bench,
    this.pressing = Pressing.normal,
  });
}

enum EventKind { goal, save, miss, yellow, red, injury, sub }

class MatchEvent {
  final int minute;
  final String text;
  final EventKind kind;
  final int teamId;

  /// false ise "tüm pozisyonlar" filtresi kapalıyken gizlenir.
  final bool important;
  MatchEvent(this.minute, this.text, this.kind, this.teamId, {this.important = true});
  bool get isGoal => kind == EventKind.goal;
}

class MatchSession {
  final Random rng;
  final MatchSide home, away;
  final double avgAtt, avgDef;

  /// true ise kullanici tarafi da otomatik degisiklik yapar (hizli simulasyon).
  bool autoAll;

  int minute = 0;
  int hg = 0, ag = 0;
  final List<MatchEvent> events = [];

  // Mactan sonra oyun durumuna islenecek olaylar (oyuncu id -> deger)
  final Map<int, int> injuries = {}; // sakatlik haftasi
  final Map<int, int> bans = {}; // ceza (mac sayisi)
  final Map<int, int> yellowsGiven = {}; // bu macta gorulen sari kart

  Rating? _rh, _ra;

  MatchSession({
    required this.rng,
    required this.home,
    required this.away,
    required this.avgAtt,
    required this.avgDef,
    this.autoAll = false,
  });

  bool get finished => minute >= 90;

  double _eff(Player p, MatchSide s) {
    final t = max(0, minute - 50) /
        40.0 *
        (1 - p.stamina / 22.0) *
        kFatigue *
        s.mentality.tiring *
        s.pressing.tiring;
    return p.ca * (1 - t);
  }

  Rating _rateSide(MatchSide s) => _rating(s.xi, s.formation, s.mentality, s.pressing, (p) => _eff(p, s));

  /// Taktik/oyuncu degisikliginden sonra puanlari yenile.
  void refresh() {
    _rh = null;
    _ra = null;
  }

  /// Topa sahip olma yuzdesi (ev sahibi), takim guclerinden turetilir.
  int get possessionHome {
    final rh = _rh, ra = _ra;
    if (rh == null || ra == null) return 50;
    final d = (rh.att + rh.def) - (ra.att + ra.def);
    return (50 + d * 1.5).round().clamp(35, 65).toInt();
  }

  void step() {
    if (finished) return;
    minute++;
    if (_rh == null || _ra == null || minute % 5 == 1) {
      _rh = _rateSide(home);
      _ra = _rateSide(away);
    }
    final lh = kBaseGoals * kHomeBoost * exp(((_rh!.att - avgAtt) - (_ra!.def - avgDef)) / kSpread) / 90;
    final la = kBaseGoals * kAwayBoost * exp(((_ra!.att - avgAtt) - (_rh!.def - avgDef)) / kSpread) / 90;
    _attack(home, away, lh);
    _attack(away, home, la);
    for (final s in [home, away]) {
      _discipline(s);
      _maybeInjury(s);
    }
    if (minute == 60 || minute == 75) {
      for (final s in [home, away]) {
        if (!s.isUser || autoAll) _autoSub(s);
      }
    }
  }

  void simulateToEnd() {
    while (!finished) {
      step();
    }
  }

  // ---- hucum: sut -> gol / kurtaris / auta ----
  Player? _pick(List<Player> list, double Function(Player) w) {
    if (list.isEmpty) return null;
    final total = list.fold<double>(0, (a, p) => a + w(p));
    var r = rng.nextDouble() * total;
    for (final p in list) {
      r -= w(p);
      if (r <= 0) return p;
    }
    return list.last;
  }

  void _attack(MatchSide atk, MatchSide def, double lambda) {
    final pShot = min(0.6, (1 - exp(-lambda)) / kConversion);
    if (rng.nextDouble() >= pShot) return;
    final shooter = _pick(
      atk.xi.where((p) => p.grp != 'GK').toList(),
      (p) => (p.finishing + 1) * (p.grp == 'FWD' ? 3.0 : p.grp == 'MID' ? 1.2 : 0.4),
    );
    if (shooter == null) return;
    atk.shots++;
    if (rng.nextDouble() < kConversion) {
      atk.onTarget++;
      if (identical(atk, home)) {
        hg++;
      } else {
        ag++;
      }
      events.add(MatchEvent(
        minute,
        "$minute'  ⚽ GOL! ${shooter.name} (${atk.teamName})   $hg-$ag",
        EventKind.goal,
        atk.teamId,
      ));
    } else if (rng.nextDouble() < kSaveGivenNoGoal) {
      atk.onTarget++;
      final gk = def.xi.where((p) => p.grp == 'GK').toList();
      final keeper = gk.isEmpty ? 'kaleci' : gk.first.name;
      final lines = [
        "🧤 $keeper, ${shooter.name}'in şutunu çıkardı!",
        "🧤 ${shooter.name} vurdu, $keeper kurtardı!",
        "🧤 Harika kurtarış: $keeper, ${shooter.name}'e geçit vermedi.",
      ];
      events.add(MatchEvent(minute, "$minute'  ${lines[rng.nextInt(lines.length)]}", EventKind.save, atk.teamId,
          important: rng.nextDouble() < 0.5));
    } else {
      final lines = [
        '${shooter.name} şutunu auta gönderdi.',
        "${shooter.name}'in şutu direğin yanından dışarı çıktı.",
        '${shooter.name} kaçırdı! Top üst direğe çarpıp oyun dışına çıktı.',
      ];
      events.add(MatchEvent(minute, "$minute'  ${lines[rng.nextInt(lines.length)]}", EventKind.miss, atk.teamId,
          important: false));
    }
  }

  // ---- disiplin ----
  void _discipline(MatchSide s) {
    final foul = s.pressing.fouls;
    if (rng.nextDouble() < kRedPerMinute * foul) {
      final p = _pick(s.xi, (q) => q.grp == 'GK' ? 0.15 : 1.0);
      if (p != null) _sendOff(s, p, 'direkt kırmızı kart gördü!', 2 + rng.nextInt(2));
      return;
    }
    if (rng.nextDouble() < kYellowPerMinute * foul) {
      final p = _pick(s.xi, (q) {
        final base = q.grp == 'DEF' ? 1.2 : q.grp == 'MID' ? 1.3 : q.grp == 'FWD' ? 0.7 : 0.15;
        return (yellowsGiven[q.id] ?? 0) >= 1 ? base * 0.35 : base; // sarı görenler temkinli oynar
      });
      if (p == null) return;
      final already = (yellowsGiven[p.id] ?? 0) >= 1;
      yellowsGiven[p.id] = (yellowsGiven[p.id] ?? 0) + 1;
      s.yellows++;
      if (already) {
        _sendOff(s, p, 'ikinci sarıdan kırmızı kart gördü!', 1);
      } else {
        events.add(MatchEvent(minute, "$minute'  🟨 ${p.name} (${s.teamName}) sarı kart gördü.", EventKind.yellow,
            s.teamId));
      }
    }
  }

  void _sendOff(MatchSide s, Player p, String what, int banMatches) {
    s.xi.removeWhere((x) => x.id == p.id);
    s.reds++;
    bans[p.id] = max(bans[p.id] ?? 0, banMatches);
    events.add(MatchEvent(minute, "$minute'  🟥 ${p.name} (${s.teamName}) $what ${s.teamName} 10 kişi kaldı.",
        EventKind.red, s.teamId));
    refresh();
  }

  // ---- sakatlik ----
  void _maybeInjury(MatchSide s) {
    if (rng.nextDouble() >= kInjuryPerMinute) return;
    final p = _pick(s.xi, (q) => 1.0);
    if (p == null) return;
    const weeks = [1, 1, 2, 2, 3, 4, 6, 8];
    injuries[p.id] = weeks[rng.nextInt(weeks.length)];
    events.add(MatchEvent(minute, "$minute'  🩹 ${p.name} (${s.teamName}) sakatlandı.", EventKind.injury, s.teamId));

    // Zorunlu degisiklik: ayni mevkiden yedek varsa ve hak kaldiysa
    Player? repl;
    if (s.subsUsed < kMaxSubs) {
      for (final b in s.bench) {
        if (b.grp == p.grp && (repl == null || b.ca > repl.ca)) repl = b;
      }
    }
    final i = s.xi.indexWhere((x) => x.id == p.id);
    if (repl != null && i >= 0) {
      s.xi[i] = repl;
      s.bench.removeWhere((x) => x.id == repl!.id);
      s.subsUsed++;
      events.add(MatchEvent(minute, "$minute'  🔄 ${s.teamName}: ${repl.name} oyuna girdi (sakatlık).",
          EventKind.sub, s.teamId));
    } else {
      s.xi.removeWhere((x) => x.id == p.id);
    }
    refresh();
  }

  // ---- degisiklikler ----
  void _autoSub(MatchSide s) {
    if (s.subsUsed >= 3) return;
    Player? worst;
    double worstEff = 1e9;
    for (final p in s.xi) {
      if (p.grp == 'GK') continue;
      final e = _eff(p, s);
      if (e < worstEff) {
        worstEff = e;
        worst = p;
      }
    }
    if (worst == null) return;
    Player? best;
    for (final b in s.bench) {
      if (b.grp == worst.grp && (best == null || b.ca > best.ca)) best = b;
    }
    if (best != null && best.ca > worstEff) substitute(s, worst, best);
  }

  /// Basariliysa null, degilse hata mesaji.
  String? substitute(MatchSide s, Player out, Player inn) {
    if (s.subsUsed >= kMaxSubs) return 'En fazla $kMaxSubs değişiklik yapılabilir';
    final oi = s.xi.indexWhere((p) => p.id == out.id);
    final bi = s.bench.indexWhere((p) => p.id == inn.id);
    if (oi < 0 || bi < 0) return 'Geçersiz oyuncu';
    if (out.grp != inn.grp) return 'Aynı mevkiden oyuncu seçin';
    s.xi[oi] = inn;
    s.bench[bi] = out;
    s.subsUsed++;
    events.add(MatchEvent(minute, "$minute'  🔄 ${s.teamName}: ${inn.name} ⇄ ${out.name}", EventKind.sub, s.teamId));
    refresh();
    return null;
  }

  void setMentality(MatchSide s, Mentality m) {
    s.mentality = m;
    refresh();
  }

  void setPressing(MatchSide s, Pressing p) {
    s.pressing = p;
    refresh();
  }
}
