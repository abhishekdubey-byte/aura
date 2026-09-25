import 'package:flutter/painting.dart';

enum AspectCategory { phone, social, desktop }

extension AspectCategoryLabel on AspectCategory {
  String get title => switch (this) {
        AspectCategory.phone => 'Phone',
        AspectCategory.social => 'Social',
        AspectCategory.desktop => 'Laptop & desktop wallpaper',
      };
}

/// A framing for photos and videos. Every aspect is a centred crop of the
/// camera frame (4:3 sensor for photos, 16:9 for video), so the viewfinder can
/// show exactly what will be saved.
class CaptureAspect {
  const CaptureAspect._(this.id, this.label, this.category, this.width, this.height, this.useCase, {this.isFull = false});

  final String id;
  final String label;
  final AspectCategory category;
  final double width;
  final double height;
  /// Where this framing is typically used, shown in the picker.
  final String useCase;
  /// Matches the phone's own screen shape (resolved at runtime).
  final bool isFull;

  /// Width / height, or null for [isFull] (depends on the screen).
  double? get ratio => isFull ? null : width / height;
  bool get isLandscape => !isFull && width > height;

  // Phone
  static const full = CaptureAspect._('full', 'Full', AspectCategory.phone, 9, 20, 'Fills your phone screen', isFull: true);
  static const tall = CaptureAspect._('9:16', '9:16', AspectCategory.phone, 9, 16, 'Tall phone photos & videos');
  static const standard = CaptureAspect._('3:4', '3:4', AspectCategory.phone, 3, 4, 'Full sensor · highest resolution');
  static const square = CaptureAspect._('1:1', '1:1', AspectCategory.phone, 1, 1, 'Square · profile pictures');

  // Social
  static const instagramPost = CaptureAspect._('ig_post', '4:5', AspectCategory.social, 4, 5, 'Instagram feed post');
  static const stories = CaptureAspect._('stories', '9:16', AspectCategory.social, 9, 16, 'Stories · Reels · Snapchat · TikTok');
  static const instagramLandscape = CaptureAspect._('ig_land', '1.91:1', AspectCategory.social, 1.91, 1, 'Instagram landscape post');

  // Laptop & desktop wallpaper
  static const desktop16x9 = CaptureAspect._('16:9', '16:9', AspectCategory.desktop, 16, 9, 'Most laptops · Full HD, QHD & 4K monitors · TVs');
  static const desktop16x10 = CaptureAspect._('16:10', '16:10', AspectCategory.desktop, 16, 10, 'MacBook · many Windows laptops');
  static const desktop3x2 = CaptureAspect._('3:2', '3:2', AspectCategory.desktop, 3, 2, 'Surface · Framework · Chromebooks');
  static const desktop21x9 = CaptureAspect._('21:9', '21:9', AspectCategory.desktop, 21, 9, 'Ultrawide monitors');
  static const desktop4x3 = CaptureAspect._('4:3', '4:3', AspectCategory.desktop, 4, 3, 'iPad · classic monitors');

  static const List<CaptureAspect> values = [
    full, tall, standard, square,
    instagramPost, stories, instagramLandscape,
    desktop16x9, desktop16x10, desktop3x2, desktop21x9, desktop4x3,
  ];

  static const CaptureAspect initial = standard;

  static CaptureAspect byId(String? id) =>
      values.firstWhere((a) => a.id == id, orElse: () => initial);

  /// Width / height for this framing on a screen of [screen] size.
  double resolveRatio(Size screen) => ratio ?? screen.width / screen.height;
}

/// Largest rectangle of [ratio] (width / height) centred in a [frame].
Size centeredCropSize(Size frame, double ratio) {
  if (frame.width / frame.height > ratio) {
    return Size(frame.height * ratio, frame.height);
  }
  return Size(frame.width, frame.width / ratio);
}

/// Cropped output resolution in whole, even pixels (what encoders need).
Size cropResolution(Size frame, double ratio) {
  final s = centeredCropSize(frame, ratio);
  int even(double v) => (v / 2).floor() * 2;
  return Size(even(s.width).toDouble(), even(s.height).toDouble());
}

/// Where the camera frame and the chosen crop sit on screen.
///
/// The crop fills the screen width where it can (like native camera apps),
/// sits centred between the top bar and the shutter controls when it fits
/// there, and otherwise extends down behind the controls. [fillScreen] makes
/// the crop cover the whole screen (the "Full" framing).
class ViewfinderGeometry {
  const ViewfinderGeometry(this.frame, this.crop);

  /// The full camera preview frame on screen (may extend off-screen).
  final Rect frame;
  /// The part that will be saved.
  final Rect crop;

  /// [frameAspect] is the preview frame's width / height (0.75 for a 4:3
  /// sensor held upright). [fieldAspect] narrows the usable field, e.g. 9/16
  /// for video, which records the centre band of the frame.
  static ViewfinderGeometry compute({
    required Size screen,
    required EdgeInsets padding,
    required double frameAspect,
    required double cropRatio,
    double? fieldAspect,
    bool fillScreen = false,
    double topBar = 56,
    double bottomControls = 200,
  }) {
    // Work in units where the frame is 1 tall
    final double field = fieldAspect == null ? frameAspect : (fieldAspect < frameAspect ? fieldAspect : frameAspect);
    final Size cropUnits = centeredCropSize(Size(field, 1), cropRatio);

    double scale;
    Offset center;
    if (fillScreen) {
      scale = screen.width / cropUnits.width;
      if (cropUnits.height * scale < screen.height) scale = screen.height / cropUnits.height;
      center = screen.center(Offset.zero);
    } else {
      final double top = padding.top + topBar;
      final double bottom = screen.height - padding.bottom - bottomControls;
      scale = screen.width / cropUnits.width;
      if (cropUnits.height * scale > screen.height - top) {
        scale = (screen.height - top) / cropUnits.height;
      }
      final double cropHeight = cropUnits.height * scale;
      final double cy = cropHeight <= bottom - top ? (top + bottom) / 2 : top + cropHeight / 2;
      center = Offset(screen.width / 2, cy);
    }

    final crop = Rect.fromCenter(center: center, width: cropUnits.width * scale, height: cropUnits.height * scale);
    final frame = Rect.fromCenter(center: center, width: frameAspect * scale, height: scale);
    return ViewfinderGeometry(frame, crop);
  }
}
