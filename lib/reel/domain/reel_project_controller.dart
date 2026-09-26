import 'package:flutter/foundation.dart';

import 'reel_commands.dart';
import 'reel_ids.dart';
import 'reel_project.dart';

/// Owns the current reel document, its edit history, and asset retention.
///
/// The controller outlives individual capture and editor routes: a project is
/// logical state, and losing a screen must not lose accepted edits. It holds no
/// decoded media — history is a list of metadata snapshots, never frames.
class ReelProjectController extends ChangeNotifier {
  ReelProjectController({
    ReelIds? ids,
    String? projectId,
    this.historyLimit = 50,
  }) : _ids = ids ?? ReelIds() {
    assert(historyLimit > 0);
    _project = ReelProject.empty(id: projectId ?? _ids.nextProject());
  }

  /// Maximum number of undo steps kept. Bounding history bounds memory; the
  /// real budget belongs to the performance feature, and this is a safe
  /// starting value, not a measured one.
  final int historyLimit;

  final ReelIds _ids;
  late ReelProject _project;
  final List<ReelProject> _past = [];
  final List<ReelProject> _future = [];
  bool _disposed = false;

  ReelProject get project => _project;

  bool get canUndo => _past.isNotEmpty;

  bool get canRedo => _future.isNotEmpty;

  /// Label of the edit `undo()` would reverse, for a future editor's UI.
  int get undoDepth => _past.length;

  int get redoDepth => _future.length;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  /// Applies [command] as one history step.
  ///
  /// The command is applied to a copy first, so a rejected edit leaves the
  /// current project and the history untouched. A new edit after an undo clears
  /// the redo stack: the abandoned branch is not reachable again.
  void run(ReelCommand command) {
    final previous = _project;
    final next = command.apply(previous);
    _project = next;
    _past.add(previous);
    if (_past.length > historyLimit) _past.removeAt(0);
    _future.clear();
    _emit();
  }

  /// Steps back one edit. Returns false when there is nothing to undo.
  bool undo() {
    if (_past.isEmpty) return false;
    _future.add(_project);
    _project = _past.removeLast();
    _emit();
    return true;
  }

  /// Steps forward one undone edit. Returns false when there is nothing to redo.
  bool redo() {
    if (_future.isEmpty) return false;
    _past.add(_project);
    if (_past.length > historyLimit) _past.removeAt(0);
    _project = _future.removeLast();
    _emit();
    return true;
  }

  /// Every revision the project can currently return to, oldest first.
  Iterable<ReelProject> get reachableRevisions => [
    ..._past,
    _project,
    ..._future.reversed,
  ];

  /// Assets some reachable revision still needs. An asset here must not be
  /// deleted, even when the current sequence no longer uses it, because undo or
  /// redo can bring its clip back.
  Set<String> get retainedAssetIds => {
    for (final revision in reachableRevisions) ...revision.referencedAssetIds,
  };

  /// Assets the project knows about that no reachable revision needs any more,
  /// typically because the history step that used them fell off the end of the
  /// bounded undo stack.
  ///
  /// This reports what is safe to clean up. It does not delete anything: file
  /// cleanup, its ownership rules, and the discard flow belong to the durable
  /// drafts feature.
  Set<String> get releasableAssetIds =>
      _project.assets.keys.toSet().difference(retainedAssetIds);

  /// Appends a finalized capture as a new clip over its whole source.
  ///
  /// Returns the created instance so a caller can refer to the slot later.
  /// Duration comes from the media itself; a non-positive duration is rejected
  /// rather than stored as an empty clip.
  ReelClipInstance appendCapturedClip({
    required String path,
    required Duration duration,
    required bool mirrored,
    required double ratio,
    Duration? usedDuration,
    bool audioEnabled = true,
  }) {
    if (duration <= Duration.zero) {
      throw const ReelProjectError(
        'A captured clip must have a positive duration',
      );
    }
    final used = usedDuration ?? duration;
    if (used <= Duration.zero || used > duration) {
      throw const ReelProjectError(
        'A captured clip must use a positive interval inside its source',
      );
    }
    final asset = MediaAsset(
      id: _ids.nextAsset(),
      path: path,
      duration: duration,
      mirrored: mirrored,
    );
    final clip = ReelClipInstance(
      id: _ids.nextClip(),
      assetId: asset.id,
      sourceIn: Duration.zero,
      sourceOut: used,
      ratio: ratio,
      audioEnabled: audioEnabled,
    );
    run(AppendClipCommand(asset: asset, clip: clip));
    return clip;
  }

  /// Removes the last clip, which is what capture's own "remove last" action
  /// does. Returns false on an empty sequence.
  bool removeLastClip() {
    if (_project.sequence.isEmpty) return false;
    run(RemoveClipCommand(_project.sequence.last.id));
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _past.clear();
    _future.clear();
    super.dispose();
  }
}
