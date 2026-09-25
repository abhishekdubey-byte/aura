import 'dart:io';

import 'package:aura/models/captured_photo.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

/// Full-screen viewer for photos taken this session. Opens instantly from the
/// local files, even while a photo is still being saved to the gallery.
class CapturePreviewScreen extends StatefulWidget {
  const CapturePreviewScreen({super.key, required this.photos});

  /// Newest first.
  final List<CapturedPhoto> photos;

  @override
  State<CapturePreviewScreen> createState() => _CapturePreviewScreenState();
}

class _CapturePreviewScreenState extends State<CapturePreviewScreen> {
  int _index = 0;

  Future<void> _openGalleryApp() async {
    try {
      await Gal.open();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open gallery app')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Decode at a bit above screen resolution: sharp, with room to zoom, without
    // holding full 16MP bitmaps in memory.
    final decodeWidth = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context) * 1.5).round();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _PhotoPage(photo: widget.photos[i], decodeWidth: decodeWidth),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      '${_index + 1} / ${widget.photos.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.photo_library, color: Colors.white),
                    tooltip: 'Open gallery',
                    onPressed: _openGalleryApp,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPage extends StatelessWidget {
  const _PhotoPage({required this.photo, required this.decodeWidth});

  final CapturedPhoto photo;
  final int decodeWidth;

  /// Shows the unsaved original with the same centred crop as the saved file
  /// (a no-op once the cropped file is shown).
  Widget _framed(Widget image) {
    final double? aspect = photo.aspect;
    if (aspect == null) return image;
    return AspectRatio(
      aspectRatio: aspect,
      child: ClipRect(child: FittedBox(fit: BoxFit.cover, child: image)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: photo.savedPath,
      builder: (context, savedPath, _) {
        final bool saved = savedPath != null;
        return Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Center(
                // Same widget structure before and after saving so gaplessPlayback
                // swaps the original for the saved file without a flash.
                child: _framed(
                  Transform.flip(
                    flipX: !saved && photo.mirrored,
                    child: Image.file(
                      File(savedPath ?? photo.originalPath),
                      cacheWidth: decodeWidth,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
            if (!saved)
              const SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Chip(
                      backgroundColor: Colors.black54,
                      side: BorderSide.none,
                      avatar: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      label: Text('Saving to gallery…', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
