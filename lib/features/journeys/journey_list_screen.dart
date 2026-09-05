import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/journey.dart';
import '../../core/models/record_entry.dart';
import '../../state/journey_controller.dart';
import '../../state/recap_controller.dart';
import '../../state/timeline_controller.dart';
import '../../widgets/media_thumbnail.dart';
import '../../widgets/streak_badge.dart';
import '../records/capture_record_screen.dart';
import 'create_journey_screen.dart';
import 'invite_and_join.dart';
import 'journey_detail_screen.dart';
import '../profile/profile_sheet.dart';

class JourneyListScreen extends StatelessWidget {
  const JourneyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<JourneyController>();
    final journeys = state.journeyList;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Behang'),
            Text(
              state.cloudReady
                  ? 'Turn everyday moments into a story'
                  : 'Offline mode · turn everyday moments into a story',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
        actions: [
          if (state.cloudReady)
            IconButton(
              tooltip: 'Join a journey',
              onPressed: () async {
                final joined = await showDialog<bool>(
                  context: context,
                  builder: (_) => const JoinJourneyDialog(),
                );
                if (joined == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Welcome to the journey! 🎉')));
                }
              },
              icon: const Icon(Icons.link_rounded),
            ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const ProfileSheet(),
            ),
            icon: CircleAvatar(
              radius: 13,
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                state.profile?.avatar ?? '?',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const CreateJourneyScreen()),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New journey'),
      ),
      body: RefreshIndicator(
        onRefresh: state.refresh,
        child: journeys.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  _EmptyState(),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: journeys.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) =>
                    _JourneyCard(journeys[index]),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🌱', style: Theme.of(context).textTheme.displayLarge),
          const SizedBox(height: 12),
          Text(
            'Start your first journey',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Set a goal, show up daily, capture a moment — and watch your story build itself.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyCard extends StatefulWidget {
  final Journey journey;

  const _JourneyCard(this.journey);

  @override
  State<_JourneyCard> createState() => _JourneyCardState();
}

class _JourneyCardState extends State<_JourneyCard> {
  VideoPlayerController? _preview;
  bool _loadingPreview = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(covariant _JourneyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.journey.id != widget.journey.id) {
      _disposePreview();
      _loadPreview();
    }
  }

  @override
  void dispose() {
    _disposePreview();
    super.dispose();
  }

  void _disposePreview() {
    _preview?.dispose();
    _preview = null;
  }

  Future<void> _loadPreview() async {
    if (_loadingPreview) return;
    _loadingPreview = true;
    try {
      final recap = context.read<RecapController>();
      final file = await recap.compilePreviewReel(widget.journey.id);
      if (!mounted || file == null) return;
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _preview = controller);
      controller.play();
    } catch (_) {
      // FFmpeg unavailable or media unresolvable — fall back to thumbnail.
    } finally {
      _loadingPreview = false;
    }
  }

  Future<void> _recordToday() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => CaptureRecordScreen(journeyId: widget.journey.id),
      ),
    );
    if (mounted) {
      _disposePreview();
      _loadPreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeline = context.watch<TimelineController>();
    final journey = widget.journey;
    final scheme = Theme.of(context).colorScheme;
    final stats = timeline.statsOf(journey.id);
    final latest = timeline.latestOf(journey.id);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => JourneyDetailScreen(journeyId: journey.id),
          ),
        ),
        onLongPress: () => _confirmDelete(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBanner(context, journey, latest),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              journey.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              journey.goal ?? journey.category.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      StreakBadge(current: stats.current, best: stats.best),
                    ],
                  ),
                  if (!journey.isOpenEnded) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: journey.progressOn(DateTime.now()),
                        ),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, value, _) =>
                            LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Day ${journey.dayNumberOn(DateTime.now()).clamp(1, journey.durationDays!)}/${journey.durationDays} · ${timeline.countOf(journey.id)} moments',
                      style: TextStyle(fontSize: 10, color: scheme.outline),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Day ${journey.dayNumberOn(DateTime.now())} · ${timeline.countOf(journey.id)} moments',
                        style: TextStyle(fontSize: 10, color: scheme.outline),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner(
    BuildContext context,
    Journey journey,
    RecordEntry? latest,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _preview;
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (preview != null && preview.value.isInitialized)
            VideoPlayer(preview)
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer,
                    scheme.tertiaryContainer,
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: latest != null
                  ? SizedBox(
                      width: 120,
                      height: 120,
                      child: MediaThumbnail(
                        relativePath: latest.mediaUrl,
                        mediaType: latest.mediaType,
                        iconSize: 34,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(journey.category.emoji,
                            style: const TextStyle(fontSize: 44)),
                        const SizedBox(height: 8),
                        const Text('Start the story',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
            ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                journey.isOpenEnded
                    ? 'Day ${journey.dayNumberOn(DateTime.now())}'
                    : 'Day ${journey.dayNumberOn(DateTime.now()).clamp(1, journey.durationDays!)}/${journey.durationDays}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: FilledButton.icon(
              onPressed: _recordToday,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: const Icon(Icons.add_a_photo_outlined, size: 16),
              label: const Text('Record today',
                  style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final journeys = context.read<JourneyController>();
    final journey = widget.journey;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete journey?'),
        content: Text(
            '"${journey.title}" and all of its moments will be removed permanently.'),
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
      await journeys.deleteJourney(journey.id);
    }
  }
}
