import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models/journey.dart';
import '../core/models/record_entry.dart';
import '../core/services/media_service.dart';
import '../core/utils/dates.dart' as dates;

class CalendarGrid extends StatelessWidget {
  final Journey journey;
  final DateTime month;
  final Map<int, RecordEntry> recordsByDay;
  final Map<int, String> badgesByDay;
  final Map<int, String> stickersByDay;
  final int? selectedEpochDay;
  final ValueChanged<int> onDayTap;
  final ValueChanged<int> onDayLongPress;

  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  const CalendarGrid({
    super.key,
    required this.journey,
    required this.month,
    required this.recordsByDay,
    required this.badgesByDay,
    required this.stickersByDay,
    required this.selectedEpochDay,
    required this.onDayTap,
    required this.onDayLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dates.epochDay(DateTime.now());
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final leadingBlanks = firstOfMonth.weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    return Column(
      children: [
        Row(
          children: [
            for (final label in _weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: scheme.outline,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.86,
          children: [
            for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
            for (var day = 1; day <= daysInMonth; day++)
              _buildCell(
                context,
                DateTime(month.year, month.month, day),
                dayEpoch: dates.epochDay(DateTime(month.year, month.month, day)),
                isToday:
                    dates.epochDay(DateTime(month.year, month.month, day)) ==
                        today,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, DateTime date,
      {required int dayEpoch, required bool isToday}) {
    final scheme = Theme.of(context).colorScheme;
    final record = recordsByDay[dayEpoch];
    final badge = badgesByDay[dayEpoch];
    final sticker = stickersByDay[dayEpoch];
    final isSelected = selectedEpochDay == dayEpoch;
    final inJourney = dayEpoch >= dates.epochDay(journey.startDate);

    final shape = BorderRadius.circular(10);

    return GestureDetector(
      onTap: () => onDayTap(dayEpoch),
      onLongPress: () => onDayLongPress(dayEpoch),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: shape,
          border: Border.all(
            width: isSelected || isToday ? 2 : 1,
            color: isSelected
                ? scheme.primary
                : isToday
                    ? scheme.primary.withValues(alpha: 0.55)
                    : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
              if (record != null && record.hasMedia && record.mediaType == MediaType.photo)
                FutureBuilder<File?>(
                  future: MediaService.resolve(record.mediaUrl),
                  builder: (context, snapshot) {
                    final file = snapshot.data;
                    if (file == null) {
                      return Container(color: scheme.surfaceContainerHighest);
                    }
                    return Image.file(file, fit: BoxFit.cover, gaplessPlayback: true);
                  },
                )
              else if (record != null && record.hasMedia && record.mediaType == MediaType.video)
                Container(
                  color: scheme.inverseSurface,
                  alignment: Alignment.center,
                  child: Icon(Icons.play_arrow_rounded,
                      size: 22, color: scheme.onInverseSurface),
                )
              else if (record != null)
                Container(
                  color: scheme.secondaryContainer,
                  alignment: Alignment.center,
                  child: Icon(Icons.notes_rounded,
                      size: 18, color: scheme.onSecondaryContainer),
                )
              else
                Container(color: scheme.surfaceContainerLowest),
              Positioned(
                top: 2,
                left: 4,
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: record == null ? scheme.onSurfaceVariant : Colors.white,
                    shadows: record == null
                        ? null
                        : const [
                            Shadow(blurRadius: 4, color: Colors.black54),
                          ],
                  ),
                ),
              ),
              if (badge != null)
                Positioned(top: 0, right: 1, child: Text(badge, style: const TextStyle(fontSize: 11))),
              if (sticker != null)
                Positioned(bottom: 0, left: 1, child: Text(sticker, style: const TextStyle(fontSize: 12))),
              if (!inJourney)
                Container(color: scheme.surface.withValues(alpha: 0.55)),
          ],
        ),
      ),
    );
  }

  String get monthTitle => DateFormat('MMMM y').format(month);
}
