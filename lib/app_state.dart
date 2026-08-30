import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'core/backend/backend.dart';
import 'core/models/journey.dart';
import 'core/models/milestone.dart';
import 'core/models/record_entry.dart';
import 'core/models/sticker.dart';
import 'core/services/notification_service.dart';
import 'core/services/streak_engine.dart';

class AppState extends ChangeNotifier {
  Backend? _backend;

  Backend get backend => _backend!;

  bool get cloudReady => _backend?.isCloud ?? false;

  UserProfile? profile;
  List<Journey> _journeys = [];
  Map<String, List<RecordEntry>> _recordsByJourney = {};
  Map<String, List<Milestone>> _milestonesByJourney = {};
  Map<String, Map<int, String>> _stickersByJourney = {};
  final Map<String, List<JourneyMember>> _membersByJourney = {};
  Map<String, RecordEntry> latestByJourney = {};
  Map<String, int> counts = {};
  Map<String, StreakStats> streaks = {};

  List<Journey> get journeyList => List.unmodifiable(_journeys);

  Future<void> refresh() async {
    notifyListeners();
  }

  Future<void> init(Backend backend) async {
    _backend = backend;
    await backend.init();
    backend.profileStream.listen((profile) {
      this.profile = profile;
      notifyListeners();
    });
    backend.journeysStream.listen((journeys) {
      _journeys = journeys;
      _recompute();
      notifyListeners();
    });
    backend.recordsByJourneyStream.listen((records) {
      _recordsByJourney = records;
      _recompute();
      notifyListeners();
    });
    backend.milestonesByJourneyStream.listen((milestones) {
      _milestonesByJourney = milestones;
      notifyListeners();
    });
    backend.stickersByJourneyStream.listen((stickers) {
      _stickersByJourney = stickers;
      notifyListeners();
    });
    notifyListeners();
  }

  void _recompute() {
    latestByJourney = {};
    counts = {};
    streaks = {};
    for (final journey in _journeys) {
      final entries = recordsOf(journey.id);
      counts[journey.id] = entries.length;
      streaks[journey.id] =
          StreakEngine.compute(entries.map((e) => e.timestamp));
      if (entries.isNotEmpty) latestByJourney[journey.id] = entries.first;
    }
  }

  Journey? journey(String id) {
    for (final journey in _journeys) {
      if (journey.id == id) return journey;
    }
    return null;
  }

  List<RecordEntry> recordsOf(String journeyId) =>
      _recordsByJourney[journeyId] ?? const [];

  List<Milestone> milestonesOf(String journeyId) =>
      _milestonesByJourney[journeyId] ?? const [];

  Map<int, String> stickersOf(String journeyId) =>
      _stickersByJourney[journeyId] ?? const {};

  List<JourneyMember> membersOf(String journeyId) =>
      _membersByJourney[journeyId] ?? const [];

  StreakStats statsOf(String journeyId) => StreakEngine.compute(
      recordsOf(journeyId).map((e) => e.timestamp));

  String? get myUid => backend.currentUserId ?? profile?.uid;

  Future<UserProfile> signIn({
    required String email,
    required String password,
    required String displayName,
    required String avatar,
    required bool createAccount,
  }) =>
      backend.signIn(
        email: email,
        password: password,
        displayName: displayName,
        avatar: avatar,
        createAccount: createAccount,
      );

  Future<void> updateProfile(UserProfile profile) =>
      backend.updateUserProfile(profile);

  Future<void> signOut() => backend.signOut();

  Future<void> createJourney(Journey journey) async {
    await backend.createJourney(journey);
    if (journey.hasReminder) {
      await NotificationService.scheduleDailyReminder(
        journeyId: journey.id,
        journeyTitle: journey.title,
        hour: journey.reminderHour!,
        minute: journey.reminderMinute!,
      );
    }
  }

  Future<void> deleteJourney(String id) async {
    await NotificationService.cancelReminder(id);
    await backend.deleteJourney(id);
  }

  Future<void> setReminder(Journey journey, TimeOfDay? time) async {
    if (time == null) {
      await NotificationService.cancelReminder(journey.id);
      await backend.setReminder(journey.id, null, null);
    } else {
      await NotificationService.scheduleDailyReminder(
        journeyId: journey.id,
        journeyTitle: journey.title,
        hour: time.hour,
        minute: time.minute,
      );
      await backend.setReminder(journey.id, time.hour, time.minute);
    }
  }

  Future<void> addRecord(RecordEntry entry, {XFile? mediaFile}) =>
      backend.addRecord(entry, mediaFile: mediaFile);

  Future<void> deleteRecord(RecordEntry entry) => backend.deleteRecord(entry);

  Future<void> placeSticker(DaySticker sticker) => backend.placeSticker(sticker);

  Future<void> removeSticker(String journeyId, int epochDay) =>
      backend.removeSticker(journeyId, epochDay);

  Future<void> saveMilestone(Milestone milestone) =>
      backend.saveMilestone(milestone);

  Future<void> achieveMilestone(Milestone milestone, DateTime when) =>
      backend.setMilestoneAchieved(milestone.id, when);

  Future<void> reopenMilestone(Milestone milestone) =>
      backend.setMilestoneAchieved(milestone.id, null);

  Future<void> deleteMilestone(String id) => backend.deleteMilestone(id);

  Future<String> inviteCode(String journeyId) => backend.inviteCode(journeyId);

  Future<String?> joinWithCode(String code) => backend.joinWithCode(code);

  Future<void> touchSeen(String journeyId) => backend.touchSeen(journeyId);

  List<RecordEntry> catchUpRecords(String journeyId) {
    final members = membersOf(journeyId);
    final me = myUid;
    final myMember = members.where((m) => m.uid == me).toList();
    final lastSeen = myMember.isEmpty ? null : myMember.first.lastSeenAt;
    return recordsOf(journeyId)
        .where((r) =>
            r.authorUid != null &&
            r.authorUid != me &&
            (lastSeen == null || r.timestamp.isAfter(lastSeen)))
        .toList();
  }

  void subscribeMembers(String journeyId) {
    backend.membersStream(journeyId).listen((members) {
      _membersByJourney[journeyId] = members;
      notifyListeners();
    });
  }
}
