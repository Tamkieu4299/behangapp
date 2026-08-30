enum JourneyCategory { baby, fitness, skill, travel, personal, other }

extension JourneyCategoryX on JourneyCategory {
  String get label => switch (this) {
        JourneyCategory.baby => 'Baby',
        JourneyCategory.fitness => 'Fitness',
        JourneyCategory.skill => 'Skill',
        JourneyCategory.travel => 'Travel',
        JourneyCategory.personal => 'Personal',
        JourneyCategory.other => 'Other',
      };

  String get emoji => switch (this) {
        JourneyCategory.baby => '🍼',
        JourneyCategory.fitness => '💪',
        JourneyCategory.skill => '🎾',
        JourneyCategory.travel => '✈️',
        JourneyCategory.personal => '🌱',
        JourneyCategory.other => '⭐',
      };
}

class Journey {
  final String id;
  final String userId;
  final String title;
  final JourneyCategory category;
  final String? goal;
  final DateTime startDate;
  final int? durationDays;
  final int? reminderHour;
  final int? reminderMinute;
  final bool archived;
  final DateTime createdAt;

  const Journey({
    required this.id,
    required this.userId,
    required this.title,
    required this.category,
    required this.startDate,
    required this.createdAt,
    this.goal,
    this.durationDays,
    this.reminderHour,
    this.reminderMinute,
    this.archived = false,
  });

  factory Journey.fromMap(Map<String, Object?> map) => Journey(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        title: map['title'] as String,
        category: JourneyCategory.values.firstWhere(
          (c) => c.name == map['category'],
          orElse: () => JourneyCategory.other,
        ),
        goal: map['goal'] as String?,
        startDate:
            DateTime.fromMillisecondsSinceEpoch(map['start_date'] as int),
        durationDays: map['duration_days'] as int?,
        reminderHour: map['reminder_hour'] as int?,
        reminderMinute: map['reminder_minute'] as int?,
        archived: (map['archived'] as int? ?? 0) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'category': category.name,
        'goal': goal,
        'start_date': startDate.millisecondsSinceEpoch,
        'duration_days': durationDays,
        'reminder_hour': reminderHour,
        'reminder_minute': reminderMinute,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  Journey copyWith({
    String? id,
    String? userId,
    String? title,
    JourneyCategory? category,
    Object? goal = _sentinel,
    DateTime? startDate,
    Object? durationDays = _sentinel,
    Object? reminderHour = _sentinel,
    Object? reminderMinute = _sentinel,
    bool? archived,
    DateTime? createdAt,
  }) =>
      Journey(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        category: category ?? this.category,
        goal: goal == _sentinel ? this.goal : goal as String?,
        startDate: startDate ?? this.startDate,
        durationDays:
            durationDays == _sentinel ? this.durationDays : durationDays as int?,
        reminderHour: reminderHour == _sentinel
            ? this.reminderHour
            : reminderHour as int?,
        reminderMinute: reminderMinute == _sentinel
            ? this.reminderMinute
            : reminderMinute as int?,
        archived: archived ?? this.archived,
        createdAt: createdAt ?? this.createdAt,
      );

  static const _sentinel = Object();

  bool get isOpenEnded => durationDays == null;

  DateTime? get endDate => durationDays == null
      ? null
      : DateTime(startDate.year, startDate.month, startDate.day)
          .add(Duration(days: durationDays! - 1));

  int dayNumberOn(DateTime date) =>
      DateTime(date.year, date.month, date.day)
          .difference(DateTime(startDate.year, startDate.month, startDate.day))
          .inDays +
      1;

  double progressOn(DateTime now) {
    if (durationDays == null || durationDays! <= 0) return 0;
    final day = dayNumberOn(now);
    return (day / durationDays!).clamp(0.0, 1.0);
  }

  bool get hasReminder => reminderHour != null && reminderMinute != null;
}
