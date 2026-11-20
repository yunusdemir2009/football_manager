import 'dart:math';

/// Oyun cekirdegi: UI'dan bagimsiz saf Dart (mac simulasyonu, fikstur, puan tablosu).

class Player {
  final int id;
  final String name;
  int age;
  int teamId;
  final String position;
  final String grp; // GK, DEF, MID, FWD
  final int finishing, passing, tackling, vision, stamina;
  int ca, pa, value, wage;

  Player({
    required this.id,
    required this.name,
    required this.age,
    required this.teamId,
    required this.position,
    required this.grp,
    required this.finishing,
    required this.passing,
    required this.tackling,
    required this.vision,
    required this.stamina,
    required this.ca,
    required this.pa,
    required this.value,
    required this.wage,
  });

  factory Player.fromMap(Map<String, Object?> m) => Player(
        id: m['id'] as int,
        name: (m['name'] as String?) ?? '?',
        age: (m['age'] as int?) ?? 25,
        teamId: (m['team_id'] as int?) ?? 0,
        position: (m['position'] as String?) ?? '',
        grp: (m['grp'] as String?) ?? 'MID',
        finishing: (m['finishing'] as int?) ?? 1,
        passing: (m['passing'] as int?) ?? 1,
        tackling: (m['tackling'] as int?) ?? 1,
        vision: (m['vision'] as int?) ?? 1,
        stamina: (m['stamina'] as int?) ?? 1,
        ca: (m['ca'] as int?) ?? 1,
        pa: (m['pa'] as int?) ?? 1,
        value: (m['value'] as int?) ?? 0,
        wage: (m['wage'] as int?) ?? 0,
      );
}

class Team {
  final int id;
  String name;
  final int leagueId;
  int budget;
  Team(this.id, this.name, this.leagueId, this.budget);
}

class Fixture {
  final int? id;
  final int week;
  final int home;
  final int away;
  int? hg;
  int? ag;
  Fixture(this.id, this.week, this.home, this.away, [this.hg, this.ag]);
  bool get played => hg != null && ag != null;
}

class Standing {
  final int teamId;
  int played = 0, won = 0, drawn = 0, lost = 0, gf = 0, ga = 0, points = 0;
  Standing(this.teamId);
  int get gd => gf - ga;
}

class Rating {
  final double att, def;
  const Rating(this.att, this.def);
}

const double kBaseGoals = 1.30;
const double kHomeBoost = 1.12;
const double kAwayBoost = 0.90;
const double kSpread = 5.0;

double _meanTop(List<Player> list, int n) {
  if (list.isEmpty) return 30;
  final s = [...list]..sort((a, b) => b.ca.compareTo(a.ca));
  final t = s.take(n).toList();
  return t.fold<int>(0, (a, p) => a + p.ca) / t.length;
}

/// 4-4-2 ilk 11'e gore hucum/savunma puani.
Rating rate(List<Player> squad) {
  List<Player> g(String k) => squad.where((p) => p.grp == k).toList();
  final gk = _meanTop(g('GK'), 1);
  final d = _meanTop(g('DEF'), 4);
  final m = _meanTop(g('MID'), 4);
  final f = _meanTop(g('FWD'), 2);
  return Rating((2 * f + m) / 3, (2 * d + gk) / 3);
}

/// Ilk 11 (4-4-2), oyuncu ekrani icin.
List<Player> bestEleven(List<Player> squad) {
  List<Player> top(String k, int n) {
    final s = squad.where((p) => p.grp == k).toList()..sort((a, b) => b.ca.compareTo(a.ca));
    return s.take(n).toList();
  }

  return [...top('GK', 1), ...top('DEF', 4), ...top('MID', 4), ...top('FWD', 2)];
}

int _poisson(Random r, double lambda) {
  final l = exp(-lambda);
  int k = 0;
  double p = 1;
  do {
    k++;
    p *= r.nextDouble();
  } while (p > l);
  return k - 1;
}

/// avgAtt/avgDef: lig ortalamasi (puanlar ligin ortalamasina gore normallestirilir).
(int, int) simulateMatch(Random r, Rating home, Rating away, double avgAtt, double avgDef) {
  final lh = kBaseGoals * kHomeBoost * exp(((home.att - avgAtt) - (away.def - avgDef)) / kSpread);
  final la = kBaseGoals * kAwayBoost * exp(((away.att - avgAtt) - (home.def - avgDef)) / kSpread);
  return (_poisson(r, lh), _poisson(r, la));
}

/// Cift devreli fikstur (circle method). Tek sayida takimda bay gecer.
List<Fixture> buildFixtures(List<int> teamIds, Random rng) {
  final ids = [...teamIds]..shuffle(rng);
  if (ids.length.isOdd) ids.add(-1);
  final n = ids.length;
  final rounds = <List<List<int>>>[];
  final rot = [...ids];
  for (int r = 0; r < n - 1; r++) {
    final pairs = <List<int>>[];
    for (int i = 0; i < n ~/ 2; i++) {
      final a = rot[i], b = rot[n - 1 - i];
      if (a == -1 || b == -1) continue;
      pairs.add(r.isEven ? [a, b] : [b, a]);
    }
    rounds.add(pairs);
    rot.insert(1, rot.removeLast());
  }
  final fixtures = <Fixture>[];
  for (int r = 0; r < rounds.length; r++) {
    for (final p in rounds[r]) {
      fixtures.add(Fixture(null, r + 1, p[0], p[1]));
    }
  }
  final half = rounds.length;
  for (int r = 0; r < rounds.length; r++) {
    for (final p in rounds[r]) {
      fixtures.add(Fixture(null, half + r + 1, p[1], p[0]));
    }
  }
  return fixtures;
}

List<Standing> computeStandings(List<int> teamIds, List<Fixture> fixtures, Map<int, String> names) {
  final m = {for (final id in teamIds) id: Standing(id)};
  for (final f in fixtures.where((f) => f.played)) {
    final h = m[f.home], a = m[f.away];
    if (h == null || a == null) continue;
    h.played++;
    a.played++;
    h.gf += f.hg!;
    h.ga += f.ag!;
    a.gf += f.ag!;
    a.ga += f.hg!;
    if (f.hg! > f.ag!) {
      h.won++;
      a.lost++;
      h.points += 3;
    } else if (f.hg! < f.ag!) {
      a.won++;
      h.lost++;
      a.points += 3;
    } else {
      h.drawn++;
      a.drawn++;
      h.points++;
      a.points++;
    }
  }
  final list = m.values.toList()
    ..sort((x, y) {
      var c = y.points.compareTo(x.points);
      if (c != 0) return c;
      c = y.gd.compareTo(x.gd);
      if (c != 0) return c;
      c = y.gf.compareTo(x.gf);
      if (c != 0) return c;
      return (names[x.teamId] ?? '').compareTo(names[y.teamId] ?? '');
    });
  return list;
}

int valueOf(int ca, int age) {
  final f = age <= 23 ? 1.3 : age <= 29 ? 1.0 : age <= 32 ? 0.7 : 0.4;
  final v = pow(ca / 100.0, 4) * 120000000 * f;
  return (v / 10000).round() * 10000;
}
