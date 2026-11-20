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

// ---------------- Kadro secimi ----------------

List<Player> _top(List<Player> squad, String grp, int n) {
  final l = squad.where((p) => p.grp == grp).toList()..sort((a, b) => b.ca.compareTo(a.ca));
  return l.take(n).toList();
}

/// Dizilise gore en iyi ilk 11 (1 GK + D + M + F).
List<Player> autoXI(List<Player> squad, Formation f) =>
    [..._top(squad, 'GK', 1), ..._top(squad, 'DEF', f.d), ..._top(squad, 'MID', f.m), ..._top(squad, 'FWD', f.f)];

/// Yedekler: 1 kaleci + en iyi 6 diger oyuncu.
List<Player> autoBench(List<Player> squad, List<Player> xi) {
  final ids = xi.map((p) => p.id).toSet();
  final rest = squad.where((p) => !ids.contains(p.id)).toList()..sort((a, b) => b.ca.compareTo(a.ca));
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

Rating _rating(List<Player> xi, Formation f, Mentality m, double Function(Player) eff) {
  double mean(String g, double dflt) {
    final l = xi.where((p) => p.grp == g).toList();
    if (l.isEmpty) return dflt;
    return l.fold<double>(0, (a, p) => a + eff(p)) / l.length;
  }

  final gk = mean('GK', 30);
  final d = mean('DEF', 30);
  final mid = mean('MID', 30);
  final fw = mean('FWD', mid - 5);
  return Rating((2 * fw + mid) / 3 + f.attMod + m.attMod, (2 * d + gk) / 3 + f.defMod + m.defMod);
}

/// Lig ortalamasina normalize etmek icin: 4-4-2, dengeli, yorgunluksuz puan.
Rating baselineRating(List<Player> squad) {
  final f = kFormations.first;
  return _rating(autoXI(squad, f), f, Mentality.balanced, (p) => p.ca.toDouble());
}

// ---------------- Canli mac ----------------

class MatchSide {
  final int teamId;
  final String teamName;
  final bool isUser;
  Formation formation;
  Mentality mentality;
  List<Player> xi;
  List<Player> bench;
  int subsUsed = 0;
  MatchSide({
    required this.teamId,
    required this.teamName,
    required this.isUser,
    required this.formation,
    required this.mentality,
    required this.xi,
    required this.bench,
  });
}

class MatchEvent {
  final int minute;
  final String text;
  final bool isGoal;
  final int teamId;
  MatchEvent(this.minute, this.text, this.isGoal, this.teamId);
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
    final t = max(0, minute - 50) / 40.0 * (1 - p.stamina / 22.0) * kFatigue * s.mentality.tiring;
    return p.ca * (1 - t);
  }

  Rating _rateSide(MatchSide s) => _rating(s.xi, s.formation, s.mentality, (p) => _eff(p, s));

  /// Taktik/oyuncu degisikliginden sonra puanlari yenile.
  void refresh() {
    _rh = null;
    _ra = null;
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
    if (rng.nextDouble() < 1 - exp(-lh)) _goal(home);
    if (rng.nextDouble() < 1 - exp(-la)) _goal(away);
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

  void _goal(MatchSide s) {
    final cands = s.xi.where((p) => p.grp != 'GK').toList();
    if (cands.isEmpty) return;
    double w(Player p) => (p.finishing + 1) * (p.grp == 'FWD' ? 3.0 : p.grp == 'MID' ? 1.2 : 0.4);
    final total = cands.fold<double>(0, (a, p) => a + w(p));
    var r = rng.nextDouble() * total;
    var scorer = cands.last;
    for (final p in cands) {
      r -= w(p);
      if (r <= 0) {
        scorer = p;
        break;
      }
    }
    if (identical(s, home)) {
      hg++;
    } else {
      ag++;
    }
    events.add(MatchEvent(minute, "$minute'  ⚽ ${scorer.name} (${s.teamName})   $hg-$ag", true, s.teamId));
  }

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
    events.add(MatchEvent(minute, "$minute'  🔄 ${s.teamName}: ${inn.name} ⇄ ${out.name}", false, s.teamId));
    refresh();
    return null;
  }

  void setMentality(MatchSide s, Mentality m) {
    s.mentality = m;
    refresh();
  }
}
