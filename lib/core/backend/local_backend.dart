import 'dart:async';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../models/journey.dart';
import '../models/milestone.dart';
import '../models/record_entry.dart';
import '../models/sticker.dart';
import '../repos/journey_repository.dart';
import '../repos/milestone_repository.dart';
import '../repos/record_repository.dart';
import '../repos/sticker_repository.dart';
import '../services/media_service.dart';
import 'backend.dart';
import 'value_stream.dart';

class LocalBackend implements Backend {
  LocalBackend(this.db);

  final Database db;

  late final JourneyRepository _journeyRepo = JourneyRepository(db);
  late final RecordRepository _recordRepo = RecordRepository(db);
  late final MilestoneRepository _milestoneRepo = MilestoneRepository(db);
  late final StickerRepository _stickerRepo = StickerRepository(db);

  late final ValueStream<UserProfile?> _profile =
      ValueStream<UserProfile?>(null);
  late final ValueStream<List<Journey>> _journeys =
      ValueStream<List<Journey>>(const []);
  late final ValueStream<Map<String, List<RecordEntry>>> _records =
      ValueStream<Map<String, List<RecordEntry>>>(const {});
  late final ValueStream<Map<String, List<Milestone>>> _milestones =
      ValueStream<Map<String, List<Milestone>>>(const {});
  late final ValueStream<Map<String, Map<int, String>>> _stickers =
      ValueStream<Map<String, Map<int, String>>>(const {});

  @override
  bool get isCloud => false;

  @override
  String? get currentUserId => _profile.value?.uid;

  @override
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _profile.add(UserProfile(
      uid: prefs.getString('user_id') ?? 'local-user',
      displayName: prefs.getString('display_name') ?? 'You',
      avatar: prefs.getString('avatar') ?? '🌱',
    ));
    await _refreshAll();
  }

  @override
  Stream<UserProfile?> get profileStream => _profile.watch();

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
    required String displayName,
    required String avatar,
    required bool createAccount,
  }) async {
    final profile = UserProfile(
      uid: _profile.value?.uid ?? 'local-user',
      displayName: displayName.trim(),
      avatar: avatar,
    );
    await updateUserProfile(profile);
    return profile;
  }

  @override
  Future<void> updateUserProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('display_name', profile.displayName);
    await prefs.setString('avatar', profile.avatar);
    await prefs.setString('user_id', profile.uid);
    _profile.add(profile);
    await _refreshRecordsOnly();
  }

  @override
  Future<void> signOut() async {}

  @override
  Stream<List<Journey>> get journeysStream => _journeys.watch();

  @override
  Stream<Map<String, List<RecordEntry>>> get recordsByJourneyStream =>
      _records.watch();

  @override
  Stream<Map<String, List<Milestone>>> get milestonesByJourneyStream =>
      _milestones.watch();

  @override
  Stream<Map<String, Map<int, String>>> get stickersByJourneyStream =>
      _stickers.watch();

  @override
  Future<void> createJourney(Journey journey) async {
    await _journeyRepo.insert(journey);
    await _refreshJourneys();
  }

  @override
  Future<void> deleteJourney(String journeyId) async {
    await _journeyRepo.delete(journeyId);
    await _refreshJourneys();
    await _refreshRecordsOnly();
  }

  @override
  Future<void> setReminder(String journeyId, int? hour, int? minute) async {
    await _journeyRepo.setReminder(journeyId, hour, minute);
    await _refreshJourneys();
  }

  @override
  Future<void> addRecord(RecordEntry record, {XFile? mediaFile}) async {
    var entry = record;
    if (mediaFile != null) {
      entry = entry.copyWith(
        mediaUrl: await MediaService.savePickedFile(
            mediaFile, record.journeyId),
      );
    }
    final me = _profile.value;
    if (me != null && entry.authorUid == null) {
      entry = entry.copyWith(
        authorUid: me.uid,
        authorName: me.displayName,
        authorAvatar: me.avatar,
      );
    }
    await _recordRepo.insert(entry);
    await _refreshRecordsOnly();
  }

  @override
  Future<void> deleteRecord(RecordEntry record) async {
    await _recordRepo.delete(record.id);
    await MediaService.deleteRelative(record.mediaUrl);
    await _refreshRecordsOnly();
  }

  @override
  Future<void> saveMilestone(Milestone milestone) async {
    await _milestoneRepo.insert(milestone);
    await _refreshMilestones();
  }

  @override
  Future<void> setMilestoneAchieved(
      String milestoneId, DateTime? when) async {
    await _milestoneRepo.setAchieved(milestoneId, when);
    await _refreshMilestones();
  }

  @override
  Future<void> deleteMilestone(String milestoneId) async {
    await _milestoneRepo.delete(milestoneId);
    await _refreshMilestones();
  }

  @override
  Future<void> placeSticker(DaySticker sticker) async {
    await _stickerRepo.upsert(sticker);
    await _refreshStickers();
  }

  @override
  Future<void> removeSticker(String journeyId, int epochDay) async {
    await _stickerRepo.remove(journeyId, epochDay);
    await _refreshStickers();
  }

  @override
  Future<String> inviteCode(String journeyId) async =>
      throw UnsupportedError(
          'Invites need cloud sync. Run flutterfire configure to enable it.');

  @override
  Future<String?> joinWithCode(String code) async => null;

  @override
  Stream<List<JourneyMember>> membersStream(String journeyId) async* {
    final me = _profile.value;
    yield [
      if (me != null)
        JourneyMember(
          uid: me.uid,
          name: me.displayName,
          avatar: me.avatar,
          role: JourneyMember.roleOwner,
        ),
    ];
  }

  @override
  Future<void> touchSeen(String journeyId) async {}

  @override
  Stream<RecapSession?> recapSessionStream(String journeyId) =>
      const Stream.empty();

  @override
  Future<void> publishRecapState(
    String journeyId, {
    required int index,
    required bool playing,
  }) async {}

  @override
  Future<File?> resolveMedia(RecordEntry record) =>
      MediaService.resolve(record.mediaUrl);

  @override
  Future<void> deleteMedia(RecordEntry record) =>
      MediaService.deleteRelative(record.mediaUrl);

  Future<void> _refreshAll() async {
    await _refreshJourneys();
    await _refreshRecordsOnly();
    await _refreshMilestones();
    await _refreshStickers();
  }

  Future<void> _refreshJourneys() async =>
      _journeys.add(await _journeyRepo.listAll());

  Future<void> _refreshRecordsOnly() async {
    final journeys = _journeys.value;
    final map = <String, List<RecordEntry>>{};
    for (final journey in journeys) {
      map[journey.id] = await _recordRepo.listForJourney(journey.id);
    }
    _records.add(map);
  }

  Future<void> _refreshMilestones() async {
    final map = <String, List<Milestone>>{};
    for (final journey in _journeys.value) {
      map[journey.id] = await _milestoneRepo.listForJourney(journey.id);
    }
    _milestones.add(map);
  }

  Future<void> _refreshStickers() async {
    final map = <String, Map<int, String>>{};
    for (final journey in _journeys.value) {
      map[journey.id] = await _stickerRepo.mapForJourney(journey.id);
    }
    _stickers.add(map);
  }
}
