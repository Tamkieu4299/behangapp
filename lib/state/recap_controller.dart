import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/backend/backend.dart';
import '../core/models/milestone.dart';
import '../core/models/record_entry.dart';
import '../core/services/app_settings.dart';
import '../core/services/reel_api.dart';
import '../core/utils/dates.dart' as dates;
import 'journey_controller.dart';
import 'timeline_controller.dart';

/// Controls the recap experience: interactive day-by-day preview vs. the
/// auto-compiled reel, watch-together session sync, home-feed reel previews,
/// and server-side reel compilation (PRD Features 04/05/06/07).
class RecapController extends ChangeNotifier {
  RecapController(this.backend, this.timeline, this.journeys, {this.reelApi});

  final Backend backend;
  final TimelineController timeline;
  final JourneyController journeys;
  final ReelApi? reelApi;

  /// True when the server-side FFmpeg worker is wired up (cloud mode).
  bool get reelAvailable => reelApi != null && backend.isCloud;

  double _clipSeconds = 1.0;
  double get clipSeconds => _clipSeconds;

  // Watch-together session.
  bool together = false;
  RecapSession? session;
  StreamSubscription? _sessionSub;
  DateTime _lastRemoteUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  // Reel compilation.
  bool compiling = false;
  double reelProgress = 0;
  String? reelFile;
  String? _reelJourney;
  String _reelSignature = '';

