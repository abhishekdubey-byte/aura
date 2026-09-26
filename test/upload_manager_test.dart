import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aura/models/upload_record.dart';
import 'package:aura/services/upload_manager.dart';
import 'package:aura/services/upload_queue_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.aura.aura/uploads');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late List<MethodCall> calls;
  late UploadManager manager;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'username': 'test_user'});
    temp = await Directory.systemTemp.createTemp('aura_upload_bridge_');
    calls = [];
    manager = UploadManager.forTesting();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temp.path,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'configure'
          ? null
          : {
              'pending': 1,
              'uploading': 0,
              'uploaded': 0,
              'blocked': 0,
              'bytes': 10,
            };
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await temp.delete(recursive: true);
  });

  test(
    'capture awaits durable native handoff and never requires gallery saving',
    () async {
      final retained = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'enqueue') await retained.future;
        return call.method == 'configure' ? null : {'pending': 1};
      });
      bool completed = false;
      final capture = manager
          .enqueue('/camera/source.jpg')
          .then((_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(completed, isFalse);
      retained.complete();
      await capture;
      expect(calls.map((c) => c.method), ['configure', 'enqueue']);
      expect(calls.last.arguments['path'], '/camera/source.jpg');
      expect(manager.summary.value.pending, 1);
    },
  );

  test('concurrent captures configure once and hand every original to native queue', () async {
    await Future.wait(
      List.generate(12, (i) => manager.enqueue('/camera/$i.jpg')),
    );
    expect(calls.where((c) => c.method == 'configure').length, 1);
    expect(calls.where((c) => c.method == 'enqueue').length, 12);
  });

  test(
    'old exhausted retries migrate before their durable source is deleted',
    () async {
      final dir = await Directory('${temp.path}/pending_uploads').create();
      final source = await File('${dir.path}/old.jpg').writeAsBytes([1, 2, 3]);
      final record = UploadRecord(
        imageId: 'old',
        localPath: source.path,
        status: UploadStatus.failed,
        retryCount: 7,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(UploadQueueStore.key, [
        jsonEncode(record.toJson()),
      ]);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'enqueue') expect(await source.exists(), isTrue);
        return call.method == 'configure' ? null : {'pending': 1};
      });
      await manager.resume();
      expect(calls.map((c) => c.method), ['configure', 'enqueue', 'resume']);
      expect(prefs.getStringList(UploadQueueStore.key), isEmpty);
      expect(await source.exists(), isFalse);
    },
  );

  test('queue failures retain a retry reference and remain visible through polling', () async {
    final source = await File('${temp.path}/source.jpg').writeAsBytes([1, 2]);
    bool fail = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'enqueue' && fail) {
        throw PlatformException(code: 'disk_busy');
      }
      return call.method == 'configure' ? null : {'pending': 0};
    });
    await manager.enqueue(source.path);
    await manager.refreshStatus();
    expect(manager.summary.value.blocked, 1);
    expect(manager.summary.value.message, isNotNull);
    expect(await source.exists(), isTrue);
    expect(
      (await SharedPreferences.getInstance()).getStringList(
        UploadQueueStore.key,
      ),
      hasLength(1),
    );
    fail = false;
    await manager.resume(retryNow: true);
    expect(
      (await SharedPreferences.getInstance()).getStringList(
        UploadQueueStore.key,
      ),
      isEmpty,
    );
    expect(manager.summary.value.blocked, 0);
    expect(
      await source.exists(),
      isTrue,
    ); // External originals never deleted by migration.
  });

  test(
    'resume wakes native network-constrained work after launch or reconnection',
    () async {
      await manager.resume();
      await manager.resume(retryNow: true);
      final requests = calls.where((c) => c.method == 'resume').toList();
      expect(requests.length, 2);
      expect(requests.last.arguments['retryNow'], isTrue);
    },
  );

  test(
    'one rejected legacy item cannot block later captures or native recovery',
    () async {
      final bad = await File('${temp.path}/bad.jpg').writeAsBytes([1]);
      final good = await File('${temp.path}/good.jpg').writeAsBytes([2]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(UploadQueueStore.key, [
        for (final file in [bad, good])
          jsonEncode(
            UploadRecord(imageId: file.path, localPath: file.path).toJson(),
          ),
      ]);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'enqueue' && call.arguments['path'] == bad.path) {
          throw PlatformException(code: 'invalid_legacy_media');
        }
        return call.method == 'configure' ? null : {'pending': 1};
      });
      await manager.resume();
      await manager.enqueue('/camera/new.jpg');
      expect(calls.where((c) => c.method == 'resume'), hasLength(1));
      expect(calls.last.arguments['path'], '/camera/new.jpg');
      expect(prefs.getStringList(UploadQueueStore.key), hasLength(1));
      expect(await bad.exists(), isTrue);
      expect(manager.summary.value.blocked, 1);
    },
  );

  test('empty camera output is never retained as a retryable upload', () async {
    final empty = await File('${temp.path}/empty.mp4').writeAsBytes([]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'enqueue') throw PlatformException(code: 'empty_file');
      return call.method == 'configure' ? null : {'pending': 0};
    });
    await manager.enqueue(empty.path);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(UploadQueueStore.key) ?? [], isEmpty);
    expect(manager.summary.value.blocked, 1);
  });
}
