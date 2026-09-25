import 'package:aura/camera/capture_aspect.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Outline of a rectangle at [ratio] (width / height), fitted in a square.
class AspectIcon extends StatelessWidget {
  const AspectIcon({super.key, required this.ratio, this.size = 18, this.color = Colors.white, this.strokeWidth = 1.8});

  final double ratio;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final double w = ratio >= 1 ? size : size * ratio;
    final double h = ratio >= 1 ? size / ratio : size;
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: strokeWidth),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing every framing by category, with the real output
/// resolution for photos (and video). Returns the chosen aspect.
Future<CaptureAspect?> showAspectRatioPicker(
  BuildContext context, {
  required CaptureAspect current,
  required Size screen,
  Size? photoFrame,
  Size videoFrame = const Size(1080, 1920),
  bool showOutputResolution = true,
}) {
  return showModalBottomSheet<CaptureAspect>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF141416),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => _AspectPickerSheet(
      current: current,
      screen: screen,
      photoFrame: photoFrame,
      videoFrame: videoFrame,
      showOutputResolution: showOutputResolution,
    ),
  );
}

class _AspectPickerSheet extends StatelessWidget {
  const _AspectPickerSheet({required this.current, required this.screen, required this.photoFrame, required this.videoFrame, required this.showOutputResolution});

  final CaptureAspect current;
  final Size screen;
  final Size? photoFrame;
  final Size videoFrame;
  final bool showOutputResolution;

  static String _format(Size s) => '${s.width.toInt()} × ${s.height.toInt()}';

  /// Wallpaper class of a landscape resolution
  static String? _wallpaperTag(Size s) {
    final double w = s.width;
    if (w >= 3840) return '4K';
    if (w >= 2560) return 'QHD';
    if (w >= 1920) return 'Full HD';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Aspect ratio', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'The viewfinder shows exactly what gets saved.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          for (final category in AspectCategory.values) ...[
            const SizedBox(height: 18),
            Text(
              category.title.toUpperCase(),
              style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1),
            ),
            if (category == AspectCategory.desktop)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Shoot a wallpaper that fits your laptop or monitor exactly.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final double tileWidth = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final aspect in CaptureAspect.values.where((a) => a.category == category))
                      SizedBox(width: tileWidth, child: _tile(context, aspect)),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, CaptureAspect aspect) {
    final bool selected = aspect == current;
    final double ratio = aspect.resolveRatio(screen);
    final Size? photo = photoFrame == null ? null : cropResolution(photoFrame!, ratio);
    final Size video = cropResolution(videoFrame, ratio);
    final String? tag = aspect.category == AspectCategory.desktop && photo != null ? _wallpaperTag(photo) : null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(context, aspect);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Colors.amber.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.amber : Colors.white12, width: selected ? 1.6 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectIcon(ratio: ratio, size: 30, color: selected ? Colors.amber : Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          aspect.label,
                          style: TextStyle(
                            color: selected ? Colors.amber : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)),
                          child: Text(tag, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(aspect.useCase, style: const TextStyle(color: Colors.white60, fontSize: 11.5, height: 1.25)),
                  const SizedBox(height: 5),
                  if (showOutputResolution && photo != null)
                    Text('Photo ${_format(photo)}', style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                  if (showOutputResolution)
                    Text('Video ${_format(video)}', style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Darkens everything outside [crop] and outlines it, so the viewfinder shows
/// exactly the area that will be saved.
class ViewfinderMaskPainter extends CustomPainter {
  ViewfinderMaskPainter(this.crop);

  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect screen = Offset.zero & size;
    final Rect visible = crop.intersect(screen);
    if (visible.width >= screen.width - 0.5 && visible.height >= screen.height - 0.5) return;
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(screen)
        ..addRect(crop),
      Paint()..color = const Color(0xE0000000),
    );
    canvas.drawRect(
      crop.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(ViewfinderMaskPainter old) => old.crop != crop;
}
