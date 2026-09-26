import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aura/models/upload_record.dart';
import 'package:aura/screens/age_gate_screen.dart';
import 'package:aura/screens/capture_preview_screen.dart';
import 'package:aura/screens/onboarding_screen.dart';
import 'package:aura/screens/registration_screen.dart';
import 'package:aura/screens/settings_screen.dart';
import 'package:aura/services/streak_service.dart';
import 'package:aura/services/upload_queue_store.dart';
import 'package:aura/theme/aura_theme.dart';
import 'package:aura/widgets/aura_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('concurrent captures increment a daily streak only once', () async {
    final results = await Future.wait(
      List.generate(20, (_) => StreakService.incrementStreak()),
    );
    expect(results.where((r) => r.justIncreased).length, 1);
    expect(results.every((r) => r.count == 1), isTrue);
    expect(await StreakService.getStreak(), 1);
  });

  test(
    'streak recovers from corrupt dates and compares calendar days',
    () async {
      SharedPreferences.setMockInitialValues({
        'last_opened_date': 'broken',
        'streak_count': 99,
      });
      expect(await StreakService.getStreak(), 0);
      expect((await StreakService.incrementStreak()).count, 1);
      expect(
        StreakService.calendarDays(
          DateTime(2026, 3, 8, 23, 59),
          DateTime(2026, 3, 9),
        ),
        1,
      );
    },
  );

  test(
    'queue edits during an upload preserve new captures and progress',
    () async {
      final store = UploadQueueStore();
      await store.change(
        (r) => r.add(UploadRecord(imageId: 'first', localPath: '/first.jpg')),
      );
      final first = await store.change((r) {
        r.first.status = UploadStatus.uploading;
        return r.first;
      });
      await Future.wait(
        List.generate(
          12,
          (i) => store.change(
            (r) =>
                r.add(UploadRecord(imageId: 'photo$i', localPath: '/$i.jpg')),
          ),
        ),
      );
      first.status = UploadStatus.uploaded;
      await store.change(
        (r) => r[r.indexWhere((e) => e.imageId == first.imageId)] = first,
      );
      final records = await store.change((r) => List.of(r));
      expect(records.length, 13);
      expect(records.first.status, UploadStatus.uploaded);
      expect(
        records.skip(1).every((r) => r.status == UploadStatus.pending),
        isTrue,
      );
    },
  );

  test('a corrupt queue row does not hide valid uploads', () async {
    final record = UploadRecord(imageId: 'valid', localPath: '/test.jpg');
    SharedPreferences.setMockInitialValues({
      UploadQueueStore.key: ['broken', jsonEncode(record.toJson())],
    });
    final records = await UploadQueueStore().change((r) => List.of(r));
    expect(records.single.imageId, 'valid');
  });

  Widget app(Widget screen, {double scale = 1, bool review = false}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: review
            ? AuraTheme.dark.copyWith(
                textTheme: AuraTheme.dark.textTheme.apply(
                  fontFamily: 'AuraReview',
                ),
                chipTheme: AuraTheme.dark.chipTheme.copyWith(
                  labelStyle: AuraTheme.dark.chipTheme.labelStyle?.copyWith(
                    fontFamily: 'AuraReview',
                  ),
                ),
                appBarTheme: AuraTheme.dark.appBarTheme.copyWith(
                  titleTextStyle: AuraTheme.dark.appBarTheme.titleTextStyle
                      ?.copyWith(fontFamily: 'AuraReview'),
                ),
              )
            : AuraTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: screen,
      );

  testWidgets(
    'settings migrates screenshot preference and saves edited-photo choice',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'save_preference': 'Screenshot',
        'username': 'aura_test',
        'full_name': 'AURA Test',
      });
      await tester.pumpWidget(app(const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Photo with score'), findsOneWidget);
      await tester.tap(find.text('Photo with score'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original + photo with score').last);
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getString('save_preference'),
        'Both',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  final screens = <String, Widget Function()>{
    'settings': () => const SettingsScreen(),
    'registration': () => const RegistrationScreen(),
    'age_gate': () => const AgeGateScreen(),
    'onboarding': () => const OnboardingScreen(),
    'empty_gallery': () => const CapturePreviewScreen(photos: []),
  };
  for (final entry in screens.entries) {
    testWidgets('${entry.key} fits a small screen with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(entry.value(), scale: 1.6));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('primary button exposes disabled state while busy', (
    tester,
  ) async {
    int count = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: AuraButton(label: 'Save', busy: true, onPressed: () => count++),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    expect(count, 0);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  // Optional review artifacts use the real widgets, never an independent mockup.
  if (const bool.fromEnvironment('AURA_UI_REVIEW')) {
    for (final entry in screens.entries.take(5)) {
      testWidgets('render ${entry.key} for visual review', (tester) async {
        final fontPath = Platform.environment['AURA_REVIEW_FONT'];
        if (fontPath != null) {
          await tester.runAsync(() async {
            final loader = FontLoader('AuraReview')
              ..addFont(
                File(fontPath)
                    .readAsBytes()
                    .then((b) => ByteData.sublistView(b)),
              );
            await loader.load();
            final icons = FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await icons.load();
          });
        }
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: key, child: app(entry.value(), review: true)),
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = await Directory('build/ui-review')
              .create(recursive: true);
          await File('${dir.path}/${entry.key}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
