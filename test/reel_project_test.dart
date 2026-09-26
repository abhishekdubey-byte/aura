import 'dart:convert';
import 'dart:math';

import 'package:aura/reel/domain/reel_commands.dart';
import 'package:aura/reel/domain/reel_ids.dart';
import 'package:aura/reel/domain/reel_project.dart';
import 'package:aura/reel/domain/reel_project_controller.dart';
import 'package:aura/reel/reel_session.dart';
import 'package:flutter_test/flutter_test.dart';

MediaAsset asset(
  String id, {
  Duration duration = const Duration(seconds: 5),
  bool mirrored = false,
  String? path,
}) => MediaAsset(
  id: id,
  path: path ?? '/tmp/$id.mp4',
  duration: duration,
  mirrored: mirrored,
);

ReelClipInstance clip(
  String id,
  String assetId, {
  Duration sourceIn = Duration.zero,
  Duration sourceOut = const Duration(seconds: 2),
  double ratio = 9 / 16,
  bool audioEnabled = true,
}) => ReelClipInstance(
  id: id,
  assetId: assetId,
  sourceIn: sourceIn,
  sourceOut: sourceOut,
  ratio: ratio,
  audioEnabled: audioEnabled,
);

ReelProject projectWith({
  required List<MediaAsset> assets,
  required List<ReelClipInstance> sequence,
  ReelCanvas? canvas,
  int revision = 1,
}) => ReelProject(
  id: 'project-test',
  revision: revision,
  canvas:
      canvas ??
      (sequence.isEmpty
          ? null
          : ReelCanvas(
              ratio: sequence.first.ratio,
              originClipId: sequence.first.id,
            )),
  assets: {for (final a in assets) a.id: a},
  sequence: sequence,
);

ReelProjectController controller({int historyLimit = 50}) =>
    ReelProjectController(
      ids: ReelIds(random: Random(7)),
      projectId: 'project-test',
      historyLimit: historyLimit,
    );

ReelClipInstance append(
  ReelProjectController c, {
  double ratio = 9 / 16,
  double seconds = 2,
  bool mirrored = false,
}) => c.appendCapturedClip(
  path: '/tmp/take-${c.project.sequence.length}.mp4',
  duration: Duration(milliseconds: (seconds * 1000).round()),
  mirrored: mirrored,
  ratio: ratio,
);

