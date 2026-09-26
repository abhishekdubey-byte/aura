import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:aura/services/media_save_queue.dart';
import 'package:aura/services/media_encoder_policy.dart';

import 'layout_draft.dart';
import 'layout_template.dart';

class LayoutExporter {
  /// Camera startup/stop latency varies by device. Timed cells are normalized
  /// to the requested duration, holding the final frame for any shortfall.
  static Future<String> normalizeTimedRecording(
    String source,
    int seconds,
  ) async {
    if (seconds < 1 || seconds > 300) {
      throw ArgumentError.value(seconds, 'seconds');
    }
    final dir = await getTemporaryDirectory();
    final output =
        '${dir.path}/layout_timed_${DateTime.now().microsecondsSinceEpoch}.mp4';
    for (final hardware in [
      if (await MediaEncoderPolicy.useHardware) true,
      false,
    ]) {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        source,
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        '-vf',
        'setpts=PTS-STARTPTS,fps=30,tpad=stop_mode=clone:stop_duration=$seconds',
        '-af',
        'asetpts=PTS-STARTPTS,apad',
        '-t',
        '$seconds',
        '-c:v',
        hardware ? 'h264_mediacodec' : 'libx264',
        if (hardware) ...[
          '-b:v',
          '12000000',
        ] else ...[
          '-preset',
          'veryfast',
          '-crf',
          '18',
        ],
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-movflags',
        '+faststart',
        output,
      ]);
      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          await File(output).length() > 0) {
        return output;
      }
    }
    if (await File(output).exists()) await File(output).delete();
    throw StateError('Could not finalize the timed recording. Please retry.');
  }

  static Future<LayoutMedia> inspectVideo(
    String path, {
    bool mirror = false,
  }) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    final streams = info?.getStreams() ?? [];
    final videos = streams.where((s) => s.getType() == 'video');
    if (videos.isEmpty) {
      throw const FormatException('This file has no readable video');
    }
    final seconds =
        double.tryParse(
          videos.first.getAllProperties()?['duration']?.toString() ?? '',
        ) ??
        double.tryParse(info?.getDuration() ?? '') ??
        0;
    if (!seconds.isFinite || seconds <= 0) {
      throw const FormatException('Video duration could not be read');
    }
    final thumbnail = '$path.thumb.jpg';
    final shot = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      path,
      '-frames:v',
      '1',
      '-vf',
      'scale=480:480:force_original_aspect_ratio=decrease',
      '-q:v',
      '3',
      thumbnail,
    ]);
    if (!ReturnCode.isSuccess(await shot.getReturnCode())) {
      throw StateError('Video thumbnail could not be generated');
    }
    return LayoutMedia(
      path: path,
      kind: CellKind.video,
      seconds: seconds,
      hasAudio: streams.any((s) => s.getType() == 'audio'),
      mirror: mirror,
      thumbnail: thumbnail,
    );
  }

  /// One encode at a time, shared with the regular camera's save queue.
  static Future<String> render(
    LayoutDraft draft, {
    ValueChanged<double>? onProgress,
    String? watermark,
    int? longEdge,
  }) {
    final snapshot = LayoutDraft.fromJson(draft.toJson());
    final done = Completer<String>();
    MediaSaveQueue.instance.add(() async {
      try {
        if (!snapshot.complete) {
          throw StateError('Fill every cell before exporting');
        }
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/layout_${DateTime.now().microsecondsSinceEpoch}.${snapshot.isVideo ? 'mp4' : 'jpg'}';
        onProgress?.call(0);
        if (snapshot.isVideo) {
          await _renderVideo(snapshot, path, onProgress, longEdge ?? 1920);
        } else {
          await compute(_renderPhoto, (
            snapshot,
            path,
            watermark,
            longEdge ?? 2160,
          ));
        }
        onProgress?.call(1);
        done.complete(path);
      } catch (e, stack) {
        done.completeError(e, stack);
      }
    });
    return done.future;
  }

  /// Argument arrays keep imported filenames out of command parsing.
  @visibleForTesting
  static List<String> videoArguments(
    LayoutDraft d,
    String output, {
    int longEdge = 1920,
    bool hardware = false,
  }) {
    if (!d.complete || !d.isVideo || d.duration <= 0) {
      throw StateError('A complete video layout is required');
    }
    final size = layoutOutputSize(d.ratio, longEdge: longEdge);
    final cells = d.template.pixelRects(size);
    final duration = d.duration.toStringAsFixed(6);
    final args = <String>['-y', '-filter_complex_threads', '1'];
    final filters = <String>[];
    for (int i = 0; i < d.media.length; i++) {
      final media = d.media[i]!;
      if (media.kind == CellKind.photo) {
        args.addAll(['-loop', '1', '-framerate', '30']);
      }
      args.addAll(['-i', media.path]);
      final r = cells[i];
      final w = r.width.toInt(), h = r.height.toInt();
      filters.add(
        '[$i:v]setpts=PTS-STARTPTS,${media.mirror ? 'hflip,' : ''}'
        'scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h,setsar=1,fps=30,'
        'format=yuv420p,tpad=stop_mode=clone:stop_duration=$duration,trim=duration=$duration[v$i]',
      );
    }
    if (d.template.isDiamond) {
      filters.add(
        'color=c=black:s=${size.width.toInt()}x${size.height.toInt()}:r=30:d=$duration[bg0]',
      );
      for (int i = 0; i < cells.length; i++) {
        final r = cells[i];
        // Compute each mask once, then replay that frame. Source pictures and
        // videos stay upright behind the cutout instead of being rotated.
        filters.add(
          "nullsrc=s=${r.width.toInt()}x${r.height.toInt()}:r=30,format=gray,"
          "geq=lum='${LayoutTemplate.diamondMaskExpression}',"
          'trim=end_frame=1,loop=loop=-1:size=1:start=0,setpts=N/(30*TB)[mask$i]',
        );
        filters.add('[v$i][mask$i]alphamerge[diamond$i]');
        filters.add(
          '[bg$i][diamond$i]overlay=x=${r.left.toInt()}:y=${r.top.toInt()}:shortest=1[bg${i + 1}]',
        );
      }
      filters.add('[bg${cells.length}]format=yuv420p[outv]');
    } else {
      final stack = List.generate(cells.length, (i) => '[v$i]').join();
      final positions = cells
          .map((r) => '${r.left.toInt()}_${r.top.toInt()}')
          .join('|');
      filters.add(
        '${stack}xstack=inputs=${cells.length}:layout=$positions:fill=black[outv]',
      );
    }
    final a = d.audioCell;
    final hasAudio = a != null && d.media[a]?.hasAudio == true;
    if (hasAudio) {
      filters.add(
        '[$a:a:0]atrim=duration=$duration,asetpts=PTS-STARTPTS,apad=whole_dur=$duration[outa]',
      );
    }
    args.addAll(['-filter_complex', filters.join(';'), '-map', '[outv]']);
    args.addAll(
      hasAudio ? ['-map', '[outa]', '-c:a', 'aac', '-b:a', '192k'] : ['-an'],
    );
    args.addAll(
      hardware
          ? ['-c:v', 'h264_mediacodec', '-b:v', '12000000']
          : [
              '-c:v',
              'libx264',
              '-preset',
              'veryfast',
              '-crf',
              '18',
              '-threads',
              '2',
            ],
    );
    args.addAll([
      '-pix_fmt',
      'yuv420p',
      '-t',
      duration,
      '-movflags',
      '+faststart',
      output,
    ]);
    return args;
  }

  static Future<void> _renderVideo(
    LayoutDraft draft,
    String path,
    ValueChanged<double>? progress,
    int longEdge,
  ) async {
    // Software works for every layout dimension; Android hardware is a fast
    // first attempt, with the same graph and a software fallback.
    for (final hardware in [
      if (await MediaEncoderPolicy.useHardware) true,
      false,
    ]) {
      final done = Completer<bool>();
      await FFmpegKit.executeWithArgumentsAsync(
        videoArguments(draft, path, hardware: hardware, longEdge: longEdge),
        (s) async {
          done.complete(ReturnCode.isSuccess(await s.getReturnCode()));
        },
        null,
        (s) => progress?.call(
          (s.getTime() / (draft.duration * 1000)).clamp(0, .99),
        ),
      );
      if (await done.future) {
        if (await File(path).length() > 0) return;
      }
    }
    throw StateError(
      'Could not render this layout. Your cells are saved; please retry.',
    );
  }
}

