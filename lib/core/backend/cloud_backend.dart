import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../models/journey.dart';
import '../models/milestone.dart';
import '../models/record_entry.dart';
import '../models/sticker.dart';
import '../services/media_service.dart';
import '../services/reel_api.dart';
import 'backend.dart';
import 'media_store.dart';
import 'value_stream.dart';

class CloudBackend implements Backend {
  CloudBackend({MediaStore? mediaStore, this.reelApi})
      : mediaStore = mediaStore ?? FirebaseMediaStore();

  @override
  bool get isCloud => true;

  final MediaStore mediaStore;
  final ReelApi? reelApi;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  final ValueStream<UserProfile?> _profile = ValueStream<UserProfile?>(null);
  final ValueStream<List<Journey>> _journeys =
      ValueStream<List<Journey>>(const []);
  final ValueStream<Map<String, List<RecordEntry>>> _records =
      ValueStream<Map<String, List<RecordEntry>>>(const {});
  final ValueStream<Map<String, List<Milestone>>> _milestones =
      ValueStream<Map<String, List<Milestone>>>(const {});
  final ValueStream<Map<String, Map<int, String>>> _stickers =
      ValueStream<Map<String, Map<int, String>>>(const {});
  final ValueStream<Map<String, List<JourneyMember>>> _members =
      ValueStream<Map<String, List<JourneyMember>>>(const {});

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _journeysSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  final Map<String, StreamSubscription> _dataSubs = {};

  String? get _uid => _auth.currentUser?.uid;

  @override
  Future<void> init() async {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
    final user = _auth.currentUser;
    if (user != null) await _onAuthChanged(user);
  }

  Future<void> _onAuthChanged(User? user) async {
    if (user == null) {
      _profile.add(null);
      await _teardown();
      return;
    }
    await _subscribeProfile(user);
    _subscribeJourneys();
  }

