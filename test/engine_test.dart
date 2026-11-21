import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager/core/engine.dart';
import 'package:football_manager/core/match.dart';

Player _p(int id, String grp, int ca, {int stamina = 10}) => Player(
      id: id,
      name: 'P$id',
      age: 25,
      teamId: 1,
      position: grp,
      grp: grp,
      finishing: 10,
      passing: 10,
      tackling: 10,
      vision: 10,
      stamina: stamina,
      ca: ca,
      pa: ca,
      value: 1000000,
      wage: 100000,
    );

List<Player> _squad() {
  var id = 0;
  return [
    for (var i = 0; i < 3; i++) _p(id++, 'GK', 40 + i),
    for (var i = 0; i < 8; i++) _p(id++, 'DEF', 40 + i),
    for (var i = 0; i < 8; i++) _p(id++, 'MID', 40 + i),
    for (var i = 0; i < 6; i++) _p(id++, 'FWD', 40 + i),
  ];
}

void main() {
  test('fikstür: çift devre, her çift iki kez, haftada en fazla 1 maç', () {
    for (final n in [10, 19, 20]) {
      final ids = List.generate(n, (i) => i + 1);
      final fx = buildFixtures(ids, Random(1));
      expect(fx.length, n * (n - 1));
      final pairs = fx.map((f) => '${f.home}-${f.away}').toSet();
      expect(pairs.length, n * (n - 1));
      final perWeek = <int, Map<int, int>>{};
      for (final f in fx) {
        final m = perWeek.putIfAbsent(f.week, () => {});
        m[f.home] = (m[f.home] ?? 0) + 1;
        m[f.away] = (m[f.away] ?? 0) + 1;
      }
      for (final m in perWeek.values) {
        expect(m.values.every((c) => c == 1), isTrue);
      }
    }
  });

  test('puan tablosu: galibiyet 3, beraberlik 1 puan', () {
    final fx = [Fixture(1, 1, 1, 2, 2, 0), Fixture(2, 1, 3, 4, 1, 1)];
    final st = computeStandings([1, 2, 3, 4], fx, {1: 'A', 2: 'B', 3: 'C', 4: 'D'});
    expect(st.first.teamId, 1);
    expect(st.first.points, 3);
    expect(st.firstWhere((s) => s.teamId == 3).points, 1);
  });

  test('otomatik ilk 11 dizilişe uyar', () {
    for (final f in kFormations) {
      final xi = autoXI(_squad(), f);
      expect(lineupValid(xi, f), isTrue, reason: f.name);
    }
  });

  test('oyuncu değişikliği: aynı mevki zorunlu, hak sınırı', () {
    final sq = _squad();
    final f = kFormations.first;
    final xi = autoXI(sq, f);
    final bench = autoBench(sq, xi);
    MatchSide side(bool user) => MatchSide(
        teamId: 1,
        teamName: 'A',
        isUser: user,
        formation: f,
        mentality: Mentality.balanced,
        xi: [...xi],
        bench: [...bench]);
    final s = MatchSession(rng: Random(1), home: side(true), away: side(false), avgAtt: 45, avgDef: 45);
    final out = s.home.xi.firstWhere((p) => p.grp == 'DEF');
    final wrong = s.home.bench.firstWhere((p) => p.grp != 'DEF');
    expect(s.substitute(s.home, out, wrong), isNotNull);
    final right = s.home.bench.firstWhere((p) => p.grp == 'DEF');
    expect(s.substitute(s.home, out, right), isNull);
    expect(s.home.subsUsed, 1);
  });

  test('maç 90 dakikada biter ve makul gol sayısı üretir', () {
    final sq = _squad();
    final f = kFormations.first;
    final xi = autoXI(sq, f);
    final base = baselineRating(sq);
    var goals = 0;
    const n = 400;
    final rng = Random(7);
    for (var i = 0; i < n; i++) {
      MatchSide side(bool u) => MatchSide(
          teamId: 1,
          teamName: 'A',
          isUser: u,
          formation: f,
          mentality: Mentality.balanced,
          xi: [...xi],
          bench: autoBench(sq, xi));
      final s = MatchSession(rng: rng, home: side(false), away: side(false), avgAtt: base.att, avgDef: base.def)
        ..autoAll = true;
      s.simulateToEnd();
      expect(s.finished, isTrue);
      goals += s.hg + s.ag;
    }
    expect(goals / n, inInclusiveRange(2.0, 3.6));
  });
}
