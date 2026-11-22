import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/platform/external_player.dart';
import 'package:watchdog/platform/external_player_android.dart';
import 'package:watchdog/platform/external_player_linux.dart';
import 'package:watchdog/platform/platform_api.dart';
import 'package:watchdog/platform/platform_impl.dart';

const a = ExternalMedia(url: 'http://172.16.50.7/a%20b.mkv', title: 'A B');
const b = ExternalMedia(url: 'http://172.16.50.7/c.mkv', title: 'C\nINJECT');

class FakeLauncher implements IntentLauncher {
  bool resolvable = true;
  Object? throwOnLaunch;
  final calls = <Map<String, Object?>>[];
  @override
  Future<bool> canView({required String data, required String type}) async =>
      resolvable;
  @override
  Future<void> viewChooser({
    required String data,
    required String type,
    required String title,
    List<int> flags = const [],
  }) async {
    if (throwOnLaunch != null) throw throwOnLaunch!;
    calls.add({'data': data, 'type': type, 'title': title, 'flags': flags});
  }
}

class FakeRunner implements ProcessRunner {
  Object? error;
  final calls = <(String, List<String>)>[];
  @override
  Future<void> startDetached(String exe, List<String> args) async {
    if (error != null) throw error!;
    calls.add((exe, args));
  }
}

