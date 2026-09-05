import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/backend/backend.dart';
import '../core/models/milestone.dart';
import '../core/models/record_entry.dart';
import '../core/models/sticker.dart';
import '../core/services/streak_engine.dart';
import '../core/utils/dates.dart' as dates;
import 'journey_controller.dart';

/// Focused controller for the record timeline: all records/milestones/stickers
/// of the user's journeys, plus derived, memoized aggregation (streaks,
/// counts, latest moment) so a single record update never recomputes every
/// journey's streak from scratch.
class TimelineController extends ChangeNotifier {
  TimelineController(this.backend, this.journeys);

  final Backend backend;
  final JourneyController journeys;

  Map<String, List<RecordEntry>> _records = {};
  Map<String, List<Milestone>> _milestones = {};
  Map<String, Map<int, String>> _stickers = {};
  final Map<String, RecordEntry> _latest = {};
  final Map<String, int> _counts = {};
  final Map<String, String> _streakFingerprint = {};
  final Map<String, StreakStats> _streakCache = {};

  final List<StreamSubscription> _subs = [];

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> init() async {
    _subs.add(backend.recordsByJourneyStream.listen((records) {
      _records = records;
      _recomputeDayAggregates();
      notifyListeners();
    }));
    _subs.add(backend.milestonesByJourneyStream.listen((milestones) {
      _milestones = milestones;
      notifyListeners();
    }));
    _subs.add(backend.stickersByJourneyStream.listen((stickers) {
      _stickers = stickers;
      notifyListeners();
    }));
  }

  void _recomputeDayAggregates() {
    _latest.clear();
    _counts.clear();
    for (final journey in journeys.journeyList) {
      final entries = recordsOf(journey.id);
      _counts[journey.id] = entries.length;
      if (entries.isNotEmpty) _latest[journey.id] = entries.first;
    }
  }

  List<RecordEntry> recordsOf(String journeyId) =>
      _records[journeyId] ?? const [];

  List<Milestone> milestonesOf(String journeyId) =>
      _milestones[journeyId] ?? const [];

  Map<int, String> stickersOf(String journeyId) =>
      _stickers[journeyId] ?? const {};

  int countOf(String journeyId) => _counts[journeyId] ?? 0;

  RecordEntry? latestOf(String journeyId) => _latest[journeyId];

  /// Memoized: streaks only recompute when the set of days with records in a
  /// journey changes (not on every record write/edit).
  StreakStats statsOf(String journeyId) {
    final days = recordsOf(journeyId)
        .map((r) => dates.epochDay(r.timestamp))
        .toSet()
        .toList()
      ..sort();
    final fingerprint = days.join(',');
    final cached = _streakCache[journeyId];
    if (cached != null && _streakFingerprint[journeyId] == fingerprint) {
      return cached;
    }
    final stats = StreakEngine.compute(
      days.map(dates.fromEpochDay),
    );
    _streakFingerprint[journeyId] = fingerprint;
    _streakCache[journeyId] = stats;
    return stats;
  }

  List<RecordEntry> catchUpRecords(String journeyId) {
    final members = journeys.membersOf(journeyId);
    final me = journeys.myUid;
    final myMember = members.where((m) => m.uid == me).toList();
    final lastSeen = myMember.isEmpty ? null : myMember.first.lastSeenAt;
    return recordsOf(journeyId)
        .where((r) =>
            r.authorUid != null &&
            r.authorUid != me &&
            (lastSeen == null || r.timestamp.isAfter(lastSeen)))
        .toList();
  }

  Future<void> addRecord(RecordEntry entry, {XFile? mediaFile, double? videoTrimSeconds}) =>
      backend.addRecord(entry, mediaFile: mediaFile, videoTrimSeconds: videoTrimSeconds);

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
}