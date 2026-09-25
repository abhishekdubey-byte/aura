import 'package:flutter/foundation.dart';

/// Runs media save jobs (image processing, FFmpeg, gallery writes) one at a
/// time in the background so the camera stays responsive and rapid captures
/// never run several full-resolution decodes or encodes in parallel.
class MediaSaveQueue {
  MediaSaveQueue._privateConstructor();
  static final MediaSaveQueue instance = MediaSaveQueue._privateConstructor();

  /// Number of jobs queued or running. Drives the "saving" indicator.
  final ValueNotifier<int> pending = ValueNotifier(0);

  Future<void> _tail = Future.value();

  void add(Future<void> Function() job) {
    pending.value++;
    _tail = _tail.then((_) async {
      try {
        await job();
      } catch (e) {
        debugPrint('MediaSaveQueue: job failed: $e');
      } finally {
        pending.value--;
      }
    });
  }
}
