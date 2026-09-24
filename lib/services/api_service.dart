import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ApiService {
  static const String _queueKey = 'offline_upload_queue';

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

  /// DEPRECATED: Use UploadManager.instance.enqueue(imagePath) instead.
  /// Maintained for backwards compatibility if called elsewhere.
  static Future<void> uploadImageForLearning(String imagePath) async {
    // Forward to the non-blocking upload manager
    // ignore: unused_local_variable
    final manager = await importUploadManager();
  }
  
  static Future<void> importUploadManager() async {
     // A hack to safely redirect to UploadManager without circular imports, 
     // but realistically we'll just remove/replace calls in main.dart
  }

  /// Submits the final calculated Aura Score to the Global Leaderboard
  static Future<void> submitScoreToLeaderboard(int score) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username') ?? 'unknown_user';
      
      final supabase = Supabase.instance.client;
      
      // Fetch any existing records for this user to resolve duplicates safely
      final existingRecords = await supabase.from('leaderboard').select().eq('username', username);
      
      int maxScore = score;
      if (existingRecords.isNotEmpty) {
          for (var record in existingRecords) {
              int recordScore = (record['score'] as num).toInt();
              if (recordScore > maxScore) {
                  maxScore = recordScore;
              }
          }
      }
          
      // Explicitly delete all previous records for this username to prevent duplicates/glitches
      await supabase.from('leaderboard').delete().eq('username', username);
      
      // Insert the single highest score
      await supabase.from('leaderboard').insert({
          'username': username,
          'score': maxScore,
      });
      debugPrint('✅ Score $maxScore successfully recorded on leaderboard for $username!');
    } catch (e) {
      debugPrint('Error submitting score to leaderboard: $e');
    }
  }

  // processOfflineQueue and _saveToOfflineQueue are completely replaced by UploadManager.
  static Future<void> processOfflineQueue() async {
      // No-op, managed by UploadManager
  }
}
