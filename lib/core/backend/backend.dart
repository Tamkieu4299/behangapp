import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../models/journey.dart';
import '../models/milestone.dart';
import '../models/record_entry.dart';
import '../models/sticker.dart';

class UserProfile {
  final String uid;
  final String displayName;
  final String avatar;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.avatar,
  });
}

class JourneyMember {
  static const roleOwner = 'owner';
  static const roleEditor = 'editor';

  final String uid;
  final String name;
  final String avatar;
  final String role;
  final DateTime? lastSeenAt;

  const JourneyMember({
    required this.uid,
    required this.name,
    required this.avatar,
    this.role = roleEditor,
    this.lastSeenAt,
  });

  bool get isOwner => role == roleOwner;
}

class RecapSession {
  final int index;
  final bool playing;
  final String updatedByName;
  final DateTime updatedAt;

  const RecapSession({
    required this.index,
    required this.playing,
    required this.updatedByName,
    required this.updatedAt,
  });
}

abstract class Backend {
  bool get isCloud;

  Future<void> init();

  Stream<UserProfile?> get profileStream;
  Future<UserProfile> signIn({
    required String email,
    required String password,
    required String displayName,
    required String avatar,
    required bool createAccount,
  });
  Future<void> updateUserProfile(UserProfile profile);
  Future<void> signOut();

  Stream<List<Journey>> get journeysStream;
  Future<void> createJourney(Journey journey);
  Future<void> deleteJourney(String journeyId);
  Future<void> setReminder(String journeyId, int? hour, int? minute);

  Stream<Map<String, List<RecordEntry>>> get recordsByJourneyStream;
  Future<void> addRecord(
    RecordEntry record, {
    XFile? mediaFile,
    double? videoTrimSeconds,
  });
  Future<void> deleteRecord(RecordEntry record);

  Stream<Map<String, List<Milestone>>> get milestonesByJourneyStream;
  Future<void> saveMilestone(Milestone milestone);
  Future<void> setMilestoneAchieved(String milestoneId, DateTime? when);
  Future<void> deleteMilestone(String milestoneId);

  Stream<Map<String, Map<int, String>>> get stickersByJourneyStream;
  Future<void> placeSticker(DaySticker sticker);
  Future<void> removeSticker(String journeyId, int epochDay);

  Future<String> inviteCode(String journeyId);
  Future<String?> joinWithCode(String code);
  Stream<List<JourneyMember>> membersStream(String journeyId);
  Future<void> touchSeen(String journeyId);

  Stream<RecapSession?> recapSessionStream(String journeyId);
  Future<void> publishRecapState(
    String journeyId, {
    required int index,
    required bool playing,
  });

  Future<File?> resolveMedia(RecordEntry record);
  Future<File?> resolveMediaKey(String key);
  Future<void> deleteMedia(RecordEntry record);

  String? get currentUserId => null;
}
