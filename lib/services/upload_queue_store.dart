import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/upload_record.dart';

/// All queue changes are serialized, including updates made during an upload.
class UploadQueueStore {
  Future<void> _tail = Future.value();
  static const key = 'upload_manager_queue';

  Future<T> change<T>(FutureOr<T> Function(List<UploadRecord>) edit) {
    final result = _tail.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final records = <UploadRecord>[];
      for (final raw in prefs.getStringList(key) ?? <String>[]) {
        try {
          records.add(
            UploadRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        } catch (e) {
          debugPrint('Ignored corrupt upload record: $e');
        }
      }
      final value = await edit(records);
      if (!await prefs.setStringList(
        key,
        records.map((r) => jsonEncode(r.toJson())).toList(),
      )) {
        throw StateError('Could not persist the upload queue');
      }
      return value;
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
