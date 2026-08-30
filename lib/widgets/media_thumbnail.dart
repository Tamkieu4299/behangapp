import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models/record_entry.dart';
import '../core/services/media_service.dart';

class MediaThumbnail extends StatefulWidget {
  final String? relativePath;
  final MediaType mediaType;
  final BoxFit fit;
  final double iconSize;
  final BorderRadius borderRadius;

  const MediaThumbnail({
    super.key,
    required this.relativePath,
    required this.mediaType,
    this.fit = BoxFit.cover,
    this.iconSize = 28,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  late Future<File?> _future;

  @override
  void initState() {
    super.initState();
    _future = MediaService.resolve(widget.relativePath);
  }

  @override
  void didUpdateWidget(covariant MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) {
      _future = MediaService.resolve(widget.relativePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snapshot) {
        final file = snapshot.data;
        final hasImage =
            file != null && widget.mediaType != MediaType.none;
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: scheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: hasImage
                    ? Image.file(file, fit: widget.fit, gaplessPlayback: true)
                    : Icon(
                        switch (widget.mediaType) {
                          MediaType.video => Icons.play_circle_outline,
                          MediaType.photo => Icons.photo_outlined,
                          MediaType.none => Icons.edit_note_outlined,
                        },
                        size: widget.iconSize,
                        color: scheme.outline,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
