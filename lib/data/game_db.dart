import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Asset icindeki game.db'yi yazilabilir konuma kopyalar. Takim/oyuncu isimlerini degistirmek
/// icin assets/game.db'yi (tools/build_game_db.py ciktisi) degistirmek yeterlidir.
class GameDb {
  late Database db;
  late String path;

  static Future<GameDb> open() async {
    final g = GameDb();
    g.path = join(await getDatabasesPath(), 'game.db');
    if (!await databaseExists(g.path)) {
      await g._copyAsset();
    }
    await g._openAndPrepare();
    return g;
  }

  Future<void> _copyAsset() async {
    await Directory(dirname(path)).create(recursive: true);
    final data = await rootBundle.load('assets/game.db');
    await File(path).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  Future<void> _openAndPrepare() async {
    db = await openDatabase(path);
    await db.execute('CREATE TABLE IF NOT EXISTS Save('
        'id INTEGER PRIMARY KEY, team_id INTEGER, league_id INTEGER, week INTEGER, season INTEGER)');
    await db.execute('CREATE TABLE IF NOT EXISTS Fixtures('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, week INTEGER, home INTEGER, away INTEGER, hg INTEGER, ag INTEGER)');
  }

  /// Yeni oyun: veritabanini asset'ten sifirla (budce/transfer degisiklikleri silinir).
  Future<void> reset() async {
    await db.close();
    await deleteDatabase(path);
    await _copyAsset();
    await _openAndPrepare();
  }

  Future<List<Map<String, Object?>>> leagues() =>
      db.rawQuery('SELECT l.id, l.country, l.name, l.strength, COUNT(t.id) AS teams '
          'FROM Leagues l LEFT JOIN Teams t ON t.league_id = l.id GROUP BY l.id ORDER BY l.strength DESC, l.name');

  Future<List<Map<String, Object?>>> teamsOf(int leagueId) =>
      db.query('Teams', where: 'league_id = ?', whereArgs: [leagueId], orderBy: 'budget DESC');

  Future<List<Map<String, Object?>>> playersOfLeague(int leagueId) => db.rawQuery(
      'SELECT p.* FROM Players p JOIN Teams t ON p.team_id = t.id WHERE t.league_id = ?', [leagueId]);

  Future<Map<String, Object?>?> loadSave() async {
    final r = await db.query('Save', where: 'id = 1');
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, Object?>>> fixtures() => db.query('Fixtures', orderBy: 'week, id');
}