void main() {
  group('identifiers and instances', () {
    test('ids are unique, prefixed and independent of sequence position', () {
      final ids = ReelIds(random: Random(1));
      final minted = {for (int i = 0; i < 500; i++) ids.nextClip()};
      expect(minted.length, 500);
      expect(minted.every((id) => id.startsWith('clip-')), isTrue);
    });

    test('two instances share one asset with different source windows', () {
      final project = projectWith(
        assets: [asset('a', duration: const Duration(seconds: 10))],
        sequence: [
          clip('c1', 'a', sourceOut: const Duration(seconds: 3)),
          clip(
            'c2',
            'a',
            sourceIn: const Duration(seconds: 3),
            sourceOut: const Duration(seconds: 7),
          ),
        ],
      );
      expect(project.referencedAssetIds, {'a'});
      expect(project.assets.length, 1);
      expect(project.totalDuration, const Duration(seconds: 7));
      expect(project.clipById('c2')!.outputDuration, const Duration(seconds: 4));
    });

    test('an empty project has no canvas and no duration', () {
      final project = ReelProject.empty(id: 'p');
      expect(project.isEmpty, isTrue);
      expect(project.canvas, isNull);
      expect(project.totalDuration, Duration.zero);
      expect(project.revision, 0);
    });
  });

  group('validation', () {
    test('a zero-length source interval is rejected, not treated as a freeze', () {
      expect(
        () => projectWith(
          assets: [asset('a')],
          sequence: [
            clip(
              'c1',
              'a',
              sourceIn: const Duration(seconds: 1),
              sourceOut: const Duration(seconds: 1),
            ),
          ],
        ),
        throwsA(isA<ReelProjectError>()),
      );
    });

    test('an interval reaching past the source is rejected', () {
      expect(
        () => projectWith(
          assets: [asset('a', duration: const Duration(seconds: 2))],
          sequence: [clip('c1', 'a', sourceOut: const Duration(seconds: 3))],
        ),
        throwsA(isA<ReelProjectError>()),
      );
    });

    test('a negative source start is rejected', () {
      expect(
        () => projectWith(
          assets: [asset('a')],
          sequence: [
            clip('c1', 'a', sourceIn: const Duration(seconds: -1)),
          ],
        ),
        throwsA(isA<ReelProjectError>()),
      );
    });

    test('a clip cannot reference a missing asset', () {
      expect(
        () => projectWith(assets: [], sequence: [clip('c1', 'ghost')]),
        throwsA(isA<ReelProjectError>()),
      );
    });

    test('duplicate clip instance ids are rejected', () {
      expect(
        () => projectWith(
          assets: [asset('a')],
          sequence: [clip('c1', 'a'), clip('c1', 'a')],
        ),
        throwsA(isA<ReelProjectError>()),
      );
    });

    test('a non-finite or non-positive ratio is rejected', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => projectWith(
            assets: [asset('a')],
            sequence: [clip('c1', 'a', ratio: bad)],
          ),
          throwsA(isA<ReelProjectError>()),
          reason: 'ratio $bad must be rejected',
        );
      }
    });

    test('clips without a canvas are rejected', () {
      expect(
        () => ReelProject(
          id: 'p',
          revision: 1,
          canvas: null,
          assets: {'a': asset('a')},
          sequence: [clip('c1', 'a')],
        ),
        throwsA(isA<ReelProjectError>()),
      );
    });
  });

  group('canvas ownership', () {
    test('the first accepted clip initializes the canvas', () {
      final c = controller();
      expect(c.project.canvas, isNull);
      final first = append(c, ratio: 1.0);
      expect(c.project.canvas!.ratio, 1.0);
      expect(c.project.canvas!.originClipId, first.id);
    });

    test('a later clip with another ratio does not change the canvas', () {
      final c = controller();
      append(c, ratio: 1.0);
      append(c, ratio: 16 / 9);
      expect(c.project.canvas!.ratio, 1.0);
      expect(c.project.sequence.last.ratio, 16 / 9);
    });

    test('removing the clip that set the canvas leaves the canvas alone', () {
      final c = controller();
      final first = append(c, ratio: 1.0);
      append(c, ratio: 16 / 9);
      c.run(RemoveClipCommand(first.id));
      expect(c.project.sequence.map((clip) => clip.id), isNot(contains(first.id)));
      expect(c.project.canvas!.ratio, 1.0);
      expect(c.project.canvas!.originClipId, first.id);
    });

    test('emptying the sequence keeps the established canvas', () {
      final c = controller();
      append(c, ratio: 4 / 5);
      c.removeLastClip();
      expect(c.project.isEmpty, isTrue);
      expect(c.project.canvas!.ratio, 4 / 5);
    });
  });

  group('commands and revisions', () {
    test('each committed command advances the revision by one', () {
      final c = controller();
      expect(c.project.revision, 0);
      append(c);
      expect(c.project.revision, 1);
      append(c);
      expect(c.project.revision, 2);
      c.removeLastClip();
      expect(c.project.revision, 3);
    });

    test('a rejected command leaves the project and history untouched', () {
      final c = controller();
      final first = append(c);
      final before = c.project;
      final depth = c.undoDepth;
      expect(
        () => c.run(RemoveClipCommand('not-a-clip')),
        throwsA(isA<ReelProjectError>()),
      );
      expect(c.project, same(before));
      expect(c.undoDepth, depth);
      expect(c.project.clipById(first.id), isNotNull);
    });

    test('appending a clip whose asset disagrees is rejected', () {
      final c = controller();
      expect(
        () => c.run(
          AppendClipCommand(asset: asset('a'), clip: clip('c1', 'other')),
        ),
        throwsA(isA<ReelProjectError>()),
      );
      expect(c.project.isEmpty, isTrue);
    });

    test('removing an absent clip is rejected', () {
      final c = controller();
      append(c);
      expect(
        () => c.run(RemoveClipCommand('ghost')),
        throwsA(isA<ReelProjectError>()),
      );
    });
  });

  group('undo and redo', () {
    test('undo restores the exact previous document', () {
      final c = controller();
      append(c, ratio: 1.0);
      final afterFirst = c.project;
      append(c, ratio: 16 / 9);
      expect(c.project.sequence.length, 2);

      expect(c.undo(), isTrue);
      expect(c.project.revision, afterFirst.revision);
      expect(c.project.sequence.map((clip) => clip.id),
          afterFirst.sequence.map((clip) => clip.id));
      expect(c.project.canvas, afterFirst.canvas);
      expect(c.project.sequence.length, 1);
    });

    test('redo reapplies the undone edit', () {
      final c = controller();
      append(c);
      final second = append(c);
      c.undo();
      expect(c.canRedo, isTrue);
      expect(c.redo(), isTrue);
      expect(c.project.sequence.last.id, second.id);
      expect(c.canRedo, isFalse);
    });

    test('a new edit after undo clears redo', () {
      final c = controller();
      append(c);
      append(c);
      c.undo();
      expect(c.canRedo, isTrue);
      append(c);
      expect(c.canRedo, isFalse);
      expect(c.redoDepth, 0);
    });

    test('undo and redo report false at the ends of history', () {
      final c = controller();
      expect(c.undo(), isFalse);
      expect(c.redo(), isFalse);
      append(c);
      expect(c.redo(), isFalse);
      expect(c.undo(), isTrue);
      expect(c.undo(), isFalse);
    });

    test('undo notifies listeners', () {
      final c = controller();
      int notifications = 0;
      c.addListener(() => notifications++);
      append(c);
      expect(notifications, 1);
      c.undo();
      expect(notifications, 2);
      c.redo();
      expect(notifications, 3);
    });

    test('history depth is bounded and keeps the newest steps', () {
      final c = controller(historyLimit: 2);
      append(c);
      append(c);
      append(c);
      append(c);
      expect(c.undoDepth, 2);
      expect(c.undo(), isTrue);
      expect(c.undo(), isTrue);
      expect(c.undo(), isFalse);
      expect(c.project.sequence.length, 2);
    });
  });

  group('asset ownership', () {
    test('a removed clip keeps its asset while undo can restore it', () {
      final c = controller();
      final first = append(c);
      final assetId = c.project.clipById(first.id)!.assetId;
      c.run(RemoveClipCommand(first.id));

      expect(c.project.referencedAssetIds, isNot(contains(assetId)));
      expect(c.retainedAssetIds, contains(assetId));
      expect(c.releasableAssetIds, isEmpty);
      expect(c.project.assets, contains(assetId));
    });

    test('an asset held only by redo is still retained', () {
      final c = controller();
      final only = append(c);
      final assetId = c.project.clipById(only.id)!.assetId;
      c.undo();
      expect(c.project.isEmpty, isTrue);
      expect(c.canRedo, isTrue);
      expect(c.retainedAssetIds, contains(assetId));
      expect(c.releasableAssetIds, isEmpty);
    });

    test('an asset becomes releasable once history can no longer reach it', () {
      final c = controller(historyLimit: 1);
      final first = append(c);
      final assetId = c.project.clipById(first.id)!.assetId;
      c.run(RemoveClipCommand(first.id));
      append(c);
      append(c);

      expect(c.retainedAssetIds, isNot(contains(assetId)));
      expect(c.releasableAssetIds, contains(assetId));
      expect(
        c.project.assets,
        contains(assetId),
        reason: 'reporting an asset as releasable must not delete it',
      );
    });

    test('shared assets stay retained while any instance remains', () {
      final shared = asset('a', duration: const Duration(seconds: 10));
      var project = projectWith(
        assets: [shared],
        sequence: [
          clip('c1', 'a', sourceOut: const Duration(seconds: 3)),
          clip(
            'c2',
            'a',
            sourceIn: const Duration(seconds: 3),
            sourceOut: const Duration(seconds: 6),
          ),
        ],
      );
      project = const RemoveClipCommand('c1').apply(project);
      expect(project.referencedAssetIds, contains('a'));
    });
  });

  group('serialization', () {
    test('a project round-trips through json unchanged', () {
      final c = controller();
      append(c, ratio: 1.0, seconds: 3, mirrored: true);
      append(c, ratio: 16 / 9, seconds: 1.5);
      c.removeLastClip();
      append(c, ratio: 4 / 5, seconds: 2);
      final original = c.project;

      final restored = ReelProject.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );

      expect(restored.id, original.id);
      expect(restored.revision, original.revision);
      expect(restored.schemaVersion, ReelProject.currentSchemaVersion);
      expect(restored.canvas, original.canvas);
      expect(restored.totalDuration, original.totalDuration);
      expect(restored.sequence, original.sequence);
      expect(restored.assets, original.assets);
    });

    test('a newer schema version is rejected rather than guessed at', () {
      final json = ReelProject.empty(id: 'p').toJson();
      json['schemaVersion'] = ReelProject.currentSchemaVersion + 1;
      expect(
        () => ReelProject.fromJson(json),
        throwsA(isA<ReelProjectError>()),
      );
    });

    test('malformed documents are rejected field by field', () {
      final base = ReelProject.empty(id: 'p').toJson();
      for (final key in ['schemaVersion', 'id', 'revision']) {
        final json = Map<String, Object?>.of(base)..remove(key);
        expect(
          () => ReelProject.fromJson(json),
          throwsA(isA<ReelProjectError>()),
          reason: 'missing $key must be rejected',
        );
      }
      expect(
        () => ReelProject.fromJson({...base, 'assets': 'not-a-list'}),
        throwsA(isA<ReelProjectError>()),
      );
      expect(
        () => ReelProject.fromJson({
          ...base,
          'sequence': [
            {'id': 'c1'},
          ],
        }),
        throwsA(isA<ReelProjectError>()),
      );
    });

    test('a serialized document that violates an invariant is rejected', () {
      final c = controller();
      append(c);
      final json = c.project.toJson();
      json['sequence'] = [
        {
          'id': 'c1',
          'assetId': 'missing-asset',
          'sourceInUs': 0,
          'sourceOutUs': 1000,
          'ratio': 1.0,
          'audioEnabled': true,
        },
      ];
      expect(
        () => ReelProject.fromJson(json),
        throwsA(isA<ReelProjectError>()),
      );
    });
  });

  group('captured clips', () {
    test('the asset keeps its full length while the clip uses the limit', () {
      final c = controller();
      c.appendCapturedClip(
        path: '/tmp/take.mp4',
        duration: const Duration(seconds: 9),
        usedDuration: const Duration(seconds: 5),
        mirrored: false,
        ratio: 1,
      );
      final clip = c.project.sequence.single;
      expect(clip.outputDuration, const Duration(seconds: 5));
      expect(c.project.assetForClip(clip).duration, const Duration(seconds: 9));
    });

    test('a non-positive or out-of-source capture is rejected', () {
      final c = controller();
      expect(
        () => c.appendCapturedClip(
          path: '/tmp/a.mp4',
          duration: Duration.zero,
          mirrored: false,
          ratio: 1,
        ),
        throwsA(isA<ReelProjectError>()),
      );
      expect(
        () => c.appendCapturedClip(
          path: '/tmp/a.mp4',
          duration: const Duration(seconds: 2),
          usedDuration: const Duration(seconds: 3),
          mirrored: false,
          ratio: 1,
        ),
        throwsA(isA<ReelProjectError>()),
      );
      expect(c.project.isEmpty, isTrue);
      expect(c.project.revision, 0);
    });

    test('mirroring is a source fact carried by the asset', () {
      final c = controller();
      append(c, mirrored: true);
      final clip = c.project.sequence.single;
      expect(c.project.assetForClip(clip).mirrored, isTrue);
    });
  });

  group('randomized edit sequences', () {
    test('project stays valid and history returns to the starting document', () {
      for (int seed = 0; seed < 25; seed++) {
        final random = Random(seed);
        final c = controller(historyLimit: 100);
        final start = c.project;
        int commands = 0;

        for (int step = 0; step < 40; step++) {
          switch (random.nextInt(4)) {
            case 0:
              append(c, ratio: [1.0, 9 / 16, 16 / 9][random.nextInt(3)]);
              commands++;
            case 1:
              if (c.removeLastClip()) commands++;
            case 2:
              c.undo();
            case 3:
              c.redo();
          }
          // Constructing a project validates it, so merely reading the current
          // document proves every intermediate state was well formed.
          final project = c.project;
          for (final clip in project.sequence) {
            expect(project.assets, contains(clip.assetId));
            expect(clip.outputDuration, greaterThan(Duration.zero));
          }
          if (project.sequence.isNotEmpty) {
            expect(project.canvas, isNotNull);
          }
        }

        if (commands > 0) {
          while (c.undo()) {}
          expect(c.project.revision, start.revision, reason: 'seed $seed');
          expect(c.project.isEmpty, isTrue, reason: 'seed $seed');
        }
      }
    });
  });

  group('capture session integration', () {
    ReelSession sessionWith({
      required List<({String path, double seconds})> takes,
      ReelProjectController? project,
    }) {
      int index = 0;
      return ReelSession(
        startCapture: () async {},
        finishCapture: () async => takes[index++],
        project: project,
      );
    }

    test('finalized takes become project clips and a derived view', () async {
      final session = sessionWith(
        takes: [(path: 'a.mp4', seconds: 2.0), (path: 'b.mp4', seconds: 1.5)],
      );
      addTearDown(session.dispose);

      await session.start(ratio: 1, mirror: false);
      await session.stop();
      await session.start(ratio: 16 / 9, mirror: true);
      await session.stop();

      expect(session.clips.map((clip) => clip.path), ['a.mp4', 'b.mp4']);
      expect(session.clips.first.ratio, 1);
      expect(session.clips.last.mirror, isTrue);
      expect(session.totalSeconds, closeTo(3.5, 1e-9));
      expect(session.project.project.sequence.length, 2);
      expect(session.project.project.canvas!.ratio, 1);
    });

    test('capture remove-last is a project edit that undo can restore', () async {
      final session = sessionWith(takes: [(path: 'a.mp4', seconds: 2.0)]);
      addTearDown(session.dispose);

      await session.start(ratio: 1, mirror: false);
      await session.stop();
      expect(session.clips, hasLength(1));

      session.undo();
      expect(session.clips, isEmpty);
      expect(session.project.canUndo, isTrue);

      session.project.undo();
      expect(session.clips, hasLength(1));
      expect(session.clips.single.path, 'a.mp4');
    });

    test('a supplied project outlives the session that filled it', () async {
      final shared = controller();
      final session = sessionWith(
        takes: [(path: 'a.mp4', seconds: 2.0)],
        project: shared,
      );
      await session.start(ratio: 1, mirror: false);
      await session.stop();
      session.dispose();

      expect(shared.project.sequence, hasLength(1));
      expect(shared.project.canvas!.ratio, 1);
      shared.dispose();
    });

    test('the hands-free limit bounds the clip, not the stored asset', () async {
      final session = sessionWith(takes: [(path: 'long.mp4', seconds: 9.0)]);
      addTearDown(session.dispose);

      await session.start(ratio: 1, mirror: false, seconds: 5);
      await session.stop();

      final clip = session.project.project.sequence.single;
      expect(clip.outputDuration, const Duration(seconds: 5));
      expect(
        session.project.project.assetForClip(clip).duration,
        const Duration(seconds: 9),
      );
      expect(session.clips.single.seconds, closeTo(5, 1e-9));
    });
  });
}
