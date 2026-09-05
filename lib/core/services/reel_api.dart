import 'dart:convert';

import 'package:http/http.dart' as http;

/// A single normalized 9:16 clip segment requested from the reel worker.
class ReelEntrySpec {
  final String recordId;
  final int dayNumber;
  final String mediaKey;
  final bool isVideo;
  final double duration;
  final String? milestoneTitle;

  const ReelEntrySpec({
    required this.recordId,
    required this.dayNumber,
    required this.mediaKey,
    required this.isVideo,
    required this.duration,
    this.milestoneTitle,
  });

  Map<String, Object?> toJson() => {
        'record_id': recordId,
        'day_number': dayNumber,
        'media_key': mediaKey,
        'media_type': isVideo ? 'video' : 'photo',
        'duration': duration,
        'milestone_title': milestoneTitle,
      };
}

class ReelApiException implements Exception {
  ReelApiException(this.message);
  final String message;

  @override
  String toString() => 'ReelApiException: $message';
}

/// Client for the server-side FFmpeg worker (replaces the on-device
/// ffmpeg-kit pipeline). Trims clips and compiles 1080x1920 reels in MinIO
/// and returns object keys; the app downloads the finished file afterwards.
class ReelApi {
  ReelApi({required this.baseUrl});

  final String baseUrl;

  Future<http.Response> _post(String path, Map<String, Object?> payload) {
    try {
      return http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 5));
    } catch (e) {
      throw ReelApiException('Could not reach reel worker at $baseUrl: $e');
    }
  }

  /// Compiles all [entries] into a single vertical reel. Returns the object
  /// key of the finished `.mp4` in the media bucket.
  Future<String> buildReel({
    required String journeyId,
    required List<ReelEntrySpec> entries,
    bool watermark = true,
    String? outputKey,
  }) async {
    if (entries.isEmpty) throw ReelApiException('No entries to stitch');
    final response = await _post('/reel/build', {
      'journey_id': journeyId,
      'entries': entries.map((e) => e.toJson()).toList(),
      'watermark': watermark,
      'output_key': ?outputKey,
    });
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ReelApiException(body['error'] as String? ?? 'build failed');
    }
    return body['output_key'] as String;
  }

  /// Trims an already-uploaded video to [seconds] and returns the new object
  /// key (idempotent — the same key is reused on retries).
  Future<String> trimVideo({
    required String mediaKey,
    required double seconds,
    String? outputKey,
  }) async {
    final response = await _post('/reel/trim', {
      'media_key': mediaKey,
      'duration': seconds,
      'output_key': ?outputKey,
    });
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ReelApiException(body['error'] as String? ?? 'trim failed');
    }
    return body['output_key'] as String;
  }

  /// Best-effort reachability probe (used to show a degraded UI).
  Future<bool> health() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, Object?>;
    } catch (_) {
      throw ReelApiException('Malformed response from reel worker');
    }
  }
}