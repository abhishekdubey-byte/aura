import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Older and virtual MediaCodec implementations can accept an encode without
/// ever producing frames. Use the bundled software encoder on those devices.
class MediaEncoderPolicy {
  static Future<bool>? _hardware;

  static Future<bool> get useHardware => _hardware ??= (() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.isPhysicalDevice && info.version.sdkInt >= 26;
    } catch (_) {
      return false;
    }
  })();
}
