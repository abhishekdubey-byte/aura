import '../theme/aura_theme.dart';

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AuraCaptionLayout {
  const AuraCaptionLayout(this.rect, this.outputSize, this.scale);
  final Rect rect;
  final Size outputSize;
  final double scale;

  /// Uses actual photo pixels, independent of the device screen or SafeArea.
  static AuraCaptionLayout place(
    Size photo,
    List<Rect> subjects,
    Size caption,
  ) {
    final margin = photo.shortestSide * 0.025;
    final blockers = subjects.map((r) => r.inflate(margin)).toList();
    for (final scale in [1.0, 0.85, 0.7]) {
      final w = caption.width * scale, h = caption.height * scale;
      final xs = <double>[margin, photo.width - margin - w];
      final ys = <double>[margin];
      for (final r in blockers) {
        xs.addAll([r.left - w, r.right]);
        ys.addAll([r.top - h, r.top, r.center.dy - h / 2, r.bottom]);
      }
      // Prefer high clear space so the caption sits above/beside the subject.
      final candidates = <Rect>[];
      for (final y in ys) {
        for (final x in xs) {
          final r = Rect.fromLTWH(x, y, w, h);
          if (r.left >= margin &&
              r.top >= margin &&
              r.right <= photo.width - margin &&
              r.bottom <= photo.height - margin &&
              !blockers.any(r.overlaps)) {
            candidates.add(r);
          }
        }
      }
      if (candidates.isNotEmpty) {
        candidates.sort((a, b) => a.top.compareTo(b.top));
        return AuraCaptionLayout(candidates.first, photo, scale);
      }
    }
    // Crowded photos cannot guarantee empty space: extend the canvas instead
    // of covering someone or silently removing the score.
    return AuraCaptionLayout(
      Rect.fromLTWH(
        margin,
        photo.height + margin,
        caption.width,
        caption.height,
      ),
      Size(photo.width, photo.height + caption.height + margin * 2),
      1,
    );
  }
}

/// Composites directly onto the decoded original. No widget screenshots,
/// screen-resolution scaling, navigation controls or preview letterboxing.
class AuraPhotoComposer {
  static Future<String> compose({
    required String imagePath,
    required int score,
    required String slang,
    required List<Rect> subjectRegions,
    String? watermark,
  }) async {
    final codec = await ui.instantiateImageCodec(
      await File(imagePath).readAsBytes(),
    );
    ui.Image? original;
    ui.Image? output;
    ui.Picture? picture;
    try {
      original = (await codec.getNextFrame()).image;
      final size = Size(original.width.toDouble(), original.height.toDouble());
      final unit = size.shortestSide / 400;
      final width = math.min(size.width * 0.8, 185 * unit);
      final pad = 12 * unit;
      TextPainter text(
        String value,
        double fontSize, {
        FontWeight weight = FontWeight.w600,
        Color color = Colors.white,
      }) => TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: fontSize * unit,
            fontWeight: weight,
            color: color,
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - pad * 2);
      final number = score.abs().toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      final lines = [
        text('${score >= 0 ? '+' : '-'}$number', 22, weight: FontWeight.w800),
        text('AURA LEVEL', 11, color: AuraColors.primary),
        text(slang, 14),
        if (watermark != null && watermark.isNotEmpty)
          text(watermark, 9, color: Colors.white70),
      ];
      final height =
          pad * 2 +
          lines.fold<double>(0, (s, t) => s + t.height) +
          (lines.length - 1) * 6 * unit;
      final layout = AuraCaptionLayout.place(
        size,
        subjectRegions,
        Size(width, height),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(AuraColors.background, BlendMode.src);
      canvas.drawImage(original, Offset.zero, Paint());
      canvas.save();
      canvas.translate(layout.rect.left, layout.rect.top);
      canvas.scale(layout.scale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, width, height),
          Radius.circular(14 * unit),
        ),
        Paint()..color = AuraColors.surface.withValues(alpha: .92),
      );
      double y = pad;
      for (final line in lines) {
        line.paint(canvas, Offset(pad, y));
        y += line.height + 6 * unit;
        line.dispose();
      }
      canvas.restore();
      picture = recorder.endRecording();
      output = await picture.toImage(
        layout.outputSize.width.ceil(),
        layout.outputSize.height.ceil(),
      );
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode the Aura photo');
      final path =
          '${(await getTemporaryDirectory()).path}/aura_result_${DateTime.now().microsecondsSinceEpoch}.png';
      await File(path).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return path;
    } finally {
      codec.dispose();
      original?.dispose();
      output?.dispose();
      picture?.dispose();
    }
  }
}
