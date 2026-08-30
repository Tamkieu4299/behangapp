class Milestone {
  final String id;
  final String journeyId;
  final String title;
  final DateTime? targetDate;
  final DateTime? achievedAt;
  final String badgeIcon;

  const Milestone({
    required this.id,
    required this.journeyId,
    required this.title,
    required this.badgeIcon,
    this.targetDate,
    this.achievedAt,
  });

  factory Milestone.fromMap(Map<String, Object?> map) => Milestone(
        id: map['id'] as String,
        journeyId: map['journey_id'] as String,
        title: map['title'] as String,
        targetDate: map['target_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['target_date'] as int),
        achievedAt: map['achieved_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['achieved_at'] as int),
        badgeIcon: (map['badge_icon'] as String?) ?? '🏅',
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'journey_id': journeyId,
        'title': title,
        'target_date': targetDate?.millisecondsSinceEpoch,
        'achieved_at': achievedAt?.millisecondsSinceEpoch,
        'badge_icon': badgeIcon,
      };

  Milestone copyWith({
    String? id,
    String? journeyId,
    String? title,
    Object? targetDate = _sentinel,
    Object? achievedAt = _sentinel,
    String? badgeIcon,
  }) =>
      Milestone(
        id: id ?? this.id,
        journeyId: journeyId ?? this.journeyId,
        title: title ?? this.title,
        targetDate:
            targetDate == _sentinel ? this.targetDate : targetDate as DateTime?,
        achievedAt: achievedAt == _sentinel
            ? this.achievedAt
            : achievedAt as DateTime?,
        badgeIcon: badgeIcon ?? this.badgeIcon,
      );

  static const _sentinel = Object();

  bool get achieved => achievedAt != null;
}
