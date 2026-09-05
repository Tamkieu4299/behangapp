import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/record_entry.dart';
import '../../core/services/app_settings.dart';
import '../../state/journey_controller.dart';
import '../../state/timeline_controller.dart';

class CaptureRecordScreen extends StatefulWidget {
  final String journeyId;

  const CaptureRecordScreen({super.key, required this.journeyId});

  @override
  State<CaptureRecordScreen> createState() => _CaptureRecordScreenState();
}

class _CaptureRecordScreenState extends State<CaptureRecordScreen> {
  final _noteController = TextEditingController();
  XFile? _media;
  bool _isVideo = false;
  bool _saving = false;
  double _clipSeconds = 1.0;

  @override
  void initState() {
    super.initState();
    AppSettings.loadClipSeconds().then((seconds) {
      if (mounted) setState(() => _clipSeconds = seconds);
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source, {required bool video}) async {
    final picker = ImagePicker();
    final picked = video
        ? await picker.pickVideo(source: source)
        : await picker.pickImage(source: source, maxWidth: 2048);
    if (picked != null && mounted) {
      setState(() {
        _media = picked;
        _isVideo = video;
      });
    }
  }

  Future<void> _chooseSource() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.camera, video: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.gallery, video: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record video'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.camera, video: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Choose video'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.gallery, video: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notes_rounded),
              title: const Text('Note only'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_media == null && _noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add a photo, a video, or a note first.')));
      return;
    }
    setState(() => _saving = true);

    final entry = RecordEntry(
      id: const Uuid().v4(),
      journeyId: widget.journeyId,
      timestamp: DateTime.now(),
      mediaType:
          _media == null ? MediaType.none : (_isVideo ? MediaType.video : MediaType.photo),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );
    if (!mounted) return;
    final timeline = context.read<TimelineController>();
    try {
      await timeline.addRecord(
        entry,
        mediaFile: _media,
        // PRD Feature 03: videos are trimmed server-side to the configured
        // clip length (falls back to the raw clip if the worker is down).
        videoTrimSeconds: _isVideo ? _clipSeconds : null,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not upload right now. Try again.')));
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final journeys = context.watch<JourneyController>();
    final journey = journeys.journey(widget.journeyId);
    final dayLabel = journey == null
        ? null
        : 'Day ${journey.dayNumberOn(DateTime.now())} of ${journey.title}';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Capture today'),
            if (dayLabel != null)
              Text(
                dayLabel,
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GestureDetector(
              onTap: _chooseSource,
              child: Container(
                height: 240,
                decoration: BoxDecoration(
                  color:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: _buildMediaPreview(scheme),
              ),
            ),
            const SizedBox(height: 8),
            if (_isVideo && _media != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Center(
                  child: Text(
                    '✂️ Video will be trimmed to ${_clipSeconds.toStringAsFixed(1)}s on upload',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ),
              ),
            Center(
              child: TextButton.icon(
                onPressed: _chooseSource,
                icon: Icon(_media == null
                    ? Icons.add_a_photo_outlined
                    : Icons.swap_horiz_rounded),
                label: Text(_media == null
                    ? 'Add photo or video'
                    : 'Replace media'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What happened today? First tries count double',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save moment', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview(ColorScheme scheme) {
    final media = _media;
    if (media == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 44, color: scheme.outline),
          const SizedBox(height: 8),
          Text('Tap to add today\'s moment',
              style: TextStyle(color: scheme.outline)),
        ],
      );
    }
    if (_isVideo) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_circle_fill_rounded,
              size: 48, color: scheme.primary),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              media.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return Image.file(File(media.path), fit: BoxFit.cover);
  }
}
