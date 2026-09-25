import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

typedef FaceBox = ({double left, double top, double width, double height});

/// Whole-frame pixel measurements plus the decoded pixels, produced in the
/// background while the ML Kit detectors run.
class FramePixels {
  FramePixels._({
    required this.width,
    required this.height,
    required this.meanLuma,
    required this.lumaStdDev,
    required this.shadowClip,
    required this.highlightClip,
    required this.saturation,
    required this.centerSharpness,
    required this.rgb,
    required this.nsfwInput,
  });

  final int width, height;
  /// 0..255
  final double meanLuma;
  /// Global contrast (standard deviation of luma).
  final double lumaStdDev;
  /// Share of crushed-black / blown-white pixels.
  final double shadowClip, highlightClip;
  /// Mean colourfulness 0..1.
  final double saturation;
  /// Variance of the Laplacian in the centre of the frame.
  final double centerSharpness;
  /// Decoded RGB bytes (width * height * 3).
  final Uint8List rgb;
  /// 224x224 RGB for the content model.
  final Uint8List nsfwInput;

  static Future<FramePixels> load(String path) async {
    final r = await Isolate.run(() => _loadFrame(path));
    return FramePixels._(
      width: r.width,
      height: r.height,
      meanLuma: r.meanLuma,
      lumaStdDev: r.lumaStdDev,
      shadowClip: r.shadowClip,
      highlightClip: r.highlightClip,
      saturation: r.saturation,
      centerSharpness: r.centerSharpness,
      rgb: r.rgb.materialize().asUint8List(),
      nsfwInput: r.nsfwInput,
    );
  }

  /// Focus, exposure and the emotion-model crop for the face.
  Future<FacePixels> face(FaceBox box) {
    final transfer = TransferableTypedData.fromList([rgb]);
    final int w = width, h = height;
    return Isolate.run(() => _faceStats(transfer.materialize().asUint8List(), w, h, box));
  }
}

class FacePixels {
  FacePixels(this.sharpness, this.luma, this.emotionInput);
  final double sharpness;
  final double luma;
  /// 48x48 grayscale, float32 0..1, as raw bytes (emotion model input).
  final Uint8List emotionInput;
}

/// What the scoring engine sees.
class PixelMetrics {
  PixelMetrics({
    required this.meanLuma,
    required this.lumaStdDev,
    required this.shadowClip,
    required this.highlightClip,
    required this.saturation,
    required this.sharpness,
    this.subjectLuma,
  });

  factory PixelMetrics.of(FramePixels frame, FacePixels? face) => PixelMetrics(
        meanLuma: frame.meanLuma,
        lumaStdDev: frame.lumaStdDev,
        shadowClip: frame.shadowClip,
        highlightClip: frame.highlightClip,
        saturation: frame.saturation,
        sharpness: face?.sharpness ?? frame.centerSharpness,
        subjectLuma: face?.luma,
      );

  final double meanLuma, lumaStdDev, shadowClip, highlightClip, saturation;
  /// Variance of the Laplacian on the subject (face, else frame centre).
  final double sharpness;
  final double? subjectLuma;
}

class _FrameResult {
  _FrameResult(this.width, this.height, this.meanLuma, this.lumaStdDev, this.shadowClip, this.highlightClip,
      this.saturation, this.centerSharpness, this.rgb, this.nsfwInput);
  final int width, height;
  final double meanLuma, lumaStdDev, shadowClip, highlightClip, saturation, centerSharpness;
  final TransferableTypedData rgb;
  final Uint8List nsfwInput;
}

