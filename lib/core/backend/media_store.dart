import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Pluggable media storage. In production the app uses [FirebaseMediaStore]
/// (Firebase Storage); during development it can use [MinioMediaStore] (local
/// MinIO/S3) to avoid requiring a paid Firebase plan. Keys are identical
/// (`journeys/<journeyId>/<recordId>.<ext>`), so switching costs one line.
abstract class MediaStore {
  Future<String?> upload({
    required String journeyId,
    required String id,
    required String extension,
    required XFile file,
  });

  Future<File?> resolve(String key);

  Future<void> delete(String key);
}

class FirebaseMediaStore implements MediaStore {
  FirebaseStorage get _storage => FirebaseStorage.instance;

  @override
  Future<String?> upload({
    required String journeyId,
    required String id,
    required String extension,
    required XFile file,
  }) async {
    final ref = _storage.ref('journeys/$journeyId/$id$extension');
    await ref.putFile(File(file.path));
    return ref.fullPath;
  }

  @override
  Future<File?> resolve(String key) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(docs.path, 'cloud_cache'));
      await cacheDir.create(recursive: true);
      final cacheFile = File(p.join(cacheDir.path, p.basename(key)));
      if (await cacheFile.exists()) return cacheFile;
      final bytes = await _storage.ref(key).getData(100 * 1024 * 1024);
      if (bytes == null) return null;
      await cacheFile.writeAsBytes(bytes, flush: true);
      return cacheFile;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.ref(key).delete();
    } catch (_) {}
  }
}

class MinioMediaStore implements MediaStore {
  MinioMediaStore({required this.baseUrl});

  final String baseUrl;

  String _contentType(String extension) {
    switch (extension.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.heic':
        return 'image/heic';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.m4v':
        return 'video/x-m4v';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Future<String?> upload({
    required String journeyId,
    required String id,
    required String extension,
    required XFile file,
  }) async {
    final key = 'journeys/$journeyId/$id$extension';
    final response = await http.post(
      Uri.parse('$baseUrl/presign/upload'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'key': key, 'content_type': _contentType(extension)}),
    );
    if (response.statusCode != 200) return null;
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final put = await http.put(
      Uri.parse(payload['url'] as String),
      headers: {'Content-Type': payload['content_type'] as String},
      body: await file.readAsBytes(),
    );
    if (put.statusCode != 200 && put.statusCode != 201) return null;
    return key;
  }

  @override
  Future<File?> resolve(String key) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(docs.path, 'cloud_cache'));
      await cacheDir.create(recursive: true);
      final cacheFile = File(p.join(cacheDir.path, p.basename(key)));
      if (await cacheFile.exists()) return cacheFile;
      final signed = await http.get(
        Uri.parse(
            '$baseUrl/presign/download?key=${Uri.encodeComponent(key)}'),
      );
      if (signed.statusCode != 200) return null;
      final url = (jsonDecode(signed.body) as Map<String, dynamic>)['url']
          as String;
      final bytes = await http.get(Uri.parse(url));
      if (bytes.statusCode != 200) return null;
      await cacheFile.writeAsBytes(bytes.bodyBytes, flush: true);
      return cacheFile;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      final signed = await http.get(
        Uri.parse('$baseUrl/presign/delete?key=${Uri.encodeComponent(key)}'),
      );
      if (signed.statusCode != 200) return;
      final url = (jsonDecode(signed.body) as Map<String, dynamic>)['url']
          as String;
      await http.delete(Uri.parse(url));
    } catch (_) {}
  }
}