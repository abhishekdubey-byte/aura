class ScoreComponent {
  final String attribute;
  final String measurement;
  final int scoreImpact;
  final String description;

  ScoreComponent(this.attribute, this.measurement, this.scoreImpact, this.description);
}

class DimensionScore {
  final int score; // 0-100
  final double confidence; // 0.0 - 1.0
  final List<String> primaryTraits;
  final List<ScoreComponent> components;

  DimensionScore(this.score, this.confidence, this.primaryTraits, {this.components = const []});
}

class DetailedAuraScore {
  final int overallPoints; // Legacy massive gamified score
  final bool isBodyOnly; // True if face was not detected

  // New Explainable Categories (0-100)
  final DimensionScore? face; 
  final DimensionScore? eyes;
  final DimensionScore? expression;
  final DimensionScore body;
  final DimensionScore posture;
  final DimensionScore pose;
  final DimensionScore style;
  final DimensionScore image;
  final DimensionScore presence;
  final DimensionScore content; // Nudity/NSFW classification
  
  final String bodyShape;
  final double bodyShapeConfidence;

  final List<String> allSlangs;
  final Map<String, double> rawMetrics;

  DetailedAuraScore({
    required this.overallPoints,
    required this.isBodyOnly,
    this.face,
    this.eyes,
    this.expression,
    required this.body,
    required this.posture,
    required this.pose,
    required this.style,
    required this.image,
    required this.presence,
    required this.content,
    required this.bodyShape,
    required this.bodyShapeConfidence,
    required this.allSlangs,
    this.rawMetrics = const {},
  });
}
