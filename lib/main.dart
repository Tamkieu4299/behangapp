import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'app_state.dart';
import 'core/backend/backend.dart';
import 'core/backend/cloud_backend.dart';
import 'core/backend/local_backend.dart';
import 'core/backend/media_store.dart';
import 'core/db/app_database.dart';
import 'core/services/notification_service.dart';

const _mediaStore = String.fromEnvironment('MEDIA_STORE', defaultValue: 'firebase');
const _uploadApi = String.fromEnvironment('UPLOAD_API', defaultValue: 'http://localhost:9010');

MediaStore _buildMediaStore() {
  switch (_mediaStore) {
    case 'minio':
      return MinioMediaStore(baseUrl: _uploadApi);
    case 'firebase':
    default:
      return FirebaseMediaStore();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.instance();
  Backend backend = LocalBackend(db);
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      final cloud = CloudBackend(mediaStore: _buildMediaStore());
      await cloud.init();
      backend = cloud;
    } catch (_) {}
  }
  final state = AppState();
  await state.init(backend);
  unawaited(NotificationService.init().catchError((_) {}));
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const BehangApp(),
    ),
  );
}
