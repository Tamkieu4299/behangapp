import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static Database? _instance;

  static Future<Database> instance() async {
    final existing = _instance;
    if (existing != null && existing.isOpen) return existing;
    final dir = await getDatabasesPath();
    _instance = await openDatabase(
      p.join(dir, 'behangidea.db'),
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: createSchema,
      onUpgrade: _upgradeSchema,
    );
    return _instance!;
  }

  static Future<void> _upgradeSchema(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final info = await db.rawQuery('PRAGMA table_info(records)');
      final columns = info.map((row) => row['name']).toSet();
      for (final column in ['author_uid', 'author_name', 'author_avatar']) {
        if (!columns.contains(column)) {
          await db.execute('ALTER TABLE records ADD COLUMN $column TEXT');
        }
      }
    }
  }

  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE journeys (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        goal TEXT,
        start_date INTEGER NOT NULL,
        duration_days INTEGER,
        reminder_hour INTEGER,
        reminder_minute INTEGER,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE records (
        id TEXT PRIMARY KEY,
        journey_id TEXT NOT NULL REFERENCES journeys(id) ON DELETE CASCADE,
        timestamp INTEGER NOT NULL,
        media_type TEXT NOT NULL DEFAULT 'none',
        media_url TEXT,
        note TEXT,
        author_uid TEXT,
        author_name TEXT,
        author_avatar TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_records_journey_time ON records(journey_id, timestamp)',
    );
    await db.execute('''
      CREATE TABLE milestones (
        id TEXT PRIMARY KEY,
        journey_id TEXT NOT NULL REFERENCES journeys(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        target_date INTEGER,
        achieved_at INTEGER,
        badge_icon TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE stickers (
        journey_id TEXT NOT NULL REFERENCES journeys(id) ON DELETE CASCADE,
        epoch_day INTEGER NOT NULL,
        emoji TEXT NOT NULL,
        PRIMARY KEY (journey_id, epoch_day)
      )
    ''');
  }
}