_FrameResult _loadFrame(String path) {
  final image = img.decodeJpg(File(path).readAsBytesSync());
  if (image == null) throw Exception('Could not decode $path');
  final int w = image.width, h = image.height;
  final Uint8List rgb = image.getBytes(order: img.ChannelOrder.rgb);

  double sum = 0, sumSq = 0, sat = 0;
  int count = 0, dark = 0, bright = 0;
  for (int i = 0; i < rgb.length; i += 6) {
    final int r = rgb[i], g = rgb[i + 1], b = rgb[i + 2];
    final double y = 0.299 * r + 0.587 * g + 0.114 * b;
    sum += y;
    sumSq += y * y;
    if (y < 16) dark++;
    if (y > 240) bright++;
    final int mx = max(r, max(g, b)), mn = min(r, min(g, b));
    if (mx > 0) sat += (mx - mn) / mx;
    count++;
  }
  final double mean = sum / count;
  final double std = sqrt(max(0.0, sumSq / count - mean * mean));
  final double centerSharp = _laplacianVariance(rgb, w, h, (w * 0.25).floor(), (h * 0.25).floor(), (w * 0.75).ceil(), (h * 0.75).ceil());

  final small = img.copyResize(image, width: 224, height: 224, interpolation: img.Interpolation.average);
  return _FrameResult(w, h, mean, std, dark / count, bright / count, sat / count, centerSharp,
      TransferableTypedData.fromList([rgb]), Uint8List.fromList(small.getBytes(order: img.ChannelOrder.rgb)));
}

FacePixels _faceStats(Uint8List rgb, int w, int h, FaceBox box) {
  final int x0 = (box.left - box.width * 0.1).floor().clamp(0, w - 2);
  final int y0 = (box.top - box.height * 0.1).floor().clamp(0, h - 2);
  final int x1 = (box.left + box.width * 1.1).ceil().clamp(x0 + 2, w);
  final int y1 = (box.top + box.height * 1.1).ceil().clamp(y0 + 2, h);

  double luma = 0;
  int n = 0;
  for (int y = y0; y < y1; y += 2) {
    for (int x = x0; x < x1; x += 2) {
      luma += _luma(rgb, w, x, y);
      n++;
    }
  }

  // Area-average the face into 48x48 grayscale, 0..1
  final floats = Float32List(48 * 48);
  final double cw = (x1 - x0) / 48, ch = (y1 - y0) / 48;
  for (int j = 0; j < 48; j++) {
    for (int i = 0; i < 48; i++) {
      final int sx0 = x0 + (i * cw).floor(), sx1 = max(sx0 + 1, x0 + ((i + 1) * cw).floor());
      final int sy0 = y0 + (j * ch).floor(), sy1 = max(sy0 + 1, y0 + ((j + 1) * ch).floor());
      double acc = 0;
      int c = 0;
      for (int y = sy0; y < sy1 && y < h; y++) {
        for (int x = sx0; x < sx1 && x < w; x++) {
          acc += _luma(rgb, w, x, y);
          c++;
        }
      }
      floats[j * 48 + i] = c == 0 ? 0 : acc / c / 255.0;
    }
  }
  // Stretch the crop's own contrast (standard for expression models), so
  // faces in dark or flat light still read clearly
  double lo = 1, hi = 0;
  for (final v in floats) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (hi - lo > 0.02) {
    for (int k = 0; k < floats.length; k++) {
      floats[k] = (floats[k] - lo) / (hi - lo);
    }
  }

  return FacePixels(
    _laplacianVariance(rgb, w, h, x0, y0, x1, y1),
    n == 0 ? 0 : luma / n,
    floats.buffer.asUint8List(),
  );
}

double _luma(Uint8List rgb, int w, int x, int y) {
  final int i = (y * w + x) * 3;
  return 0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2];
}

/// Focus measure: variance of the 4-neighbour Laplacian over a region.
double _laplacianVariance(Uint8List rgb, int w, int h, int x0, int y0, int x1, int y1) {
  final int stride = max(1, ((x1 - x0) * (y1 - y0) / 90000).ceil());
  double sum = 0, sumSq = 0;
  int n = 0;
  for (int y = max(1, y0); y < min(h - 1, y1); y += stride) {
    for (int x = max(1, x0); x < min(w - 1, x1); x += stride) {
      final double l = _luma(rgb, w, x - 1, y) + _luma(rgb, w, x + 1, y) + _luma(rgb, w, x, y - 1) + _luma(rgb, w, x, y + 1) - 4 * _luma(rgb, w, x, y);
      sum += l;
      sumSq += l * l;
      n++;
    }
  }
  if (n == 0) return 0;
  final double mean = sum / n;
  return sumSq / n - mean * mean;
}
