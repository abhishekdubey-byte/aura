import 'dart:io';

import 'package:aura/boomerang/boomerang_effect.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Mirrors and stitches recorded clips without lowering their quality: output
/// keeps the source resolution and bitrate. Encodes with the phone's hardware
/// H.264 encoder (the same one the camera records with, and fast), falling back
/// to near-lossless x264 if the hardware encoder is unavailable.
class VideoProcessor {
  /// Filter step cropping the centre of the frame to [aspect] (width /
  /// height) with even dimensions, or '' for no crop. Starts with a comma so
  /// it can be appended to a chain.
  @visibleForTesting
  static String cropFilter(double? aspect) {
    if (aspect == null) return '';
    final r = aspect.toStringAsFixed(6);
    return ",crop=w='trunc(min(iw,ih*$r)/2)*2':h='trunc(min(ih,iw/$r)/2)*2'";
  }

  /// Mirrors a front-camera clip, optionally cropping it to [aspect].
  /// Returns the output path, or null on failure.
  static Future<String?> mirror(String input, {double? aspect}) async {
    final info = await _probe(input);
    final output = await _outputPath('mirrored');
    final ok = await _encode(
      (encoder) => "-y -i '$input' -vf \"hflip${cropFilter(aspect)}\" $encoder -c:a copy '$output'",
      info.bitrate,
    );
    return ok ? output : null;
  }

  /// Crops a clip to [aspect] (width / height), keeping its bitrate.
  /// Returns the output path, or null on failure.
  static Future<String?> crop(String input, double aspect) async {
    final info = await _probe(input);
    final output = await _outputPath('cropped');
    final ok = await _encode(
      (encoder) => "-y -i '$input' -vf \"${cropFilter(aspect).substring(1)}\" $encoder -c:a copy '$output'",
      info.bitrate,
    );
    return ok ? output : null;
  }

  /// Joins clips recorded across a camera flip, mirroring front-camera parts.
  /// Returns the output path, or null on failure.
  static Future<String?> stitch(List<({String path, bool mirror})> segments, {double? aspect}) async {
    final infos = await Future.wait(segments.map((s) => _probe(s.path)));

    // Output at the largest recorded resolution and bitrate, in the orientation
    // of the first clip, so no part is downscaled.
    final largest = infos.reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
    final longSide = largest.width > largest.height ? largest.width : largest.height;
    final shortSide = largest.width > largest.height ? largest.height : largest.width;
    final portrait = infos.first.height >= infos.first.width;
    final int w = portrait ? shortSide : longSide;
    final int h = portrait ? longSide : shortSide;
    final int bitrate = infos.map((i) => i.bitrate).reduce((a, b) => a > b ? a : b);

    String inputs = '';
    String filterComplex = '';
    String concatInputs = '';
    for (int i = 0; i < segments.length; i++) {
      inputs += "-i '${segments[i].path}' ";
      final flip = segments[i].mirror ? 'hflip,' : '';
      filterComplex +=
          '[$i:v]${flip}scale=$w:$h:force_original_aspect_ratio=decrease:flags=lanczos,'
          'pad=$w:$h:(ow-iw)/2:(oh-ih)/2,setsar=1[v$i];'
          '[$i:a]aresample=48000[a$i];';
      concatInputs += '[v$i][a$i]';
    }
    filterComplex += '${concatInputs}concat=n=${segments.length}:v=1:a=1[cv][outa];[cv]null${cropFilter(aspect)}[outv]';

    final output = await _outputPath('stitched');
    final ok = await _encode(
      (encoder) => '-y $inputs -filter_complex "$filterComplex" -map "[outv]" -map "[outa]" '
          "$encoder -c:a aac -b:a 192k '$output'",
      bitrate,
    );
    return ok ? output : null;
  }

