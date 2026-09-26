import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/detailed_aura_score.dart';
import '../scorers/aura_engine.dart';
import 'pixel_analysis.dart';

/// Visual matching, not identity recognition. Anchors never drift toward each
/// subsequent shot. Small local changes veto a match even if the average scene
/// is similar. Thresholds intentionally prefer a new score over a false match.
class AuraVisualSignature {
  AuraVisualSignature(
    this.digest,
    this.aspect,
    this.colors,
    this.faceColors,
    this.faceCount,
    this.labels, {
    Set<String>? confidentLabels,
  }) : confidentLabels = confidentLabels ?? labels;
  final String digest;
  final double aspect;
  final List<int> colors;
  final List<int>? faceColors;
  final int faceCount;
  final Set<String> labels;
  final Set<String> confidentLabels;

  static Future<AuraVisualSignature> create(
    FramePixels frame,
    FaceBox? face,
    int faceCount,
    List<LabelFinding> labels,
  ) async {
    final values = await compute(_fingerprint, (
      frame.rgb,
      frame.width,
      frame.height,
      face,
    ));
    return AuraVisualSignature(
      values.$1,
      frame.width / frame.height,
      values.$2,
      values.$3,
      faceCount,
      labels
          .where((l) => l.confidence >= 0.55)
          .map((l) => l.label.toLowerCase())
          .toSet(),
      confidentLabels: labels
          .where((l) => l.confidence >= 0.8)
          .map((l) => l.label.toLowerCase())
          .toSet(),
    );
  }

  bool matches(AuraVisualSignature other) {
    if (digest == other.digest) return true;
    if ((aspect - other.aspect).abs() > 0.015 ||
        faceCount != other.faceCount ||
        (faceColors == null) != (other.faceColors == null)) {
      return false;
    }
    // A confident newly detected/removed accessory or scene object must be
    // allowed to change the score. Compare all confident labels conservatively.
    if (!other.labels.containsAll(confidentLabels) ||
        !labels.containsAll(other.confidentLabels)) {
      return false;
    }
    return _close(colors, other.colors, meanLimit: 7, localLimit: 25) &&
        (faceColors == null ||
            _close(
              faceColors!,
              other.faceColors!,
              meanLimit: 9,
              localLimit: 30,
            ));
  }

  static bool _close(
    List<int> a,
    List<int> b, {
    required double meanLimit,
    required double localLimit,
  }) {
    if (a.length != b.length || a.isEmpty || a.length % 3 != 0) return false;
    double sum = 0;
    int changed = 0;
    for (int i = 0; i < a.length; i += 3) {
      final delta =
          ((a[i] - b[i]).abs() +
              (a[i + 1] - b[i + 1]).abs() +
              (a[i + 2] - b[i + 2]).abs()) /
          3;
      sum += delta;
      if (delta > localLimit) changed++;
    }
    final cells = a.length ~/ 3;
    return sum / cells <= meanLimit && changed / cells <= 0.01;
  }

  Map<String, dynamic> toJson() => {
    'digest': digest,
    'aspect': aspect,
    'colors': colors,
    'face': faceColors,
    'count': faceCount,
    'labels': labels.toList(),
    'confidentLabels': confidentLabels.toList(),
  };
  factory AuraVisualSignature.fromJson(Map<String, dynamic> j) =>
      AuraVisualSignature(
        j['digest'] as String,
        (j['aspect'] as num).toDouble(),
        List<int>.from(j['colors'] as List),
        j['face'] == null ? null : List<int>.from(j['face'] as List),
        j['count'] as int,
        Set<String>.from(j['labels'] as List),
        confidentLabels: Set<String>.from(
          (j['confidentLabels'] ?? j['labels']) as List,
        ),
      );
}

