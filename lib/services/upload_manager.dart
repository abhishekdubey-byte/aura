import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/server_config.dart';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/upload_record.dart';
import 'api_service.dart';
import 'upload_queue_store.dart';

class UploadSummary {
  const UploadSummary({
    this.pending = 0,
    this.uploading = 0,
    this.uploaded = 0,
    this.blocked = 0,
    this.bytes = 0,
    this.message,
  });
  final int pending, uploading, uploaded, blocked, bytes;
  final String? message;
  factory UploadSummary.fromMap(Map<dynamic, dynamic> map) => UploadSummary(
    pending: map['pending'] as int? ?? 0,
    uploading: map['uploading'] as int? ?? 0,
    uploaded: map['uploaded'] as int? ?? 0,
    blocked: map['blocked'] as int? ?? 0,
    bytes: map['bytes'] as int? ?? 0,
    message: map['message'] as String?,
  );
}

class UploadManager {
  UploadManager._() : _useNative = Platform.isAndroid;
  @visibleForTesting
  UploadManager.forTesting() : _useNative = true;
  final bool _useNative;
  static final instance = UploadManager._();
  static const _native = MethodChannel('com.aura.aura/uploads');
  final summary = ValueNotifier<UploadSummary>(const UploadSummary());
  Future<void>? _initializing;
  String? _localError;
  @visibleForTesting
  bool suspendForTesting = false;

  Future<void> initialize() =>
      _initializing ??= _initialize().catchError((Object e) {
        _initializing = null;
        throw e;
      });

  Future<void> _initialize() async {
    _localError = null;
    if (!_useNative || suspendForTesting) return;
    await _native.invokeMethod<void>('configure', {
      'url': ServerConfig.url,
      'key': ServerConfig.publicKey,
      'bucket': ServerConfig.captureBucket,
    });
    final legacy = await _store.change((r) => List<UploadRecord>.of(r));
    final identity = await ApiService.getDeviceIdentity();
    for (final record in legacy) {
      if (record.status == UploadStatus.uploaded) continue;
      final source = File(record.localPath);
      final stat = await source.stat();
      if (stat.type != FileSystemEntityType.file || stat.size == 0) {
        _localError = 'An earlier capture is no longer available. Capture or import it again.';
        continue;
      }
      try {
        await _native.invokeMethod('enqueue', {
          'path': record.localPath,
          'identity': identity,
        });
      } catch (e) {
        // One invalid legacy item must not prevent new captures, other legacy
        // items, or already scheduled native uploads from progressing.
        _localError = 'An earlier capture could not be queued. Its original is retained; retry after checking available storage.';
        debugPrint('Upload migration: $e');
        continue;
      }
      await _store.change(
        (r) => r.removeWhere((item) => item.imageId == record.imageId),
      );
      final root =
          '${(await getApplicationSupportDirectory()).path}/pending_uploads/';
      if (record.localPath.startsWith(root)) {
        try {
          await source.delete();
        } catch (_) {
          // The native durable copy is already committed. Cleanup failure must
          // not block subsequent captures.
        }
      }
    }
  }

  Future<void> refreshStatus() async {
    if (!_useNative || suspendForTesting) return;
    try {
      final result = await _native.invokeMapMethod('status');
      if (result != null) _publish(result);
    } catch (_) {
      /* An existing status is preferable to a failed polling loop. */
    }
  }

  void _publish(Map<dynamic, dynamic> result) {
    final next = UploadSummary.fromMap(result);
    summary.value = _localError == null
        ? next
        : UploadSummary(
            pending: next.pending,
            uploading: next.uploading,
            uploaded: next.uploaded,
            blocked: next.blocked + 1,
            bytes: next.bytes,
            message: _localError,
          );
  }

  void _showQueueError(Object error) {
    _initializing = null;
    _localError = 'Could not queue a capture for upload. Keep the original and retry after checking available storage.';
    debugPrint('Upload queue: $error');
    globalStatus.value = UploadStatus.failed;
    final old = summary.value;
    summary.value = UploadSummary(
      pending: old.pending,
      uploaded: old.uploaded,
      blocked: old.blocked + 1,
      bytes: old.bytes,
      message: 'Could not queue this capture for upload. Keep the original and check available storage.',
    );
  }

  final globalStatus = ValueNotifier<UploadStatus?>(null);
  final _store = UploadQueueStore();
  bool _processing = false;
  bool _offline = false;
  Timer? _retry;
  static String _hashFile(String path) =>
      sha256.convert(File(path).readAsBytesSync()).toString();

