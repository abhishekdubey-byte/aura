import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Normalized cell bounds and shapes shared by icons, preview and export.
enum LayoutTemplate {
  quad('Four', [
    Rect.fromLTWH(0, 0, .5, .5),
    Rect.fromLTWH(.5, 0, .5, .5),
    Rect.fromLTWH(0, .5, .5, .5),
    Rect.fromLTWH(.5, .5, .5, .5),
  ]),
  rows('Two rows', [Rect.fromLTWH(0, 0, 1, .5), Rect.fromLTWH(0, .5, 1, .5)]),
  columns('Two columns', [
    Rect.fromLTWH(0, 0, .5, 1),
    Rect.fromLTWH(.5, 0, .5, 1),
  ]),
  thirds('Three rows', [
    Rect.fromLTWH(0, 0, 1, 1 / 3),
    Rect.fromLTWH(0, 1 / 3, 1, 1 / 3),
    Rect.fromLTWH(0, 2 / 3, 1, 1 / 3),
  ]),
  six('Six', [
    Rect.fromLTWH(0, 0, .5, 1 / 3),
    Rect.fromLTWH(.5, 0, .5, 1 / 3),
    Rect.fromLTWH(0, 1 / 3, .5, 1 / 3),
    Rect.fromLTWH(.5, 1 / 3, .5, 1 / 3),
    Rect.fromLTWH(0, 2 / 3, .5, 1 / 3),
    Rect.fromLTWH(.5, 2 / 3, .5, 1 / 3),
  ]),
  featured('One + two', [
    Rect.fromLTWH(0, 0, .5, 1),
    Rect.fromLTWH(.5, 0, .5, .5),
    Rect.fromLTWH(.5, .5, .5, .5),
  ]),
  diamondEight('Diamond eight', [
    // Three above, two staggered in the middle, three below. The bounds
    // overlap, but the diamond masks leave a small gap between photographs.
    Rect.fromLTWH(.10, .07, .26, .42),
    Rect.fromLTWH(.37, .07, .26, .42),
    Rect.fromLTWH(.64, .07, .26, .42),
    Rect.fromLTWH(.235, .285, .26, .42),
    Rect.fromLTWH(.505, .285, .26, .42),
    Rect.fromLTWH(.10, .50, .26, .42),
    Rect.fromLTWH(.37, .50, .26, .42),
    Rect.fromLTWH(.64, .50, .26, .42),
  ]),
  nineStrips('Nine strips', [
    Rect.fromLTWH(0, 0, 1 / 9, 1),
    Rect.fromLTWH(1 / 9, 0, 1 / 9, 1),
    Rect.fromLTWH(2 / 9, 0, 1 / 9, 1),
    Rect.fromLTWH(3 / 9, 0, 1 / 9, 1),
    Rect.fromLTWH(4 / 9, 0, 1 / 9, 1),
    Rect.fromLTWH(5 / 9, 0, 1 / 9, 1),
    Rect.fromLTWH(6 / 9, 0, 1 / 9, 1),
    Rect.fromLTWH(7 / 9, 0, 1 / 9, 1),
    Rect.fromLTWH(8 / 9, 0, 1 / 9, 1),
  ]),
  sevenStrips('Seven strips', [
    Rect.fromLTWH(0, 0, 1 / 7, 1),
    Rect.fromLTWH(1 / 7, 0, 1 / 7, 1),
    Rect.fromLTWH(2 / 7, 0, 1 / 7, 1),
    Rect.fromLTWH(3 / 7, 0, 1 / 7, 1),
    Rect.fromLTWH(4 / 7, 0, 1 / 7, 1),
    Rect.fromLTWH(5 / 7, 0, 1 / 7, 1),
    Rect.fromLTWH(6 / 7, 0, 1 / 7, 1),
  ]);

  const LayoutTemplate(this.label, this.cells);
  final String label;
  final List<Rect> cells;
  bool get isDiamond => this == diamondEight;

  Path cellPath(Rect bounds) {
    if (!isDiamond) return Path()..addRect(bounds);
    return Path()
      ..moveTo(bounds.center.dx, bounds.top)
      ..lineTo(bounds.right, bounds.center.dy)
      ..lineTo(bounds.center.dx, bounds.bottom)
      ..lineTo(bounds.left, bounds.center.dy)
      ..close();
  }

  /// Pixel centers use the same diamond inequality as the video alpha mask.
  bool containsInCell(Rect bounds, Offset point) =>
      bounds.contains(point) &&
      (!isDiamond ||
          ((point.dx - bounds.center.dx).abs() / (bounds.width / 2) +
                  (point.dy - bounds.center.dy).abs() / (bounds.height / 2)) <=
              1);

  static const diamondMaskExpression =
      'if(lte(abs(2*(X+0.5)/W-1)+abs(2*(Y+0.5)/H-1),1),255,0)';

  /// Shared, even pixel boundaries avoid encoder seams, including thirds.
  List<Rect> pixelRects(Size output) => cells.map((r) {
    double x(double v) => (v * output.width / 2).round() * 2.0;
    double y(double v) => (v * output.height / 2).round() * 2.0;
    return Rect.fromLTRB(x(r.left), y(r.top), x(r.right), y(r.bottom));
  }).toList();
}

Size layoutOutputSize(double ratio, {int longEdge = 1920}) {
  if (!ratio.isFinite || ratio <= 0 || longEdge < 12) {
    throw ArgumentError('Invalid layout dimensions');
  }
  double even(double n) => math.max(2, (n / 2).round() * 2).toDouble();
  return ratio >= 1
      ? Size(even(longEdge.toDouble()), even(longEdge / ratio))
      : Size(even(longEdge * ratio), even(longEdge.toDouble()));
}

/// Center-cover crop in upright source coordinates; never distorts the source.
Rect layoutSourceCrop(Size source, double ratio) {
  final w = math.min(source.width, source.height * ratio);
  final h = math.min(source.height, source.width / ratio);
  return Rect.fromLTWH((source.width - w) / 2, (source.height - h) / 2, w, h);
}
