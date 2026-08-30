import 'package:sqflite/sqflite.dart';

import '../models/milestone.dart';

class MilestoneRepository {
  final Database db;

  MilestoneRepository(this.db);

  Future<void> insert(Milestone milestone) =>
      db.insert('milestones', milestone.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> update(Milestone milestone) =>
      db.update('milestones', milestone.toMap(),
          where: 'id = ?', whereArgs: [milestone.id]);

  Future<void> delete(String id) =>
      db.delete('milestones', where: 'id = ?', whereArgs: [id]);

  Future<List<Milestone>> listForJourney(String journeyId) async {
    final rows = await db.query(
      'milestones',
      where: 'journey_id = ?',
      whereArgs: [journeyId],
      orderBy: 'target_date IS NULL, target_date',
    );
    return [for (final row in rows) Milestone.fromMap(row)];
  }

  Future<void> setAchieved(String id, DateTime? when) =>
      db.update(
        'milestones',
        {'achieved_at': when?.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
}
