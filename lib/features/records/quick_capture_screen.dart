import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/record_entry.dart';
import '../../core/services/app_settings.dart';
import '../../state/journey_controller.dart';
import '../../state/timeline_controller.dart';
import 'capture_record_screen.dart';

enum _CaptureMode { video, photo }

class QuickCaptureScreen extends StatefulWidget {
  final String journeyId;

  const QuickCaptureScreen({super.key, required this.journeyId});

  @override
  State<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends State<QuickCaptureScreen> {
  final _noteController = TextEditingController();
  CameraController? _camera;
  _CaptureMode _mode = _CaptureMode.video;
  double _clipSeconds = 1.0;
  bool _ready = false;
  bool _recording = false;
  bool _captured = false;
  bool _saving = false;
  bool _frontCamera = true;
  Timer? _autoStop;
  XFile? _media;

  @override
  void initState() {
    super.initState();
    AppSettings.loadClipSeconds().then((seconds) {
      if (mounted) setState(() => _clipSeconds = seconds);
    });
    _initCamera();
  }

  @override
  void dispose() {
    _autoStop?.cancel();
    _noteController.dispose();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        _fallbackToGalleryFlow();
        return;
      }
      final CameraDescription target;
      if (_frontCamera) {
        target = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
      } else {
        target = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.last,
        );
      }
      final controller = CameraController(
        target,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _ready = true;
      });
      if (_mode == _CaptureMode.video) {
        // PRD Feature 03: the clip begins on its own so capture takes one tap.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mounted && !_captured && !_recording) {
          await _startRecording();
        }
      }
    } on CameraException catch (_) {
      if (!mounted) return;
      _fallbackToGalleryFlow();
    }
  }

  void _fallbackToGalleryFlow() {
    // Camera unavailable (e.g. simulator) — hand off to the picker flow.
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => CaptureRecordScreen(journeyId: widget.journeyId),
    ));
  }

  void _flipCamera() {
    if (_recording || _saving) return;
    setState(() {
      _frontCamera = !_frontCamera;
      _ready = false;
    });
    final old = _camera;
    _camera = null;
    old?.dispose();
    _initCamera();
  }

  void _setMode(_CaptureMode mode) {
    if (_recording || _saving || mode == _mode) return;
    setState(() => _mode = mode);
    if (mode == _CaptureMode.video && !_captured) {
      _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final camera = _camera;
    if (camera == null || _recording || _captured) return;
    try {
      await camera.startVideoRecording();
    } catch (_) {
      if (!mounted) return;
      _fallbackToGalleryFlow();
      return;
    }
    if (!mounted) return;
    setState(() => _recording = true);
    _autoStop?.cancel();
    _autoStop = Timer(Duration(milliseconds: (_clipSeconds * 1000).round()),
        () => _stopRecording());
  }

  Future<void> _stopRecording() async {
    final camera = _camera;
    if (camera == null || !_recording) return;
    _autoStop?.cancel();
    XFile? file;
    try {
      file = await camera.stopVideoRecording();
    } catch (_) {
      if (!mounted) return;
      setState(() => _recording = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _media = file;
      _captured = true;
    });
  }

  Future<void> _snapPhoto() async {
    final camera = _camera;
    if (camera == null || _recording || _captured || _mode != _CaptureMode.photo) {
      return;
    }
    try {
      final file = await camera.takePicture();
      if (!mounted) return;
      setState(() {
        _media = file;
        _captured = true;
      });
    } catch (_) {}
  }

  Future<void> _pickGallery() async {
    if (_recording || _saving) return;
    final picker = ImagePicker();
    final picked = _mode == _CaptureMode.video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, maxWidth: 2048);
    if (picked == null || !mounted) return;
    setState(() {
      _media = picked;
      _captured = true;
    });
  }

  void _retake() {
    setState(() {
      _captured = false;
      _media = null;
    });
    if (_mode == _CaptureMode.video) {
      _startRecording();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final media = _media;
    if (media == null && _noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add a photo, a video, or a note first.')));
      return;
    }
    setState(() => _saving = true);

    final entry = RecordEntry(
      id: const Uuid().v4(),
      journeyId: widget.journeyId,
      timestamp: DateTime.now(),
      mediaType: media == null
          ? MediaType.none
          : (_mode == _CaptureMode.video ? MediaType.video : MediaType.photo),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );
    if (!mounted) return;
    final timeline = context.read<TimelineController>();
    try {
      await timeline.addRecord(
        entry,
        mediaFile: media,
        // PRD Feature 03: videos are trimmed server-side to the configured
        // clip length (falls back to the raw clip if the worker is down).
        videoTrimSeconds:
            media != null && _mode == _CaptureMode.video ? _clipSeconds : null,
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

  Future<void> _close() async {
    if (_recording) {
      _autoStop?.cancel();
      try {
        await _camera?.stopVideoRecording();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final journeys = context.watch<JourneyController>();
    final journey = journeys.journey(widget.journeyId);
    final dayLabel = journey == null
        ? null
        : 'Day ${journey.dayNumberOn(DateTime.now())} of ${journey.title}';
    final camera = _camera;
    final showLive = !_captured && !_saving && camera != null && _ready;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (showLive)
            CameraPreview(camera)
          else
            _buildReviewPanel(scheme),
          if (showLive) _buildCameraOverlay(scheme, dayLabel),
          if (_saving)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraOverlay(ColorScheme scheme, String? dayLabel) {
    return SafeArea(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _close,
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
              ),
              if (dayLabel != null)
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        dayLabel,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              IconButton(
                onPressed: _flipCamera,
                icon: const Icon(Icons.flip_camera_ios_rounded),
                color: Colors.white,
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _pickGallery,
                icon: const Icon(Icons.photo_library_outlined),
                color: Colors.white,
                iconSize: 28,
              ),
              const SizedBox(width: 32),
              _buildShutter(scheme),
              const SizedBox(width: 32),
              _buildModeToggle(scheme),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildShutter(ColorScheme scheme) {
    final recording = _recording;
    return GestureDetector(
      onTap: _mode == _CaptureMode.video
          ? () => recording ? _stopRecording() : _startRecording()
          : _snapPhoto,
      child: Container(
        width: 72,
        height: 72,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: recording ? const Color(0xFFE53935) : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle(ColorScheme scheme) {
    final isVideo = _mode == _CaptureMode.video;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _recording || _saving
                ? null
                : () => _setMode(_CaptureMode.video),
            icon: Icon(Icons.videocam_rounded,
                color: isVideo ? Colors.white : Colors.white38),
          ),
          IconButton(
            onPressed: _recording || _saving
                ? null
                : () => _setMode(_CaptureMode.photo),
            icon: Icon(Icons.photo_camera_rounded,
                color: !isVideo ? Colors.white : Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewPanel(ColorScheme scheme) {
    if (!_captured) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final media = _media;
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            alignment: Alignment.center,
            child: media == null
                ? const SizedBox.shrink()
                : _buildMediaPreview(scheme, media),
          ),
        ),
        Container(
          color: scheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_mode == _CaptureMode.video && media != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Clip will be trimmed to ${_clipSeconds.toStringAsFixed(1)}s',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Note (optional) — first tries count double',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _retake,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retake'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48)),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Save moment'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaPreview(ColorScheme scheme, XFile media) {
    if (_mode == _CaptureMode.video) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.play_circle_fill_rounded,
              size: 48, color: Colors.white),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              media.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      );
    }
    return Image.file(File(media.path), fit: BoxFit.contain);
  }
}