import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart'
    show TaskStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/downloads/bd_backend.dart';
import 'package:watchdog/features/downloads/download_backend.dart';
import 'package:watchdog/features/downloads/download_manager.dart';
import 'package:watchdog/platform/platform_api.dart';
import 'package:watchdog/platform/platform_impl.dart';

class FakeBackend implements DownloadBackend {
  int started = 0;
  bool refuse = false;
  bool pauseOk = true;
  final specs = <DownloadSpec>[];
  final recs = <DownloadProgress>[];
  final canceled = <String>[];
  final deleted = <String>[];
  final ctrl = StreamController<DownloadProgress>.broadcast();

  bool disposed = false;
  @override
  Future<void> dispose() async => disposed = true;
  @override
  Future<void> start() async => started++;
  @override
  Stream<DownloadProgress> get updates => ctrl.stream;
  @override
  Future<List<DownloadProgress>> records() async => List.of(recs);
  @override
  Future<String?> enqueue(DownloadSpec s) async {
    if (refuse) return null;
    specs.add(s);
    final id = 'id${specs.length}';
    recs.add(
      DownloadProgress(
        id: id,
        filename: s.filename,
        state: DownloadState.queued,
        fileId: s.fileId,
        url: s.url,
        filePath: '${s.directory}/${s.filename}',
      ),
    );
    return id;
  }

  @override
  Future<bool> pause(String id) async => pauseOk;
  @override
  Future<bool> resume(String id) async => true;
  @override
  Future<bool> cancel(String id) async {
    canceled.add(id);
    return true;
  }

  @override
  Future<void> deleteRecord(String id) async {
    deleted.add(id);
    recs.removeWhere((r) => r.id == id);
  }
}