  Future<void> _subscribeProfile(User user) async {
    await _profileSub?.cancel();
    final docRef = _fs.collection('users').doc(user.uid);
    final snap = await docRef.get();
    if (!snap.exists) {
      await docRef.set({
        'displayName': user.displayName ?? 'Traveler',
        'avatar': '🌱',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    _profileSub = docRef.snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      _profile.add(UserProfile(
        uid: user.uid,
        displayName: (data['displayName'] as String?) ?? 'Traveler',
        avatar: (data['avatar'] as String?) ?? '🌱',
      ));
    });
  }

  void _subscribeJourneys() {
    final uid = _uid;
    if (uid == null) return;
    _journeysSub?.cancel();
    _journeysSub = _fs
        .collection('journeys')
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
      final journeys = <Journey>[];
      final seenIds = <String>{};
      for (final doc in snapshot.docs) {
        seenIds.add(doc.id);
        journeys.add(_journeyFromDoc(doc));
      }
      for (final existing in _dataSubs.keys.toList()) {
        final jid = existing.split('::').first;
        if (!seenIds.contains(jid)) {
          _dataSubs.remove(existing)?.cancel();
        }
      }
      for (final journey in journeys) {
        if (!_dataSubs.containsKey('${journey.id}::records')) {
          _listenJourneyData(journey.id);
        }
      }
      _journeys.add(journeys);
    });
  }

  void _listenJourneyData(String journeyId) {
    _dataSubs['$journeyId::records'] =
        _recordsRef(journeyId).snapshots().listen((snapshot) {
      final list = snapshot.docs.map(_recordFromDoc).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _records.add(Map.of(_records.value)..[journeyId] = list);
    });
    _dataSubs['$journeyId::milestones'] = _fs
        .collection('journeys')
        .doc(journeyId)
        .collection('milestones')
        .snapshots()
        .listen((snapshot) {
      final list = snapshot.docs.map(_milestoneFromDoc).toList();
      _milestones.add(Map.of(_milestones.value)..[journeyId] = list);
    });
    _dataSubs['$journeyId::stickers'] = _fs
        .collection('journeys')
        .doc(journeyId)
        .collection('stickers')
        .snapshots()
        .listen((snapshot) {
      final map = <int, String>{};
      for (final doc in snapshot.docs) {
        map[int.parse(doc.id)] = (doc.data()['emoji'] as String?) ?? '✨';
      }
      _stickers.add(Map.of(_stickers.value)..[journeyId] = map);
    });
    _dataSubs['$journeyId::members'] = _fs
        .collection('journeys')
        .doc(journeyId)
        .collection('members')
        .snapshots()
        .listen((snapshot) {
      final list = snapshot.docs.map(_memberFromDoc).toList()
        ..sort((a, b) {
          if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      _members.add(Map.of(_members.value)..[journeyId] = list);
    });
  }

  Future<void> _teardown() async {
    await _journeysSub?.cancel();
    _journeysSub = null;
    for (final sub in _dataSubs.values) {
      await sub.cancel();
    }
    _dataSubs.clear();
    _journeys.add(const []);
    _records.add(const {});
    _milestones.add(const {});
    _stickers.add(const {});
    _members.add(const {});
  }

  CollectionReference<Map<String, dynamic>> _recordsRef(String jid) =>
      _fs.collection('journeys').doc(jid).collection('records');

  Journey _journeyFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Journey(
      id: doc.id,
      userId: (d['createdBy'] as String?) ?? '',
      title: (d['title'] as String?) ?? 'Untitled',
      category: JourneyCategory.values.firstWhere(
        (c) => c.name == (d['category'] as String?),
        orElse: () => JourneyCategory.other,
      ),
      goal: d['goal'] as String?,
      startDate: DateTime.fromMillisecondsSinceEpoch(d['startDate'] as int),
      durationDays: d['durationDays'] as int?,
      reminderHour: d['reminderHour'] as int?,
      reminderMinute: d['reminderMinute'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(d['createdAt'] as int),
    );
  }

  RecordEntry _recordFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return RecordEntry(
      id: doc.id,
      journeyId: d['journeyId'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(d['timestamp'] as int),
      mediaType: mediaTypeFromName(d['mediaType'] as String?),
      mediaUrl: d['mediaPath'] as String?,
      note: d['note'] as String?,
      authorUid: d['authorUid'] as String?,
      authorName: d['authorName'] as String?,
      authorAvatar: d['authorAvatar'] as String?,
    );
  }

  Milestone _milestoneFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return Milestone(
      id: doc.id,
      journeyId: d['journeyId'] as String? ?? '',
      title: (d['title'] as String?) ?? '',
      targetDate: d['targetDate'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(d['targetDate'] as int),
      achievedAt: d['achievedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(d['achievedAt'] as int),
      badgeIcon: (d['badgeIcon'] as String?) ?? '🏅',
    );
  }

  JourneyMember _memberFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return JourneyMember(
      uid: doc.id,
      name: (d['name'] as String?) ?? 'Traveler',
      avatar: (d['avatar'] as String?) ?? '🌱',
      role: (d['role'] as String?) ?? JourneyMember.roleEditor,
      lastSeenAt: d['lastSeenAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(d['lastSeenAt'] as int),
    );
  }

  String _randomCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final random = DateTime.now().microsecondsSinceEpoch;
    var seed = random;
    return String.fromCharCodes(List.generate(6, (i) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return chars.codeUnitAt(seed % chars.length);
    }));
  }

  UserProfile? get _me => _profile.value;

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
    if (createAccount) {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _fs.collection('users').doc(cred.user!.uid).set({
        'displayName': displayName.trim().isEmpty
            ? 'Traveler'
            : displayName.trim(),
        'avatar': avatar,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    }
    final me = _me;
    if (me != null) return me;
    throw StateError('Sign-in did not complete');
  }

  @override
  Future<void> updateUserProfile(UserProfile profile) async {
    final uid = _uid;
    if (uid == null) return;
    await _fs.collection('users').doc(uid).set({
      'displayName': profile.displayName,
      'avatar': profile.avatar,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> signOut() => _auth.signOut();

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

  Stream<List<JourneyMember>> membersOf(String journeyId) async* {
    yield _members.value[journeyId] ?? const [];
    await for (final all in _members.watch()) {
      yield all[journeyId] ?? const [];
    }
  }

  @override
  Stream<List<JourneyMember>> membersStream(String journeyId) =>
      membersOf(journeyId);

  @override
  Future<void> createJourney(Journey journey) async {
    final uid = _uid!;
    final code = _randomCode();
    final journeyRef = _fs.collection('journeys').doc(journey.id);
    final batch = _fs.batch();
    batch.set(journeyRef, {
      'title': journey.title,
      'category': journey.category.name,
      'goal': journey.goal,
      'startDate': journey.startDate.millisecondsSinceEpoch,
      'durationDays': journey.durationDays,
      'reminderHour': journey.reminderHour,
      'reminderMinute': journey.reminderMinute,
      'createdBy': uid,
      'inviteCode': code,
      'memberIds': [uid],
      'createdAt': journey.createdAt.millisecondsSinceEpoch,
      'lastActivityAt': DateTime.now().millisecondsSinceEpoch,
    });
    batch.set(
        journeyRef.collection('members').doc(uid),
        _memberMap(JourneyMember(
          uid: uid,
          name: _me?.displayName ?? 'Traveler',
          avatar: _me?.avatar ?? '🌱',
          role: JourneyMember.roleOwner,
        )));
    batch.set(_fs.collection('invites').doc(code), {'journeyId': journey.id});
    // All writes commit atomically; the members/{uid} rule below uses
    // getAfter() so the owner bootstrap is allowed within this same batch.
    await batch.commit();
  }

  Map<String, Object?> _memberMap(JourneyMember member) => {
        'name': member.name,
        'avatar': member.avatar,
        'role': member.role,
        'joinedAt': DateTime.now().millisecondsSinceEpoch,
        if (member.lastSeenAt != null)
          'lastSeenAt': member.lastSeenAt!.millisecondsSinceEpoch,
      };

  @override
  Future<void> deleteJourney(String journeyId) async {
    final journeyRef = _fs.collection('journeys').doc(journeyId);
    for (final collection in ['records', 'milestones', 'stickers', 'members']) {
      final docs = await journeyRef.collection(collection).get();
      for (final doc in docs.docs) {
        await doc.reference.delete();
      }
    }
    final inviteSnap = await _fs
        .collection('invites')
        .where('journeyId', isEqualTo: journeyId)
        .get();
    for (final doc in inviteSnap.docs) {
      await doc.reference.delete();
    }
    await journeyRef.delete();
  }

  @override
  Future<void> setReminder(String journeyId, int? hour, int? minute) =>
      _fs.collection('journeys').doc(journeyId).set({
        'reminderHour': hour,
        'reminderMinute': minute,
      }, SetOptions(merge: true));

  @override
  Future<void> addRecord(
    RecordEntry record, {
    XFile? mediaFile,
    double? videoTrimSeconds,
  }) async {
    final entry = record.copyWith(
      authorUid: record.authorUid ?? _me?.uid,
      authorName: record.authorName ?? _me?.displayName,
      authorAvatar: record.authorAvatar ?? _me?.avatar,
    );
    String? mediaPath = entry.mediaUrl;
    if (mediaFile != null) {
      final ext = p.extension(mediaFile.path);
      final uploaded = await mediaStore.upload(
        journeyId: entry.journeyId,
        id: entry.id,
        extension: ext,
        file: mediaFile,
      );
      if (uploaded == null) {
        throw Exception('Media upload did not return a path');
      }
      mediaPath = uploaded;
      // Server-side clip trim (PRD Feature 03): the stored daily clip is
      // shortened to the configured length. Falls back to the raw clip when
      // the worker is unreachable.
      if (videoTrimSeconds != null && entry.mediaType == MediaType.video) {
        final worker = reelApi;
        if (worker != null) {
          try {
            final trimmed = await worker.trimVideo(
              mediaKey: uploaded,
              seconds: videoTrimSeconds,
            );
            if (trimmed.isNotEmpty && trimmed != uploaded) {
              await mediaStore.delete(uploaded);
              mediaPath = trimmed;
            }
          } catch (_) {}
        }
      }
    }
    await _recordsRef(entry.journeyId).doc(entry.id).set({
      'journeyId': entry.journeyId,
      'timestamp': entry.timestamp.millisecondsSinceEpoch,
      'mediaType': entry.mediaType.name,
      'mediaPath': mediaPath,
      'note': entry.note,
      'authorUid': entry.authorUid,
      'authorName': entry.authorName,
      'authorAvatar': entry.authorAvatar,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _fs.collection('journeys').doc(entry.journeyId).set({
      'lastActivityAt': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteRecord(RecordEntry record) async {
    await _recordsRef(record.journeyId).doc(record.id).delete();
    await deleteMedia(record);
  }

  @override
  Future<void> saveMilestone(Milestone milestone) =>
      _fs
          .collection('journeys')
          .doc(milestone.journeyId)
          .collection('milestones')
          .doc(milestone.id)
          .set({
        'journeyId': milestone.journeyId,
        'title': milestone.title,
        'targetDate': milestone.targetDate?.millisecondsSinceEpoch,
        'achievedAt': milestone.achievedAt?.millisecondsSinceEpoch,
        'badgeIcon': milestone.badgeIcon,
      });

  @override
  Future<void> setMilestoneAchieved(String milestoneId, DateTime? when) async {
    final ownerJourneys =
        _journeys.value.where((j) => _ownsMilestone(j.id, milestoneId));
    for (final journey in ownerJourneys) {
      await _fs
          .collection('journeys')
          .doc(journey.id)
          .collection('milestones')
          .doc(milestoneId)
          .set({'achievedAt': when?.millisecondsSinceEpoch},
              SetOptions(merge: true));
      return;
    }
  }

  bool _ownsMilestone(String journeyId, String milestoneId) =>
      (_milestones.value[journeyId] ?? [])
          .any((m) => m.id == milestoneId);

  @override
  Future<void> deleteMilestone(String milestoneId) async {
    for (final journey in _journeys.value) {
      final exists = _ownsMilestone(journey.id, milestoneId);
      if (!exists) continue;
      await _fs
          .collection('journeys')
          .doc(journey.id)
          .collection('milestones')
          .doc(milestoneId)
          .delete();
      return;
    }
  }

  @override
  Future<void> placeSticker(DaySticker sticker) => _fs
      .collection('journeys')
      .doc(sticker.journeyId)
      .collection('stickers')
      .doc('${sticker.epochDay}')
      .set({'emoji': sticker.emoji});

  @override
  Future<void> removeSticker(String journeyId, int epochDay) => _fs
      .collection('journeys')
      .doc(journeyId)
      .collection('stickers')
      .doc('$epochDay')
      .delete();

  @override
  Future<String> inviteCode(String journeyId) async {
    final snap = await _fs.collection('journeys').doc(journeyId).get();
    final existing = snap.data()?['inviteCode'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final code = _randomCode();
    await _fs.collection('journeys').doc(journeyId).set(
      {'inviteCode': code},
      SetOptions(merge: true),
    );
    await _fs
        .collection('invites')
        .doc(code)
        .set({'journeyId': journeyId});
    return code;
  }

  @override
  Future<String?> joinWithCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length != 6) return null;
    final inviteSnap = await _fs.collection('invites').doc(code).get();
    final journeyId = inviteSnap.data()?['journeyId'] as String?;
    if (journeyId == null) return null;
    final journeySnap =
        await _fs.collection('journeys').doc(journeyId).get();
    if (!journeySnap.exists) return null;
    final uid = _uid!;
    await _fs.collection('journeys').doc(journeyId).set({
      'memberIds': FieldValue.arrayUnion([uid]),
    }, SetOptions(merge: true));
    await _fs
        .collection('journeys')
        .doc(journeyId)
        .collection('members')
        .doc(uid)
        .set(_memberMap(JourneyMember(
          uid: uid,
          name: _me?.displayName ?? 'Traveler',
          avatar: _me?.avatar ?? '🌱',
        )), SetOptions(merge: true));
    return journeyId;
  }

  @override
  Future<void> touchSeen(String journeyId) async {
    final uid = _uid;
    if (uid == null) return;
    await _fs
        .collection('journeys')
        .doc(journeyId)
        .collection('members')
        .doc(uid)
        .set({
      'lastSeenAt': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
  }

  @override
  Stream<RecapSession?> recapSessionStream(String journeyId) => _fs
      .collection('journeys')
      .doc(journeyId)
      .collection('recap')
      .doc('main')
      .snapshots()
      .map((snap) {
    final d = snap.data();
    if (d == null || !snap.exists) return null;
    return RecapSession(
      index: (d['index'] as num?)?.toInt() ?? 0,
      playing: (d['playing'] as bool?) ?? false,
      updatedByName: (d['updatedByName'] as String?) ?? '',
      updatedAt: d['updatedAt'] == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(d['updatedAt'] as int),
    );
  });

  @override
  Future<void> publishRecapState(
    String journeyId, {
    required int index,
    required bool playing,
  }) =>
      _fs
          .collection('journeys')
          .doc(journeyId)
          .collection('recap')
          .doc('main')
          .set({
        'index': index,
        'playing': playing,
        'updatedByName': _me?.displayName ?? 'Someone',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Future<File?> resolveMedia(RecordEntry record) async {
    final path = record.mediaUrl;
    if (path == null || path.isEmpty) return null;
    if (!path.startsWith('journeys/')) {
      return MediaService.resolve(path);
    }
    return mediaStore.resolve(path);
  }

  @override
  Future<File?> resolveMediaKey(String key) async {
    if (key.isEmpty) return null;
    if (!key.startsWith('journeys/') && !key.startsWith('reels/')) {
      return MediaService.resolve(key);
    }
    return mediaStore.resolve(key);
  }

  @override
  Future<void> deleteMedia(RecordEntry record) async {
    final path = record.mediaUrl;
    if (path == null || !path.startsWith('journeys/')) return;
    try {
      await mediaStore.delete(path);
    } catch (_) {}
  }

  @override
  String? get currentUserId => _uid;

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _profileSub?.cancel();
    await _teardown();
  }
}
