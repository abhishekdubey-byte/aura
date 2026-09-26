import 'dart:math';

/// Mints the opaque identifiers project objects keep for life.
///
/// An ID is assigned once and never changes, so undo history, a future draft on
/// disk, and an export job can all name the same asset or the same timeline slot
/// across revisions. Nothing derives meaning from an ID's text, and nothing
/// identifies a clip by its position in the sequence.
///
/// Pass a seeded [Random] in tests to get reproducible IDs.
class ReelIds {
  ReelIds({Random? random}) : _random = random ?? Random();

  final Random _random;
  int _counter = 0;

  static const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  /// A new ID carrying [prefix] for readability in logs and test failures.
  String next(String prefix) {
    final sequence = (_counter++).toRadixString(36).padLeft(3, '0');
    final suffix = String.fromCharCodes([
      for (int i = 0; i < 8; i++)
        _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
    ]);
    return '$prefix-$sequence-$suffix';
  }

  String nextAsset() => next('asset');

  String nextClip() => next('clip');

  String nextProject() => next('project');
}