void main() {
  localTests();
  symlinkAndRootTests();
  test('buildM3u', () {
    expect(
      buildM3u([a, b]),
      '#EXTM3U\n#EXTINF:-1,A B\nhttp://172.16.50.7/a%20b.mkv\n'
      '#EXTINF:-1,C INJECT\nhttp://172.16.50.7/c.mkv\n',
    );
  });

  group('android', () {
    late FakeLauncher l;
    late Directory tmp;
    late AndroidExternalPlayer p;
    setUp(() {
      l = FakeLauncher();
      tmp = Directory.systemTemp.createTempSync('wd');
      p = AndroidExternalPlayer(launcher: l, cacheDir: () async => tmp);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('single item: VIEW url as video/*', () async {
      await p.open([a]);
      expect(l.calls.single['data'], a.url);
      expect(l.calls.single['type'], 'video/*');
    });

    test(
      'several items: writes m3u, opens content uri with read grant',
      () async {
        await p.open([a, b]);
        final c = l.calls.single;
        expect(c['type'], m3uMimeType);
        expect(
          c['data'],
          startsWith('content://$androidFileProviderAuthority/'),
        );
        expect(c['data'], endsWith('/m3u/watchdog_playlist.m3u'));
        expect(c['flags'], [1]);
        expect(
          File('${tmp.path}/m3u/watchdog_playlist.m3u').readAsStringSync(),
          buildM3u([a, b]),
        );
      },
    );

    test('no resolvable activity -> noPlayer', () async {
      l.resolvable = false;
      expect(
        p.open([a]),
        throwsA(
          isA<ExternalPlayerException>().having(
            (e) => e.error,
            'error',
            ExternalPlayerError.noPlayer,
          ),
        ),
      );
    });

    test('PlatformException mapped', () async {
      l.throwOnLaunch = PlatformException(
        code: 'error',
        message: 'No Activity found to handle Intent',
      );
      await expectLater(
        p.open([a]),
        throwsA(
          isA<ExternalPlayerException>().having(
            (e) => e.error,
            'error',
            ExternalPlayerError.noPlayer,
          ),
        ),
      );
      l.throwOnLaunch = PlatformException(code: 'error', message: 'boom');
      await expectLater(
        p.open([a]),
        throwsA(
          isA<ExternalPlayerException>().having(
            (e) => e.error,
            'error',
            ExternalPlayerError.launchFailed,
          ),
        ),
      );
    });
  });

  group('linux', () {
    test('single item gets title', () async {
      final r = FakeRunner();
      await LinuxExternalPlayer(runner: r).open([a]);
      expect(r.calls.single.$1, 'mpv');
      expect(r.calls.single.$2, ['--force-media-title=A B', '--', a.url]);
    });

    test('several items: urls only', () async {
      final r = FakeRunner();
      await LinuxExternalPlayer(runner: r).open([a, b]);
      expect(r.calls.single.$2, ['--', a.url, b.url]);
    });

    test('missing mpv -> noPlayer', () async {
      final r = FakeRunner()
        ..error = const ProcessException('mpv', [], 'not found', 2);
      expect(
        LinuxExternalPlayer(runner: r).open([a]),
        throwsA(
          isA<ExternalPlayerException>().having(
            (e) => e.error,
            'error',
            ExternalPlayerError.noPlayer,
          ),
        ),
      );
    });
  });

  test('PlatformApiImpl delegates', () async {
    final opened = <List<ExternalMedia>>[];
    String? copied;
    final api = PlatformApiImpl(
      openExternalImpl: (i) async => opened.add(i),
      setClipboard: (t) async => copied = t,
    );
    await api.openExternal([a]);
    await api.copyUrl('x');
    expect(opened.single.single, a);
    expect(copied, 'x');
  });
}

void localTests() {
  group('local file', () {
    late Directory root;
    late File f;
    setUp(() {
      root = Directory.systemTemp.createTempSync('wdl');
      f = File('${root.path}/My Movie (2020).mkv')..writeAsStringSync('x');
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('validateLocalPath', () {
      expect(validateLocalPath(f.path, root.path), f.path);
      for (final bad in [
        '${root.path}/../x.mkv',
        '${root.path}/a/../../x.mkv',
        '/etc/passwd',
        'relative.mkv',
        root.path,
        '',
      ]) {
        expect(
          () => validateLocalPath(bad, root.path),
          throwsA(
            isA<ExternalPlayerException>().having(
              (e) => e.error,
              'error',
              ExternalPlayerError.invalidPath,
            ),
          ),
          reason: bad,
        );
      }
    });

    test('inferVideoMime', () {
      expect(inferVideoMime('a.MKV'), 'video/x-matroska');
      expect(inferVideoMime('a.mp4'), 'video/mp4');
      expect(inferVideoMime('a.xyz'), 'video/*');
      expect(inferVideoMime('noext'), 'video/*');
    });

    test('android: content uri, grant flag, inferred type', () async {
      final l = FakeLauncher();
      final p = AndroidExternalPlayer(
        launcher: l,
        downloadRoots: () async => [root.path],
        providerRoot: () async => root.path,
      );
      await p.openLocal(f.path);
      final c = l.calls.single;
      expect(
        c['data'],
        'content://$androidFileProviderAuthority/downloads/'
        'My%20Movie%20(2020).mkv',
      );
      expect(c['type'], 'video/x-matroska');
      expect(c['flags'], [1]);
      await p.openLocal(f.path, mimeType: 'video/mp4');
      expect(l.calls.last['type'], 'video/mp4');
    });

    test('android: rejects outside / missing, no player', () async {
      final l = FakeLauncher();
      final p = AndroidExternalPlayer(
        launcher: l,
        downloadRoots: () async => [root.path],
        providerRoot: () async => root.path,
      );
      await expectLater(
        p.openLocal('/etc/passwd'),
        throwsA(isA<ExternalPlayerException>()),
      );
      await expectLater(
        p.openLocal('${root.path}/nope.mkv'),
        throwsA(isA<ExternalPlayerException>()),
      );
      expect(l.calls, isEmpty);
      l.resolvable = false;
      await expectLater(
        p.openLocal(f.path),
        throwsA(
          isA<ExternalPlayerException>().having(
            (e) => e.error,
            'error',
            ExternalPlayerError.noPlayer,
          ),
        ),
      );
    });

    test('linux: mpv, falls back to xdg-open, then noPlayer', () async {
      final r = FakeRunner();
      final p = LinuxExternalPlayer(
        runner: r,
        downloadRoots: () async => [root.path],
      );
      await p.openLocal(f.path);
      expect(r.calls.single.$1, 'mpv');
      expect(r.calls.single.$2, ['--', f.path]);

      final r2 = _MissingMpvRunner();
      await LinuxExternalPlayer(
        runner: r2,
        downloadRoots: () async => [root.path],
      ).openLocal(f.path);
      expect(r2.calls.single.$1, 'xdg-open');
      expect(r2.calls.single.$2, [f.path]);

      final r3 = FakeRunner()..error = const ProcessException('x', [], 'nf', 2);
      await expectLater(
        LinuxExternalPlayer(
          runner: r3,
          downloadRoots: () async => [root.path],
        ).openLocal(f.path),
        throwsA(
          isA<ExternalPlayerException>().having(
            (e) => e.error,
            'error',
            ExternalPlayerError.noPlayer,
          ),
        ),
      );
      await expectLater(
        LinuxExternalPlayer(
          runner: r,
          downloadRoots: () async => [root.path],
        ).openLocal('${root.path}/../x'),
        throwsA(isA<ExternalPlayerException>()),
      );
    });

    test('PlatformApiImpl.openLocalFile delegates', () async {
      String? got;
      String? gotMime;
      final api = PlatformApiImpl(
        openLocalImpl: (p, {mimeType}) async {
          got = p;
          gotMime = mimeType;
        },
      );
      await api.openLocalFile('/x/y.mkv', mimeType: 'video/mp4');
      expect((got, gotMime), ('/x/y.mkv', 'video/mp4'));
    });
  });
}

void symlinkAndRootTests() {
  group('symlinks and roots', () {
    late Directory base, root, outside;
    setUp(() {
      base = Directory.systemTemp.createTempSync('wds');
      root = Directory('${base.path}/root')..createSync();
      outside = Directory('${base.path}/outside')..createSync();
      File('${outside.path}/secret.mkv').writeAsStringSync('s');
      File('${root.path}/ok.mkv').writeAsStringSync('x');
    });
    tearDown(() => base.deleteSync(recursive: true));

    Matcher err(ExternalPlayerError e) => throwsA(
      isA<ExternalPlayerException>().having((x) => x.error, 'error', e),
    );

    test('file symlink escaping the root is rejected', () async {
      Link('${root.path}/evil.mkv').createSync('${outside.path}/secret.mkv');
      await expectLater(
        resolveLocalPath('${root.path}/evil.mkv', [root.path]),
        err(ExternalPlayerError.invalidPath),
      );
    });

    test('directory symlink escaping the root is rejected', () async {
      Link('${root.path}/dir').createSync(outside.path);
      await expectLater(
        resolveLocalPath('${root.path}/dir/secret.mkv', [root.path]),
        err(ExternalPlayerError.invalidPath),
      );
    });

    test('symlinked root itself is fine', () async {
      Link('${base.path}/rootlink').createSync(root.path);
      final r = await resolveLocalPath('${base.path}/rootlink/ok.mkv', [
        '${base.path}/rootlink',
      ]);
      expect(r.path, endsWith('/root/ok.mkv'));
    });

    test('any of several roots; missing roots ignored', () async {
      final r = await resolveLocalPath('${root.path}/ok.mkv', [
        '${base.path}/nope',
        outside.path,
        root.path,
      ]);
      expect(r.root, endsWith('/root'));
    });

    test(
      'android: path outside provider folder -> unsupportedLocation',
      () async {
        final l = FakeLauncher();
        final p = AndroidExternalPlayer(
          launcher: l,
          downloadRoots: () async => [root.path, outside.path],
          providerRoot: () async => root.path,
        );
        await expectLater(
          p.openLocal('${outside.path}/secret.mkv'),
          err(ExternalPlayerError.unsupportedLocation),
        );
        expect(l.calls, isEmpty);
        await p.openLocal('${root.path}/ok.mkv');
        expect(l.calls, hasLength(1));
      },
    );

    test('android: no external storage -> unsupportedLocation', () async {
      final l = FakeLauncher();
      final p = AndroidExternalPlayer(
        launcher: l,
        downloadRoots: () async => [root.path],
        providerRoot: () async => null,
      );
      await expectLater(
        p.openLocal('${root.path}/ok.mkv'),
        err(ExternalPlayerError.unsupportedLocation),
      );
      expect(l.calls, isEmpty);
    });

    test('linux: accepts a record folder outside the default', () async {
      final r = FakeRunner();
      await LinuxExternalPlayer(
        runner: r,
        downloadRoots: () async => [root.path, outside.path],
      ).openLocal('${outside.path}/secret.mkv');
      expect(r.calls.single.$1, 'mpv');
    });
  });
}

class _MissingMpvRunner implements ProcessRunner {
  final calls = <(String, List<String>)>[];
  @override
  Future<void> startDetached(String exe, List<String> args) async {
    if (exe == 'mpv') throw const ProcessException('mpv', [], 'nf', 2);
    calls.add((exe, args));
  }
}