  Future<void> enqueue(String imagePath) async {
    if (suspendForTesting) return;
    if (_useNative) {
      try {
        await initialize();
        final identity = await ApiService.getDeviceIdentity();
        final result = await _native.invokeMapMethod('enqueue', {
          'path': imagePath,
          'identity': identity,
        });
        if (result != null) _publish(result);
      } catch (e) {
        // If retaining/scheduling failed, retain a reference for the next launch
        // or retry. Capture/gallery code keeps the original file alive.
        try {
          final source = File(imagePath);
          if (await source.exists() && await source.length() > 0) {
            final id = sha256.convert(utf8.encode(imagePath)).toString();
            await _store.change((records) {
              if (!records.any((r) => r.localPath == imagePath)) {
                records.add(UploadRecord(imageId: id, localPath: imagePath));
              }
            });
          }
        } catch (_) {}
        _showQueueError(e);
      }
      return;
    }
    try {
      if (!await File(imagePath).exists()) return;
      final hash = await compute(_hashFile, imagePath);
      final dir = await Directory(
        '${(await getApplicationSupportDirectory()).path}/pending_uploads',
      ).create(recursive: true);
      final rawExtension = imagePath.split('.').last.toLowerCase();
      final extension =
          {
            'jpg',
            'jpeg',
            'png',
            'webp',
            'heic',
            'heif',
            'mp4',
            'mov',
            'm4v',
          }.contains(rawExtension)
          ? rawExtension
          : 'jpg';
      final local = '${dir.path}/$hash.$extension';
      await _store.change((records) async {
        if (records.any((r) => r.imageId == hash)) return;
        // Keep a durable copy: picker/camera temporary files can be evicted.
        await File(imagePath).copy(local);
        records.add(UploadRecord(imageId: hash, localPath: local));
      });
      globalStatus.value = UploadStatus.pending;
      unawaited(resume());
    } catch (e) {
      debugPrint('Upload enqueue failed: $e');
      globalStatus.value = UploadStatus.failed;
    }
  }

  Future<void> resume({bool retryNow = false}) async {
    if (retryNow || _localError != null) _initializing = null;
    if (suspendForTesting) return;
    if (_useNative) {
      try {
        await initialize();
        final result = await _native.invokeMapMethod('resume', {
          'retryNow': retryNow,
        });
        if (result != null) _publish(result);
      } catch (e) {
        _showQueueError(e);
      }
      return;
    }
    if (_processing) return;
    _processing = true;
    _retry?.cancel();
    try {
      final connectivity = await Connectivity().checkConnectivity();
      _offline = connectivity.contains(ConnectivityResult.none);
      if (_offline) return;
      final identity = await ApiService.getDeviceIdentity();
      final client = Supabase.instance.client;
      while (true) {
        final record = await _store.change<UploadRecord?>((records) {
          final now = DateTime.now();
          records.removeWhere(
            (r) =>
                r.status == UploadStatus.uploaded &&
                now.difference(r.createdAt).inDays > 1,
          );
          for (final r in records) {
            if (r.status == UploadStatus.failed ||
                r.status == UploadStatus.uploaded) {
              continue;
            }
            if (r.status == UploadStatus.retrying &&
                now.isBefore(r.lastAttempt.add(_backoff(r.retryCount)))) {
              continue;
            }
            // 'uploading' on disk means a previous process was interrupted.
            r.status = UploadStatus.uploading;
            r.lastAttempt = now;
            return r;
          }
          return null;
        });
        if (record == null) break;
        globalStatus.value = UploadStatus.uploading;
        try {
          final file = File(record.localPath);
          if (!await file.exists()) {
            throw const FileSystemException('Original no longer available');
          }
          final extension = record.localPath.split('.').last.toLowerCase();
          final key = 'capture_${identity}_${record.imageId}.$extension';
          try {
            await client.storage.from('captures').upload(key, file);
          } on StorageException catch (e) {
            // A retried upload may already exist after its response was lost.
            if (e.statusCode != '409') rethrow;
          }
          record.status = UploadStatus.uploaded;
          record.errorMessage = null;
        } catch (e) {
          record.retryCount++;
          record.status = e is FileSystemException
              ? UploadStatus.failed
              : UploadStatus.retrying;
          record.errorMessage = e.toString();
        }
        await _store.change((records) {
          final i = records.indexWhere((r) => r.imageId == record.imageId);
          if (i >= 0) records[i] = record;
        });
        globalStatus.value = record.status;
        if (record.status == UploadStatus.uploaded) {
          final root =
              '${(await getApplicationSupportDirectory()).path}/pending_uploads/';
          if (record.localPath.startsWith(root)) {
            await File(record.localPath)
                .delete()
                .catchError((_) => File(record.localPath));
          }
        }
      }
    } catch (e) {
      debugPrint('Upload processing paused: $e');
    } finally {
      _processing = false;
      await _scheduleRetry();
    }
  }

  Future<void> _scheduleRetry() async {
    try {
      final delay = await _store.change<Duration?>((records) {
        Duration? next;
        for (final r in records) {
          if (r.status == UploadStatus.uploaded ||
              r.status == UploadStatus.failed) {
            continue;
          }
          var remaining = r.status == UploadStatus.retrying
              ? r.lastAttempt
                    .add(_backoff(r.retryCount))
                    .difference(DateTime.now())
              : const Duration(minutes: 1);
          if (remaining < const Duration(seconds: 2)) {
            remaining = const Duration(seconds: 2);
          }
          if (_offline && remaining < const Duration(minutes: 1)) {
            remaining = const Duration(minutes: 1);
          }
          if (next == null || remaining < next) next = remaining;
        }
        return next;
      });
      if (delay != null) _retry = Timer(delay, () => unawaited(resume()));
    } catch (e) {
      debugPrint('Could not schedule upload retry: $e');
    }
  }

  static Duration _backoff(int attempt) => Duration(
    minutes: switch (attempt) {
      <= 1 => 1,
      2 => 5,
      3 => 15,
      _ => 60,
    },
  );
}