  /// Extracts the first [seconds] of a clip as small upright JPEG frames at
  /// [fps] for the live boomerang preview. Returns the frame paths in order.
  static Future<List<String>?> extractFrames(
    String input, {
    required double seconds,
    required bool mirror,
    double? aspect,
    int width = 432,
    int fps = 30,
  }) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/boomerang_${DateTime.now().millisecondsSinceEpoch}');
    await dir.create(recursive: true);
    final flip = mirror ? ',hflip' : '';
    final session = await FFmpegKit.execute(
      "-y -t ${seconds.toStringAsFixed(3)} -i '$input' -vf \"fps=$fps$flip${cropFilter(aspect)},scale=$width:-2\" -q:v 3 '${dir.path}/f_%04d.jpg'",
    );
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      debugPrint('VideoProcessor: frame extraction failed: ${await session.getLogsAsString()}');
      return null;
    }
    final files = dir.listSync().whereType<File>().map((f) => f.path).where((p) => p.endsWith('.jpg')).toList()..sort();
    return files;
  }

  /// Renders a full-quality boomerang: the first [frameCount] frames (at 30fps)
  /// played forward then backward with the effect's speed ramp, looped so it
  /// plays for about 8 seconds even in players that don't repeat. Silent, like
  /// every boomerang. Returns the output path, or null on failure.
  static Future<String?> boomerang(
    String input, {
    required double seconds,
    required bool mirror,
    required int frameCount,
    required BoomerangEffect effect,
    double? aspect,
  }) async {
    final timing = BoomerangTiming(effect, frameCount);
    final info = await _probe(input);
    final filter = boomerangFilter(timing, mirror: mirror, aspect: aspect);

    final cycle = await _outputPath('boomerang_cycle');
    final ok = await _encode(
      (encoder) => "-y -t ${seconds.toStringAsFixed(3)} -i '$input' -filter_complex \"$filter\" "
          "-map \"[out]\" -an $encoder '$cycle'",
      info.bitrate < 16000000 ? 16000000 : info.bitrate,
    );
    if (!ok) return null;

    // Repeat the cycle without re-encoding
    final int loops = (8 / timing.cycleSeconds).round().clamp(2, 8);
    final output = await _outputPath('boomerang');
    final session = await FFmpegKit.execute(
      "-y -stream_loop ${loops - 1} -i '$cycle' -c copy -movflags +faststart '$output'",
    );
    if (ReturnCode.isSuccess(await session.getReturnCode())) {
      File(cycle).delete().ignore();
      return output;
    }
    return cycle;
  }

  /// Filter graph for one boomerang cycle: forward pass, then the reversed
  /// pass without the turn-around frames, each with the effect's speed ramp.
  @visibleForTesting
  static String boomerangFilter(BoomerangTiming timing, {required bool mirror, double? aspect}) {
    final int n = timing.frameCount;
    final flip = mirror ? ',hflip' : '';
    // Echo: weighted blend of the current frame and every other one of the
    // previous six (oldest first), matching the live preview's trail
    final echo = timing.effect.echo ? ",tmix=frames=7:weights='1 0 2 0 3 0 8'" : '';
    return '[0:v]fps=30,trim=end_frame=$n,setpts=PTS-STARTPTS$flip${cropFilter(aspect)},split[a][b];'
        '[a]setpts=${timing.setptsExpression(forward: true)}[f];'
        '[b]reverse,trim=start_frame=1:end_frame=${n - 1},setpts=PTS-STARTPTS,'
        'setpts=${timing.setptsExpression(forward: false)}[r];'
        '[f][r]concat=n=2:v=1:a=0,fps=30$echo,format=yuv420p[out]';
  }

  /// Tries the hardware encoder at the source bitrate, then x264 at CRF 18
  /// (visually lossless).
  static Future<bool> _encode(String Function(String encoder) command, int bitrate) async {
    final encoders = [
      '-c:v h264_mediacodec -b:v $bitrate',
      '-c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p',
    ];
    for (final encoder in encoders) {
      final session = await FFmpegKit.execute(command(encoder));
      if (ReturnCode.isSuccess(await session.getReturnCode())) return true;
      debugPrint('VideoProcessor: encode with "$encoder" failed: ${await session.getLogsAsString()}');
    }
    return false;
  }

  /// Cuts the audio of a clip to its video length without re-encoding. Used
  /// for clips finalized after the app left the screen, where the microphone
  /// kept recording after the camera stopped. Returns null on failure.
  static Future<String?> trimToVideo(String input) async {
    final info = await _Mp4Header.read(input);
    if (info == null || info.seconds <= 0) return null;
    final output = await _outputPath('trimmed');
    final session = await FFmpegKit.execute(
      "-y -i '$input' -map 0 -c copy -t ${info.seconds.toStringAsFixed(3)} -movflags +faststart '$output'",
    );
    return ReturnCode.isSuccess(await session.getReturnCode()) ? output : null;
  }

  /// Whether [path] is a complete MP4 (has its index), i.e. safe to save.
  static Future<bool> isPlayable(String path) async {
    try {
      return await _Mp4Header.read(path) != null;
    } catch (_) {
      return false;
    }
  }

  /// Reads the display size (after the rotation flag phone cameras write) and
  /// the average bitrate straight from the MP4 header.
  static Future<_VideoInfo> _probe(String path) async {
    try {
      final info = await _Mp4Header.read(path);
      if (info != null) return info;
    } catch (e) {
      debugPrint('VideoProcessor: could not read MP4 header of $path: $e');
    }
    return _VideoInfo(1080, 1920, 20000000, 0);
  }

  static Future<String> _outputPath(String prefix) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }
}

