import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../core/models/record_entry.dart';

/// Interactive story player (PRD Feature 05): a video/full-bleed media area
/// with a segmented horizontal story bar (Day 1, Day 2, ...) that supports
/// live scrubbing, tap zones, and swipe navigation. Used both as the primary
/// interface inside a Journey and for recaps.
class StoryPlayer extends StatefulWidget {
  final List<RecordEntry> records;
  final List<File?> slides;
  final int Function(int index)? dayNumber;
  final List<String> Function(int index)? badgesOn;
  final double holdSeconds;
  final bool autoPlay;
  final Widget? topRightOverlay;
  final ValueChanged<int>? onIndexChanged;
  final VoidCallback? onTogglePlay;

  const StoryPlayer({
    super.key,
    required this.records,
    required this.slides,
    this.dayNumber,
    this.badgesOn,
    this.holdSeconds = 3.0,
    this.autoPlay = true,
    this.topRightOverlay,
    this.onIndexChanged,
    this.onTogglePlay,
  });

  @override
  State<StoryPlayer> createState() => StoryPlayerState();
}

class StoryPlayerState extends State<StoryPlayer> {
  int _index = 0;
  bool _playing = true;
  VideoPlayerController? _video;
  Timer? _advanceTimer;

  int get currentIndex => _index;
  bool get isPlaying => _playing;

  @override
  void initState() {
    super.initState();
    _startAdvancing();
    _attachVideoFor(_index);
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _video?.dispose();
    super.dispose();
  }

  Duration get _holdDuration =>
      Duration(milliseconds: (widget.holdSeconds * 1000).round());

  void playIndex(int index) {
    if (widget.records.isEmpty) return;
    setState(() {
      _index = ((index % widget.records.length) + widget.records.length) %
          widget.records.length;
      _playing = widget.autoPlay;
    });
    _attachVideoFor(_index);
    _startAdvancing();
    widget.onIndexChanged?.call(_index);
  }

  void togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _startAdvancing();
    } else {
      _advanceTimer?.cancel();
    }
    final video = _video;
    if (video != null && video.value.isInitialized) {
      _playing ? video.play() : video.pause();
    }
    widget.onTogglePlay?.call();
  }

  void _startAdvancing() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    if (!_playing || !widget.autoPlay) return;
    _advanceTimer = Timer(_holdDuration, () {
      if (!mounted || !_playing || !widget.autoPlay) return;
      playIndex(_index + 1);
    });
  }

  Future<void> _attachVideoFor(int index) async {
    final previous = _video;
    _video = null;
    previous?.dispose();
    final record = widget.records[index];
    final file = widget.slides[index];
    if (record.mediaType != MediaType.video || file == null) return;
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    if (!mounted) return;
    setState(() => _video = controller);
    if (_playing) {
      controller.play();
      controller.setLooping(false);
    }
    var completedOnce = false;
    controller.addListener(() {
      if (!mounted) return;
      if (controller.value.position >= controller.value.duration &&
          !completedOnce) {
        completedOnce = true;
        playIndex(_index + 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          playIndex(_index + 1);
        } else if (velocity > 200) {
          playIndex(_index - 1);
        }
      },
      onTapUp: (details) {
        if (widget.records.length <= 1) {
          togglePlay();
          return;
        }
        final width = MediaQuery.of(context).size.width;
        if (details.localPosition.dx > width * 2 / 3) {
          playIndex(_index + 1);
        } else if (details.localPosition.dx < width * 1 / 3) {
          playIndex(_index - 1);
        } else {
          togglePlay();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildSlideMedia(_index),
          _buildScrubberBar(),
          if (widget.badgesOn != null)
            _buildBadgeChips(widget.badgesOn!(_index)),
          _buildCaption(_index),
          if (widget.topRightOverlay != null)
            Positioned(
              top: 48,
              right: 16,
              child: widget.topRightOverlay!,
            ),
        ],
      ),
    );
  }

  Widget _buildSlideMedia(int index) {
    final record = widget.records[index];
    final file = widget.slides[index];
    if (record.mediaType == MediaType.video) {
      final video = _video;
      if (video != null && video.value.isInitialized) {
        return Center(
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: VideoPlayer(video),
          ),
        );
      }
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: file != null
          ? Image.file(file, fit: BoxFit.contain)
          : const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white70),
                SizedBox(height: 8),
                Text('Resolving media…',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
    );
  }

  Widget _buildScrubberBar() {
    final n = widget.records.length;
    if (n <= 1) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              final raw =
                  details.localPosition.dx / barWidth * n;
              final index = raw.floor().clamp(0, n - 1);
              if (index != _index) playIndex(index);
            },
            child: Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                            begin: i < _index ? 1.0 : 0.0,
                            end: i <= _index ? 1.0 : 0.0),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, value, _) => ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                        ),
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

  Widget _buildBadgeChips(List<String> badges) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + (widget.records.length > 1 ? 34 : 12),
      left: 14,
      child: Row(
        children: [
          for (final badge in badges)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(badge, style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }

  Widget _buildCaption(int index) {
    final record = widget.records[index];
    final day = widget.dayNumber?.call(index);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (day != null)
              Text(
                'Day $day',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              DateFormat('EEEE, MMMM d, y').format(record.timestamp),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
            if ((record.note ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                record.note!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}