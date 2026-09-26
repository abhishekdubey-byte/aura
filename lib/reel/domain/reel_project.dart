import 'package:flutter/foundation.dart';

/// Thrown when a project or an edit would produce an invalid document. Callers
/// see a rejected edit and an unchanged project, never a half-applied one.
class ReelProjectError implements Exception {
  const ReelProjectError(this.message);

  final String message;

  @override
  String toString() => 'ReelProjectError: $message';
}

/// A source file the project depends on.
///
/// An asset is owned by the project, not by a timeline position. Several clips
/// may reference one asset, and an asset stays retained while any revision the
/// project can return to still references it. Only facts capture actually knows
/// live here; pixel dimensions and audio-track details are deliberately absent
/// until a feature that genuinely probes the file needs them, because a
/// fabricated probe result is worse than a missing one.
@immutable
class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.path,
    required this.duration,
    required this.mirrored,
  });

  /// Stable asset ID, assigned once.
  final String id;

  /// Location of the source file. Persistent for the lifetime of the asset.
  final String path;

  /// Full duration of the source, independent of any clip that trims it.
  final Duration duration;

  /// Whether the source was recorded with a mirrored (front) camera. Source
  /// orientation and mirroring are represented once, here, rather than being
  /// re-derived per clip.
  final bool mirrored;

  MediaAsset copyWith({String? path, Duration? duration, bool? mirrored}) =>
      MediaAsset(
        id: id,
        path: path ?? this.path,
        duration: duration ?? this.duration,
        mirrored: mirrored ?? this.mirrored,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'durationUs': duration.inMicroseconds,
    'mirrored': mirrored,
  };

  static MediaAsset fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final path = json['path'];
    final durationUs = json['durationUs'];
    final mirrored = json['mirrored'];
    if (id is! String || id.isEmpty) {
      throw const ReelProjectError('Asset is missing its id');
    }
    if (path is! String || path.isEmpty) {
      throw ReelProjectError('Asset $id is missing its path');
    }
    if (durationUs is! int) {
      throw ReelProjectError('Asset $id has a non-integer duration');
    }
    if (mirrored is! bool) {
      throw ReelProjectError('Asset $id is missing its mirrored flag');
    }
    return MediaAsset(
      id: id,
      path: path,
      duration: Duration(microseconds: durationUs),
      mirrored: mirrored,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaAsset &&
      other.id == id &&
      other.path == path &&
      other.duration == duration &&
      other.mirrored == mirrored;

  @override
  int get hashCode => Object.hash(id, path, duration, mirrored);
}

/// One entry in the primary sequence: a use of an asset over a source interval.
///
/// A clip instance is not its asset. Two instances may share an asset with
/// different source windows, which is what lets a later feature split a clip
/// without copying media.
///
/// [sourceIn] and [sourceOut] form a half-open interval `[in, out)`. A
/// zero-length interval is invalid, never a freeze frame.
@immutable
class ReelClipInstance {
  const ReelClipInstance({
    required this.id,
    required this.assetId,
    required this.sourceIn,
    required this.sourceOut,
    required this.ratio,
    this.audioEnabled = true,
  });

  /// Stable instance ID. Survives reorder and replacement of the underlying
  /// media, so attachments made in later features keep pointing at this slot.
  final String id;

  /// The [MediaAsset] this instance draws from.
  final String assetId;

  /// Inclusive start of the used source interval.
  final Duration sourceIn;

  /// Exclusive end of the used source interval.
  final Duration sourceOut;

  /// Framing selected when the clip was captured, kept as a crop instruction
  /// rather than baked into the file. Width / height.
  final double ratio;

  /// Whether this clip contributes its own original recorded sound.
  final bool audioEnabled;

  /// Output length of this instance. At 1x this is simply the source span;
  /// retiming features introduce a time map and must not assume this identity.
  Duration get outputDuration => sourceOut - sourceIn;

  ReelClipInstance copyWith({
    Duration? sourceIn,
    Duration? sourceOut,
    double? ratio,
    bool? audioEnabled,
  }) => ReelClipInstance(
    id: id,
    assetId: assetId,
    sourceIn: sourceIn ?? this.sourceIn,
    sourceOut: sourceOut ?? this.sourceOut,
    ratio: ratio ?? this.ratio,
    audioEnabled: audioEnabled ?? this.audioEnabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'assetId': assetId,
    'sourceInUs': sourceIn.inMicroseconds,
    'sourceOutUs': sourceOut.inMicroseconds,
    'ratio': ratio,
    'audioEnabled': audioEnabled,
  };