Future<void> _renderPhoto((LayoutDraft, String, String?, int) args) async {
  final (draft, path, watermark, longEdge) = args;
  final size = layoutOutputSize(draft.ratio, longEdge: longEdge);
  final output = img.Image(
    width: size.width.toInt(),
    height: size.height.toInt(),
  );
  final cells = draft.template.pixelRects(size);
  for (int i = 0; i < cells.length; i++) {
    final media = draft.media[i]!;
    final decoded = img.decodeImage(await File(media.path).readAsBytes());
    if (decoded == null) {
      throw FormatException('Cell ${i + 1} cannot be decoded');
    }
    var source = img.bakeOrientation(decoded);
    if (media.mirror) source = img.flipHorizontal(source);
    final r = cells[i];
    final crop = layoutSourceCrop(
      Size(source.width.toDouble(), source.height.toDouble()),
      r.width / r.height,
    );
    source = img.copyCrop(
      source,
      x: crop.left.round(),
      y: crop.top.round(),
      width: crop.width.round().clamp(1, source.width),
      height: crop.height.round().clamp(1, source.height),
    );
    final scaled = img.copyResize(
      source,
      width: r.width.toInt(),
      height: r.height.toInt(),
      interpolation: img.Interpolation.linear,
    );
    if (draft.template.isDiamond) {
      final local = Rect.fromLTWH(0, 0, r.width, r.height);
      for (final pixel in scaled) {
        if (draft.template.containsInCell(
          local,
          Offset(pixel.x + .5, pixel.y + .5),
        )) {
          output.setPixel(
            r.left.toInt() + pixel.x,
            r.top.toInt() + pixel.y,
            pixel,
          );
        }
      }
    } else {
      img.compositeImage(
        output,
        scaled,
        dstX: r.left.toInt(),
        dstY: r.top.toInt(),
      );
    }
  }
  if (watermark != null && watermark.isNotEmpty) {
    img.drawString(
      output,
      watermark,
      font: img.arial24,
      x: 20,
      y: output.height - 40,
      color: img.ColorRgb8(255, 255, 255),
    );
  }
  await File(path)
      .writeAsBytes(img.encodeJpg(output, quality: 95), flush: true);
}
