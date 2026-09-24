import 'dart:math';

class StatisticsEngine {
  /// Maps a value through a sigmoid curve to produce an S-curve output.
  /// Useful for soft-clipping and smooth score normalization.
  static double sigmoidCurve(double x, {double midpoint = 0.5, double steepness = 10.0}) {
    return 1.0 / (1.0 + exp(-steepness * (x - midpoint)));
  }

  /// Calculates the mean of a list of numbers
  static double mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Calculates the standard deviation of a list of numbers
  static double standardDeviation(List<double> values) {
    if (values.isEmpty) return 0.0;
    double mu = mean(values);
    double variance = values.map((x) => pow(x - mu, 2)).reduce((a, b) => a + b) / values.length;
    return sqrt(variance);
  }
}