  static ReelClipInstance fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final assetId = json['assetId'];
    final inUs = json['sourceInUs'];
    final outUs = json['sourceOutUs'];
    final ratio = json['ratio'];
    final audioEnabled = json['audioEnabled'];
    if (id is! String || id.isEmpty) {
      throw const ReelProjectError('Clip is missing its id');
    }
    if (assetId is! String || assetId.isEmpty) {
      throw ReelProjectError('Clip $id is missing its assetId');
    }
    if (inUs is! int || outUs is! int) {
      throw ReelProjectError('Clip $id has a non-integer source interval');
    }
    if (ratio is! num) {
      throw ReelProjectError('Clip $id has a non-numeric ratio');
    }
    if (audioEnabled is! bool) {
      throw ReelProjectError('Clip $id is missing its audioEnabled flag');
    }
    return ReelClipInstance(
      id: id,
      assetId: assetId,
      sourceIn: Duration(microseconds: inUs),
      sourceOut: Duration(microseconds: outUs),
      ratio: ratio.toDouble(),
      audioEnabled: audioEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReelClipInstance &&
      other.id == id &&
      other.assetId == assetId &&
      other.sourceIn == sourceIn &&
      other.sourceOut == sourceOut &&
      other.ratio == ratio &&
      other.audioEnabled == audioEnabled;

  @override
  int get hashCode =>
      Object.hash(id, assetId, sourceIn, sourceOut, ratio, audioEnabled);
}

/// The output shape of the whole reel.
///
/// The first accepted visual item initializes the canvas; from then on the
/// canvas is project state. It does not follow whichever clip happens to be
/// first, so removing, reordering, or replacing that clip leaves the output
/// shape alone. [originClipId] records provenance only, and is kept even after
/// that clip is gone.
@immutable
class ReelCanvas {
  const ReelCanvas({required this.ratio, required this.originClipId});

  /// Width / height of the output.
  final double ratio;

  /// The clip instance that initialized the canvas, for provenance.
  final String originClipId;

  Map<String, Object?> toJson() => {
    'ratio': ratio,
    'originClipId': originClipId,
  };

  static ReelCanvas fromJson(Map<String, Object?> json) {
    final ratio = json['ratio'];
    final originClipId = json['originClipId'];
    if (ratio is! num) {
      throw const ReelProjectError('Canvas has a non-numeric ratio');
    }
    if (originClipId is! String || originClipId.isEmpty) {
      throw const ReelProjectError('Canvas is missing its originClipId');
    }
    return ReelCanvas(ratio: ratio.toDouble(), originClipId: originClipId);
  }

  @override
  bool operator ==(Object other) =>
      other is ReelCanvas &&
      other.ratio == ratio &&
      other.originClipId == originClipId;

  @override
  int get hashCode => Object.hash(ratio, originClipId);
}

/// An immutable, validated reel document.
///
/// Every edit produces a new [ReelProject] with a higher [revision], which is
/// what makes undo a matter of keeping earlier values rather than reversing
/// mutations. The asset table is deliberately not pruned when a clip leaves the
/// sequence: the file must survive until nothing the project can return to
/// needs it.
@immutable
class ReelProject {
  ReelProject({
    required this.id,
    required this.revision,
    required this.canvas,
    required Map<String, MediaAsset> assets,
    required List<ReelClipInstance> sequence,
    this.schemaVersion = currentSchemaVersion,
  }) : assets = Map.unmodifiable(assets),
       sequence = List.unmodifiable(sequence) {
    _validate();
  }

  /// Bumped whenever the serialized shape changes in a way that needs a
  /// migration. A project written by a newer schema is rejected, not guessed at.
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String id;

  /// Increases by one per committed edit. Identifies the exact document an
  /// export or a draft was made from.
  final int revision;

  /// Null only before the first clip is accepted.
  final ReelCanvas? canvas;

  /// Every asset the project knows about, including ones no longer in the
  /// sequence but still reachable through undo.
  final Map<String, MediaAsset> assets;

  /// The primary sequence, in playback order.
  final List<ReelClipInstance> sequence;

  static ReelProject empty({required String id}) => ReelProject(
    id: id,
    revision: 0,
    canvas: null,
    assets: const {},
    sequence: const [],
  );

  bool get isEmpty => sequence.isEmpty;

  /// Total output length at 1x.
  Duration get totalDuration => sequence.fold(
    Duration.zero,
    (sum, clip) => sum + clip.outputDuration,
  );

  /// Assets the current sequence needs. Assets held only by history are not
  /// included; the controller unions across revisions to decide what is safe to
  /// delete.
  Set<String> get referencedAssetIds => {
    for (final clip in sequence) clip.assetId,
  };

