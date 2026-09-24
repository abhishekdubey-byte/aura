import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/upload_record.dart';
import 'api_service.dart';

class UploadManager {
  // Singleton
  UploadManager._privateConstructor();
  static final UploadManager instance = UploadManager._privateConstructor();

  static const String _queueKey = 'upload_manager_queue';
  
  // Expose global status to the UI without blocking
  final ValueNotifier<UploadStatus?> globalStatus = ValueNotifier(null);

  bool _isProcessing = false;

  /// Enqueue an image for upload
  Future<void> enqueue(String imagePath) async {
    final file = File(imagePath);
    if (!file.existsSync()) return;

    try {
      // Create canonical hash for duplicate prevention
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString();

      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getStringList(_queueKey) ?? [];
      
      List<UploadRecord> queue = queueJson
          .map((e) => UploadRecord.fromJson(jsonDecode(e)))
          .toList();

      // Duplicate Check
      if (queue.any((record) => record.imageId == hash && 
         (record.status == UploadStatus.uploaded || 
          record.status == UploadStatus.pending || 
          record.status == UploadStatus.uploading || 
          record.status == UploadStatus.retrying))) {
        debugPrint('UploadManager: Image already in queue or uploaded. Skipping duplicate.');
        return;
      }

      // Add to queue
      final record = UploadRecord(
        imageId: hash,
        localPath: imagePath,
        status: UploadStatus.pending,
      );
      
      queue.add(record);
      await _saveQueue(prefs, queue);
      
      _updateGlobalStatus(UploadStatus.pending);
      
      // Trigger processing asynchronously
      _processQueue();
    } catch (e) {
      debugPrint('UploadManager Enqueue Error: $e');
    }
  }

  Future<void> _saveQueue(SharedPreferences prefs, List<UploadRecord> queue) async {
    final jsonList = queue.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_queueKey, jsonList);
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getStringList(_queueKey) ?? [];
      List<UploadRecord> queue = queueJson
          .map((e) => UploadRecord.fromJson(jsonDecode(e)))
          .toList();

      if (queue.isEmpty) {
        _isProcessing = false;
        return;
      }

      // Check network once before starting
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint('UploadManager: Offline. Waiting for network.');
        _isProcessing = false;
        return;
      }

      final identity = await ApiService.getDeviceIdentity(); // Requires making it public
      final supabase = Supabase.instance.client;

      bool anyUploaded = false;

      for (var i = 0; i < queue.length; i++) {
        var record = queue[i];
        
        if (record.status == UploadStatus.uploaded || record.status == UploadStatus.failed) {
          continue;
        }

        // Retry Backoff logic
        if (record.status == UploadStatus.retrying) {
          final backoffMinutes = _getBackoffMinutes(record.retryCount);
          final nextAttempt = record.lastAttempt.add(Duration(minutes: backoffMinutes));
          if (DateTime.now().isBefore(nextAttempt)) {
            continue; // Not ready to retry yet
          }
        }

        // Prepare upload
        record.status = UploadStatus.uploading;
        record.lastAttempt = DateTime.now();
        await _saveQueue(prefs, queue);
        _updateGlobalStatus(UploadStatus.uploading);

        try {
          final file = File(record.localPath);
          if (!file.existsSync()) {
             record.status = UploadStatus.failed;
             record.errorMessage = 'File missing locally';
             continue;
          }

          final fileName = 'capture_${identity}_${DateTime.now().millisecondsSinceEpoch}_${record.imageId.substring(0, 8)}.jpg';
          await supabase.storage.from('captures').upload(fileName, file);

          record.status = UploadStatus.uploaded;
          anyUploaded = true;
          debugPrint('UploadManager: Successfully uploaded ${record.imageId}');
        } catch (e) {
          debugPrint('UploadManager: Failed to upload ${record.imageId} - $e');
          record.retryCount++;
          if (record.retryCount >= 5) {
            record.status = UploadStatus.failed;
            record.errorMessage = e.toString();
          } else {
            record.status = UploadStatus.retrying;
          }
        }
        
        await _saveQueue(prefs, queue);
      }
      
      if (anyUploaded) {
        _updateGlobalStatus(UploadStatus.uploaded);
      } else {
        // Find most relevant status to show
        if (queue.any((r) => r.status == UploadStatus.retrying)) {
          _updateGlobalStatus(UploadStatus.retrying);
        } else if (queue.any((r) => r.status == UploadStatus.pending)) {
          _updateGlobalStatus(UploadStatus.pending);
        } else if (queue.any((r) => r.status == UploadStatus.failed)) {
          _updateGlobalStatus(UploadStatus.failed);
        }
      }
      
      // Cleanup: Remove successfully uploaded items older than 24 hours to keep history but not bloat
      queue.removeWhere((r) => r.status == UploadStatus.uploaded && DateTime.now().difference(r.createdAt).inHours > 24);
      await _saveQueue(prefs, queue);

    } catch (e) {
      debugPrint('UploadManager Process Error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  int _getBackoffMinutes(int retryCount) {
    if (retryCount <= 1) return 1;
    if (retryCount == 2) return 5;
    if (retryCount == 3) return 15;
    return 60; // Max 1 hour
  }

  void _updateGlobalStatus(UploadStatus status) {
    // Run on microtask to avoid UI build collisions
    Future.microtask(() {
      globalStatus.value = status;
    });
  }
}