void main() {
  group('sanitizeFilename', () {
    test('strips separators and controls, keeps unicode', () {
      expect(sanitizeFilename('a/b\\c.mkv'), 'a_b_c.mkv');
      expect(sanitizeFilename('../../etc/passwd'), '__.._etc_passwd');
      expect(
        sanitizeFilename('Pather Panchali (পথের পাঁচালী).mkv'),
        'Pather Panchali (পথের পাঁচালী).mkv',
      );
      expect(sanitizeFilename('x\ny.mp4'), 'x_y.mp4');
      expect(sanitizeFilename('...'), '_');
      expect(sanitizeFilename('  '), 'download');
    });
    test('long names keep extension', () {
      final s = sanitizeFilename('${'a' * 300}.mkv');
      expect(utf8.encode(s).length, lessThanOrEqualTo(249));
      expect(s.endsWith('.mkv'), isTrue);
    });
  });

  group('byte budget', () {
    int bytes(String s) => utf8.encode(s).length;
    void check(String name, {String? ext}) {
      final s = sanitizeFilename(name);
      expect(bytes(s) + 6, lessThanOrEqualTo(255), reason: s);
      if (ext != null) expect(s.endsWith(ext), isTrue);
      // valid UTF-16 (no lone surrogate)
      expect(() => utf8.encode(s), returnsNormally);
      expect(s.contains('\uFFFD'), isFalse);
    }

    test('CJK 200 chars', () => check('${'電' * 200}.mkv', ext: '.mkv'));
    test('Bengali keeps clusters', () {
      final name = '${'পথের পাঁচালী ' * 20}.mkv';
      check(name, ext: '.mkv');
      final s = sanitizeFilename(name);
      // does not end with a dangling vowel sign/virama before the extension
      final stem = s.substring(0, s.length - 4);
      expect(
        RegExp(r'[\u09BE-\u09CD\u0981-\u0983]$').hasMatch(stem) &&
            !RegExp(r'[\u0995-\u09B9\u09BE-\u09CC\u0981-\u0983\u09CD\u09BC]')
                .hasMatch(stem[0]),
        isFalse,
      );
    });
    test('emoji at the cut point', () {
      // 4-byte emoji; prefix pads so the cut lands inside/at a ZWJ family.
      for (var pad = 230; pad < 249; pad++) {
        final name = '${'a' * pad}\u{1F468}\u200D\u{1F469}\u200D\u{1F467}.mkv';
        check(name, ext: '.mkv');
        final s = sanitizeFilename(name);
        expect(s.contains('\u200D.mkv'), isFalse);
        final stem = s.substring(0, s.length - 4);
        expect(stem.endsWith('\u200D'), isFalse);
      }
    });
    test('long ASCII with extension', () {
      final s = sanitizeFilename('${'x' * 400}.mkv');
      expect(bytes(s), 249);
      expect(s.endsWith('.mkv'), isTrue);
    });
    test('short names untouched', () {
      expect(sanitizeFilename('Movie (2020).mkv'), 'Movie (2020).mkv');
    });
  });

  test('dispose reaches backend', () async {
    final be = FakeBackend();
    await DownloadManager(
      backend: be,
      defaultDirectory: () async => '/d',
    ).dispose();
    expect(be.disposed, isTrue);
  });

  test('uniqueFilename suffixes before extension', () {
    final taken = {'a.mkv', 'a (1).mkv', 'noext'};
    expect(uniqueFilename('a.mkv', taken.contains), 'a (2).mkv');
    expect(uniqueFilename('b.mkv', taken.contains), 'b.mkv');
    expect(uniqueFilename('noext', taken.contains), 'noext (1)');
  });

  test('mapStatus covers every TaskStatus', () {
    expect(
      {for (final s in TaskStatus.values) s: mapStatus(s)},
      {
        TaskStatus.enqueued: DownloadState.queued,
        TaskStatus.waitingToRetry: DownloadState.queued,
        TaskStatus.running: DownloadState.running,
        TaskStatus.paused: DownloadState.paused,
        TaskStatus.complete: DownloadState.complete,
        TaskStatus.canceled: DownloadState.canceled,
        TaskStatus.failed: DownloadState.failed,
        TaskStatus.notFound: DownloadState.failed,
      },
    );
  });

  test('fileId metadata roundtrip', () {
    expect(fileIdFromMeta(encodeMeta(42, 'http://x/y')), 42);
    expect(fileIdFromMeta(encodeMeta(null, 'http://x/y')), isNull);
    expect(fileIdFromMeta(''), isNull);
    expect(fileIdFromMeta('garbage'), isNull);
  });

  group('DownloadManager', () {
    late FakeBackend be;
    late Set<String> onDisk;
    late List<String> deletedFiles;
    late DownloadManager m;
    setUp(() {
      be = FakeBackend();
      onDisk = {};
      deletedFiles = [];
      m = DownloadManager(
        backend: be,
        defaultDirectory: () async => '/dl/watchdog',
        fileExists: onDisk.contains,
        deleteFile: (p) async => deletedFiles.add(p),
      );
    });

    test(
      'enqueue links fileId, sanitises, uses default dir, starts once',
      () async {
        final id = await m.enqueue('http://h/a.mkv', 'a/b.mkv', fileId: 7);
        await m.enqueue('http://h/c.mkv', 'c.mkv');
        expect(id, 'id1');
        expect(be.started, 1);
        expect(be.specs.first.filename, 'a_b.mkv');
        expect(be.specs.first.directory, '/dl/watchdog');
        expect(be.specs.first.fileId, 7);
        final d = await m.downloads();
        expect(d.first.fileId, 7);
        expect(d.first.url, 'http://h/a.mkv');
      },
    );

    test('explicit directory wins', () async {
      await m.enqueue('u', 'a.mkv', directory: '/sd/x');
      expect(be.specs.single.directory, '/sd/x');
    });

    test('collisions: on disk and in queue', () async {
      onDisk.add('/dl/watchdog/a.mkv');
      await m.enqueue('u', 'a.mkv');
      await m.enqueue('u', 'a.mkv');
      expect(be.specs.map((s) => s.filename), ['a (1).mkv', 'a (2).mkv']);
    });

    test('refused enqueue throws', () async {
      be.refuse = true;
      expect(m.enqueue('u', 'a.mkv'), throwsStateError);
    });

    test('pause failure surfaces', () async {
      be.pauseOk = false;
      expect(m.pause('x'), throwsStateError);
    });

    test('remove cancels active, deletes record, optionally file', () async {
      final id = await m.enqueue('u', 'a.mkv');
      await m.remove(id, deleteFile: true);
      expect(be.canceled, [id]);
      expect(be.deleted, [id]);
      expect(deletedFiles, ['/dl/watchdog/a.mkv']);
    });

    test(
      'remove without deleteFile keeps file; finished not canceled',
      () async {
        final id = await m.enqueue('u', 'a.mkv');
        be.recs[0] = DownloadProgress(
          id: id,
          filename: 'a.mkv',
          state: DownloadState.complete,
          filePath: '/dl/watchdog/a.mkv',
        );
        await m.remove(id);
        expect(be.canceled, isEmpty);
        expect(be.deleted, [id]);
        expect(deletedFiles, isEmpty);
      },
    );

    test('updates stream passes through backend events', () async {
      final got = <DownloadProgress>[];
      final sub = m.updates.listen(got.add);
      await Future<void>.delayed(Duration.zero);
      be.ctrl.add(
        const DownloadProgress(
          id: 'i',
          filename: 'f',
          state: DownloadState.running,
          progress: .5,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(got.single.progress, .5);
      await sub.cancel();
    });

    test('PlatformApiImpl delegates downloads to the manager', () async {
      final api = PlatformApiImpl(downloads: m);
      final id = await api.enqueueDownload('u', 'a.mkv', fileId: 3);
      expect((await api.downloads()).single.fileId, 3);
      expect(await api.defaultDownloadDirectory(), '/dl/watchdog');
      await api.removeDownload(id);
      expect(await api.downloads(), isEmpty);
    });
  });
}
