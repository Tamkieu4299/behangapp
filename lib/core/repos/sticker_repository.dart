import 'package:sqflite/sqflite.dart';

import '../models/sticker.dart';

class StickerRepository {
  final Database db;

  StickerRepository(this.db);

  Future<void> upsert(DaySticker sticker) =>
      db.insert('stickers', sticker.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> remove(String journeyId, int epochDay) =>
      db.delete(
        'stickers',
        where: 'journey_id = ? AND epoch_day = ?',
        whereArgs: [journeyId, epochDay],
      );

  Future<Map<int, String>> mapForJourney(String journeyId) async {
    final rows = await db.query(
      'stickers',
      where: 'journey_id = ?',
      whereArgs: [journeyId],
    );
    return {
      for (final row in rows) row['epoch_day'] as int: row['emoji'] as String,
    };
  }
}
