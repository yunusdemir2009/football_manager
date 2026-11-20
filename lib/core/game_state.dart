import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/game_db.dart';
import 'engine.dart';

const int kMinSquad = 18;
const int kMaxSquad = 30;

/// Oyun durumu: yonetilen lig bellekte tutulur, degisiklikler SQLite'a yazilir.
class GameState {
  final GameDb gdb;
  final int teamId; // yonetilen takim
  final int leagueId;
  int week;
  int season;
  final Random rng = Random();

  List<Team> teams = [];
  List<Player> players = [];
  List<Fixture> fixtures = [];
  List<String> lastResults = [];

  GameState._(this.gdb, this.teamId, this.leagueId, this.week, this.season);

  static Future<GameState> create(GameDb gdb, int leagueId, int teamId) async {
    await gdb.reset();
    final s = GameState._(gdb, teamId, leagueId, 1, 1);
    await s._loadTeamsAndPlayers();
    await s._generateFixtures();
    await s._saveMeta();
    return s;
  }

  static Future<GameState?> resume(GameDb gdb) async {
    final m = await gdb.loadSave();
    if (m == null) return null;
    final s = GameState._(gdb, m['team_id'] as int, m['league_id'] as int, m['week'] as int, m['season'] as int);
    await s._loadTeamsAndPlayers();
    s.fixtures = (await gdb.fixtures())
        .map((r) => Fixture(r['id'] as int, r['week'] as int, r['home'] as int, r['away'] as int,
            r['hg'] as int?, r['ag'] as int?))
        .toList();
    return s;
  }

  Future<void> _loadTeamsAndPlayers() async {
    teams = (await gdb.teamsOf(leagueId))
        .map((r) => Team(r['id'] as int, r['name'] as String, r['league_id'] as int, r['budget'] as int))
        .toList();
    players = (await gdb.playersOfLeague(leagueId)).map(Player.fromMap).toList();
  }

  Future<void> _generateFixtures() async {
    fixtures = buildFixtures(teams.map((t) => t.id).toList(), rng);
    await gdb.db.delete('Fixtures');
    final b = gdb.db.batch();
    for (final f in fixtures) {
      b.insert('Fixtures', {'week': f.week, 'home': f.home, 'away': f.away});
    }
    await b.commit(noResult: true);
    final rows = await gdb.fixtures();
    fixtures = rows
        .map((r) => Fixture(r['id'] as int, r['week'] as int, r['home'] as int, r['away'] as int))
        .toList();
  }

