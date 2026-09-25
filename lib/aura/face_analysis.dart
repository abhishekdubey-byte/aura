import 'dart:math';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Geometry measured from one ML Kit face (landmarks, contours and
/// classification). All ratios are scale-free; qualities are 0..1.
class FaceMetrics {
  FaceMetrics({
    required this.box,
    required this.sizeFraction,
    required this.centerX,
    required this.centerY,
    required this.yaw,
    required this.pitch,
    required this.roll,
    this.eyesOpen,
    this.smile,
    this.asymmetry,
    this.thirds,
    this.eyeSpacing,
    this.lengthRatio,
    this.jawRatio,
  });

  /// Face box in analysis-image pixels.
  final ({double left, double top, double width, double height}) box;
  /// Face box area / image area.
  final double sizeFraction;
  /// Face centre, 0..1 of image width / height.
  final double centerX, centerY;
  final double yaw, pitch, roll;
  final double? eyesOpen, smile;

  /// Mean left/right mismatch of paired features across the face midline
  /// (0 = perfectly symmetric).
  final double? asymmetry;
  /// Upper / middle / lower face thirds as fractions of face height.
  final List<double>? thirds;
  /// Eye distance / face width.
  final double? eyeSpacing;
  /// Face length / width.
  final double? lengthRatio;
  /// Jaw width (lower face) / widest face width.
  final double? jawRatio;

  /// How far the face turns from the camera, 0 (frontal) .. 1 (profile).
  double get turn => min(1.0, sqrt(yaw * yaw + pitch * pitch) / 45.0);

  static FaceMetrics fromFace(Face face, int imageWidth, int imageHeight) {
    final r = face.boundingBox;
    final double yaw = face.headEulerAngleY ?? 0, pitch = face.headEulerAngleX ?? 0, roll = face.headEulerAngleZ ?? 0;

    final oval = _points(face, FaceContourType.face);
    final leftEye = _landmark(face, FaceLandmarkType.leftEye) ?? _centroid(_points(face, FaceContourType.leftEye));
    final rightEye = _landmark(face, FaceLandmarkType.rightEye) ?? _centroid(_points(face, FaceContourType.rightEye));

    double? asymmetry, eyeSpacing, lengthRatio, jawRatio;
    List<double>? thirds;

    if (leftEye != null && rightEye != null && oval.length >= 30) {
      // Undo head roll using the eye line so vertical measures are upright
      final double angle = atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x);
      final Point<double> pivot = Point((leftEye.x + rightEye.x) / 2, (leftEye.y + rightEye.y) / 2);
      Point<double> up(Point<double> p) => _rotate(p, pivot, -angle);

      final uOval = oval.map(up).toList();
      final double iod = _dist(leftEye, rightEye);
      final double minX = uOval.map((p) => p.x).reduce(min), maxX = uOval.map((p) => p.x).reduce(max);
      final double minY = uOval.map((p) => p.y).reduce(min), maxY = uOval.map((p) => p.y).reduce(max);
      final double faceWidth = maxX - minX, faceHeight = maxY - minY;

      if (faceWidth > 1 && faceHeight > 1 && iod > 1) {
        eyeSpacing = iod / faceWidth;
        lengthRatio = faceHeight / faceWidth;

        // Midline from the nose bridge (fallback: between the eyes)
        final bridge = _points(face, FaceContourType.noseBridge).map(up).toList();
        final double midX = bridge.isNotEmpty ? bridge.map((p) => p.x).reduce((a, b) => a + b) / bridge.length : pivot.x;

        final pairs = <(Point<double>, Point<double>)>[];
        pairs.add((up(leftEye), up(rightEye)));
        final lm = _landmark(face, FaceLandmarkType.leftMouth), rm = _landmark(face, FaceLandmarkType.rightMouth);
        if (lm != null && rm != null) pairs.add((up(lm), up(rm)));
        final lc = _landmark(face, FaceLandmarkType.leftCheek), rc = _landmark(face, FaceLandmarkType.rightCheek);
        if (lc != null && rc != null) pairs.add((up(lc), up(rc)));
        // Face oval: point 0 is top centre; i and 36 - i mirror each other
        final int n = uOval.length;
        for (int i = 4; i <= 14; i += 2) {
          pairs.add((uOval[i], uOval[n - i]));
        }

        double total = 0;
        for (final (a, b) in pairs) {
          final double da = (a.x - midX).abs(), db = (b.x - midX).abs();
          final double horizontal = (da - db).abs() / max(da + db, 1e-6);
          final double vertical = (a.y - b.y).abs() / iod;
          total += horizontal + 0.5 * vertical;
        }
        asymmetry = total / pairs.length;

        // Facial thirds: forehead (oval top → brows), nose, lower face
        final brows = [
          ..._points(face, FaceContourType.leftEyebrowTop),
          ..._points(face, FaceContourType.rightEyebrowTop),
        ].map(up).toList();
        final noseBottom = _points(face, FaceContourType.noseBottom).map(up).toList();
        if (brows.isNotEmpty && noseBottom.isNotEmpty) {
          final double browY = brows.map((p) => p.y).reduce((a, b) => a + b) / brows.length;
          final double noseY = noseBottom.map((p) => p.y).reduce((a, b) => a + b) / noseBottom.length;
          final double upper = browY - minY, middle = noseY - browY, lower = maxY - noseY;
          if (upper > 0 && middle > 0 && lower > 0) {
            thirds = [upper / faceHeight, middle / faceHeight, lower / faceHeight];
          }
          // Jaw width a little above the chin vs the widest point
          final double jawY = noseY + 0.65 * (maxY - noseY);
          final double jawWidth = _widthAt(uOval, jawY);
          if (jawWidth > 0) jawRatio = jawWidth / faceWidth;
        }
      }
    }

    double? eyesOpen;
    final lo = face.leftEyeOpenProbability, ro = face.rightEyeOpenProbability;
    if (lo != null && ro != null) eyesOpen = (lo + ro) / 2;

    return FaceMetrics(
      box: (left: r.left, top: r.top, width: r.width, height: r.height),
      sizeFraction: (r.width * r.height) / (imageWidth * imageHeight),
      centerX: r.center.dx / imageWidth,
      centerY: r.center.dy / imageHeight,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      eyesOpen: eyesOpen,
      smile: face.smilingProbability,
      asymmetry: asymmetry,
      thirds: thirds,
      eyeSpacing: eyeSpacing,
      lengthRatio: lengthRatio,
      jawRatio: jawRatio,
    );
  }

  static List<Point<double>> _points(Face face, FaceContourType type) =>
      face.contours[type]?.points.map((p) => Point<double>(p.x.toDouble(), p.y.toDouble())).toList() ?? const [];

  static Point<double>? _landmark(Face face, FaceLandmarkType type) {
    final p = face.landmarks[type]?.position;
    return p == null ? null : Point<double>(p.x.toDouble(), p.y.toDouble());
  }

  static Point<double>? _centroid(List<Point<double>> pts) {
    if (pts.isEmpty) return null;
    double x = 0, y = 0;
    for (final p in pts) {
      x += p.x;
      y += p.y;
    }
    return Point(x / pts.length, y / pts.length);
  }

  static double _dist(Point<double> a, Point<double> b) => sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));

  static Point<double> _rotate(Point<double> p, Point<double> c, double a) {
    final double dx = p.x - c.x, dy = p.y - c.y;
    return Point(c.x + dx * cos(a) - dy * sin(a), c.y + dx * sin(a) + dy * cos(a));
  }

  /// Width of a closed contour at height [y] (distance between crossings).
  static double _widthAt(List<Point<double>> contour, double y) {
    final xs = <double>[];
    for (int i = 0; i < contour.length; i++) {
      final a = contour[i], b = contour[(i + 1) % contour.length];
      if ((a.y - y) * (b.y - y) <= 0 && a.y != b.y) {
        xs.add(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x));
      }
    }
    if (xs.length < 2) return 0;
    return xs.reduce(max) - xs.reduce(min);
  }
}
