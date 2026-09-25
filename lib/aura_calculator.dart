import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';

import 'aura/face_analysis.dart';
import 'aura/model_runner.dart';
import 'aura/pixel_analysis.dart';
import 'aura/pose_analysis.dart';
import 'aura/silhouette_analysis.dart';
import 'models/analysis_image.dart';
import 'models/detailed_aura_score.dart';
import 'scorers/aura_engine.dart';
import 'utils/gender_predictor.dart';

class AuraResult {
  final int score;
  final bool hasHuman;
  /// Point to highlight, in original-photo pixels.
  final Point<double>? targetPoint;
  final String? hypeMessage;
  final DetailedAuraScore? details;
  /// Upright size of the analysed photo.
  final int imageWidth;
  final int imageHeight;
  /// Set when the photo could not be analysed at all.
  final String? error;
  /// Why nobody was found, when the photo itself is the likely cause.
  final String? hint;

  AuraResult({
    required this.score,
    required this.hasHuman,
    this.targetPoint,
    this.hypeMessage,
    this.details,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.error,
    this.hint,
  });
}

/// Runs the Aura pipeline: one prepared image through ML Kit face, pose,
/// labeling and subject segmentation, the emotion and content TFLite models,
/// and pixel analysis, then scores the findings with [AuraEngine].
///
/// A single shared instance keeps every model loaded between photos.
class AuraCalculatorService {
  AuraCalculatorService._();
  static final AuraCalculatorService instance = AuraCalculatorService._();
  factory AuraCalculatorService() => instance;

