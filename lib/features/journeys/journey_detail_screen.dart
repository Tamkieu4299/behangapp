import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../app_state.dart';
import '../../core/models/journey.dart';
import '../../core/models/milestone.dart';
import '../../core/models/record_entry.dart';
import '../../core/models/sticker.dart';
import '../../core/utils/dates.dart' as dates;
import '../../widgets/calendar_grid.dart';
import '../../widgets/streak_badge.dart';
import '../../widgets/timeline_view.dart';
import '../records/capture_record_screen.dart';
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
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

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
      final state = context.read<AppState>();
      state.subscribeMembers(widget.journeyId);
      if (!_touchedSeen) {
        _touchedSeen = true;
        state.touchSeen(widget.journeyId);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final journey = state.journey(widget.journeyId);
    if (journey == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scheme = Theme.of(context).colorScheme;
    final records = state.recordsOf(journey.id);
    final catchUp = state.catchUpRecords(journey.id);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: state.cloudReady
                ? 'Watch recap together'
                : 'Recap video',
            onPressed: () => _openRecap(),
            icon: Icon(state.cloudReady
                ? Icons.groups_rounded
                : Icons.movie_creation_outlined),
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
              if (value == 'delete') _confirmDelete();
            },
            itemBuilder: (_) => const [
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        journey.category.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            journey.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          if ((journey.goal ?? '').isNotEmpty)
                            Text(
                              '🎯 ${journey.goal}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StreakBadge(
                        current: state.statsOf(journey.id).current,
                        best: state.statsOf(journey.id).best),
                    _chip('${records.length} moments',
                        Icons.photo_library_outlined),
                    _chip('Day ${journey.dayNumberOn(DateTime.now())}',
                        Icons.flag_outlined),
                  ],
                ),
                const SizedBox(height: 10),
                _membersRow(context, journey),
                if (!journey.isOpenEnded) ...[
                  const SizedBox(height: 14),
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                        begin: 0, end: journey.progressOn(DateTime.now())),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                          value: value, minHeight: 8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${(journey.progressOn(DateTime.now()) * 100).toStringAsFixed(0)}% of ${journey.durationDays} days',
                      style: TextStyle(fontSize: 10, color: scheme.outline),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
          if (catchUp.isNotEmpty)
            _catchUpBanner(context, journey.id, catchUp),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Timeline'),
              Tab(text: 'Calendar'),
              Tab(text: 'Milestones'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                TimelineView(
                  journey: journey,
                  records: records,
                  onDelete: (record) =>
                      context.read<AppState>().deleteRecord(record),
                ),
                _calendarTab(journey),
                _milestonesTab(journey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _membersRow(BuildContext context, Journey journey) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final members = state.membersOf(journey.id);
    return Row(
      children: [
        Text('With',
            style: TextStyle(fontSize: 11, color: scheme.outline)),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 32,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < members.length && i < 6; i++)
                  Positioned(
                    left: i * 26.0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: scheme.surface, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(members[i].avatar,
                          style: const TextStyle(fontSize: 15)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => InviteSheet(journeyId: journey.id),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: Text(members.isEmpty ? 'Invite' : 'Invite more'),
          style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12)),
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
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text('📬', style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${records.length} new moment${records.length == 1 ? '' : 's'} from $names — catch up!',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: scheme.onSecondaryContainer),
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
                    trailing: record.hasMedia
                        ? const Icon(Icons.photo_outlined)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted) {
      await context.read<AppState>().touchSeen(journeyId);
    }
  }

  Widget _chip(String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _calendarTab(Journey journey) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final byDay = <int, RecordEntry>{};
    for (final record in state.recordsOf(journey.id).reversed) {
      byDay[dates.epochDay(record.timestamp)] = record;
    }
    final badgesByDay = <int, String>{};
    for (final milestone in state.milestonesOf(journey.id)) {
      if (milestone.achievedAt != null) {
        badgesByDay[dates.epochDay(milestone.achievedAt!)] =
            milestone.badgeIcon;
      }
    }
    final selectedRecords = _selectedEpochDay == null
        ? const <RecordEntry>[]
        : state
            .recordsOf(journey.id)
            .where((r) => dates.epochDay(r.timestamp) == _selectedEpochDay)
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => setState(() => _calendarMonth = DateTime(
                    _calendarMonth.year, _calendarMonth.month - 1, 1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                DateFormat('MMMM y').format(_calendarMonth),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              IconButton(
                onPressed: () => setState(() => _calendarMonth = DateTime(
                    _calendarMonth.year, _calendarMonth.month + 1, 1)),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CalendarGrid(
            journey: journey,
            month: _calendarMonth,
            recordsByDay: byDay,
            badgesByDay: badgesByDay,
            stickersByDay: state.stickersOf(journey.id),
            selectedEpochDay: _selectedEpochDay,
            onDayTap: (day) => setState(() =>
                _selectedEpochDay = _selectedEpochDay == day ? null : day),
            onDayLongPress: _pickSticker,
          ),
          const SizedBox(height: 6),
          Text(
            'Long-press a day to add a sticker · badges appear when milestones are achieved',
            style: TextStyle(fontSize: 10, color: scheme.outline),
          ),
          const SizedBox(height: 12),
          ...selectedRecords.map(
            (r) => Card(
              child: ListTile(
                leading: Text(r.authorAvatar ?? '📷',
                    style: const TextStyle(fontSize: 20)),
                title: Text(DateFormat('EEE, MMM d · HH:mm')
                    .format(r.timestamp)),
                subtitle: r.note == null || r.note!.isEmpty
                    ? null
                    : Text(r.note!, maxLines: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _milestonesTab(Journey journey) {
    final state = context.watch<AppState>();
    final milestones = state.milestonesOf(journey.id);
    final achievedCount = milestones.where((m) => m.achieved).length;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (milestones.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Column(
                  children: [
                    Text('🏅',
                        style: Theme.of(context).textTheme.displayMedium),
                    const SizedBox(height: 10),
                    Text('Define checkpoints worth celebrating',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Milestones appear as badge overlays on your calendar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              )
            else ...[
              Text('$achievedCount of ${milestones.length} achieved',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 8),
              for (final milestone in milestones)
                _MilestoneCard(milestone: milestone),
            ],
          ],
        ),
        Positioned(
          right: 16,
          bottom: 24,
          child: FilledButton.icon(
            onPressed: () => _openMilestoneEditor(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add milestone'),
          ),
        ),
      ],
    );
  }

  Future<void> _capture() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => CaptureRecordScreen(journeyId: widget.journeyId),
      ),
    );
    if (saved != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Moment captured 🔥')),
    );
  }

  void _openRecap() {
    final state = context.read<AppState>();
    final photoRecords = state
        .recordsOf(widget.journeyId)
        .where((r) => r.mediaType == MediaType.photo)
        .toList();
    if (photoRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add some photos first to build a recap.')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecapPlayerScreen(
          journey: state.journey(widget.journeyId)!,
          records: photoRecords,
        ),
      ),
    );
  }

  Future<void> _pickSticker(int epochDay) async {
    final state = context.read<AppState>();
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
    if (chosen == '__remove__') {
      await state.removeSticker(widget.journeyId, epochDay);
    } else {
      await state.placeSticker(DaySticker(
        journeyId: widget.journeyId,
        epochDay: epochDay,
        emoji: chosen,
      ));
    }
  }

  Future<void> _editReminder() async {
    final journey = context.read<AppState>().journey(widget.journeyId);
    if (journey == null) return;
    final state = context.read<AppState>();
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
                style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.outline),
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
                    await state.setReminder(journey, picked);
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
                    await state.setReminder(journey, null);
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

  Future<void> _openMilestoneEditor() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) =>
          _MilestoneEditorSheet(journeyId: widget.journeyId),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete journey?'),
        content: const Text(
            'All moments and milestones will be removed permanently.'),
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
      await context.read<AppState>().deleteJourney(widget.journeyId);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

class _MilestoneCard extends StatelessWidget {
  final Milestone milestone;

  const _MilestoneCard({required this.milestone});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.read<AppState>();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
            decoration:
                milestone.achieved ? TextDecoration.lineThrough : null,
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
                await state.achieveMilestone(milestone, DateTime.now());
                break;
              case 'reopen':
                await state.reopenMilestone(milestone);
                break;
              case 'delete':
                await state.deleteMilestone(milestone.id);
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
                await context.read<AppState>().saveMilestone(Milestone(
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
