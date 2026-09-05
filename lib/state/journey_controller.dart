import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../core/backend/backend.dart';
import '../core/models/journey.dart';
import '../core/services/notification_service.dart';

/// Focused controller for the signed-in user, their profile and the journeys
/// they belong to (including collaborative members and invite flows).
class JourneyController extends ChangeNotifier {
  JourneyController(this.backend);

  final Backend backend;

  bool get cloudReady => backend.isCloud;

  UserProfile? profile;

  List<Journey> _journeys = [];
  final Map<String, List<JourneyMember>> _members = {};
  final List<StreamSubscription> _subs = [];
  final Map<String, StreamSubscription> _memberSubs = {};

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    for (final sub in _memberSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> init() async {
    await backend.init();
    _subs.add(backend.profileStream.listen((profile) {
      this.profile = profile;
      notifyListeners();
    }));
    _subs.add(backend.journeysStream.listen((journeys) {
      _journeys = journeys;
      _pruneMemberSubs();
      notifyListeners();
    }));
  }

  void _pruneMemberSubs() {
    final active = _journeys.map((j) => j.id).toSet();
    for (final jid in _memberSubs.keys.toList()) {
      if (!active.contains(jid)) {
        _memberSubs.remove(jid)?.cancel();
        _members.remove(jid);
      }
    }
  }

  List<Journey> get journeyList => List.unmodifiable(_journeys);

  Journey? journey(String id) {
    for (final journey in _journeys) {
      if (journey.id == id) return journey;
    }
    return null;
  }

  String? get myUid => backend.currentUserId ?? profile?.uid;

  List<JourneyMember> membersOf(String journeyId) =>
      _members[journeyId] ?? const [];

  void subscribeMembers(String journeyId) {
    if (_memberSubs.containsKey(journeyId)) return;
    _memberSubs[journeyId] = backend.membersStream(journeyId).listen((members) {
      _members[journeyId] = members;
      notifyListeners();
    });
  }

  Future<void> refresh() async {
    notifyListeners();
  }

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

  Future<String> inviteCode(String journeyId) => backend.inviteCode(journeyId);

  Future<String?> joinWithCode(String code) => backend.joinWithCode(code);

  Future<void> touchSeen(String journeyId) => backend.touchSeen(journeyId);
}