import 'dart:math';
import 'package:flutter/foundation.dart';

class MathUtils {
  static const double epsilon = 1e-9;

  /// Calculates the Euclidean distance between two points
  static double euclideanDistance(Point<double> p1, Point<double> p2) {
    return sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2));
  }

  /// Calculates the angle between three points with p2 as the vertex
  static double calculateAngle(Point<double> p1, Point<double> p2, Point<double> p3) {
    double a = euclideanDistance(p2, p3);
    double b = euclideanDistance(p1, p3);
    double c = euclideanDistance(p1, p2);

    if (a == 0 || c == 0) return 0.0;

    double cosB = (a * a + c * c - b * b) / (2 * a * c);
    return acos(cosB.clamp(-1.0, 1.0)) * (180.0 / pi);
  }

  /// Clamps a value between min and max
  static double clamp(double value, double minVal, double maxVal) {
    return min(max(value, minVal), maxVal);
  }

  /// Normalizes a value from [minRaw, maxRaw] to [0, 1]
  static double normalize(double rawValue, double minRaw, double maxRaw) {
    if ((maxRaw - minRaw).abs() < epsilon) {
       return 0.0;
    }
    double normalized = (rawValue - minRaw) / (maxRaw - minRaw);
    return clamp(normalized, 0.0, 1.0);
  }
  
  /// Scales a normalized value [0, 1] to a presentation score [0, 100]
  static int toPresentationScore(double normalizedValue) {
    return (clamp(normalizedValue, 0.0, 1.0) * 100).round();
  }
}

class MeasuredValue {
  final double raw;
  final double normalized;
  final double confidence;

  MeasuredValue({
    required this.raw,
    required this.normalized,
    required this.confidence,
  });
}
