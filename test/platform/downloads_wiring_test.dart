import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/downloads/bd_backend.dart';
import 'package:watchdog/features/downloads/download_backend.dart';
import 'package:watchdog/features/downloads/download_manager.dart';
import 'package:watchdog/features/downloads/downloads_providers.dart';
import 'package:watchdog/platform/platform_api.dart';
import 'package:watchdog/platform/platform_impl.dart';

class _Backend implements DownloadBackend {
  bool disposed = false;
  @override
  Future<void> dispose() async => disposed = true;
  @override
  Future<void> start() async {}
  @override
  Stream<DownloadProgress> get updates => const Stream.empty();
  @override
  Future<List<DownloadProgress>> records() async => [];
  @override
  Future<String?> enqueue(DownloadSpec s) async => null;
  @override
  Future<bool> pause(String id) async => true;
  @override
  Future<bool> resume(String id) async => true;
  @override
  Future<bool> cancel(String id) async => true;
  @override
  Future<void> deleteRecord(String id) async {}
}

class _Api implements PlatformApi {
  final ctrl = StreamController<DownloadProgress>.broadcast();
  final gate = Completer<void>();
  @override
  Stream<DownloadProgress> get downloadUpdates => ctrl.stream;
  @override
  Future<List<DownloadProgress>> downloads() async {
    await gate.future;
    return const [
      DownloadProgress(id: 'a', filename: 'a', state: DownloadState.queued),
      DownloadProgress(id: 'b', filename: 'b', state: DownloadState.queued),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

void main() {
  test('provider disposal disposes the download manager', () async {
    final be = _Backend();
    final api = PlatformApiImpl(
      openExternalImpl: (_) async {},
      openLocalImpl: (_, {mimeType}) async {},
      downloads: DownloadManager(
        backend: be,
        defaultDirectory: () async => '/d',
      ),
    );
    final c = ProviderContainer(
      overrides: platformOverrides(create: () => api),
    );
    c.read(platformApiProvider);
    expect(be.disposed, isFalse);
    c.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(be.disposed, isTrue);
  });

  test('downloadsProvider keeps updates emitted during the snapshot', () async {
    final api = _Api();
    final c = ProviderContainer(
      overrides: [platformApiProvider.overrideWithValue(api)],
    );
    addTearDown(c.dispose);
    final seen = <List<DownloadProgress>>[];
    c.listen(downloadsProvider, (_, n) {
      if (n.hasValue) seen.add(n.requireValue);
    });
    await Future<void>.delayed(Duration.zero);
    // Emitted while downloads() is still awaiting; newer than the snapshot.
    api.ctrl
      ..add(
        const DownloadProgress(
          id: 'a',
          filename: 'a',
          state: DownloadState.running,
          progress: .4,
        ),
      )
      ..add(
        const DownloadProgress(
          id: 'c',
          filename: 'c',
          state: DownloadState.running,
        ),
      );
    await Future<void>.delayed(Duration.zero);
    api.gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final m = {for (final d in seen.last) d.id: d};
    expect(m.keys.toSet(), {'a', 'b', 'c'});
    expect(m['a']!.state, DownloadState.running);
    // live update after snapshot still flows
    api.ctrl.add(
      const DownloadProgress(
        id: 'b',
        filename: 'b',
        state: DownloadState.complete,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      {for (final d in seen.last) d.id: d}['b']!.state,
      DownloadState.complete,
    );
  });

  test('LastProgress prunes on terminal state, cancel and remove', () {
    final lp = LastProgress()
      ..note('a', .5)
      ..note('b', .5)
      ..note('c', .5)
      ..note('d', .5);
    expect(lp.onStatus('a', DownloadState.running), .5);
    expect(lp.length, 4);
    expect(lp.onStatus('a', DownloadState.complete), .5);
    lp.onStatus('b', DownloadState.canceled);
    lp.onStatus('c', DownloadState.failed);
    lp.forget('d');
    expect(lp.length, 0);
  });
}
