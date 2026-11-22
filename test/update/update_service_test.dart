import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/features/update/release.dart';
import 'package:watchdog/features/update/update_service.dart';

void main() {
  final bytes = List<int>.generate(5000, (i) => i % 251);
  final good = sha256.convert(bytes).toString();

  ReleaseInfo release({String? sha, int? size}) => ReleaseInfo(
    tag: 'v0.2.0',
    version: '0.2.0',
    notes: '',
    pageUrl: 'p',
    apkUrl: 'https://dl.example/watchdog.apk',
    apkName: 'watchdog-arm64.apk',
    apkSize: size ?? bytes.length,
    sha256: sha ?? good,
  );

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('upd'));
  tearDown(() => dir.deleteSync(recursive: true));

  String releasesJson(String tag) => jsonEncode([
    {
      'tag_name': tag,
      'prerelease': true,
      'body': 'hi',
      'html_url': 'u',
      'assets': [
        {'name': 'a-arm64.apk', 'browser_download_url': 'd', 'size': 1},
      ],
    },
  ]);

  group('check', () {
    test('newer release is returned; sends a generic user agent', () async {
      late http.Request seen;
      final s = UpdateService(
        client: MockClient((r) async {
          seen = r;
          return http.Response(releasesJson('v0.2.0'), 200);
        }),
      );
      final r = await s.check(currentVersion: '0.1.0+1');
      expect(r?.tag, 'v0.2.0');
      expect(seen.url.host, 'api.github.com');
      expect(seen.url.path, '/repos/mahmudulHmanik/watchdog/releases');
      expect(seen.headers['User-Agent'], 'watchdog-updater');
    });

    test('same version -> null', () async {
      final s = UpdateService(
        client: MockClient(
          (_) async => http.Response(releasesJson('v0.1.0'), 200),
        ),
      );
      expect(await s.check(currentVersion: '0.1.0+1'), isNull);
    });

    test('rate limit, server error, bad json, offline', () async {
      Future<Object?> run(http.Client c) async {
        try {
          await UpdateService(client: c).check(currentVersion: '0.1.0');
          return null;
        } on UpdateException catch (e) {
          return e.message;
        }
      }

      expect(
        await run(MockClient((_) async => http.Response('', 403))),
        contains('rate limit'),
      );
      expect(
        await run(MockClient((_) async => http.Response('', 500))),
        contains('500'),
      );
      expect(
        await run(MockClient((_) async => http.Response('<html>', 200))),
        contains('Unreadable'),
      );
      expect(
        await run(MockClient((_) async => throw const SocketException('x'))),
        contains('Cannot reach'),
      );
    });
  });

  group('download', () {
    http.Client serve(List<int> body, {int status = 200}) =>
        MockClient.streaming(
          (req, _) async => http.StreamedResponse(
            Stream.fromIterable([body.sublist(0, 2000), body.sublist(2000)]),
            status,
            contentLength: body.length,
          ),
        );

    test('writes the apk, reports progress, verifies sha', () async {
      final seen = <int>[];
      final f = await UpdateService(client: serve(bytes))
          .download(release(), dir, onProgress: (g, t) => seen.add(g));
      expect(f.readAsBytesSync(), bytes);
      expect(f.path, endsWith('watchdog-arm64.apk'));
      expect(seen.last, bytes.length);
      expect(File('${f.path}.part').existsSync(), isFalse);
    });

    test('checksum mismatch deletes the file and throws', () async {
      await expectLater(
        UpdateService(client: serve(bytes)).download(release(sha: 'bad'), dir),
        throwsA(isA<UpdateException>()),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('size mismatch throws', () async {
      await expectLater(
        UpdateService(client: serve(bytes)).download(release(size: 10), dir),
        throwsA(isA<UpdateException>()),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('HTTP error', () async {
      await expectLater(
        UpdateService(client: serve(bytes, status: 404))
            .download(release(), dir),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'msg',
            contains('404'),
          ),
        ),
      );
    });

    test('cancel removes the partial file', () async {
      final c = CancelToken();
      await expectLater(
        UpdateService(
          client: serve(bytes),
        ).download(release(), dir, cancel: c, onProgress: (_, _) => c.cancel()),
        throwsA(
          isA<UpdateException>().having((e) => e.message, 'msg', 'Cancelled'),
        ),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('a verified earlier download is reused without a request', () async {
      var calls = 0;
      final s = UpdateService(
        client: MockClient.streaming((req, _) async {
          calls++;
          return http.StreamedResponse(Stream.value(bytes), 200);
        }),
      );
      await s.download(release(), dir);
      expect(calls, 1);
      await s.download(release(), dir);
      expect(calls, 1);
    });

    test('no apk attached', () async {
      const r = ReleaseInfo(tag: 'v1', version: '1', notes: '', pageUrl: 'p');
      await expectLater(
        UpdateService(client: serve(bytes)).download(r, dir),
        throwsA(isA<UpdateException>()),
      );
    });
  });
}
