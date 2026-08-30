import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models/journey.dart';
import '../core/models/record_entry.dart';
import '../core/services/media_service.dart';
import 'media_thumbnail.dart';
import 'video_player_screen.dart';

class TimelineView extends StatelessWidget {
  final Journey journey;
  final List<RecordEntry> records;
  final void Function(RecordEntry record)? onDelete;

  const TimelineView({
    super.key,
    required this.journey,
    required this.records,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('📷', style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 8),
            Text(
              'No moments yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Capture your first moment to start the story.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: records.length + _monthHeaderCount(records),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final headerIndex = _headerIndexFor(index);
        if (headerIndex != null) {
          return Padding(
            padding: EdgeInsets.fromLTRB(4, index == 0 ? 4 : 16, 4, 6),
            child: Text(
              DateFormat('MMMM y').format(records[headerIndex].timestamp),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          );
        }
        final recordIndex = index - _headersBefore(index);
        return _RecordTile(
          journey: journey,
          record: records[recordIndex],
          onDelete: onDelete == null
              ? null
              : () => onDelete!(records[recordIndex]),
        );
      },
    );
  }

  int _monthHeaderCount(List<RecordEntry> list) {
    var count = 0;
    int? lastMonth;
    for (final r in list) {
      final m = r.timestamp.year * 12 + r.timestamp.month;
      if (m != lastMonth) {
        count++;
        lastMonth = m;
      }
    }
    return count;
  }

  int? _headerIndexFor(int visualIndex) {
    var headersSeen = 0;
    int? lastMonth;
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final m = r.timestamp.year * 12 + r.timestamp.month;
      if (m != lastMonth) {
        if (visualIndex == i + headersSeen) return i;
        headersSeen++;
        lastMonth = m;
      }
    }
    return null;
  }

  int _headersBefore(int visualIndex) {
    var headers = 0;
    int? lastMonth;
    for (var i = 0; i < records.length && i < visualIndex; i++) {
      final r = records[i];
      final m = r.timestamp.year * 12 + r.timestamp.month;
      if (m != lastMonth) {
        headers++;
        lastMonth = m;
      }
    }
    return headers;
  }
}

class _RecordTile extends StatelessWidget {
  final Journey journey;
  final RecordEntry record;
  final VoidCallback? onDelete;

  const _RecordTile({
    required this.journey,
    required this.record,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      confirmDismiss: (_) async => onDelete != null,
      onDismissed: (_) => onDelete?.call(),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          onTap: () => _openMedia(context),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: MediaThumbnail(
                    relativePath: record.mediaUrl,
                    mediaType: record.mediaType,
                    iconSize: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            DateFormat('EEE, MMM d').format(record.timestamp),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Day ${journey.dayNumberOn(record.timestamp)}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          if ((record.authorName ?? '').isNotEmpty)
                            Text(
                              '${record.authorAvatar ?? ''} ${record.authorName}',
                              style: TextStyle(
                                  fontSize: 10, color: scheme.outline),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('HH:mm').format(record.timestamp),
                        style: TextStyle(
                            fontSize: 11, color: scheme.outline),
                      ),
                      if ((record.note ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          record.note!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMedia(BuildContext context) async {
    if (!record.hasMedia || record.mediaType == MediaType.none) return;
    final file = await MediaService.resolve(record.mediaUrl);
    if (file == null || !context.mounted) return;
    if (record.mediaType == MediaType.video) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              VideoPlayerScreen(file: file, title: journey.title),
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: InteractiveViewer(
            child: Center(child: Image.file(file)),
          ),
        ),
      );
    }
  }
}