class _VideoInfo {
  _VideoInfo(this.width, this.height, this.bitrate, this.seconds);
  final int width;
  final int height;
  final int bitrate;
  /// Length of the video track.
  final double seconds;
}

/// Minimal MP4 reader: finds the video track and returns its display size
/// (tkhd size with the rotation matrix applied) and average bitrate.
class _Mp4Header {
  static Future<_VideoInfo?> read(String path) async {
    final file = await File(path).open();
    try {
      final int length = await file.length();
      int offset = 0;
      while (offset + 8 <= length) {
        await file.setPosition(offset);
        final header = ByteData.sublistView(await file.read(16));
        int size = header.getUint32(0);
        final String type = String.fromCharCodes(header.buffer.asUint8List(header.offsetInBytes + 4, 4));
        int headerSize = 8;
        if (size == 1) {
          size = header.getUint64(8);
          headerSize = 16;
        } else if (size == 0) {
          size = length - offset;
        }
        if (size < headerSize) return null;
        if (type == 'moov') {
          await file.setPosition(offset + headerSize);
          final moov = ByteData.sublistView(await file.read(size - headerSize));
          return _parseMoov(moov, length);
        }
        offset += size;
      }
      return null;
    } finally {
      await file.close();
    }
  }

  static _VideoInfo? _parseMoov(ByteData moov, int fileLength) {
    for (final trak in _children(moov, 0, moov.lengthInBytes).where((b) => b.type == 'trak')) {
      _Box? tkhd, mdia;
      for (final b in _children(moov, trak.start, trak.end)) {
        if (b.type == 'tkhd') tkhd = b;
        if (b.type == 'mdia') mdia = b;
      }
      if (tkhd == null || mdia == null) continue;

      bool isVideo = false;
      double seconds = 0;
      for (final b in _children(moov, mdia.start, mdia.end)) {
        if (b.type == 'hdlr') {
          isVideo = String.fromCharCodes(moov.buffer.asUint8List(moov.offsetInBytes + b.start + 8, 4)) == 'vide';
        } else if (b.type == 'mdhd') {
          final bool v1 = moov.getUint8(b.start) == 1;
          final int timescale = moov.getUint32(b.start + (v1 ? 20 : 12));
          final int duration = v1 ? moov.getUint64(b.start + 24) : moov.getUint32(b.start + 16);
          if (timescale > 0) seconds = duration / timescale;
        }
      }
      if (!isVideo) continue;

      // tkhd: version/flags, times, track id, reserved, duration, reserved,
      // layer, group, volume, reserved, 3x3 matrix, width, height (16.16)
      final bool v1 = moov.getUint8(tkhd.start) == 1;
      final int matrixAt = tkhd.start + 4 + (v1 ? 32 : 20) + 8 + 8;
      final int a = moov.getInt32(matrixAt);
      final int d = moov.getInt32(matrixAt + 16);
      int width = moov.getUint32(matrixAt + 36) >> 16;
      int height = moov.getUint32(matrixAt + 40) >> 16;
      if (width == 0 || height == 0) return null;

      // A 90° or 270° rotation matrix has zero on its diagonal
      if (a == 0 && d == 0) {
        final t = width;
        width = height;
        height = t;
      }
      final int bitrate = seconds > 0 ? (fileLength * 8 / seconds).round() : 20000000;
      return _VideoInfo(width, height, bitrate, seconds);
    }
    return null;
  }

  static Iterable<_Box> _children(ByteData data, int start, int end) sync* {
    int offset = start;
    while (offset + 8 <= end) {
      int size = data.getUint32(offset);
      int headerSize = 8;
      if (size == 1) {
        size = data.getUint64(offset + 8);
        headerSize = 16;
      } else if (size == 0) {
        size = end - offset;
      }
      if (size < headerSize || offset + size > end) return;
      final String type = String.fromCharCodes(data.buffer.asUint8List(data.offsetInBytes + offset + 4, 4));
      yield _Box(type, offset + headerSize, offset + size);
      offset += size;
    }
  }
}

class _Box {
  _Box(this.type, this.start, this.end);
  final String type;
  final int start;
  final int end;
}
