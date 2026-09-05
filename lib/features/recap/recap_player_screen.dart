import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/journey.dart';
import '../../core/models/record_entry.dart';
import '../../state/journey_controller.dart';
import '../../state/recap_controller.dart';
import '../../widgets/story_player.dart';

enum _RecapMode { interactive, reel }

class RecapPlayerScreen extends StatefulWidget {
  final Journey journey;
  final List<RecordEntry> records;

  const RecapPlayerScreen({
    super.key,
    required this.journey,
    required this.records,
  });

  @override
  State<RecapPlayerScreen> createState() => _RecapPlayerScreenState();
}

class _RecapPlayerScreenState extends State<RecapPlayerScreen> {
  late List<File?> _slides;
  late List<RecordEntry> _ordered;

  _RecapMode _mode = _RecapMode.interactive;
  final GlobalKey<StoryPlayerState> _storyKey = GlobalKey();

  VideoPlayerController? _reel;
  bool _reelReady = false;
  bool _reelBuildStarted = false;

  late RecapController _recap;
  late JourneyController _journeys;

  @override
  void initState() {
    super.initState();
    _recap = context.read<RecapController>();
    _journeys = context.read<JourneyController>();
    _ordered = [...widget.records];
    _slides = List<File?>.filled(_ordered.length, null);
    _resolveSlides();
    _recap.addListener(_onRecapChanged);
  }

  @override
  void dispose() {
    _recap.removeListener(_onRecapChanged);
    _reel?.dispose();
    super.dispose();
  }

  Future<void> _resolveSlides() async {
    final resolved = <File?>[];
    for (final record in _ordered) {
      resolved.add(await _recap.backend.resolveMedia(record));
    }
    if (!mounted) return;
    setState(() => _slides = resolved);
  }

  bool get hasSlides => _ordered.isNotEmpty;

  void _publish() {
    final story = _storyKey.currentState;
    if (story == null) return;
    _recap.publishSession(
      widget.journey.id,
      index: story.currentIndex,
      playing: story.isPlaying,
    );
  }

