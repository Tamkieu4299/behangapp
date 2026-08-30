import 'package:sqflite/sqflite.dart';

import '../models/record_entry.dart';

class RecordRepository {
  final Database db;

  RecordRepository(this.db);

  Future<void> insert(RecordEntry record) =>
      db.insert('records', record.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> delete(String id) =>
      db.delete('records', where: 'id = ?', whereArgs: [id]);

  Future<RecordEntry?> getById(String id) async {
    final rows = await db.query(
      'records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : RecordEntry.fromMap(rows.first);
  }

  Future<List<RecordEntry>> listForJourney(String journeyId) async {
    final rows = await db.query(
      'records',
      where: 'journey_id = ?',
      whereArgs: [journeyId],
      orderBy: 'timestamp DESC',
    );
    return [for (final row in rows) RecordEntry.fromMap(row)];
  }

  Future<int> countForJourney(String journeyId) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM records WHERE journey_id = ?',
      [journeyId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, RecordEntry>> latestByJourney() async {
    final rows = await db.query('records', orderBy: 'timestamp DESC');
    final latest = <String, RecordEntry>{};
    for (final row in rows) {
      final entry = RecordEntry.fromMap(row);
      latest.putIfAbsent(entry.journeyId, () => entry);
    }
    return latest;
  }
}
