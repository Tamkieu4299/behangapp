import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:behangideaapp/core/db/app_database.dart';
import 'package:behangideaapp/core/models/journey.dart';
import 'package:behangideaapp/core/models/milestone.dart';
import 'package:behangideaapp/core/models/record_entry.dart';
import 'package:behangideaapp/core/models/sticker.dart';
import 'package:behangideaapp/core/repos/journey_repository.dart';
import 'package:behangideaapp/core/repos/milestone_repository.dart';
import 'package:behangideaapp/core/repos/record_repository.dart';
import 'package:behangideaapp/core/repos/sticker_repository.dart';

void main() {
  late Database db;
  late JourneyRepository journeys;
  late RecordRepository records;
  late MilestoneRepository milestones;
  late StickerRepository stickers;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: AppDatabase.createSchema,
      ),
    );
    journeys = JourneyRepository(db);
    records = RecordRepository(db);
    milestones = MilestoneRepository(db);
    stickers = StickerRepository(db);
  });

  tearDown(() => db.close());

  Journey buildJourney(String id) => Journey(
        id: id,
        userId: 'user-1',
        title: 'Baby\'s First Year',
        category: JourneyCategory.baby,
        goal: 'First steps',
        startDate: DateTime(2026, 8, 1),
        durationDays: 365,
        createdAt: DateTime(2026, 8, 1),
      );

  test('journey round-trips through the database', () async {
    final journey = buildJourney('j1');
    await journeys.insert(journey);

    final loaded = await journeys.getById('j1');
    expect(loaded, isNotNull);
    expect(loaded!.title, journey.title);
    expect(loaded.category, JourneyCategory.baby);
    expect(loaded.goal, 'First steps');
    expect(loaded.durationDays, 365);
    expect(loaded.archived, isFalse);

    await journeys.setArchived('j1', true);
    expect((await journeys.listAll()).isEmpty, isTrue);
    expect((await journeys.listAll(includeArchived: true)).length, 1);
  });

  test('records are listed newest first and counted', () async {
    await journeys.insert(buildJourney('j1'));
    await records.insert(RecordEntry(
      id: 'r1',
      journeyId: 'j1',
      timestamp: DateTime(2026, 8, 2, 10),
      note: 'tummy time',
    ));
    await records.insert(RecordEntry(
      id: 'r2',
      journeyId: 'j1',
      timestamp: DateTime(2026, 8, 3, 18),
      mediaType: MediaType.photo,
      mediaUrl: 'media/j1/p.jpg',
    ));

    final list = await records.listForJourney('j1');
    expect(list.first.id, 'r2');
    expect(list.last.note, 'tummy time');
    expect(await records.countForJourney('j1'), 2);
    expect(await records.countForJourney('missing'), 0);

    final latest = await records.latestByJourney();
    expect(latest['j1']!.id, 'r2');
  });

  test('milestones can be achieved and reopened', () async {
    await journeys.insert(buildJourney('j1'));
    await milestones.insert(Milestone(
      id: 'm1',
      journeyId: 'j1',
      title: 'Rolled over',
      badgeIcon: '🐣',
      targetDate: DateTime(2026, 9, 1),
    ));

    var list = await milestones.listForJourney('j1');
    expect(list.single.achieved, isFalse);

    final when = DateTime(2026, 8, 15);
    await milestones.setAchieved('m1', when);
    list = await milestones.listForJourney('j1');
    expect(list.single.achievedAt, when);

    await milestones.setAchieved('m1', null);
    list = await milestones.listForJourney('j1');
    expect(list.single.achievedAt, isNull);
  });

  test('stickers upsert one per day', () async {
    await journeys.insert(buildJourney('j1'));
    await stickers
        .upsert(DaySticker(journeyId: 'j1', epochDay: 20600, emoji: '✨'));
    await stickers.upsert(DaySticker(
        journeyId: 'j1', epochDay: 20600, emoji: '🌟'));

    final map = await stickers.mapForJourney('j1');
    expect(map[20600], '🌟');

    await stickers.remove('j1', 20600);
    expect((await stickers.mapForJourney('j1')).isEmpty, isTrue);
  });
}
