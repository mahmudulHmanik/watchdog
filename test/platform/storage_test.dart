import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/platform/platform_api.dart';
import 'package:watchdog/platform/storage.dart';

void write(String path, int bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(List.filled(bytes, 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, support, cache, dl, shared;

  StorageOps ops({bool android = false, MethodChannel? ch}) => StorageOps(
    supportDir: () async => support,
    cacheDir: () async => cache,
    downloadDirs: () async => [dl, if (android) shared],
    freeBytes: () async => 999,
    android: android,
    channel: ch,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('storage');
    support = Directory('${root.path}/support')..createSync();
    cache = Directory('${root.path}/cache')..createSync();
    dl = Directory('${root.path}/dl')..createSync();
    shared = Directory('${root.path}/movies')..createSync();
    write('${support.path}/watchdog.db', 1000);
    write('${support.path}/watchdog.db-wal', 200);
    write('${support.path}/watchdog.db-shm', 30);
    write('${support.path}/player_settings.json', 5000); // not the index
    write('${cache.path}/$kImageCacheDirName/a', 100);
    write('${cache.path}/$kImageCacheDirName/b', 50);
    write('${cache.path}/file_picker/1/x.srt', 7);
    write('${cache.path}/m3u/watchdog_playlist.m3u', 3);
    write('${cache.path}/updates/new.apk', 99999); // not player cache
    write('${dl.path}/Movie.mkv', 4000);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('usage sums each area separately', () async {
    final u = await ops().usage();
    expect(u.indexBytes, 1230);
    expect(u.imageCacheBytes, 150);
    expect(u.playerCacheBytes, 10);
    expect(u.downloadsBytes, 4000);
    expect(u.freeBytes, 999);
    expect(u.totalBytes, 1230 + 150 + 10 + 4000);
  });

  test('missing folders count as zero', () async {
    root.deleteSync(recursive: true);
    root.createSync();
    final u = await ops().usage();
    expect(u.totalBytes, 0);
  });

  test('clear image / player cache touch only their folders', () async {
    final o = ops();
    await o.clearImageCache();
    expect(Directory('${cache.path}/$kImageCacheDirName').listSync(), isEmpty);
    expect(File('${cache.path}/file_picker/1/x.srt').existsSync(), isTrue);
    await o.clearPlayerCache();
    expect(File('${cache.path}/file_picker/1/x.srt').existsSync(), isFalse);
    expect(
      File('${cache.path}/m3u/watchdog_playlist.m3u').existsSync(),
      isFalse,
    );
    expect(File('${cache.path}/updates/new.apk').existsSync(), isTrue);
    expect(File('${support.path}/watchdog.db').existsSync(), isTrue);
  });

  test('clearPlayerTemp (player close) leaves the m3u and updates', () {
    clearPlayerTemp(cache.path);
    expect(File('${cache.path}/file_picker/1/x.srt').existsSync(), isFalse);
    expect(
      File('${cache.path}/m3u/watchdog_playlist.m3u').existsSync(),
      isTrue,
    );
    expect(File('${cache.path}/updates/new.apk').existsSync(), isTrue);
  });

  test('sweepDownloads (Linux) keeps active files', () async {
    write('${dl.path}/active.mkv', 10);
    final n = await ops().sweepDownloads(keep: {'${dl.path}/active.mkv'});
    expect(n, 1);
    expect(File('${dl.path}/Movie.mkv').existsSync(), isFalse);
    expect(File('${dl.path}/active.mkv').existsSync(), isTrue);
  });

  group('Android MediaStore channel', () {
    const ch = MethodChannel('test/storage');
    final calls = <String>[];
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, (c) async {
            calls.add(c.method);
            return switch (c.method) {
              'downloadsUsage' => {'bytes': 5000000, 'count': 2},
              'deleteDownloads' => 2,
              _ => null,
            };
          });
      write('${shared.path}/ignored.mkv', 123456); // MediaStore is the source
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, null),
    );

    test('downloads = owned MediaStore bytes + private folder', () async {
      final u = await ops(android: true, ch: ch).usage();
      expect(u.downloadsBytes, 5000000 + 4000);
    });

    test('falls back to walking Movies/watchdog without MediaStore', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, (c) async => null);
      final u = await ops(android: true, ch: ch).usage();
      expect(u.downloadsBytes, 4000 + 123456);
    });

    test(
      'sweep asks MediaStore to delete owned rows, then the private folder',
      () async {
        final n = await ops(android: true, ch: ch).sweepDownloads();
        expect(calls, contains('deleteDownloads'));
        expect(n, 2 + 1);
        expect(File('${dl.path}/Movie.mkv').existsSync(), isFalse);
        // The shared folder is never walked directly when MediaStore answers.
        expect(File('${shared.path}/ignored.mkv').existsSync(), isTrue);
      },
    );
  });
}
