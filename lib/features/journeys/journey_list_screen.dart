import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/journey.dart';
import '../../core/models/record_entry.dart';
import '../../widgets/media_thumbnail.dart';
import '../../widgets/streak_badge.dart';
import 'create_journey_screen.dart';
import 'invite_and_join.dart';
import 'journey_detail_screen.dart';
import '../profile/profile_sheet.dart';

class JourneyListScreen extends StatelessWidget {
  const JourneyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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

class _JourneyCard extends StatelessWidget {
  final Journey journey;

  const _JourneyCard(this.journey);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final stats = state.streaks[journey.id];
    final latest = state.latestByJourney[journey.id];
    final count = state.counts[journey.id] ?? 0;

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
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      journey.category.emoji,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                        const SizedBox(height: 3),
                        Text(
                          journey.goal ?? journey.category.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        StreakBadge(
                          current: stats?.current ?? 0,
                          best: stats?.best ?? 0,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: MediaThumbnail(
                      relativePath: latest?.mediaUrl,
                      mediaType: latest?.mediaType ?? MediaType.none,
                      iconSize: 22,
                    ),
                  ),
                ],
              ),
              if (!journey.isOpenEnded) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: journey.progressOn(DateTime.now())),
                          duration: const Duration(milliseconds: 500),
                          builder: (context, value, _) => LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Day ${journey.dayNumberOn(DateTime.now()).clamp(1, journey.durationDays!)}/${journey.durationDays} · $count moments',
                      style: TextStyle(fontSize: 10, color: scheme.outline),
                    ),
                  ],
                ),
              ] else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Day ${journey.dayNumberOn(DateTime.now())} · $count moments',
                    style: TextStyle(fontSize: 10, color: scheme.outline),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final state = context.read<AppState>();
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
    if (confirmed == true) {
      await state.deleteJourney(journey.id);
    }
  }
}
