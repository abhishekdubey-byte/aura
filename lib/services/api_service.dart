import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ApiService {
  static Future<String> getDeviceIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'unknown_user';

    String deviceId = 'unknown_device';
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceId = '${info.model}_${info.id}';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        deviceId = '${info.name}_${info.identifierForVendor}';
      }
    } catch (e) {
      debugPrint('Failed to get device info: $e');
    }

    deviceId = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final sanitizedUsername = username.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    return '${sanitizedUsername}_$deviceId';
  }
}
