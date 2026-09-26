import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Conservative exclusion regions in upright source-photo coordinates.
/// Segmentation protects clothing/hair too; landmarks alone are only a skeleton.
class SubjectRegions {
  static List<Rect> detect({
    required List<Face> faces,
    required List<Pose> poses,
    required int width,
    required int height,
    required int sourceWidth,
    required int sourceHeight,
    List<double>? mask,
  }) {
    final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final regions = <Rect>[];
    bool segmented = false;
    if (mask != null && mask.length == width * height) {
      int left = width, top = height, right = -1, bottom = -1;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          if (mask[y * width + x] >= 0.35) {
            left = math.min(left, x);
            right = math.max(right, x);
            top = math.min(top, y);
            bottom = math.max(bottom, y);
          }
        }
      }
      if (right >= left && bottom >= top) {
        regions.add(
          Rect.fromLTRB(
            left.toDouble(),
            top.toDouble(),
            right + 1.0,
            bottom + 1.0,
          ).inflate(width * 0.025),
        );
        segmented = true;
      }
    }
    for (final face in faces) {
      final b = face.boundingBox;
      // Include hair above and beside the detector's facial bounding box.
      regions.add(
        Rect.fromLTRB(
          b.left - b.width * 0.25,
          b.top - b.height * 0.45,
          b.right + b.width * 0.25,
          b.bottom + b.height * 0.15,
        ),
      );
      if (!segmented) {
        // A close-up may have no pose. Reserve the likely shoulders/torso too.
        regions.add(
          Rect.fromLTRB(
            b.center.dx - b.width * 1.8,
            b.bottom,
            b.center.dx + b.width * 1.8,
            height.toDouble(),
          ),
        );
      }
    }
    for (final pose in poses) {
      final visible = pose.landmarks.values
          .where(
            (p) =>
                p.likelihood >= 0.6 &&
                p.x >= 0 &&
                p.x <= width &&
                p.y >= 0 &&
                p.y <= height,
          )
          .toList();
      if (visible.length < 4) continue;
      final b = Rect.fromLTRB(
        visible.map((p) => p.x).reduce(math.min),
        visible.map((p) => p.y).reduce(math.min),
        visible.map((p) => p.x).reduce(math.max),
        visible.map((p) => p.y).reduce(math.max),
      );
      regions.add(b.inflate(math.max(width * 0.05, b.width * 0.12)));
    }
    // Without localization (for example illustrated people), do not guess a
    // safe spot over the photo. The exporter will add a caption strip instead.
    if (regions.isEmpty) regions.add(bounds);
    return regions
        .map((r) => r.intersect(bounds))
        .where((r) => !r.isEmpty)
        .map(
          (r) => Rect.fromLTRB(
            r.left * sourceWidth / width,
            r.top * sourceHeight / height,
            r.right * sourceWidth / width,
            r.bottom * sourceHeight / height,
          ),
        )
        .toList();
  }
}
