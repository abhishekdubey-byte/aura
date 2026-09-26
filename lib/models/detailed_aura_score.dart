class ScoreComponent {
  final String attribute;
  final String measurement;
  final int scoreImpact;
  final String description;

  Map<String, dynamic> toJson() => {
    'attribute': attribute,
    'measurement': measurement,
    'scoreImpact': scoreImpact,
    'description': description,
  };
  factory ScoreComponent.fromJson(Map<String, dynamic> j) => ScoreComponent(
    j['attribute'] as String,
    j['measurement'] as String,
    j['scoreImpact'] as int,
    j['description'] as String,
  );

  ScoreComponent(
    this.attribute,
    this.measurement,
    this.scoreImpact,
    this.description,
  );
}

class DimensionScore {
  final int score; // 0-100
  final double confidence; // 0.0 - 1.0
  final List<String> primaryTraits;
  final List<ScoreComponent> components;

  Map<String, dynamic> toJson() => {
    'score': score,
    'confidence': confidence,
    'traits': primaryTraits,
    'components': components.map((c) => c.toJson()).toList(),
  };
  factory DimensionScore.fromJson(Map<String, dynamic> j) => DimensionScore(
    j['score'] as int,
    (j['confidence'] as num).toDouble(),
    List<String>.from(j['traits'] as List),
    components: (j['components'] as List)
        .map(
          (c) => ScoreComponent.fromJson(Map<String, dynamic>.from(c as Map)),
        )
        .toList(),
  );

  DimensionScore(
    this.score,
    this.confidence,
    this.primaryTraits, {
    this.components = const [],
  });
}

class AuraScoreCheck {
  const AuraScoreCheck(this.name, this.passed, this.tip, this.milestone);
  final String name;
  final bool passed;
  final String tip;

  /// Minimum milestone these requirements unlock (1M or 10M).
  final int milestone;

  Map<String, dynamic> toJson() => {
    'name': name,
    'passed': passed,
    'tip': tip,
    'milestone': milestone,
  };
  factory AuraScoreCheck.fromJson(Map<String, dynamic> json) => AuraScoreCheck(
    json['name'] as String,
    json['passed'] as bool,
    json['tip'] as String,
    json['milestone'] as int,
  );
}

class DetailedAuraScore {
  final int overallPoints;
  final int scoringVersion;
  final List<AuraScoreCheck> qualityChecks;
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

  Map<String, dynamic> toJson() => {
    'scoringVersion': scoringVersion,
    'qualityChecks': qualityChecks.map((c) => c.toJson()).toList(),
    'overallPoints': overallPoints,
    'isBodyOnly': isBodyOnly,
    'face': face?.toJson(),
    'eyes': eyes?.toJson(),
    'expression': expression?.toJson(),
    'body': body.toJson(),
    'posture': posture.toJson(),
    'pose': pose.toJson(),
    'style': style.toJson(),
    'image': image.toJson(),
    'presence': presence.toJson(),
    'content': content.toJson(),
    'bodyShape': bodyShape,
    'bodyShapeConfidence': bodyShapeConfidence,
    'allSlangs': allSlangs,
    'rawMetrics': rawMetrics,
  };

  factory DetailedAuraScore.fromJson(Map<String, dynamic> j) {
    DimensionScore? dim(String key) => j[key] == null
        ? null
        : DimensionScore.fromJson(Map<String, dynamic>.from(j[key] as Map));
    return DetailedAuraScore(
      scoringVersion: j['scoringVersion'] as int? ?? 0,
      qualityChecks: (j['qualityChecks'] as List? ?? const [])
          .map(
            (c) => AuraScoreCheck.fromJson(Map<String, dynamic>.from(c as Map)),
          )
          .toList(),
      overallPoints: j['overallPoints'] as int,
      isBodyOnly: j['isBodyOnly'] as bool,
      face: dim('face'),
      eyes: dim('eyes'),
      expression: dim('expression'),
      body: dim('body')!,
      posture: dim('posture')!,
      pose: dim('pose')!,
      style: dim('style')!,
      image: dim('image')!,
      presence: dim('presence')!,
      content: dim('content')!,
      bodyShape: j['bodyShape'] as String,
      bodyShapeConfidence: (j['bodyShapeConfidence'] as num).toDouble(),
      allSlangs: List<String>.from(j['allSlangs'] as List),
      rawMetrics: (j['rawMetrics'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      ),
    );
  }

  DetailedAuraScore({
    this.scoringVersion = 0,
    this.qualityChecks = const [],
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
