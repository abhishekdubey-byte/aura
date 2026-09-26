import 'dart:typed_data';

import 'package:aura/aura/model_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an unavailable native model runtime does not poison camera warm-up', () async {
    // The host test runner has no packaged Android TensorFlow library. Exercise
    // the same dynamic-library failure seen on older Android devices.
    final runner = ModelRunner.instance;
    await Future.wait([runner.load(), runner.load()]);
    expect(await runner.emotion(Uint8List(48 * 48 * 4)), isNull);
    expect(await runner.nsfw(Uint8List(224 * 224 * 3)), isNull);
    await runner.load();
  });
}