  // Home-feed preview reel.
  bool previewBuilding = false;
  String? previewFile;
  String? _previewJourney;
  String _previewSignature = '';

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }

  Future<void> refreshClipSeconds() async {
    _clipSeconds = await AppSettings.loadClipSeconds();
    notifyListeners();
  }

  String get _myName => journeys.profile?.displayName ?? '';

  void startWatchingTogether(String journeyId) {
    together = true;
    _sessionSub?.cancel();
    _sessionSub =
        backend.recapSessionStream(journeyId).listen((session) {
      if (session == null) return;
      if (session.updatedAt.isBefore(_lastRemoteUpdate)) return;
      if (_myName.isNotEmpty &&
          session.updatedByName == _myName &&
          DateTime.now().difference(session.updatedAt).inSeconds < 5) {
        return;
      }
      _lastRemoteUpdate = session.updatedAt;
      this.session = session;
      notifyListeners();
    });
    notifyListeners();
  }

  void stopWatchingTogether() {
    together = false;
    _sessionSub?.cancel();
    _sessionSub = null;
    session = null;
    notifyListeners();
  }

  Future<void> publishSession(
    String journeyId, {
    required int index,
    required bool playing,
  }) async {
    if (!together) return;
    await backend.publishRecapState(
      journeyId,
      index: index,
      playing: playing,
    );
  }

  String _recordsSignature(String journeyId, {int limit = 0}) {
    final records = timeline.recordsOf(journeyId);
    if (records.isEmpty) return 'empty';
    final sub = limit <= 0 ? records : records.take(limit).toList();
    return '${sub.length}:${sub.first.id}:${sub.last.id}:$_clipSeconds';
  }

  int? _dayNumber(RecordEntry entry) =>
      journeys.journey(entry.journeyId)?.dayNumberOn(entry.timestamp);

  /// Milestone caption burned for the day of a given record, if any.
  String? _milestoneTitleFor(RecordEntry entry) {
    final day = dates.epochDay(entry.timestamp);
    for (final milestone in timeline.milestonesOf(entry.journeyId)) {
      if (milestone.achievedAt != null &&
          dates.epochDay(milestone.achievedAt!) == day) {
        return milestone.title;
      }
      if (milestone.targetDate != null &&
          dates.epochDay(milestone.targetDate!) == day) {
        return milestone.title;
      }
    }
    return null;
  }

  /// Translates media records in chronological order into worker segment
  /// specs (clipped to [clipSeconds] each, "Day N" + milestone burned in).
  List<ReelEntrySpec> _specsFor(List<RecordEntry> records) => records
      .where((r) => r.hasMedia && r.mediaType != MediaType.none)
      .map(
        (record) => ReelEntrySpec(
          recordId: record.id,
          dayNumber: _dayNumber(record) ?? 1,
          mediaKey: record.mediaUrl!,
          isVideo: record.mediaType == MediaType.video,
          duration: _clipSeconds,
          milestoneTitle: _milestoneTitleFor(record),
        ),
      )
      .toList();

  Future<File?> _downloadReel(String outputKey) =>
      backend.resolveMediaKey(outputKey);

  /// Badge icons for milestones on a given record's day (stories overlay).
  List<String> milestoneBadgesFor(RecordEntry entry) {
    final day = dates.epochDay(entry.timestamp);
    final badges = <String>[];
    for (final milestone in timeline.milestonesOf(entry.journeyId)) {
      if (milestone.achievedAt != null &&
          dates.epochDay(milestone.achievedAt!) == day) {
        badges.add(milestone.badgeIcon);
      }
    }
    return badges;
  }

  List<Milestone> milestonesOn(String journeyId, int epochDay) =>
      timeline
          .milestonesOf(journeyId)
          .where((m) =>
              (m.achievedAt != null &&
                  dates.epochDay(m.achievedAt!) == epochDay) ||
              (m.targetDate != null &&
                  dates.epochDay(m.targetDate!) == epochDay))
          .toList();

  /// Compiles (or reuses a cached) `journey_recap.mp4` for the journey,
  /// on the server-side FFmpeg worker. Returns null when the worker is
  /// unavailable or there is nothing to stitch.
  Future<File?> compileJourneyReel(String journeyId) async {
    final signature = _recordsSignature(journeyId);
    if (reelFile != null &&
        _reelJourney == journeyId &&
        _reelSignature == signature) {
      return File(reelFile!);
    }
    final worker = reelApi;
    if (worker == null) return null;

    final records = timeline
        .recordsOf(journeyId)
        .where((r) => r.hasMedia && r.mediaType != MediaType.none)
        .toList();
    if (records.isEmpty) return null;

    final specs = _specsFor(records);
    if (specs.isEmpty) return null;

    compiling = true;
    reelProgress = 0;
    notifyListeners();
    try {
      final outputKey = await worker.buildReel(
        journeyId: journeyId,
        entries: specs,
        watermark: true,
        outputKey: 'reels/$journeyId/recap_${_clipSeconds.toStringAsFixed(1)}s.mp4',
      );
      final reel = await _downloadReel(outputKey);
      if (reel == null) return null;
      reelProgress = 1;
      reelFile = reel.path;
      _reelJourney = journeyId;
      _reelSignature = signature;
      return reel;
    } finally {
      compiling = false;
      notifyListeners();
    }
  }

  /// 3-second preview reel for the home feed (PRD Feature 04). Uses the
  /// latest up-to-3 media records, no watermark, and is cached per signature.
  Future<File?> compilePreviewReel(String journeyId) async {
    const limit = 3;
    final signature = _recordsSignature(journeyId, limit: limit);
    if (previewFile != null &&
        _previewJourney == journeyId &&
        _previewSignature == signature) {
      return File(previewFile!);
    }
    final worker = reelApi;
    if (worker == null) return null;

    final records = timeline
        .recordsOf(journeyId)
        .where((r) => r.hasMedia && r.mediaType != MediaType.none)
        .take(limit)
        .toList();
    if (records.isEmpty) return null;

    final specs = _specsFor(records);
    if (specs.isEmpty) return null;

    previewBuilding = true;
    notifyListeners();
    try {
      final outputKey = await worker.buildReel(
        journeyId: journeyId,
        entries: specs,
        watermark: false,
        outputKey: 'reels/$journeyId/preview_${_clipSeconds.toStringAsFixed(1)}s.mp4',
      );
      final reel = await _downloadReel(outputKey);
      if (reel == null) return null;
      previewFile = reel.path;
      _previewJourney = journeyId;
      _previewSignature = signature;
      return reel;
    } finally {
      previewBuilding = false;
      notifyListeners();
    }
  }

  void clearReelCache() {
    reelFile = null;
    _reelJourney = null;
    _reelSignature = '';
  }

  void clearPreviewCache() {
    previewFile = null;
    _previewJourney = null;
    _previewSignature = '';
  }
}