import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/backend/backend.dart';
import 'core/backend/cloud_backend.dart';
import 'core/backend/local_backend.dart';
import 'core/backend/media_store.dart';
import 'core/db/app_database.dart';
import 'core/services/notification_service.dart';
import 'core/services/reel_api.dart';
import 'state/journey_controller.dart';
import 'state/recap_controller.dart';
import 'state/timeline_controller.dart';

const _mediaStore = String.fromEnvironment('MEDIA_STORE', defaultValue: 'firebase');
const _uploadApi = String.fromEnvironment('UPLOAD_API', defaultValue: 'http://localhost:9010');
const _reelApi = String.fromEnvironment('REEL_API', defaultValue: 'http://localhost:9011');

MediaStore _buildMediaStore() {
  switch (_mediaStore) {
    case 'minio':
      return MinioMediaStore(baseUrl: _uploadApi);
    case 'firebase':
    default:
      return FirebaseMediaStore();
  }
}

ReelApi? _buildReelApi() {
  const value = _reelApi;
  return value.isEmpty ? null : ReelApi(baseUrl: value);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.instance();
  Backend backend = LocalBackend(db);
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      final reel = _buildReelApi();
      final cloud = CloudBackend(mediaStore: _buildMediaStore(), reelApi: reel);
      await cloud.init();
      backend = cloud;
    } catch (_) {}
  }
  final journeys = JourneyController(backend);
  final timeline = TimelineController(backend, journeys);
  final recap = RecapController(
    backend,
    timeline,
    journeys,
    reelApi: _buildReelApi(),
  );
  await journeys.init();
  await timeline.init();
  unawaited(NotificationService.init().catchError((_) {}));
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: journeys),
        ChangeNotifierProvider.value(value: timeline),
        ChangeNotifierProvider.value(value: recap),
      ],
      child: const BehangApp(),
    ),
  );
}
