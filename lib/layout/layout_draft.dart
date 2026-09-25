import 'dart:math' as math;

import 'layout_template.dart';

enum LayoutMode { photos, videos, hybrid }

enum CellKind { photo, video }

class LayoutMedia {
  const LayoutMedia({
    required this.path,
    required this.kind,
    this.mirror = false,
    this.seconds = 0,
    this.hasAudio = false,
    this.thumbnail,
  });
  final String path;
  final CellKind kind;
  final bool mirror;
  final double seconds;
  final bool hasAudio;
  final String? thumbnail;
  Map<String, dynamic> toJson() => {
    'path': path,
    'kind': kind.name,
    'mirror': mirror,
    'seconds': seconds,
    'hasAudio': hasAudio,
    'thumbnail': thumbnail,
  };
  factory LayoutMedia.fromJson(Map<String, dynamic> j) => LayoutMedia(
    path: j['path'] as String,
    kind: CellKind.values.byName(j['kind'] as String),
    mirror: j['mirror'] == true,
    seconds: (j['seconds'] as num?)?.toDouble() ?? 0,
    hasAudio: j['hasAudio'] == true,
    thumbnail: j['thumbnail'] as String?,
  );
}

class LayoutDraft {
  LayoutDraft({
    this.template = LayoutTemplate.quad,
    this.mode = LayoutMode.photos,
    this.aspectId = '3:4',
    this.ratio = .75,
  }) {
    media = List.filled(template.cells.length, null);
    kinds = List.filled(
      template.cells.length,
      mode == LayoutMode.videos ? CellKind.video : CellKind.photo,
    );
  }
  LayoutTemplate template;
  LayoutMode mode;
  String aspectId;

  /// Resolved once (including Full); device rotation does not mutate output.
  double ratio;
  int selected = 0;
  int? audioCell;
  late List<LayoutMedia?> media;
  late List<CellKind> kinds;
  bool get complete => media.every((m) => m != null);
  bool get hasMedia => media.any((m) => m != null);
  bool get isVideo => media.any((m) => m?.kind == CellKind.video);
  double get duration =>
      media.fold(0.0, (n, m) => math.max(n, m?.seconds ?? 0));
  CellKind get selectedKind => kinds[selected];
  int get filled => media.whereType<LayoutMedia>().length;

  void put(int index, LayoutMedia value) {
    if (mode == LayoutMode.photos && value.kind != CellKind.photo ||
        mode == LayoutMode.videos && value.kind != CellKind.video) {
      throw StateError('Media does not match layout mode');
    }
    media[index] = value;
    kinds[index] = value.kind;
    if (audioCell == index && !value.hasAudio) audioCell = null;
    selected = media.indexWhere((m) => m == null);
    if (selected < 0) selected = index;
  }

  void clear(int index) {
    media[index] = null;
    if (audioCell == index) audioCell = null;
    selected = index;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'template': template.name,
    'mode': mode.name,
    'aspectId': aspectId,
    'ratio': ratio,
    'selected': selected,
    'audioCell': audioCell,
    'kinds': kinds.map((k) => k.name).toList(),
    'media': media.map((m) => m?.toJson()).toList(),
  };
  factory LayoutDraft.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) throw const FormatException('Unknown layout draft');
    final d = LayoutDraft(
      template: LayoutTemplate.values.byName(j['template']),
      mode: LayoutMode.values.byName(j['mode']),
      aspectId: j['aspectId'],
      ratio: (j['ratio'] as num).toDouble(),
    );
    if (!d.ratio.isFinite || d.ratio <= 0) {
      throw const FormatException('Invalid ratio');
    }
    d.media = (j['media'] as List)
        .map(
          (m) => m == null
              ? null
              : LayoutMedia.fromJson(Map<String, dynamic>.from(m)),
        )
        .toList();
    d.kinds = (j['kinds'] as List)
        .map((k) => CellKind.values.byName(k))
        .toList();
    if (d.media.length != d.template.cells.length ||
        d.kinds.length != d.media.length) {
      throw const FormatException('Invalid cells');
    }
    d.selected = (j['selected'] as int).clamp(0, d.media.length - 1);
    final a = j['audioCell'] as int?;
    d.audioCell =
        a != null &&
            a >= 0 &&
            a < d.media.length &&
            d.media[a]?.hasAudio == true
        ? a
        : null;
    return d;
  }
}