  Future<void> _saveMeta() => gdb.db.insert(
        'Save',
        {'id': 1, 'team_id': teamId, 'league_id': leagueId, 'week': week, 'season': season},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ---- sorgular ----
  Team team(int id) => teams.firstWhere((t) => t.id == id);
  Team get myTeam => team(teamId);
  String teamName(int id) => team(id).name;
  List<Player> squad(int tid) => players.where((p) => p.teamId == tid).toList();
  int get totalWeeks => fixtures.isEmpty ? 0 : fixtures.map((f) => f.week).reduce(max);
  bool get seasonOver => week > totalWeeks;
  List<Fixture> fixturesOfWeek(int w) => fixtures.where((f) => f.week == w).toList();
  Fixture? myFixture(int w) {
    for (final f in fixtures) {
      if (f.week == w && (f.home == teamId || f.away == teamId)) return f;
    }
    return null;
  }

  List<Standing> standings() =>
      computeStandings(teams.map((t) => t.id).toList(), fixtures, {for (final t in teams) t.id: t.name});

  int squadValue(int tid) => squad(tid).fold<int>(0, (a, p) => a + p.value);
  int squadWages(int tid) => squad(tid).fold<int>(0, (a, p) => a + p.wage);

  // ---- hafta oynat ----
  Future<void> playWeek() async {
    if (seasonOver) return;
    final ratings = {for (final t in teams) t.id: rate(squad(t.id))};
    final avgAtt = ratings.values.fold<double>(0, (a, r) => a + r.att) / ratings.length;
    final avgDef = ratings.values.fold<double>(0, (a, r) => a + r.def) / ratings.length;

    lastResults = [];
    final batch = gdb.db.batch();
    for (final f in fixturesOfWeek(week)) {
      final (hg, ag) = simulateMatch(rng, ratings[f.home]!, ratings[f.away]!, avgAtt, avgDef);
      f.hg = hg;
      f.ag = ag;
      batch.update('Fixtures', {'hg': hg, 'ag': ag}, where: 'id = ?', whereArgs: [f.id]);
      lastResults.add('${teamName(f.home)} $hg-$ag ${teamName(f.away)}');
    }

    // Finans (yonetilen takim): haftalik maas gideri, mac geliri
    final mine = myFixture(week);
    final sv = squadValue(teamId);
    int net = -(squadWages(teamId) / max(totalWeeks, 1)).round();
    if (mine != null) {
      final isHome = mine.home == teamId;
      final my = isHome ? mine.hg! : mine.ag!;
      final opp = isHome ? mine.ag! : mine.hg!;
      double income = 0.0030 + (isHome ? 0.0012 : 0.0);
      if (my > opp) income += 0.0008;
      net += (sv * income).round();
    }
    myTeam.budget += net;
    batch.update('Teams', {'budget': myTeam.budget}, where: 'id = ?', whereArgs: [teamId]);
    week++;
    await batch.commit(noResult: true);
    await _saveMeta();
  }

  // ---- transfer ----
  int buyPrice(Player p) => (p.value * 1.1).round();
  int sellPrice(Player p) => (p.value * 0.8).round();

  /// Basariliysa null, degilse hata mesaji.
  Future<String?> buy(Player p) async {
    if (p.teamId == teamId) return 'Oyuncu zaten takımınızda';
    final price = buyPrice(p);
    if (myTeam.budget < price) return 'Bütçe yetersiz';
    if (squad(teamId).length >= kMaxSquad) return 'Kadro dolu (maks. $kMaxSquad)';
    if (squad(p.teamId).length <= kMinSquad) return 'Rakip kulüp kadrosunu daha fazla küçültmez';
    final from = p.teamId;
    myTeam.budget -= price;
    team(from).budget += price;
    p.teamId = teamId;
    await _persistTransfer(p, [myTeam, team(from)]);
    return null;
  }

  Future<String?> sell(Player p) async {
    if (p.teamId != teamId) return 'Oyuncu sizin değil';
    final mine = squad(teamId);
    if (mine.length <= kMinSquad) return 'Kadro en az $kMinSquad oyuncu olmalı';
    if (p.grp == 'GK' && mine.where((x) => x.grp == 'GK').length <= 2) return 'En az 2 kaleci gerekli';
    final buyers = teams.where((t) => t.id != teamId && squad(t.id).length < kMaxSquad).toList();
    if (buyers.isEmpty) return 'Alıcı kulüp bulunamadı';
    final to = buyers[rng.nextInt(buyers.length)];
    final price = sellPrice(p);
    myTeam.budget += price;
    to.budget -= price;
    p.teamId = to.id;
    await _persistTransfer(p, [myTeam, to]);
    return null;
  }

  Future<void> _persistTransfer(Player p, List<Team> changed) async {
    final b = gdb.db.batch();
    b.update('Players', {'team_id': p.teamId}, where: 'id = ?', whereArgs: [p.id]);
    for (final t in changed) {
      b.update('Teams', {'budget': t.budget}, where: 'id = ?', whereArgs: [t.id]);
    }
    await b.commit(noResult: true);
  }

  // ---- yeni sezon ----
  Future<void> newSeason() async {
    for (final p in players) {
      p.age++;
      if (p.age <= 22 && p.ca < p.pa) {
        p.ca = min(p.pa, p.ca + rng.nextInt(4));
      } else if (p.age >= 31) {
        p.ca = max(1, p.ca - rng.nextInt(4));
      } else {
        p.ca = max(1, p.ca + rng.nextInt(3) - 1);
      }
      p.value = valueOf(p.ca, p.age);
      p.wage = (p.value * 0.12).round();
    }
    final b = gdb.db.batch();
    for (final p in players) {
      b.update('Players', {'age': p.age, 'ca': p.ca, 'value': p.value, 'wage': p.wage},
          where: 'id = ?', whereArgs: [p.id]);
    }
    await b.commit(noResult: true);
    season++;
    week = 1;
    lastResults = [];
    await _generateFixtures();
    await _saveMeta();
  }
}
