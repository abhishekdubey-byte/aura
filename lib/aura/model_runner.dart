
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// The two bundled TFLite models, loaded once and run off the UI thread.
///
/// emotion.tflite: float32 [1,48,48,1] face crop -> float32 [1,7]
///   (FER-2013 classes: angry, disgust, fear, happy, sad, surprise, neutral)
/// nsfw.tflite:    uint8 [1,224,224,3] RGB -> uint8 [1,2] (safe, nsfw)
class ModelRunner {
  ModelRunner._();
  static final ModelRunner instance = ModelRunner._();

  static const List<String> emotionLabels = ['angry', 'disgust', 'fear', 'happy', 'sad', 'surprise', 'neutral'];

  IsolateInterpreter? _emotion, _nsfw;
  Future<void>? _loading;
  // IsolateInterpreter ignores a run while another is in flight, so runs are
  // chained one after another
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() job) {
    final result = _queue.then((_) => job());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final options = InterpreterOptions()..threads = 2;
    try {
      final emotion = await Interpreter.fromAsset('assets/models/emotion.tflite', options: options);
      _emotion = await IsolateInterpreter.create(address: emotion.address);
    } catch (e) {
      debugPrint('ModelRunner: emotion model unavailable: $e');
    }
    try {
      final nsfw = await Interpreter.fromAsset('assets/models/nsfw.tflite', options: options);
      _nsfw = await IsolateInterpreter.create(address: nsfw.address);
    } catch (e) {
      debugPrint('ModelRunner: nsfw model unavailable: $e');
    }
  }

  /// Emotion probabilities for a 48x48 face crop (float32 bytes).
  Future<List<double>?> emotion(Uint8List faceBytes) async {
    await load();
    final interpreter = _emotion;
    if (interpreter == null) return null;
    try {
      final out = Uint8List(7 * 4).buffer;
      await _serial(() => interpreter.run(faceBytes, out));
      final probs = out.asFloat32List();
      return List<double>.generate(7, (i) => probs[i]);
    } catch (e) {
      debugPrint('ModelRunner: emotion failed: $e');
      return null;
    }
  }

  /// Probability (0..1) that the image is explicit.
  Future<double?> nsfw(Uint8List rgbBytes) async {
    await load();
    final interpreter = _nsfw;
    if (interpreter == null) return null;
    try {
      final out = Uint8List(2).buffer;
      await _serial(() => interpreter.run(rgbBytes, out));
      final scores = out.asUint8List();
      final int total = scores[0] + scores[1];
      return total == 0 ? 0.0 : scores[1] / total;
    } catch (e) {
      debugPrint('ModelRunner: nsfw failed: $e');
      return null;
    }
  }
}
