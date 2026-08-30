import 'package:sqflite/sqflite.dart';

import '../models/journey.dart';

class JourneyRepository {
  final Database db;

  JourneyRepository(this.db);

  Future<void> insert(Journey journey) =>
      db.insert('journeys', journey.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> update(Journey journey) =>
      db.update('journeys', journey.toMap(),
          where: 'id = ?', whereArgs: [journey.id]);

  Future<List<Journey>> listAll({bool includeArchived = false}) async {
    final rows = await db.query(
      'journeys',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'created_at DESC',
    );
    return [for (final row in rows) Journey.fromMap(row)];
  }

  Future<Journey?> getById(String id) async {
    final rows = await db.query(
      'journeys',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Journey.fromMap(rows.first);
  }

  Future<void> setReminder(String id, int? hour, int? minute) async {
    await db.update(
      'journeys',
      {'reminder_hour': hour, 'reminder_minute': minute},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    await db.update(
      'journeys',
      {'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    await db.delete('records', where: 'journey_id = ?', whereArgs: [id]);
    await db.delete('milestones', where: 'journey_id = ?', whereArgs: [id]);
    await db.delete('stickers', where: 'journey_id = ?', whereArgs: [id]);
    await db.delete('journeys', where: 'id = ?', whereArgs: [id]);
  }
}
