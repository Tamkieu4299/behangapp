enum MediaType { photo, video, none }

MediaType mediaTypeFromName(String? name) {
  for (final t in MediaType.values) {
    if (t.name == name) return t;
  }
  return MediaType.none;
}

class RecordEntry {
  final String id;
  final String journeyId;
  final DateTime timestamp;
  final MediaType mediaType;
  final String? mediaUrl;
  final String? note;
  final String? authorUid;
  final String? authorName;
  final String? authorAvatar;

  const RecordEntry({
    required this.id,
    required this.journeyId,
    required this.timestamp,
    this.mediaType = MediaType.none,
    this.mediaUrl,
    this.note,
    this.authorUid,
    this.authorName,
    this.authorAvatar,
  });

  factory RecordEntry.fromMap(Map<String, Object?> map) => RecordEntry(
        id: map['id'] as String,
        journeyId: map['journey_id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        mediaType: mediaTypeFromName(map['media_type'] as String?),
        mediaUrl: map['media_url'] as String?,
        note: map['note'] as String?,
        authorUid: map['author_uid'] as String?,
        authorName: map['author_name'] as String?,
        authorAvatar: map['author_avatar'] as String?,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'journey_id': journeyId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'media_type': mediaType.name,
        'media_url': mediaUrl,
        'note': note,
        'author_uid': authorUid,
        'author_name': authorName,
        'author_avatar': authorAvatar,
      };

  RecordEntry copyWith({
    MediaType? mediaType,
    Object? mediaUrl = _sentinel,
    Object? note = _sentinel,
    String? authorUid,
    String? authorName,
    String? authorAvatar,
  }) =>
      RecordEntry(
        id: id,
        journeyId: journeyId,
        timestamp: timestamp,
        mediaType: mediaType ?? this.mediaType,
        mediaUrl: mediaUrl == _sentinel ? this.mediaUrl : mediaUrl as String?,
        note: note == _sentinel ? this.note : note as String?,
        authorUid: authorUid ?? this.authorUid,
        authorName: authorName ?? this.authorName,
        authorAvatar: authorAvatar ?? this.authorAvatar,
      );

  static const _sentinel = Object();

  bool get hasMedia =>
      mediaType != MediaType.none && (mediaUrl?.isNotEmpty ?? false);
}
