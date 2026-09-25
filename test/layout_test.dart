import 'dart:io';

import 'package:aura/camera/capture_aspect.dart';
import 'package:aura/layout/layout_draft.dart';
import 'package:aura/layout/layout_exporter.dart';
import 'package:aura/layout/layout_store.dart';
import 'package:aura/layout/layout_template.dart';
import 'package:aura/layout/layout_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final sources = <String>[];
  final colors = [
    [240, 20, 20],
    [20, 230, 20],
    [20, 20, 240],
    [240, 230, 20],
    [230, 20, 230],
    [20, 230, 230],
    [150, 150, 150],
    [240, 120, 20],
    [120, 50, 230],
  ];
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('aura_layout_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    for (int i = 0; i < colors.length; i++) {
      final image = img.Image(width: 48, height: 64);
      img.fill(
        image,
        color: img.ColorRgb8(colors[i][0], colors[i][1], colors[i][2]),
      );
      final path = '${temp.path}/source_$i.jpg';
      await File(path).writeAsBytes(img.encodeJpg(image, quality: 100));
      sources.add(path);
    }
  });
  tearDownAll(() async => temp.delete(recursive: true));

  for (final template in LayoutTemplate.values) {
    for (final aspect in CaptureAspect.values) {
      for (final rotated in [false, true]) {
        for (final mode in LayoutMode.values) {
          test(
            '${template.name}/${aspect.id}/${rotated ? 'rotated' : 'original'}/${mode.name}',
            () async {
              final original = aspect.resolveRatio(const Size(1080, 2400));
              final ratio = rotated ? 1 / original : original;
              final d = LayoutDraft(
                template: template,
                aspectId: aspect.id,
                ratio: ratio,
                mode: mode,
              );
              for (int i = 0; i < d.media.length; i++) {
                final kind =
                    mode == LayoutMode.photos ||
                        mode == LayoutMode.hybrid && i.isEven
                    ? CellKind.photo
                    : CellKind.video;
                d.put(
                  i,
                  LayoutMedia(
                    path: sources[i],
                    kind: kind,
                    seconds: kind == CellKind.video ? i + 1.0 : 0,
                    hasAudio: kind == CellKind.video,
                  ),
                );
              }
              expect(d.complete, isTrue);
              final size = layoutOutputSize(ratio);
              expect(
                (size.width - size.height * ratio).abs(),
                lessThanOrEqualTo(2 * ratio + 2),
              );
              final cells = template.pixelRects(size);
              var area = 0.0;
              for (int i = 0; i < cells.length; i++) {
                final r = cells[i];
                expect(r.width, greaterThan(0));
                expect(r.height, greaterThan(0));
                for (final v in [r.left, r.top, r.width, r.height]) {
                  expect(v % 2, 0);
                }
                expect((Offset.zero & size).contains(r.center), isTrue);
                area += r.width * r.height;
                for (int j = i + 1; j < cells.length; j++) {
                  if (template.isDiamond) {
                    final intersection = Path.combine(
                      PathOperation.intersect,
                      template.cellPath(r),
                      template.cellPath(cells[j]),
                    );
                    expect(intersection.computeMetrics().isEmpty, isTrue);
                  } else {
                    expect(r.overlaps(cells[j]), isFalse);
                  }
                }
                final crop = layoutSourceCrop(
                  const Size(4000, 3000),
                  r.width / r.height,
                );
                expect(crop.center.dx, closeTo(2000, .000001));
                expect(crop.center.dy, closeTo(1500, .000001));
                expect(
                  crop.width / crop.height,
                  closeTo(r.width / r.height, .000001),
                );
                expect(crop.width, lessThanOrEqualTo(4000));
                expect(crop.height, lessThanOrEqualTo(3000));
              }
              expect(
                area * (template.isDiamond ? .5 : 1),
                template.isDiamond
                    ? lessThan(size.width * size.height)
                    : size.width * size.height,
              );
              expect(LayoutDraft.fromJson(d.toJson()).toJson(), d.toJson());
              if (d.isVideo) {
                final args = LayoutExporter.videoArguments(d, '/output.mp4');
                final graph = args[args.indexOf('-filter_complex') + 1];
                expect(
                  graph,
                  contains(
                    template.isDiamond
                        ? 'alphamerge[diamond7]'
                        : 'xstack=inputs=${cells.length}',
                  ),
                );
                expect(graph, contains('tpad=stop_mode=clone'));
                expect(
                  args[args.indexOf('-t') + 1],
                  d.duration.toStringAsFixed(6),
                );
                expect(args, contains('-an'));
              } else {
                final path = await LayoutExporter.render(d, longEdge: 192);
                final result = img.decodeJpg(await File(path).readAsBytes())!;
                final expectedSize = layoutOutputSize(ratio, longEdge: 192);
                expect(result.width, expectedSize.width);
                expect(result.height, expectedSize.height);
                final rects = template.pixelRects(expectedSize);
                for (int i = 0; i < rects.length; i++) {
                  final pixel = result.getPixel(
                    rects[i].center.dx.floor(),
                    rects[i].center.dy.floor(),
                  );
                  expect(pixel.r, closeTo(colors[i][0], 8));
                  expect(pixel.g, closeTo(colors[i][1], 8));
                  expect(pixel.b, closeTo(colors[i][2], 8));
                }
                if (template.isDiamond) {
                  // The corner of the top-left cell is cut away, while its
                  // center above is still the original source color.
                  final r = rects.first;
                  final cut = result.getPixel(
                    (r.left + r.width * .12).floor(),
                    (r.top + r.height * .12).floor(),
                  );
                  expect(cut.r, lessThan(25));
                  expect(cut.g, lessThan(25));
                  expect(cut.b, lessThan(25));
                  expect(result.getPixel(1, 1).luminance, lessThan(10));
                }
                await File(path).delete();
                const previews = String.fromEnvironment('LAYOUT_PREVIEW_DIR');
                if (previews.isNotEmpty &&
                    template.index >= LayoutTemplate.diamondEight.index &&
                    aspect == CaptureAspect.desktop16x10 &&
                    !rotated) {
                  await Directory(previews).create(recursive: true);
                  final large = await LayoutExporter.render(d, longEdge: 1280);
                  await File(large).copy('$previews/${template.name}.jpg');
                }
              }
            },
          );
        }
      }
    }
  }

  test('draft advances, retakes, clears and enforces mode', () {
    final d = LayoutDraft();
    d.put(0, const LayoutMedia(path: 'first.jpg', kind: CellKind.photo));
    expect(d.selected, 1);
    d.put(0, const LayoutMedia(path: 'retake.jpg', kind: CellKind.photo));
    expect(d.filled, 1);
    expect(d.media[0]!.path, 'retake.jpg');
    expect(
      () => d.put(1, const LayoutMedia(path: 'v.mp4', kind: CellKind.video)),
      throwsStateError,
    );
    d.clear(0);
    expect(d.filled, 0);
    expect(d.selected, 0);
  });

  test('audio maps just the selected cell, muted stays silent, filename is one argument', () {
    final d = LayoutDraft(
      template: LayoutTemplate.rows,
      mode: LayoutMode.hybrid,
    );
    d.put(
      0,
      const LayoutMedia(path: "/photo's image.jpg", kind: CellKind.photo),
    );
    d.put(
      1,
      const LayoutMedia(
        path: '/video clip.mp4',
        kind: CellKind.video,
        seconds: 2,
        hasAudio: true,
      ),
    );
    d.audioCell = 1;
    final args = LayoutExporter.videoArguments(d, '/output.mp4');
    expect(args, contains("/photo's image.jpg"));
    expect(args, contains('/video clip.mp4'));
    expect(args.join(' '), contains('[1:a:0]atrim'));
    expect(args, isNot(contains('-an')));
    d.clear(1);
    expect(d.audioCell, isNull);
  });

  test(
    'incomplete composition fails without producing a misleading file',
    () async {
      await expectLater(LayoutExporter.render(LayoutDraft()), throwsStateError);
    },
  );

  test('draft originals and latest state survive reopening, missing files become empty', () async {
    final store = LayoutStore(Directory('${temp.path}/draft'));
    final retained = await store.retain(sources[0]);
    final d = LayoutDraft()
      ..put(0, LayoutMedia(path: retained, kind: CellKind.photo));
    final firstSave = store.save(d);
    d.ratio = 1.5;
    await store.save(d);
    await firstSave;
    final reopened = await LayoutStore(store.directory).load();
    expect(reopened!.ratio, 1.5);
    expect(reopened.media[0]!.path, retained);
    await File(retained).delete();
    expect((await store.load())!.filled, 0);
    await store.discard();
    expect(await store.load(), isNull);
    expect(await File(sources[0]).exists(), isTrue);
  });

  test('invalid persisted geometry is rejected', () {
    final json = LayoutDraft().toJson();
    json['ratio'] = 0;
    expect(() => LayoutDraft.fromJson(json), throwsFormatException);
  });

  test('retake cleanup keeps the current original and removes only managed orphans', () async {
    final store = LayoutStore(Directory('${temp.path}/cleanup'));
    final old = await store.retain(sources[0]);
    final replacement = await store.retain(sources[1]);
    final unrelated = File('${store.directory.path}/notes.txt');
    await unrelated.writeAsString('keep');
    final draft = LayoutDraft()
      ..put(0, LayoutMedia(path: replacement, kind: CellKind.photo));
    await store.save(draft);
    await store.prune(draft);
    expect(await File(old).exists(), isFalse);
    expect(await File(replacement).exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
    expect((await store.load())!.media[0]!.path, replacement);
  });

  test('photo export mirrors pixels exactly once', () async {
    final src = img.Image(width: 80, height: 80);
    img.fill(src, color: img.ColorRgb8(240, 0, 0));
    img.fillRect(
      src,
      x1: 40,
      y1: 0,
      x2: 79,
      y2: 79,
      color: img.ColorRgb8(0, 0, 240),
    );
    final path = '${temp.path}/mirror.jpg';
    await File(path).writeAsBytes(img.encodeJpg(src));
    final d = LayoutDraft(template: LayoutTemplate.columns, ratio: 2);
    d.put(0, LayoutMedia(path: path, kind: CellKind.photo));
    d.put(1, LayoutMedia(path: path, kind: CellKind.photo, mirror: true));
    final out = img.decodeJpg(
      await File(await LayoutExporter.render(d, longEdge: 160)).readAsBytes(),
    )!;
    expect(out.getPixel(10, 40).r, greaterThan(200));
    expect(out.getPixel(90, 40).b, greaterThan(200));
  });

  testWidgets(
    'all grids fit portrait and landscape screens with selectable cells',
    (tester) async {
      for (final screen in [const Size(390, 844), const Size(844, 390)]) {
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        for (final t in LayoutTemplate.values) {
          for (final aspect in CaptureAspect.values) {
            int? selected;
            final d = LayoutDraft(
              template: t,
              ratio: aspect.resolveRatio(screen),
              mode: LayoutMode.hybrid,
            );
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: LayoutGrid(
                      draft: d,
                      livePreview: const ColoredBox(color: Colors.grey),
                      onSelect: (i) => selected = i,
                    ),
                  ),
                ),
              ),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${t.name}/${aspect.id}/$screen',
            );
            await tester.tap(
              find.byKey(ValueKey('layout-cell-${t.cells.length - 1}')),
            );
            expect(selected, t.cells.length - 1);
          }
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('diamond cutouts reject taps outside their visible shape', (
    tester,
  ) async {
    final draft = LayoutDraft(
      template: LayoutTemplate.diamondEight,
      ratio: 1.6,
    );
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LayoutGrid(draft: draft, onSelect: (i) => selected = i),
          ),
        ),
      ),
    );
    final first = tester.getRect(find.byKey(const ValueKey('layout-cell-0')));
    await tester.tapAt(first.center);
    expect(selected, 0);
    selected = null;
    await tester.tapAt(
      first.topLeft + Offset(first.width * .12, first.height * .12),
    );
    expect(selected, isNull);
    await tester.tap(find.byKey(const ValueKey('layout-cell-7')));
    expect(selected, 7);
  });

  testWidgets(
    'numbered selector reaches the ninth strip and respects recording lock',
    (tester) async {
      final draft = LayoutDraft(template: LayoutTemplate.nineStrips);
      int? selected;
      Widget build(bool enabled) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              child: LayoutCellSelector(
                draft: draft,
                onSelect: enabled ? (i) => selected = i : null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(build(true));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('layout-select-8')),
        180,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.byKey(const ValueKey('layout-select-8')));
      expect(selected, 8);
      selected = null;
      await tester.pumpWidget(build(false));
      await tester.tap(find.byKey(const ValueKey('layout-select-8')));
      expect(selected, isNull);
    },
  );

  testWidgets('picker exposes nine layouts and all three media modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLayoutPicker(context, LayoutDraft()),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final t in LayoutTemplate.values) {
      expect(find.byKey(ValueKey('template-${t.name}')), findsOneWidget);
    }
    for (final label in ['Photos', 'Videos', 'Hybrid']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Hybrid'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a photo or video for each cell.'), findsOneWidget);
  });
}
