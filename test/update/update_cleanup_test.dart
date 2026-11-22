import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/features/update/release.dart';
import 'package:watchdog/features/update/update_cleanup.dart';
import 'package:watchdog/features/update/update_service.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('upc'));
  tearDown(() => dir.deleteSync(recursive: true));

  File mk(String name, {DateTime? age}) {
    final f = File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);
    if (age != null) f.setLastModifiedSync(age);
    return f;
  }

  List<String> left() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('versionInApkName', () {
    expect(versionInApkName('watchdog-0.2.1-arm64.apk'), '0.2.1');
    expect(versionInApkName('watchdog-v1.10-arm64-v8a.apk'), '1.10');
    expect(versionInApkName('app.apk'), isNull);
  });

  group('cleanInstalledUpdates (launch)', () {
    test('deletes versions <= current, keeps newer and unparsable', () async {
      mk('watchdog-0.1.0-arm64.apk');
      mk('watchdog-0.2.0-arm64.apk');
      mk('watchdog-0.3.0-arm64.apk');
      mk('mystery.apk');
      mk('notes.txt');
      final n = await cleanInstalledUpdates(dir, currentVersion: '0.2.0+2');
      expect(n, 2);
      expect(left(), ['mystery.apk', 'notes.txt', 'watchdog-0.3.0-arm64.apk']);
    });

    test('stale .part removed, fresh .part kept', () async {
      final now = DateTime.now();
      mk('a-0.9.0.apk.part', age: now.subtract(const Duration(hours: 1)));
      mk('b-0.9.0.apk.part', age: now);
      await cleanInstalledUpdates(dir, currentVersion: '0.2.0');
      expect(left(), ['b-0.9.0.apk.part']);
    });

    test('never deletes the APK of an active install', () async {
      final f = mk('watchdog-0.2.0-arm64.apk');
      final g = InstallGuard()..begin(f.path);
      expect(
        await cleanInstalledUpdates(dir, currentVersion: '0.2.0', guard: g),
        0,
      );
      expect(f.existsSync(), isTrue);
      g.end();
      expect(await cleanInstalledUpdates(dir, currentVersion: '0.2.0'), 1);
      expect(f.existsSync(), isFalse);
    });

    test('missing dir is fine', () async {
      expect(
        await cleanInstalledUpdates(
          Directory('${dir.path}/nope'),
          currentVersion: '0.2.0',
        ),
        0,
      );
    });
  });

  group('cleanBeforeDownload', () {
    test('keeps only keepName and the guarded install', () async {
      mk('watchdog-0.2.0-arm64.apk');
      mk('watchdog-0.3.0-arm64.apk');
      final installing = mk('watchdog-0.4.0-arm64.apk');
      mk('watchdog-0.4.0-arm64.apk.part');
      mk('notes.txt');
      final g = InstallGuard()..begin(installing.path);
      final n = await cleanBeforeDownload(
        dir,
        keepName: 'watchdog-0.3.0-arm64.apk',
        guard: g,
      );
      g.end();
      expect(n, 2);
      expect(left(), [
        'notes.txt',
        'watchdog-0.3.0-arm64.apk',
        'watchdog-0.4.0-arm64.apk',
      ]);
    });
  });

  group('InstallGuard lifecycle', () {
    test('cleared when the app returns after having left', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final g = InstallGuard()..begin('/x.apk');
      expect(g.active, isTrue);
      g.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(g.active, isTrue, reason: 'never left yet');
      g.didChangeAppLifecycleState(AppLifecycleState.inactive);
      g.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(g.active, isTrue);
      g.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(g.active, isFalse);
      expect(g.path, isNull);
    });
  });

  group('UpdateService.download cleans the dir first', () {
    const r = ReleaseInfo(
      tag: 'v0.3.0',
      version: '0.3.0',
      notes: '',
      pageUrl: 'x',
      apkUrl: 'https://dl/watchdog-0.3.0-arm64.apk',
      apkName: 'watchdog-0.3.0-arm64.apk',
      apkSize: 3,
    );
    http.Client client() => MockClient.streaming(
      (req, _) async =>
          http.StreamedResponse(Stream.value([1, 2, 3]), 200, contentLength: 3),
    );

    test('old APKs go, installing one stays', () async {
      mk('watchdog-0.1.0-arm64.apk');
      final installing = mk('watchdog-0.2.0-arm64.apk');
      final g = InstallGuard()..begin(installing.path);
      final s = UpdateService(client: client(), guard: g);
      final f = await s.download(r, dir);
      g.end();
      expect(f.path.endsWith('watchdog-0.3.0-arm64.apk'), isTrue);
      expect(left(), ['watchdog-0.2.0-arm64.apk', 'watchdog-0.3.0-arm64.apk']);
    });

    test('a verified earlier download of the same release is reused', () async {
      mk('watchdog-0.3.0-arm64.apk');
      mk('watchdog-0.2.0-arm64.apk');
      var calls = 0;
      final c = MockClient.streaming((req, _) async {
        calls++;
        return http.StreamedResponse(Stream.value([1, 2, 3]), 200);
      });
      await UpdateService(client: c).download(r, dir);
      expect(calls, 0);
      expect(left(), ['watchdog-0.3.0-arm64.apk']);
    });
  });
}