  late final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.05,
    ),
  );
  late final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.single));
  late final ImageLabeler _imageLabeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.55));
  late final SubjectSegmenter _segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: false,
      enableForegroundConfidenceMask: true,
      enableMultipleSubjects: SubjectResultOptions(enableConfidenceMask: false, enableSubjectBitmap: false),
    ),
  );
  final AuraEngine _engine = AuraEngine();

  Future<void>? _warming;

  /// Loads the TFLite models and initialises every ML Kit detector on a tiny
  /// image, so the first real photo doesn't pay start-up costs. Called when
  /// Aura mode is opened.
  Future<void> warmUp() => _warming ??= _warmUp();

  Future<void> _warmUp() async {
    final models = ModelRunner.instance.load();
    try {
      final path = '${(await getTemporaryDirectory()).path}/aura_warmup.jpg';
      await File(path).writeAsBytes(await compute((_) => img.encodeJpg(img.Image(width: 96, height: 96)), null));
      final input = InputImage.fromFilePath(path);
      await Future.wait([
        _faceDetector.processImage(input),
        _poseDetector.processImage(input),
        _imageLabeler.processImage(input),
        _segmenter.processImage(input),
      ]);
    } catch (e) {
      debugPrint('Aura: warm-up skipped: $e');
    }
    await models;
  }

  /// Models stay loaded for the app's lifetime; kept for older call sites.
  void dispose() {}

  Future<AuraResult> analyzeImage(String imagePath) => calculateAura(imagePath);

  Future<AuraResult> calculateAura(String imagePath) async {
    final clock = Stopwatch()..start();
    final timings = <String, int>{};
    void mark(String stage) => timings[stage] = clock.elapsedMilliseconds;

    AnalysisImage? analysis;
    Future<FramePixels>? frameFuture;
    try {
      warmUp();
      analysis = await AnalysisImage.create(imagePath);
      final input = analysis.inputImage;
      final int w = analysis.width, h = analysis.height;
      mark('prepare');

      // Pixels and the content model don't need the detectors: start them now
      frameFuture = FramePixels.load(analysis.path);
      final Future<double?> nsfwFuture = frameFuture.then((f) => ModelRunner.instance.nsfw(f.nsfwInput));
      nsfwFuture.ignore();

      // Face, pose and labels are independent: run them together. The
      // silhouette only matters with a real body in view, so segmentation
      // starts as soon as the (faster) pose result shows one.
      final poseFuture = _poseDetector.processImage(input);
      final Future<SilhouetteMetrics?> silhouetteFuture = poseFuture.then((poses) {
        if (poses.isEmpty || !PoseMetrics.fromPose(poses.first, w, h).isConfidentPerson) return null;
        return _segmenter.processImage(input).then((r) {
          final mask = r.foregroundConfidenceMask;
          return mask == null ? null : SilhouetteMetrics.fromMask(mask, w, h, poses.first);
        });
      }).catchError((Object e) {
        debugPrint('Aura: segmentation failed: $e');
        return null;
      });
      silhouetteFuture.ignore();
      final detections = await Future.wait([
        _faceDetector.processImage(input),
        poseFuture,
        _imageLabeler.processImage(input),
      ]);
      final faces = (detections[0] as List<Face>).where((f) => f.boundingBox.width >= w * 0.04).toList()
        ..sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
      final poses = detections[1] as List<Pose>;
      final labels = (detections[2] as List<ImageLabel>).map((l) => LabelFinding(l.label, l.confidence)).toList();
      mark('mlkit');

      final Face? face = faces.isNotEmpty ? faces.first : null;
      final FaceMetrics? faceMetrics = face == null ? null : FaceMetrics.fromFace(face, w, h);
      final Pose? pose = poses.isNotEmpty ? poses.first : null;
      final PoseMetrics? poseMetrics = pose == null ? null : PoseMetrics.fromPose(pose, w, h);
      final bool isArt = faceMetrics == null && !(poseMetrics?.isConfidentPerson ?? false) && _looksLikeIllustratedPerson(labels);

      final bool hasHuman = faceMetrics != null || (poseMetrics?.isConfidentPerson ?? false) || isArt;
      if (!hasHuman) {
        if (kDebugMode) {
          debugPrint('AURA_TIMING no-human prepare=${timings['prepare']} mlkit=${timings['mlkit']} total=${clock.elapsedMilliseconds}ms '
              'faces=${(detections[0] as List).length} poseConfidence=${poseMetrics?.coreConfidence.toStringAsFixed(2)} '
              'lowLight=${analysis.detectorPath != analysis.path}');
        }
        // Say why when the photo itself is the likely problem
        String? hint;
        try {
          final frame = await frameFuture.timeout(const Duration(milliseconds: 800));
          if (frame.meanLuma < 50) {
            hint = 'Too dark to see you clearly. Try again with more light.';
          } else if (frame.centerSharpness < 25) {
            hint = 'Too blurry to see you clearly. Hold the phone steady.';
          }
        } catch (_) {}
        return AuraResult(
          score: 0,
          hasHuman: false,
          imageWidth: analysis.sourceWidth,
          imageHeight: analysis.sourceHeight,
          hint: hint,
        );
      }

      final frame = await frameFuture;
      final FacePixels? facePixels = faceMetrics == null ? null : await frame.face(faceMetrics.box);
      final pixels = PixelMetrics.of(frame, facePixels);
      mark('pixels');
      final modelResults = await Future.wait<Object?>([
        facePixels != null ? ModelRunner.instance.emotion(facePixels.emotionInput) : Future.value(null),
        nsfwFuture,
      ]);
      mark('models');
      final silhouette = await silhouetteFuture;
      mark('segmentation');

      final double genderProbability = face != null ? GenderPredictor.calculateGenderProbability(face, pose) : 0.5;
      final details = _engine.calculateScore(AuraFeatures(
        face: faceMetrics,
        // Other people only count if they're a real part of the shot
        faceCount: faces
            .where((f) => f.boundingBox.width * f.boundingBox.height >= 0.3 * face!.boundingBox.width * face.boundingBox.height)
            .length,
        pose: poseMetrics,
        silhouette: silhouette,
        pixels: pixels,
        labels: labels,
        emotions: modelResults[0] as List<double>?,
        nsfw: modelResults[1] as double?,
        isArt: isArt,
        isLikelyFemale: genderProbability >= 0.5,
      ));

      final double toSource = analysis.toSourceScale;
      Point<double>? target;
      if (pose != null && (poseMetrics?.hasTorso ?? false)) {
        final ls = pose.landmarks[PoseLandmarkType.leftShoulder]!, rs = pose.landmarks[PoseLandmarkType.rightShoulder]!;
        target = Point((ls.x + rs.x) / 2 * toSource, (ls.y + rs.y) / 2 * toSource);
      } else if (face != null) {
        target = Point(face.boundingBox.center.dx * toSource, (face.boundingBox.top - 0.3 * face.boundingBox.height) * toSource);
      }

      final slangs = details.allSlangs;
      final String hype = slangs.isEmpty ? 'Looking good! ✨' : slangs[details.overallPoints % slangs.length];
      if (kDebugMode) {
        debugPrint('AURA_TIMING prepare=${timings['prepare']} mlkit=${timings['mlkit']} pixels=${timings['pixels']} '
            'models=${timings['models']} segmentation=${timings['segmentation']} total=${clock.elapsedMilliseconds}ms');
      }

      return AuraResult(
        score: details.overallPoints,
        hasHuman: true,
        targetPoint: target,
        hypeMessage: hype,
        details: details,
        imageWidth: analysis.sourceWidth,
        imageHeight: analysis.sourceHeight,
      );
    } catch (e, stack) {
      debugPrint('Error in Aura Calculation: $e\n$stack');
      return AuraResult(
        score: 0,
        hasHuman: false,
        imageWidth: analysis?.sourceWidth ?? 0,
        imageHeight: analysis?.sourceHeight ?? 0,
        error: 'Could not analyse this photo',
      );
    } finally {
      // The background pixel job may still be reading the file
      final a = analysis;
      if (frameFuture != null) {
        frameFuture.then((_) {}, onError: (_) {}).whenComplete(() => a?.deleteFile());
      } else {
        a?.deleteFile();
      }
    }
  }

  /// Illustrations (anime, cartoons) where ML Kit finds no real face or body:
  /// needs a confident art label plus a confident person-related label.
  /// Labels are compared as whole words (a "Chair" is not "hair").
  static bool _looksLikeIllustratedPerson(List<LabelFinding> labels) {
    const art = {'anime', 'cartoon', 'illustration', 'comics', 'drawing', 'fictional character', 'art'};
    const person = {'selfie', 'smile', 'beard', 'moustache', 'eyelash', 'lipstick', 'skin', 'muscle', 'hairstyle', 'face'};
    bool hasArt = false, hasPerson = false;
    for (final l in labels) {
      if (l.confidence < 0.6) continue;
      final name = l.label.toLowerCase();
      if (art.contains(name)) hasArt = true;
      if (person.contains(name)) hasPerson = true;
    }
    return hasArt && hasPerson;
  }
}
