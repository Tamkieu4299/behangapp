import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/journey.dart';
import '../../core/models/milestone.dart';
import '../../core/models/record_entry.dart';
import '../../core/models/sticker.dart';
import '../../core/utils/dates.dart' as dates;
import '../../state/journey_controller.dart';
import '../../state/recap_controller.dart';
import '../../state/timeline_controller.dart';
import '../../widgets/calendar_grid.dart';
import '../../widgets/media_thumbnail.dart';
import '../../widgets/story_player.dart';
import '../../widgets/streak_badge.dart';
import '../records/quick_capture_screen.dart';
import '../recap/recap_player_screen.dart';
import 'invite_and_join.dart';

class JourneyDetailScreen extends StatefulWidget {
  final String journeyId;

  const JourneyDetailScreen({super.key, required this.journeyId});

  @override
  State<JourneyDetailScreen> createState() => _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends State<JourneyDetailScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<StoryPlayerState> _storyKey = GlobalKey();

  List<RecordEntry> _storyRecords = [];
  List<File?> _slides = [];

  DateTime _calendarMonth = dates.dateOnly(DateTime.now());
  int? _selectedEpochDay;
  bool _touchedSeen = false;

  static const _stickerChoices = [
    '✨', '⭐', '🌟', '💖', '🌈', '🔥', '🎉', '🍀', '☀️', '🌙', '❄️', '🌸',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final journeys = context.read<JourneyController>();
      journeys.subscribeMembers(widget.journeyId);
      if (!_touchedSeen) {
        _touchedSeen = true;
        journeys.touchSeen(widget.journeyId);
      }
      _resolveStoryAssets();
    });
  }

  Future<void> _resolveStoryAssets() async {
    final timeline = context.read<TimelineController>();
    final recap = context.read<RecapController>();
    final records = timeline
        .recordsOf(widget.journeyId)
        .where((r) => r.hasMedia && r.mediaType != MediaType.none)
        .toList()
        .reversed
        .toList();
    final slides = <File?>[];
    for (final record in records) {
      slides.add(await recap.backend.resolveMedia(record));
    }
    if (!mounted) return;
    setState(() {
      _storyRecords = records;
      _slides = slides;
    });
  }

  void _jumpToStory(RecordEntry record) {
    final index = _storyRecords.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      _storyKey.currentState?.playIndex(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<JourneyController>();
    final timeline = context.watch<TimelineController>();
    final journey = journeys.journey(widget.journeyId);
    if (journey == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final records = timeline.recordsOf(journey.id);
    final catchUp = timeline.catchUpRecords(journey.id);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: journeys.cloudReady
                ? 'Watch recap together'
                : 'Recap video',
            onPressed: () => _openRecap(),
            icon: Icon(journeys.cloudReady
                ? Icons.groups_rounded
                : Icons.movie_creation_outlined),
          ),
          IconButton(
            tooltip: 'Calendar',
            onPressed: _openCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'Daily reminder',
            onPressed: () => _editReminder(),
            icon: Icon(
              journey.hasReminder
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'milestones':
                  _openMilestones();
                  break;
                case 'delete':
                  _confirmDelete();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'milestones',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.emoji_events_outlined),
                  title: Text('Milestones'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete journey'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'capture',
        onPressed: () => _capture(),
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Capture'),
      ),
      body: Column(
        children: [
          _buildHeader(context, journey, timeline),
          if (catchUp.isNotEmpty)
            _catchUpBanner(context, journey.id, catchUp),
          Expanded(
            flex: 5,
            child: _buildStory(context, journey),
          ),
          Expanded(
            flex: 4,
            child: _buildFeed(context, journey, timeline, records),
          ),
        ],
      ),
    );
  }

  void _publishStory() {
    final recap = context.read<RecapController>();
    final story = _storyKey.currentState;
    if (story == null || !recap.together) return;
    recap.publishSession(
      widget.journeyId,
      index: story.currentIndex,
      playing: story.isPlaying,
    );
  }

  Widget _buildStory(BuildContext context, Journey journey) {
    final recap = context.read<RecapController>();
    if (_storyRecords.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🎞️', style: TextStyle(fontSize: 44)),
            SizedBox(height: 8),
            Text('Capture moments to build your story',
                style: TextStyle(color: Colors.black45)),
          ],
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: ClipRRect(
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(18)),
        child: StoryPlayer(
          key: _storyKey,
          records: _storyRecords,
          slides: _slides,
          holdSeconds: recap.clipSeconds,
          dayNumber: (i) =>
              journey.dayNumberOn(_storyRecords[i].timestamp),
          badgesOn: (i) => recap.milestoneBadgesFor(_storyRecords[i]),
          onIndexChanged: (_) => _publishStory(),
          onTogglePlay: _publishStory,
          topRightOverlay: recap.together
              ? const Text(
                  '👀 together',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildFeed(
    BuildContext context,
    Journey journey,
    TimelineController timeline,
    List<RecordEntry> records,
  ) {
    final stats = timeline.statsOf(journey.id);
    final milestones = timeline.milestonesOf(journey.id);
    final byDay = <int, String>{};
    for (final milestone in milestones) {
      if (milestone.achievedAt != null) {
        byDay[dates.epochDay(milestone.achievedAt!)] = milestone.badgeIcon;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Row(
            children: [
              StreakBadge(current: stats.current, best: stats.best),
              const SizedBox(width: 10),
              _chip('${records.length} moments', Icons.photo_library_outlined),
              const SizedBox(width: 8),
              _chip('Day ${journey.dayNumberOn(DateTime.now())}',
                  Icons.flag_outlined),
            ],
          ),
        ),
        Expanded(
          child: records.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('📷', style: TextStyle(fontSize: 34)),
                      SizedBox(height: 6),
                      Text('No moments yet'),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return _FeedTile(
                      journey: journey,
                      record: record,
                      badge: byDay[dates.epochDay(record.timestamp)],
                      onTap: () => _jumpToStory(record),
                      onLongPress: () => _confirmDeleteRecord(record),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteRecord(RecordEntry record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete moment?'),
        content: Text('The moment from '
            '${DateFormat('MMM d').format(record.timestamp)} will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<TimelineController>().deleteRecord(record);
    }
  }

  Widget _chip(String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, Journey journey, TimelineController timeline) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(journey.category.emoji,
                    style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      journey.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    if ((journey.goal ?? '').isNotEmpty)
                      Text(
                        '🎯 ${journey.goal}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              _membersRow(context, journey),
            ],
          ),
          if (!journey.isOpenEnded) ...[
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(
                  begin: 0, end: journey.progressOn(DateTime.now())),
              duration: const Duration(milliseconds: 500),
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: value, minHeight: 5),
              ),
            ),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(journey.progressOn(DateTime.now()) * 100).toStringAsFixed(0)}% of ${journey.durationDays} days',
                style: TextStyle(fontSize: 9, color: scheme.outline),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _membersRow(BuildContext context, Journey journey) {
    final journeys = context.read<JourneyController>();
    final scheme = Theme.of(context).colorScheme;
    final members = journeys.membersOf(journey.id);
    final visibleCount = members.length.clamp(0, 4);
    return Row(
      children: [
        SizedBox(
          width: visibleCount == 0 ? 0 : (visibleCount - 1) * 22.0 + 28,
          height: 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < visibleCount; i++)
                Positioned(
                  left: i * 22.0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(members[i].avatar,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => InviteSheet(journeyId: journey.id),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
          label: Text(members.isEmpty ? 'Invite' : '+'),
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  Widget _catchUpBanner(
      BuildContext context, String journeyId, List<RecordEntry> records) {
    final scheme = Theme.of(context).colorScheme;
    final names = records
        .map((r) => r.authorName ?? 'Someone')
        .toSet()
        .take(2)
        .join(' & ');
    return GestureDetector(
      onTap: () => _openCatchUp(journeyId, records),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Text('📬'),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${records.length} new moment${records.length == 1 ? '' : 's'} from $names — catch up!',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: scheme.onSecondaryContainer, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _openCatchUp(
      String journeyId, List<RecordEntry> records) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Catch up 📬',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: records.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final record = records[index];
                  return ListTile(
                    leading: Text(record.authorAvatar ?? '🌱',
                        style: const TextStyle(fontSize: 22)),
                    title: Text(
                        '${record.authorName ?? 'Someone'} · ${DateFormat('MMM d').format(record.timestamp)}'),
                    subtitle: record.note == null || record.note!.isEmpty
                        ? null
                        : Text(record.note!, maxLines: 2),
                    trailing:
                        record.hasMedia ? const Icon(Icons.photo_outlined) : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted) {
      await context.read<JourneyController>().touchSeen(journeyId);
    }
  }

  void _openCalendar() {
    final timeline = context.read<TimelineController>();
    final journey = context.read<JourneyController>().journey(widget.journeyId);
    if (journey == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final records = timeline.recordsOf(journey.id);
          final byDay = <int, RecordEntry>{};
          for (final record in records.reversed) {
            byDay[dates.epochDay(record.timestamp)] = record;
          }
          final badgesByDay = <int, String>{};
          for (final milestone in timeline.milestonesOf(journey.id)) {
            if (milestone.achievedAt != null) {
              badgesByDay[dates.epochDay(milestone.achievedAt!)] =
                  milestone.badgeIcon;
            }
          }
          final selectedRecords = _selectedEpochDay == null
              ? const <RecordEntry>[]
              : records
                  .where((r) =>
                      dates.epochDay(r.timestamp) == _selectedEpochDay)
                  .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            builder: (context, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text('Calendar',
                    style: Theme.of(sheetContext).textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => setSheetState(() => _calendarMonth =
                          DateTime(_calendarMonth.year, _calendarMonth.month - 1)),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text(DateFormat('MMMM y').format(_calendarMonth),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      onPressed: () => setSheetState(() => _calendarMonth =
                          DateTime(_calendarMonth.year, _calendarMonth.month + 1)),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                CalendarGrid(
                  journey: journey,
                  month: _calendarMonth,
                  recordsByDay: byDay,
                  badgesByDay: badgesByDay,
                  stickersByDay: timeline.stickersOf(journey.id),
                  selectedEpochDay: _selectedEpochDay,
                  onDayTap: (day) => setSheetState(() =>
                      _selectedEpochDay = _selectedEpochDay == day ? null : day),
                  onDayLongPress: _pickSticker,
                ),
                const SizedBox(height: 6),
                Text(
                  'Long-press a day to add a sticker · tap to see that day\'s moments',
                  style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline),
                ),
                ...selectedRecords.map(
                  (r) => Card(
                    child: ListTile(
                      leading: Text(r.authorAvatar ?? '📷',
                          style: const TextStyle(fontSize: 20)),
                      title: Text(
                          DateFormat('EEE, MMM d · HH:mm').format(r.timestamp)),
                      subtitle: r.note == null || r.note!.isEmpty
                          ? null
                          : Text(r.note!, maxLines: 2),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openMilestones() {
    final timeline = context.read<TimelineController>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scrollController) {
          final milestones = timeline.milestonesOf(widget.journeyId);
          final achievedCount = milestones.where((m) => m.achieved).length;
          return Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text('Milestones',
                            style: Theme.of(sheetContext).textTheme.titleMedium),
                        const Spacer(),
                        if (milestones.isNotEmpty)
                          Text(
                              '$achievedCount of ${milestones.length} achieved',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(sheetContext)
                                      .colorScheme
                                      .outline)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: milestones.isEmpty
                        ? const Center(child: Text('No milestones yet'))
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                            children: [
                              for (final milestone in milestones)
                                _MilestoneCard(milestone: milestone),
                            ],
                          ),
                  ),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FilledButton.icon(
                  onPressed: () => showModalBottomSheet<bool>(
                    context: sheetContext,
                    isScrollControlled: true,
                    builder: (_) =>
                        _MilestoneEditorSheet(journeyId: widget.journeyId),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add milestone'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _capture() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => QuickCaptureScreen(journeyId: widget.journeyId),
      ),
    );
  }

  void _openRecap() {
    final timeline = context.read<TimelineController>();
    final journeys = context.read<JourneyController>();
    final records = timeline
        .recordsOf(widget.journeyId)
        .where((r) => r.hasMedia && r.mediaType != MediaType.none)
        .toList();
    final journey = journeys.journey(widget.journeyId);
    if (records.isEmpty || journey == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add some photos/videos first to build a recap.')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecapPlayerScreen(
          journey: journey,
          records: records,
        ),
      ),
    );
  }

  Future<void> _pickSticker(int epochDay) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Decorate this day',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final sticker in _stickerChoices)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(sheetContext, sticker),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(sticker,
                            style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.pop(sheetContext, '__remove__'),
                icon: const Icon(Icons.backspace_outlined, size: 18),
                label: const Text('Remove sticker'),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    if (!mounted) return;
    if (chosen == '__remove__') {
      await context
          .read<TimelineController>()
          .removeSticker(widget.journeyId, epochDay);
    } else {
      await context
          .read<TimelineController>()
          .placeSticker(DaySticker(
            journeyId: widget.journeyId,
            epochDay: epochDay,
            emoji: chosen,
          ));
    }
  }

  Future<void> _editReminder() async {
    final journeys = context.read<JourneyController>();
    final journey = journeys.journey(widget.journeyId);
    if (journey == null) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Daily reminder',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                journey.hasReminder
                    ? 'Every day at ${TimeOfDay(hour: journey.reminderHour!, minute: journey.reminderMinute!).format(sheetContext)}'
                    : 'Reminders are off',
                style:
                    TextStyle(color: Theme.of(sheetContext).colorScheme.outline),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: sheetContext,
                    initialTime: TimeOfDay(
                      hour: journey.reminderHour ?? 20,
                      minute: journey.reminderMinute ?? 0,
                    ),
                  );
                  if (picked != null) {
                    await journeys.setReminder(journey, picked);
                  }
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                icon: const Icon(Icons.schedule_rounded),
                label: const Text('Set time'),
              ),
              if (journey.hasReminder) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await journeys.setReminder(journey, null);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.notifications_off_outlined),
                  label: const Text('Turn off'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete journey?'),
        content: const Text(
            'All moments, milestones and stories will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<JourneyController>().deleteJourney(widget.journeyId);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

class _FeedTile extends StatelessWidget {
  final Journey journey;
  final RecordEntry record;
  final String? badge;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FeedTile({
    required this.journey,
    required this.record,
    required this.badge,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${journey.dayNumberOn(record.timestamp)}',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant),
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
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('HH:mm').format(record.timestamp),
                        style:
                            TextStyle(fontSize: 10, color: scheme.outline),
                      ),
                      if ((record.authorName ?? '').isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${record.authorAvatar ?? ''} ${record.authorName}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10, color: scheme.outline),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if ((record.note ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      record.note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Text(badge!, style: const TextStyle(fontSize: 16)),
            ],
            if (record.hasMedia) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                height: 40,
                child: MediaThumbnail(
                  relativePath: record.mediaUrl,
                  mediaType: record.mediaType,
                  iconSize: 16,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  final Milestone milestone;

  const _MilestoneCard({required this.milestone});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timeline = context.read<TimelineController>();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: milestone.achieved
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Opacity(
            opacity: milestone.achieved ? 1 : 0.55,
            child: Text(milestone.badgeIcon,
                style: const TextStyle(fontSize: 22)),
          ),
        ),
        title: Text(
          milestone.title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: milestone.achieved ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          milestone.achievedAt != null
              ? 'Achieved ${DateFormat('MMM d, y').format(milestone.achievedAt!)}'
              : (milestone.targetDate != null
                  ? 'Target ${DateFormat('MMM d, y').format(milestone.targetDate!)}'
                  : 'No target date'),
          style: TextStyle(fontSize: 11, color: scheme.outline),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'achieve':
                await timeline.achieveMilestone(milestone, DateTime.now());
                break;
              case 'reopen':
                await timeline.reopenMilestone(milestone);
                break;
              case 'delete':
                await timeline.deleteMilestone(milestone.id);
                break;
            }
          },
          itemBuilder: (_) => [
            if (!milestone.achieved)
              const PopupMenuItem(
                value: 'achieve',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.emoji_events_outlined),
                  title: Text('Mark achieved'),
                ),
              ),
            if (milestone.achieved)
              const PopupMenuItem(
                value: 'reopen',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restart_alt_rounded),
                  title: Text('Reopen'),
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline),
                title: Text('Delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilestoneEditorSheet extends StatefulWidget {
  final String journeyId;

  const _MilestoneEditorSheet({required this.journeyId});

  @override
  State<_MilestoneEditorSheet> createState() => _MilestoneEditorSheetState();
}

class _MilestoneEditorSheetState extends State<_MilestoneEditorSheet> {
  final _titleController = TextEditingController();
  String _badge = _badgeChoices.first;
  DateTime? _targetDate;

  static const _badgeChoices = [
    '🏆', '🎯', '🚀', '🌟', '🏅', '🐣', '🎓', '🏔️', '💍', '🌱', '📸', '🎉',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, insets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New milestone',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'e.g. "First steps", "Black belt test"'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final badge in _badgeChoices)
                ChoiceChip(
                  label: Text(badge),
                  selected: _badge == badge,
                  showCheckmark: false,
                  labelStyle: const TextStyle(fontSize: 18),
                  onSelected: (_) => setState(() => _badge = badge),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(_targetDate == null
                ? 'Target date (optional)'
                : DateFormat('EEE, MMM d, y').format(_targetDate!)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _targetDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (picked != null) setState(() => _targetDate = picked);
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final title = _titleController.text.trim();
                if (title.isEmpty) return;
                await context
                    .read<TimelineController>()
                    .saveMilestone(Milestone(
                  id: const Uuid().v4(),
                  journeyId: widget.journeyId,
                  title: title,
                  targetDate: _targetDate,
                  badgeIcon: _badge,
                ));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save milestone'),
            ),
          ),
        ],
      ),
    );
  }
}