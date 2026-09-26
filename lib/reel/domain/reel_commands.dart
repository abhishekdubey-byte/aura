import 'package:flutter/foundation.dart';

import 'reel_project.dart';

/// One atomic, undoable edit.
///
/// A command either produces a complete valid project or throws
/// [ReelProjectError] and leaves the caller's project untouched. There is no
/// partially applied edit, which is what lets history keep plain snapshots.
@immutable
abstract class ReelCommand {
  const ReelCommand();

  /// Short human-readable label, used in tests and diagnostics.
  String get description;

  /// Returns the edited project. Implementations must not mutate [project].
  ReelProject apply(ReelProject project);

  /// Produces the next project with its revision advanced.
  @protected
  ReelProject advance(
    ReelProject project, {
    ReelCanvas? canvas,
    Map<String, MediaAsset>? assets,
    List<ReelClipInstance>? sequence,
  }) => ReelProject(
    id: project.id,
    schemaVersion: project.schemaVersion,
    revision: project.revision + 1,
    canvas: canvas ?? project.canvas,
    assets: assets ?? project.assets,
    sequence: sequence ?? project.sequence,
  );
}

/// Appends a newly accepted clip to the end of the primary sequence.
///
/// This is the command capture uses when a recording finalizes. If the project
/// has no canvas yet, this clip initializes it — the only way a canvas is ever
/// set in this feature, so the output shape is decided once by the first
/// accepted item and then belongs to the project.
class AppendClipCommand extends ReelCommand {
  const AppendClipCommand({required this.asset, required this.clip});

  final MediaAsset asset;
  final ReelClipInstance clip;

  @override
  String get description => 'Add clip';

  @override
  ReelProject apply(ReelProject project) {
    if (clip.assetId != asset.id) {
      throw ReelProjectError(
        'Clip ${clip.id} references ${clip.assetId}, not the supplied '
        'asset ${asset.id}',
      );
    }
    if (project.clipById(clip.id) != null) {
      throw ReelProjectError('Clip ${clip.id} is already in the sequence');
    }
    final existing = project.assets[asset.id];
    if (existing != null && existing != asset) {
      throw ReelProjectError(
        'Asset ${asset.id} is already known with different metadata',
      );
    }
    return advance(
      project,
      canvas:
          project.canvas ??
          ReelCanvas(ratio: clip.ratio, originClipId: clip.id),
      assets: {...project.assets, asset.id: asset},
      sequence: [...project.sequence, clip],
    );
  }
}

/// Removes one clip instance from the primary sequence.
///
/// The asset stays in the project's asset table. Removal from the reel is not
/// permission to delete the file: undo must be able to bring the clip back, and
/// a later draft or export may still own it.
///
/// The canvas is not recomputed. Removing the clip that happened to initialize
/// the canvas leaves the output shape alone.
///
/// This feature drives the command from capture's existing "remove the last
/// clip" action only. Exposing arbitrary removal in the editor, with its own
/// ripple and asset-retention interface, belongs to the clip-removal feature.
class RemoveClipCommand extends ReelCommand {
  const RemoveClipCommand(this.clipId);

  final String clipId;

  @override
  String get description => 'Remove clip';

  @override
  ReelProject apply(ReelProject project) {
    final index = project.indexOfClip(clipId);
    if (index < 0) {
      throw ReelProjectError('Clip $clipId is not in the sequence');
    }
    return advance(
      project,
      sequence: [...project.sequence]..removeAt(index),
    );
  }
}
