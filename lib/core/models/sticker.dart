class DaySticker {
  final String journeyId;
  final int epochDay;
  final String emoji;

  const DaySticker({
    required this.journeyId,
    required this.epochDay,
    required this.emoji,
  });

  factory DaySticker.fromMap(Map<String, Object?> map) => DaySticker(
        journeyId: map['journey_id'] as String,
        epochDay: map['epoch_day'] as int,
        emoji: map['emoji'] as String,
      );

  Map<String, Object?> toMap() => {
        'journey_id': journeyId,
        'epoch_day': epochDay,
        'emoji': emoji,
      };
}
