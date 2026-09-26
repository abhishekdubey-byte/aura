import 'dart:io';

import 'package:aura/models/captured_photo.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/aura_theme.dart';
import '../widgets/aura_controls.dart';

class CapturePreviewScreen extends StatefulWidget {
  const CapturePreviewScreen({super.key, required this.photos});
  final List<CapturedPhoto> photos;
  @override
  State<CapturePreviewScreen> createState() => _CapturePreviewScreenState();
}

class _CapturePreviewScreenState extends State<CapturePreviewScreen> {
  int _index = 0;
  bool _sharing = false;
  Future<void> _gallery() async {
    try {
      await Gal.open();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open your gallery.')),
        );
      }
    }
  }

  Future<void> _share(String path) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final box = context.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not share this photo. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your photos')),
        body: AuraEmptyState(
          icon: Icons.photo_library_outlined,
          title: 'Make your first moment',
          message: 'Photos you capture appear here.',
          action: 'Back to camera',
          onAction: () => Navigator.maybePop(context),
        ),
      );
    }
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context) *
                1.5)
            .round();
    final current = widget.photos[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('Photo ${_index + 1} of ${widget.photos.length}'),
        actions: [
          IconButton(
            tooltip: 'Open gallery',
            onPressed: _gallery,
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                itemCount: widget.photos.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) =>
                    _PhotoPage(photo: widget.photos[i], decodeWidth: width),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ValueListenableBuilder<String?>(
                valueListenable: current.savedPath,
                builder: (_, saved, _) => ValueListenableBuilder<String?>(
                  valueListenable: current.saveError,
                  builder: (_, error, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (error != null) ...[
                        AuraNotice(error, error: true),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: current.retrySave,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry save'),
                        ),
                      ] else if (saved == null)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text('Saving to your gallery…'),
                            ],
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Saved to your gallery',
                            style: TextStyle(
                              color: AuraColors.green,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: AuraButton(
                          label: 'Share photo',
                          icon: Icons.ios_share_rounded,
                          busy: _sharing,
                          onPressed: saved == null ? null : () => _share(saved),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPage extends StatelessWidget {
  const _PhotoPage({required this.photo, required this.decodeWidth});
  final CapturedPhoto photo;
  final int decodeWidth;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: photo.savedPath,
    builder: (_, saved, _) {
      Widget image = Transform.flip(
        flipX: saved == null && photo.mirrored,
        child: Image.file(
          File(saved ?? photo.originalPath),
          cacheWidth: decodeWidth,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const AuraEmptyState(
            icon: Icons.broken_image_outlined,
            title: 'Photo unavailable',
            message: 'This file may have been moved or removed.',
          ),
        ),
      );
      if (photo.aspect != null) {
        image = AspectRatio(
          aspectRatio: photo.aspect!,
          child: ClipRect(
            child: FittedBox(fit: BoxFit.cover, child: image),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: InteractiveViewer(maxScale: 5, child: Center(child: image)),
        ),
      );
    },
  );
}
