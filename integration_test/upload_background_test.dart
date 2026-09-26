import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Run on an isolated emulator with Wi-Fi/mobile data disabled. After this
/// passes, background and kill the app (not force-stop), reconnect networking,
/// and verify the host receiver gets this exact hash without reopening AURA.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'offline original is durably queued for a native background worker',
    (tester) async {
      const native = MethodChannel('com.aura.aura/uploads');
      const scope = String.fromEnvironment(
        'AURA_UPLOAD_TEST_SCOPE',
        defaultValue: 'test_background_v1',
      );
      const url = String.fromEnvironment(
        'AURA_UPLOAD_TEST_URL',
        defaultValue: 'http://10.0.2.2:8754',
      );
      expect(
        await Connectivity().checkConnectivity(),
        contains(ConnectivityResult.none),
      );
      await native.invokeMethod('configure', {
        'scope': scope,
        'url': url,
        'key': 'test-only',
        'bucket': 'captures',
      });
      final image = img.Image(width: 128, height: 96);
      img.fill(image, color: img.ColorRgb8(40, 100, 160));
      final bytes = img.encodePng(image);
      final hash = sha256.convert(bytes).toString();
      final path =
          '${(await getTemporaryDirectory()).path}/background_probe.png';
      await File(path).writeAsBytes(bytes, flush: true);
      final queued = await native.invokeMapMethod('enqueue', {
        'scope': scope,
        'path': path,
        'identity': 'native_test',
      });
      expect(queued!['pending'], 1);
      await File(path).delete();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Offline capture queued'))),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      final restored = await native.invokeMapMethod('status', {'scope': scope});
      expect(restored!['pending'], 1);
      expect(restored['uploaded'], 0);
      debugPrint('UPLOAD_PROBE scope=$scope sha=$hash bytes=${bytes.length}');
    },
    skip: !const bool.fromEnvironment('AURA_OFFLINE_PROBE'),
  );
}