  void _toggleTogether() {
    if (_recap.together) {
      _recap.stopWatchingTogether();
      return;
    }
    _recap.startWatchingTogether(widget.journey.id);
    _publish();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 2),
      content: Text('Watching together — everyone follows your playback 🎬'),
    ));
  }

  void _onRecapChanged() {
    final session = _recap.session;
    if (session == null || !mounted || _mode == _RecapMode.reel) return;
    final story = _storyKey.currentState;
    if (story == null) return;
    if (story.currentIndex != session.index) {
      story.playIndex(session.index);
    }
    if (story.isPlaying != session.playing && story.currentIndex == session.index) {
      story.togglePlay();
    }
  }

  void _enterReelMode() {
    setState(() {
      _mode = _RecapMode.reel;
      final story = _storyKey.currentState;
      if (story != null && story.isPlaying) story.togglePlay();
    });
    _prepareReel();
  }

  void _leaveReelMode() {
    setState(() {
      _mode = _RecapMode.interactive;
      _reelReady = false;
      _reel?.dispose();
      _reel = null;
    });
    setState(() {});
  }

  Future<void> _prepareReel() async {
    if (_reelReady) return;
    if (!_reelBuildStarted) {
      _reelBuildStarted = true;
      setState(() {});
    }
    final reel = await _recap.compileJourneyReel(widget.journey.id);
    if (!mounted) return;
    if (reel == null) {
      setState(() => _reelReady = true);
      return;
    }
    final controller = VideoPlayerController.file(reel);
    await controller.initialize();
    controller.setLooping(false);
    controller.play();
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {
      _reel = controller;
      _reelReady = true;
    });
    controller.addListener(() {
      if (!mounted) return;
      if (controller.value.position >= controller.value.duration &&
          controller.value.isInitialized) {
        _recap.publishSession(widget.journey.id, index: 0, playing: false);
      }
    });
  }

  Future<void> _toggleReelPlay() async {
    if (_reel == null || !_reel!.value.isInitialized) return;
    _reel!.value.isPlaying ? _reel!.pause() : _reel!.play();
    setState(() {});
    _recap.publishSession(
      widget.journey.id,
      index: 0,
      playing: _reel!.value.isPlaying,
    );
  }

  Future<void> _exportShare() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Building the reel… this takes a moment'),
        duration: Duration(seconds: 1)));
    File? reel;
    try {
      reel = await _recap.compileJourneyReel(widget.journey.id);
    } catch (_) {
      reel = null;
    }
    if (!mounted) return;
    if (reel == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Nothing to export yet — add photos/videos first.')));
      return;
    }
    messenger.hideCurrentSnackBar();
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(reel.path, mimeType: 'video/mp4')],
        text: '${widget.journey.title} recap 🎬',
      ),
    );
    if (mounted && result.status != ShareResultStatus.dismissed) {
      messenger.showSnackBar(const SnackBar(content: Text('Shared!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cloudReady = _journeys.cloudReady;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.journey.title} · Recap'),
        actions: [
          IconButton(
            tooltip: 'Export & Share',
            onPressed: _exportShare,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          if (cloudReady)
            IconButton.filledTonal(
              tooltip: 'Watch together',
              onPressed: _toggleTogether,
              isSelected: _recap.together,
              icon: const Icon(Icons.groups_rounded),
              selectedIcon: const Icon(Icons.groups_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _mode == _RecapMode.interactive
                ? _buildInteractiveStage()
                : _buildReelStage(),
          ),
          _buildControls(scheme),
        ],
      ),
    );
  }

  Widget _buildControls(ColorScheme scheme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            SegmentedButton<_RecapMode>(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: const [
                ButtonSegment(
                  value: _RecapMode.interactive,
                  icon: Icon(Icons.touch_app_outlined),
                  tooltip: 'Interactive preview',
                  label: Text('Swipe'),
                ),
                ButtonSegment(
                  value: _RecapMode.reel,
                  icon: Icon(Icons.movie_creation_outlined),
                  tooltip: 'Compiled reel',
                  label: Text('Reel'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                selection.first == _RecapMode.reel
                    ? _enterReelMode()
                    : _leaveReelMode();
              },
            ),
            const Spacer(),
            if (_mode == _RecapMode.interactive)
              IconButton(
                onPressed: () =>
                    _storyKey.currentState?.togglePlay(),
                color: Colors.white,
                icon: Icon(
                  _storyKey.currentState?.isPlaying == true
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              )
            else
              IconButton(
                onPressed: _toggleReelPlay,
                color: Colors.white,
                icon: Icon(_reel?.value.isPlaying == true
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveStage() {
    if (!hasSlides) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🎞️', style: TextStyle(fontSize: 48)),
            SizedBox(height: 10),
            Text(
              'No memory with media yet',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    return StoryPlayer(
      key: _storyKey,
      records: _ordered,
      slides: _slides,
      holdSeconds: _recap.clipSeconds,
      dayNumber: (i) =>
          widget.journey.dayNumberOn(_ordered[i].timestamp),
      badgesOn: (i) => _recap.milestoneBadgesFor(_ordered[i]),
      onIndexChanged: (_) => _publish(),
      onTogglePlay: _publish,
      topRightOverlay: _recap.together
          ? const Text(
              '👀 together',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            )
          : null,
    );
  }

  Widget _buildReelStage() {
    if (_recap.compiling || (!_reelReady && _reelBuildStarted)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            Text(
              'Stitching your story… ${(_recap.reelProgress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }
    final reel = _reel;
    if (reel != null && reel.value.isInitialized) {
      return Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleReelPlay,
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(reel),
                if (!reel.value.isPlaying)
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        size: 72, color: Colors.white70),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _reelBuildStarted
                ? null
                : () {
                    setState(() {
                      _reelBuildStarted = true;
                    });
                    _prepareReel();
                  },
            icon: const Icon(Icons.movie_creation_outlined),
            label: const Text('Build reel'),
          ),
          const SizedBox(height: 8),
          Text('1080×1920 · ${_recap.clipSeconds.toStringAsFixed(0)}s per day · Day N overlay',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}