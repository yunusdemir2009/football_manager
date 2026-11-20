import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/game_db.dart';
import 'engine.dart';
import 'match.dart';

const int kMinSquad = 18;
const int kMaxSquad = 30;
const Map<String, int> kMinByGroup = {'GK': 2, 'DEF': 5, 'MID': 5, 'FWD': 3};

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

  // Taktik
  Formation formation = kFormations.first;
  Mentality mentality = Mentality.balanced;
  List<int> xiIds = [];

  // Hafta durumu
  final Map<int, (int, int)> _pending = {};
  MatchSession? live;

  GameState._(this.gdb, this.teamId, this.leagueId, this.week, this.season);

  static Future<GameState> create(GameDb gdb, int leagueId, int teamId) async {
    await gdb.reset();
    final s = GameState._(gdb, teamId, leagueId, 1, 1);
    await s._loadTeamsAndPlayers();
    await s._generateFixtures();
    s.ensureLineup(forceAuto: true);
    await s._saveMeta();
    await s._saveTactic();
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
    final l = await gdb.loadLineup();
    if (l != null) {
      s.formation = formationByName((l['formation'] as String?) ?? '4-4-2');
      final mi = (l['mentality'] as int?) ?? 1;
      s.mentality = Mentality.values[mi.clamp(0, Mentality.values.length - 1).toInt()];
      final raw = (l['xi'] as String?) ?? '';
      s.xiIds = raw.isEmpty ? [] : raw.split(',').map(int.parse).toList();
    }
    s.ensureLineup();
    return s;
  }

  Future<void> _loadTeamsAndPlayers() async {
    teams = (await gdb.teamsOf(leagueId))
        .map((r) => Team(r['id'] as int, r['name'] as String, r['league_id'] as int, r['budget'] as int))
        .toList();
    players = (await gdb.playersOfLeague(leagueId)).map(Player.fromMap).toList();
  }

  Future<void> _generateFixtures() async {
    final gen = buildFixtures(teams.map((t) => t.id).toList(), rng);
    await gdb.db.delete('Fixtures');
    final b = gdb.db.batch();
    for (final f in gen) {
      b.insert('Fixtures', {'week': f.week, 'home': f.home, 'away': f.away});
    }
    await b.commit(noResult: true);
    fixtures = (await gdb.fixtures())
        .map((r) => Fixture(r['id'] as int, r['week'] as int, r['home'] as int, r['away'] as int))
        .toList();
  }

  Future<void> _saveMeta() => gdb.db.insert(
        'Save',
        {'id': 1, 'team_id': teamId, 'league_id': leagueId, 'week': week, 'season': season},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> _saveTactic() => gdb.db.insert(
        'Lineup',
        {'id': 1, 'formation': formation.name, 'mentality': mentality.index, 'xi': xiIds.join(',')},
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

  // ---- taktik / kadro ----
  List<Player> get myXI {
    final byId = {for (final p in squad(teamId)) p.id: p};
    return xiIds.map((id) => byId[id]).whereType<Player>().toList();
  }

  List<Player> get myBench => autoBench(squad(teamId), myXI);

  /// Ilk 11 gecersizse (oyuncu satildi, dizilis uymuyor) otomatik duzelt.
  void ensureLineup({bool forceAuto = false}) {
    final sq = squad(teamId);
    final xi = myXI;
    if (forceAuto || !lineupValid(xi, formation)) {
      xiIds = autoXI(sq, formation).map((p) => p.id).toList();
    }
  }

  Future<void> setFormation(Formation f) async {
    formation = f;
    xiIds = autoXI(squad(teamId), f).map((p) => p.id).toList();
    await _saveTactic();
  }

  Future<void> setMentality(Mentality m) async {
    mentality = m;
    await _saveTactic();
  }

  /// Ilk 11'de ayni mevkiden oyuncu degistir.
  Future<String?> swapStarter(Player out, Player inn) async {
    if (out.grp != inn.grp) return 'Aynı mevkiden oyuncu seçin';
    final i = xiIds.indexOf(out.id);
    if (i < 0) return 'Oyuncu ilk 11\'de değil';
    xiIds[i] = inn.id;
    await _saveTactic();
    return null;
  }

  Future<void> autoPickLineup() async {
    ensureLineup(forceAuto: true);
    await _saveTactic();
  }

  MatchSide _userSide() {
    final xi = myXI;
    return MatchSide(
      teamId: teamId,
      teamName: myTeam.name,
      isUser: true,
      formation: formation,
      mentality: mentality,
      xi: [...xi],
      bench: [...autoBench(squad(teamId), xi)],
    );
  }

  MatchSide _aiSide(Team t) {
    final sq = squad(t.id);
    final f = kFormations[(t.id * 7) % kFormations.length];
    final xi = autoXI(sq, f);
    return MatchSide(
      teamId: t.id,
      teamName: t.name,
      isUser: false,
      formation: f,
      mentality: Mentality.balanced,
      xi: xi,
      bench: autoBench(sq, xi),
    );
  }

  // ---- hafta ----
  /// Haftayi baslatir: diger maclar hemen simule edilir. Yonetilen takimin maci varsa canli oturum doner.
  MatchSession? beginWeek() {
    if (seasonOver) return null;
    ensureLineup();
    final base = {for (final t in teams) t.id: baselineRating(squad(t.id))};
    final avgAtt = base.values.fold<double>(0, (a, r) => a + r.att) / base.length;
    final avgDef = base.values.fold<double>(0, (a, r) => a + r.def) / base.length;

    _pending.clear();
    live = null;
    for (final f in fixturesOfWeek(week)) {
      final mine = f.home == teamId || f.away == teamId;
      final home = f.home == teamId ? _userSide() : _aiSide(team(f.home));
      final away = f.away == teamId ? _userSide() : _aiSide(team(f.away));
      final session = MatchSession(rng: rng, home: home, away: away, avgAtt: avgAtt, avgDef: avgDef);
      if (mine) {
        live = session;
      } else {
        session.autoAll = true;
        session.simulateToEnd();
        _pending[f.id!] = (session.hg, session.ag);
      }
    }
    return live;
  }

  /// Sonuclari isler, finansi gunceller, haftayi ilerletir.
  Future<void> finishWeek() async {
    if (seasonOver) return;
    final s = live;
    if (s != null && !s.finished) {
      s.autoAll = true;
      s.simulateToEnd();
    }
    lastResults = [];
    final batch = gdb.db.batch();
    for (final f in fixturesOfWeek(week)) {
      final mine = f.home == teamId || f.away == teamId;
      final r = mine ? (s != null ? (s.hg, s.ag) : null) : _pending[f.id!];
      if (r == null) continue;
      f.hg = r.$1;
      f.ag = r.$2;
      batch.update('Fixtures', {'hg': r.$1, 'ag': r.$2}, where: 'id = ?', whereArgs: [f.id]);
      lastResults.add('${teamName(f.home)} ${r.$1}-${r.$2} ${teamName(f.away)}');
    }

    // Finans: haftalik maas gideri + mac geliri
    final mine = myFixture(week);
    final sv = squadValue(teamId);
    int net = -(squadWages(teamId) / max(totalWeeks, 1)).round();
    if (mine != null && mine.played) {
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
    live = null;
    _pending.clear();
    await batch.commit(noResult: true);
    await _saveMeta();
  }

  /// Hizli simulasyon: canli izlemeden, kayitli taktikle haftayi oynar.
  Future<void> quickPlayWeek() async {
    final s = beginWeek();
    if (s != null) {
      s.autoAll = true;
      s.simulateToEnd();
    }
    await finishWeek();
  }

  // ---- transfer ----
  int buyPrice(Player p) => (p.value * 1.1).round();
  int sellPrice(Player p) => (p.value * 0.8).round();

  int _groupCount(int tid, String grp) => players.where((p) => p.teamId == tid && p.grp == grp).length;

  /// Basariliysa null, degilse hata mesaji.
  Future<String?> buy(Player p) async {
    if (p.teamId == teamId) return 'Oyuncu zaten takımınızda';
    final price = buyPrice(p);
    if (myTeam.budget < price) return 'Bütçe yetersiz';
    if (squad(teamId).length >= kMaxSquad) return 'Kadro dolu (maks. $kMaxSquad)';
    if (squad(p.teamId).length <= kMinSquad || _groupCount(p.teamId, p.grp) <= (kMinByGroup[p.grp] ?? 0)) {
      return 'Rakip kulüp bu oyuncuyu satmak istemiyor';
    }
    final from = p.teamId;
    myTeam.budget -= price;
    team(from).budget += price;
    p.teamId = teamId;
    await _persistTransfer(p, [myTeam, team(from)]);
    ensureLineup();
    await _saveTactic();
    return null;
  }

  Future<String?> sell(Player p) async {
    if (p.teamId != teamId) return 'Oyuncu sizin değil';
    if (squad(teamId).length <= kMinSquad) return 'Kadro en az $kMinSquad oyuncu olmalı';
    if (_groupCount(teamId, p.grp) <= (kMinByGroup[p.grp] ?? 0)) {
      return 'Bu mevkide en az ${kMinByGroup[p.grp]} oyuncu kalmalı';
    }
    final buyers = teams.where((t) => t.id != teamId && squad(t.id).length < kMaxSquad).toList();
    if (buyers.isEmpty) return 'Alıcı kulüp bulunamadı';
    final to = buyers[rng.nextInt(buyers.length)];
    final price = sellPrice(p);
    myTeam.budget += price;
    to.budget -= price;
    p.teamId = to.id;
    await _persistTransfer(p, [myTeam, to]);
    ensureLineup();
    await _saveTactic();
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
    ensureLineup();
    await _saveMeta();
    await _saveTactic();
  }
}