(String, List<int>, List<int>?) _fingerprint(
  (Uint8List, int, int, FaceBox?) args,
) {
  final (rgb, w, h, face) = args;
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgb.buffer,
    bytesOffset: rgb.offsetInBytes,
    numChannels: 3,
  );
  List<int> sample(img.Image source, int side) => img
      .copyResize(
        source,
        width: side,
        height: side,
        interpolation: img.Interpolation.average,
      )
      .getBytes(order: img.ChannelOrder.rgb)
      .toList();
  List<int>? faceColors;
  if (face != null) {
    final x = face.left.floor().clamp(0, w - 1),
        y = face.top.floor().clamp(0, h - 1);
    final crop = img.copyCrop(
      image,
      x: x,
      y: y,
      width: math.max(1, face.width.ceil()).clamp(1, w - x),
      height: math.max(1, face.height.ceil()).clamp(1, h - y),
    );
    faceColors = sample(crop, 24);
  }
  return (
    sha256.convert([...utf8.encode('$w:$h:'), ...rgb]).toString(),
    sample(image, 48),
    faceColors,
  );
}

class AuraScoreMemory {
  AuraScoreMemory({this.fileOverride});
  final File? fileOverride;
  static final instance = AuraScoreMemory();
  static const _capacity = 100;
  final List<(AuraVisualSignature, DetailedAuraScore)> _entries = [];
  bool _loaded = false;

  Future<File> _file() async =>
      fileOverride ??
      File(
        '${(await getApplicationSupportDirectory()).path}/aura_score_memory_v1.json',
      );

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as List;
      for (final raw in data.take(_capacity)) {
        final j = Map<String, dynamic>.from(raw as Map);
        final score = DetailedAuraScore.fromJson(
          Map<String, dynamic>.from(j['score'] as Map),
        );
        if (score.scoringVersion != AuraEngine.scoringVersion) continue;
        _entries.add((
          AuraVisualSignature.fromJson(
            Map<String, dynamic>.from(j['signature'] as Map),
          ),
          score,
        ));
      }
    } catch (e) {
      _entries.clear();
      debugPrint('Aura: score memory could not be loaded: $e');
    }
  }

  Future<DetailedAuraScore?> find(
    AuraVisualSignature signature, {
    DetailedAuraScore? currentScore,
  }) async {
    await _load();
    // Exact matches win over approximate ones regardless of recency.
    for (final entry in _entries) {
      if (entry.$1.digest == signature.digest &&
          _compatible(entry.$2, currentScore)) {
        return entry.$2;
      }
    }
    for (final entry in _entries) {
      if (entry.$1.matches(signature) && _compatible(entry.$2, currentScore)) {
        return entry.$2;
      }
    }
    return null;
  }

  // A similar thumbnail cannot bypass current lighting/focus gates. Blur may
  // disappear when downsampled for matching, so compare measured quality too.
  static bool _compatible(DetailedAuraScore saved, DetailedAuraScore? current) {
    if (saved.scoringVersion != AuraEngine.scoringVersion) return false;
    if (current == null) return true;
    if (saved.qualityChecks.length != current.qualityChecks.length) {
      return false;
    }
    for (int i = 0; i < saved.qualityChecks.length; i++) {
      if (saved.qualityChecks[i].passed != current.qualityChecks[i].passed) {
        return false;
      }
    }
    final a = saved.rawMetrics, b = current.rawMetrics;
    if (saved.overallPoints > (b['Score Ceiling'] ?? 0)) return false;
    for (final key in ['Frame Luma', 'Subject Luma']) {
      if (((a[key] ?? 0) - (b[key] ?? 0)).abs() > 8) return false;
    }
    if (((a['Clipped Pixels'] ?? 0) - (b['Clipped Pixels'] ?? 0)).abs() >
        0.02) {
      return false;
    }
    final sharpA = a['Sharpness'] ?? 0, sharpB = b['Sharpness'] ?? 0;
    if ((sharpA - sharpB).abs() >
        math.max(10, math.max(sharpA, sharpB) * 0.2)) {
      return false;
    }
    return true;
  }

  Future<void> remember(
    AuraVisualSignature signature,
    DetailedAuraScore score,
  ) async {
    await _load();
    _entries.insert(0, (signature, score));
    if (_entries.length > _capacity) _entries.removeLast();
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode(
          _entries
              .map((e) => {'signature': e.$1.toJson(), 'score': e.$2.toJson()})
              .toList(),
        ),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('Aura: score memory could not be saved: $e');
    }
  }
}
