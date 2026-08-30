import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/journey.dart';
import '../../core/models/record_entry.dart';
import '../../core/services/media_service.dart';

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
  static const _slideDuration = Duration(milliseconds: 2400);

  late List<File?> _slides;
  int _index = 0;
  bool _playing = true;

  bool _together = false;
  StreamSubscription? _sessionSub;
  DateTime _lastRemoteUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _slides = List<File?>.filled(widget.records.length, null);
    _resolveSlides();
    _advanceLoop();
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }

  Future<void> _resolveSlides() async {
    final resolved = <File?>[];
    for (final record in widget.records) {
      resolved.add(await MediaService.resolve(record.mediaUrl));
    }
    if (!mounted) return;
    setState(() => _slides = resolved);
  }

  AppState get _state => context.read<AppState>();

  Future<void> _publish() async {
    if (!_together) return;
    await _state.backend.publishRecapState(
      widget.journey.id,
      index: _index,
      playing: _playing,
    );
  }

  void _advanceLoop() {
    Future.doWhile(() async {
      await Future<void>.delayed(_slideDuration);
      if (!mounted) return false;
      if (!_playing || _slides.isEmpty) return true;
      setState(() => _index = (_index + 1) % _slides.length);
      await _publish();
      return true;
    });
  }

  Future<void> _toggleTogether() async {
    final state = _state;
    final turningOn = !_together;
    setState(() => _together = turningOn);
    await _sessionSub?.cancel();
    _sessionSub = null;
    if (!turningOn) return;
    _sessionSub =
        state.backend.recapSessionStream(widget.journey.id).listen((session) {
      if (!mounted || session == null) return;
      if (session.updatedAt.isBefore(_lastRemoteUpdate)) return;
      final me = state.profile?.displayName ?? '';
      if (session.updatedByName == me &&
          DateTime.now().difference(session.updatedAt).inSeconds < 5) {
        return;
      }
      _lastRemoteUpdate = session.updatedAt;
      if (_slides.isEmpty) return;
      setState(() {
        _index = session.index.clamp(0, _slides.length - 1);
        _playing = session.playing;
      });
    });
    await _publish();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 2),
          content: Text(
              'Watching together — everyone with this journey open follows your playback 🎬')));
    }
  }

  bool get hasAnySlide => _slides.any((f) => f != null);

  void _showExportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export HD video'),
        content: const Text(
            'Watermark-free HD export and premium recap templates are coming soon. '
            'For now, enjoy your in-app slideshow recap!'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final journey = widget.journey;
    final scheme = Theme.of(context).colorScheme;
    final hasSlides = hasAnySlide && _index < _slides.length;
    final currentRecord = hasSlides ? widget.records[_index] : null;
    final file = hasSlides ? _slides[_index] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('${journey.title} · Recap'),
        actions: [
          IconButton(
            tooltip: 'Export',
            onPressed: () => _showExportDialog(context),
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildStage(file, currentRecord)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () async {
                      setState(() => _playing = !_playing);
                      await _publish();
                    },
                    icon: Icon(_playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value:
                            _slides.isEmpty ? 0 : (_index + 1) / _slides.length,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _slides.isEmpty ? '0' : '${_index + 1}/${_slides.length}',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                  if (state.cloudReady)
                    IconButton.filledTonal(
                      tooltip: 'Watch together',
                      onPressed: _toggleTogether,
                      isSelected: _together,
                      icon: const Icon(Icons.groups_rounded),
                      selectedIcon: const Icon(Icons.groups_rounded),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage(File? file, RecordEntry? record) {
    if (!hasAnySlide) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('🎞️', style: TextStyle(fontSize: 48)),
            SizedBox(height: 10),
            Text('No photos in this journey yet'),
          ],
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: Container(
            key: ValueKey(_index),
            color: Colors.black,
            alignment: Alignment.center,
            child: file != null
                ? Image.file(file, fit: BoxFit.contain)
                : const CircularProgressIndicator(),
          ),
        ),
        Positioned(
          top: 12,
          right: 16,
          child: AnimatedOpacity(
            opacity: _together ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('👀 together',
                  style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
        ),
        if (record != null)
          Positioned(
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
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Day ${widget.journey.dayNumberOn(record.timestamp)}',
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
                        fontSize: 13),
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
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
