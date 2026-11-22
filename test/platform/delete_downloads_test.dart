import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/downloads/download_backend.dart';
import 'package:watchdog/features/downloads/download_manager.dart';
import 'package:watchdog/platform/platform_api.dart';
import 'package:watchdog/platform/platform_impl.dart';
import 'package:watchdog/platform/storage.dart';

class _Backend implements DownloadBackend {
  _Backend(this.recs);
  final List<DownloadProgress> recs;
  final deleted = <String>[];
  @override
  Future<void> start() async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<DownloadProgress> get updates => const Stream.empty();
  @override
  Future<List<DownloadProgress>> records() async => [
    for (final r in recs)
      if (!deleted.contains(r.id)) r,
  ];
  @override
  Future<String?> enqueue(DownloadSpec spec) async => null;
  @override
  Future<bool> pause(String id) async => true;
  @override
  Future<bool> resume(String id) async => true;
  @override
  Future<bool> cancel(String id) async => true;
  @override
  Future<void> deleteRecord(String id) async => deleted.add(id);
}

void main() {
  test(
    'deleteAllDownloads: finished records + files go, active ones stay',
    () async {
      final dir = Directory.systemTemp.createTempSync('dlall');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/done.mkv').writeAsStringSync('x');
      File('${dir.path}/orphan.mkv').writeAsStringSync('x');
      File('${dir.path}/running.mkv').writeAsStringSync('x');
      final be = _Backend([
        DownloadProgress(
          id: 'a',
          filename: 'done.mkv',
          state: DownloadState.complete,
          filePath: '${dir.path}/done.mkv',
        ),
        DownloadProgress(
          id: 'b',
          filename: 'running.mkv',
          state: DownloadState.running,
          filePath: '${dir.path}/running.mkv',
        ),
      ]);
      final api = PlatformApiImpl(
        openExternalImpl: (_) async {},
        openLocalImpl: (_, {mimeType}) async {},
        downloads: DownloadManager(
          backend: be,
          defaultDirectory: () async => dir.path,
        ),
        storage: StorageOps(
          supportDir: () async => dir,
          cacheDir: () async => dir,
          downloadDirs: () async => [dir],
          android: false,
        ),
      );
      final n = await api.deleteAllDownloads();
      expect(n, 2, reason: 'done.mkv via its record, orphan.mkv via the sweep');
      expect(be.deleted, ['a']);
      expect(File('${dir.path}/done.mkv').existsSync(), isFalse);
      expect(File('${dir.path}/orphan.mkv').existsSync(), isFalse);
      expect(File('${dir.path}/running.mkv').existsSync(), isTrue);
    },
  );
}