  ReelClipInstance? clipById(String clipId) {
    for (final clip in sequence) {
      if (clip.id == clipId) return clip;
    }
    return null;
  }

  int indexOfClip(String clipId) =>
      sequence.indexWhere((clip) => clip.id == clipId);

  MediaAsset assetForClip(ReelClipInstance clip) {
    final asset = assets[clip.assetId];
    if (asset == null) {
      throw ReelProjectError('Clip ${clip.id} references a missing asset');
    }
    return asset;
  }

  ReelProject copyWith({
    int? revision,
    ReelCanvas? canvas,
    Map<String, MediaAsset>? assets,
    List<ReelClipInstance>? sequence,
  }) => ReelProject(
    id: id,
    schemaVersion: schemaVersion,
    revision: revision ?? this.revision,
    canvas: canvas ?? this.canvas,
    assets: assets ?? this.assets,
    sequence: sequence ?? this.sequence,
  );

  void _validate() {
    if (revision < 0) {
      throw const ReelProjectError('Project revision cannot be negative');
    }
    if (id.isEmpty) {
      throw const ReelProjectError('Project is missing its id');
    }
    final seenClipIds = <String>{};
    for (final clip in sequence) {
      if (!seenClipIds.add(clip.id)) {
        throw ReelProjectError('Duplicate clip instance ${clip.id}');
      }
      if (!clip.ratio.isFinite || clip.ratio <= 0) {
        throw ReelProjectError('Clip ${clip.id} has an invalid ratio');
      }
      if (clip.sourceIn.isNegative) {
        throw ReelProjectError('Clip ${clip.id} starts before its source');
      }
      if (clip.sourceOut <= clip.sourceIn) {
        throw ReelProjectError(
          'Clip ${clip.id} has an empty source interval; '
          '[in, out) must contain at least one microsecond',
        );
      }
      final asset = assets[clip.assetId];
      if (asset == null) {
        throw ReelProjectError('Clip ${clip.id} references a missing asset');
      }
      if (clip.sourceOut > asset.duration) {
        throw ReelProjectError(
          'Clip ${clip.id} ends past the end of asset ${asset.id}',
        );
      }
    }
    final canvas = this.canvas;
    if (canvas != null && (!canvas.ratio.isFinite || canvas.ratio <= 0)) {
      throw const ReelProjectError('Canvas has an invalid ratio');
    }
    if (canvas == null && sequence.isNotEmpty) {
      throw const ReelProjectError(
        'A project with clips must have an initialized canvas',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'revision': revision,
    'canvas': canvas?.toJson(),
    'assets': [for (final asset in assets.values) asset.toJson()],
    'sequence': [for (final clip in sequence) clip.toJson()],
  };

  /// Reads a serialized project. A newer schema is rejected rather than
  /// partially understood; there is no persistence in this feature, but the
  /// version gate exists from the first revision so drafts can migrate later.
  static ReelProject fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw const ReelProjectError('Project is missing its schemaVersion');
    }
    if (schemaVersion > currentSchemaVersion) {
      throw ReelProjectError(
        'Project schema $schemaVersion is newer than supported '
        '$currentSchemaVersion',
      );
    }
    final id = json['id'];
    final revision = json['revision'];
    if (id is! String || id.isEmpty) {
      throw const ReelProjectError('Project is missing its id');
    }
    if (revision is! int) {
      throw const ReelProjectError('Project has a non-integer revision');
    }
    final rawAssets = json['assets'];
    final rawSequence = json['sequence'];
    if (rawAssets is! List || rawSequence is! List) {
      throw const ReelProjectError('Project assets or sequence is malformed');
    }
    final assets = <String, MediaAsset>{};
    for (final entry in rawAssets) {
      if (entry is! Map) {
        throw const ReelProjectError('Project asset entry is malformed');
      }
      final asset = MediaAsset.fromJson(entry.cast<String, Object?>());
      assets[asset.id] = asset;
    }
    final sequence = <ReelClipInstance>[
      for (final entry in rawSequence)
        if (entry is Map)
          ReelClipInstance.fromJson(entry.cast<String, Object?>())
        else
          throw const ReelProjectError('Project clip entry is malformed'),
    ];
    final rawCanvas = json['canvas'];
    return ReelProject(
      id: id,
      schemaVersion: schemaVersion,
      revision: revision,
      canvas: rawCanvas is Map
          ? ReelCanvas.fromJson(rawCanvas.cast<String, Object?>())
          : null,
      assets: assets,
      sequence: sequence,
    );
  }
}
