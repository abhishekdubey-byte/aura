import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'layout_draft.dart';

/// Originals live outside camera cache. Writes are serialized and atomic.
class LayoutStore {
  LayoutStore(this.directory);
  final Directory directory;
  Future<void> _tail = Future.value();
  static Future<LayoutStore> open() async => LayoutStore(
    Directory('${(await getApplicationSupportDirectory()).path}/layout_draft'),
  );
  File get _manifest => File('${directory.path}/draft.json');

  Future<LayoutDraft?> load() async {
    if (!await _manifest.exists()) return null;
    final draft = LayoutDraft.fromJson(
      jsonDecode(await _manifest.readAsString()),
    );
    for (int i = 0; i < draft.media.length; i++) {
      final m = draft.media[i];
      if (m != null && !await File(m.path).exists()) draft.clear(i);
    }
    return draft;
  }

  Future<void> save(LayoutDraft draft) {
    final json = jsonEncode(draft.toJson()); // Snapshot before another UI edit.
    final next = _tail.then((_) async {
      await directory.create(recursive: true);
      final pending = File('${directory.path}/draft.pending');
      await pending.writeAsString(json, flush: true);
      await pending.rename(_manifest.path);
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<String> retain(String source) async {
    await directory.create(recursive: true);
    final suffix = source.split('/').last.split('.').last.toLowerCase();
    final ext = RegExp(r'^[a-z0-9]{1,6}$').hasMatch(suffix) ? suffix : 'media';
    return (await File(source).copy(
      '${directory.path}/cell_${DateTime.now().microsecondsSinceEpoch}.$ext',
    )).path;
  }

  Future<void> discard() async {
    await _tail;
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// Called only after the new manifest is durable. Retakes and clears should
  /// not accumulate full camera originals for the lifetime of a saved draft.
  Future<void> prune(LayoutDraft draft) async {
    await _tail;
    if (!await directory.exists()) return;
    final retained = <String>{
      for (final media in draft.media.whereType<LayoutMedia>()) ...[
        media.path,
        if (media.thumbnail != null) media.thumbnail!,
      ],
    };
    await for (final entry in directory.list()) {
      if (entry is File &&
          entry.uri.pathSegments.last.startsWith('cell_') &&
          !retained.contains(entry.path)) {
        try {
          await entry.delete();
        } on FileSystemException {
          /* Retry on the next edit. */
        }
      }
    }
  }
}
