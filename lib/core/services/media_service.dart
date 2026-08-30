import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MediaService {
  MediaService._();

  static Future<String> savePickedFile(XFile picked, String journeyId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'media', journeyId));
    await dir.create(recursive: true);
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(picked.path)}';
    final savedPath = p.join(dir.path, fileName);
    await File(picked.path).copy(savedPath);
    return p.relative(savedPath, from: docs.path);
  }

  static Future<File?> resolve(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, relativePath));
    return file.existsSync() ? file : null;
  }

  static Future<void> deleteRelative(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, relativePath));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
