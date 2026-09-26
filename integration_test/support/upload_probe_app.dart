// Standalone diagnostic entry point. Unlike `flutter test`, this installation
// stays on the emulator so native WorkManager recovery can be tested after the
// UI process is killed. Contains synthetic media only; never ships as main.
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Background upload probe'))),
    ),
  );
  const channel = MethodChannel('com.aura.aura/uploads');
  const scope = 'test_background_process';
  try {
    if (!(await Connectivity().checkConnectivity()).contains(
      ConnectivityResult.none,
    )) {
      throw StateError('Disable emulator networking before this probe.');
    }
    await channel.invokeMethod('configure', {
      'scope': scope,
      'url': 'http://10.0.2.2:8754',
      'key': 'test-only',
      'bucket': 'captures',
    });
    final photo = img.Image(width: 128, height: 96);
    img.fill(photo, color: img.ColorRgb8(40, 100, 160));
    final bytes = img.encodePng(photo);
    final file = await File(
      '${(await getTemporaryDirectory()).path}/offline_probe.png',
    ).writeAsBytes(bytes);
    await channel.invokeMethod('enqueue', {
      'scope': scope,
      'path': file.path,
      'identity': 'native_test',
    });
    await file.delete();
    final status = await channel.invokeMapMethod('status', {'scope': scope});
    if (status?['pending'] != 1 || status?['uploaded'] != 0) {
      throw StateError('Unexpected offline queue: $status');
    }
    debugPrint(
      'UPLOAD_PROCESS_PROBE_READY sha=${sha256.convert(bytes)} bytes=${bytes.length}',
    );
  } catch (e) {
    debugPrint('UPLOAD_PROCESS_PROBE_FAILED $e');
  }
}
