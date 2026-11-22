import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/host_limiter.dart';
import 'package:watchdog/crawler/listing_client.dart';

import 'api_fakes.dart';

const _year = '/DHAKA-FLIX-7/English%20Movies/%282020%29/';
final _yearUrl = Uri.parse('http://172.16.50.7$_year');

H5aiApiClient _client(
  FakeApi f, {
  HostLimiters? limiters,
  int offload = 1 << 30,
}) => H5aiApiClient(
  client: f.client,
  limiters: limiters,
  backoffBase: Duration.zero,
  decodeOffloadBytes: offload,
);

void main() {
  group('probe / capability', () {
    test('what=0 answer with items -> supported, cached per run', () async {
      final f = FakeApi.fixtures({'/|0': 'probe_what0.json'});
      final c = _client(f);
      expect(await c.supportsApi('172.16.50.7'), isTrue);
      expect(await c.supportsApi('172.16.50.7'), isTrue);
      expect(f.calls, [('/', 0)]); // one request for two questions
      expect((await c.probe('172.16.50.7')).supported, isTrue);
    });

    test(
      '404, HTML page, timeout, down host -> false (never throws)',
      () async {
        Future<ApiProbe> p(
          http.Client cl, {
          Duration t = const Duration(seconds: 1),
        }) => H5aiApiClient(client: cl, probeTimeout: t).probe('h');
        final r404 = await p(
          MockClient((_) async => http.Response('nope', 404)),
        );
        expect(r404.supported, isFalse);
        expect(r404.reason, ApiFailure.unsupported);
        final html = await p(
          MockClient((_) async => http.Response('<html>', 200)),
        );
        expect(html.supported, isFalse);
        final wrong = await p(
          MockClient((_) async => http.Response('{"error":1}', 200)),
        );
        expect(wrong.supported, isFalse);
        final slow = await p(
          MockClient((_) => Completer<http.Response>().future),
          t: const Duration(milliseconds: 20),
        );
        expect(slow.supported, isFalse);
        expect(slow.reason, ApiFailure.timeout);
        final down = await p(
          MockClient((_) async => throw http.ClientException('no route')),
        );
        expect(down.supported, isFalse);
        expect(down.reason, ApiFailure.connect);
      },
    );

    test('markUnsupported / forgetProbe', () async {
      final f = FakeApi.fixtures({'/|0': 'probe_what0.json'});
      final c = _client(f);
      c.markUnsupported('h', 'bad answers');
      expect(await c.supportsApi('h'), isFalse);
      c.forgetProbe('h');
      expect(await c.supportsApi('h'), isTrue);
    });
  });

  group('getFolder', () {
    final api = FakeApi.fixtures({'$_year|2': 'year_2020_what2.json'});

    test('rebuilds children + grandchildren from the flat answer', () async {
      final c = _client(api);
      final folder = await c.getFolder(_yearUrl);
      expect(folder.href, _year);
      expect(folder.name, '(2020)');
      expect(folder.isListed, isTrue);
      expect(folder.children!.length, 11);
      final t = folder.children!.first;
      expect(t.name, '1 Interrogation (2020) 720p WEBRip'); // decoded
      expect(t.href, startsWith(_year)); // as served, encoded
      expect(t.href, contains('%20'));
      expect(t.isFolder, isTrue);
      expect(t.isListed, isTrue); // grandchildren present
      final mkv = t.files.firstWhere((f) => f.name.endsWith('.mkv'));
      expect(mkv.size, 835532406); // bytes
      expect(mkv.isFolder, isFalse);
      expect(mkv.children, isNull);
      // ancestors' siblings were dropped
      expect(folder.children!.any((x) => x.href.contains('3D')), isFalse);
    });

    test('request body: encoded href, what, POST JSON', () async {
      late http.Request seen;
      final c = H5aiApiClient(
        client: MockClient((r) async {
          seen = r;
          return http.Response.bytes(fixtureBytes('year_2020_what2.json'), 200);
        }),
      );
      await c.getFolder(
        Uri.parse(
          'http://172.16.50.7/DHAKA-FLIX-7/English%20Movies/%282020%29',
        ),
      ); // missing trailing slash is added
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://172.16.50.7/_h5ai/public/index.php');
      expect(seen.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(seen.body), {
        'action': 'get',
        'items': {'href': _year, 'what': 2},
      });
    });

    test(
      'times are exact UTC; timeAsListing matches the HTML parser form',
      () async {
        final folder = await _client(api).getFolder(_yearUrl);
        final mkv = folder.children!.first.files.firstWhere(
          (f) => f.name.endsWith('.mkv'),
        );
        expect(mkv.time!.isUtc, isTrue);
        expect(mkv.time, DateTime.utc(2020, 11, 17, 2, 57, 58));
        // The HTML listing shows "2020-11-17 02:57" for this file and the
        // listing parser reads it as a local DateTime.
        expect(mkv.timeAsListing, DateTime(2020, 11, 17, 2, 57));
      },
    );

    test('what is capped at 2', () async {
      final f = FakeApi.fixtures({'$_year|2': 'year_2020_what2.json'});
      await _client(f).getFolder(_yearUrl, what: 9);
      expect(f.calls.single.$2, 2);
    });

    test('what=1 lists children only (grandchildren unlisted)', () async {
      final f = FakeApi.fixtures({
        '/DHAKA-FLIX-7/English%20Movies/|1': 'english_root_what1.json',
      });
      final root = await _client(f).getFolder(
        Uri.parse('http://172.16.50.7/DHAKA-FLIX-7/English%20Movies/'),
        what: 1,
      );
      expect(root.children!.length, 8);
      expect(root.children!.every((c) => c.isFolder && !c.isListed), isTrue);
    });

    test('raw escaped slashes in real answers parse (probe fixture)', () async {
      final item = parseApiTree(
        fixtureBytes('probe_what0.json'),
        '/DHAKA-FLIX-7/English%20Movies/%282020%29/',
      );
      expect(item.href, '/DHAKA-FLIX-7/English%20Movies/%282020%29/');
      expect(item.children, isEmpty);
    });

    test('isolate decode gives the same tree', () async {
      final a = await _client(api).getFolder(_yearUrl);
      final b = await _client(api, offload: 0).getFolder(_yearUrl);
      String dump(ApiItem n) =>
          '${n.href}|${n.time}|${n.size}|[${(n.children ?? []).map(dump).join(',')}]';
      expect(dump(b), dump(a));
    });

    test('encodeHref round-trips awkward names', () {
      const names = [
        'Tom & Jerry (1940)',
        '100% Wolf',
        "It's #1 [HD]",
        'Star ★',
      ];
      final h = encodeHref(['DHAKA-FLIX-7', ...names]);
      expect(h.startsWith('/DHAKA-FLIX-7/'), isTrue);
      expect(h.contains(' '), isFalse);
      expect(h.contains('&'), isFalse);
      expect(h.contains('#'), isFalse);
      expect(Uri.decodeComponent(h), '/DHAKA-FLIX-7/${names.join('/')}/');
      expect(encodeHref(['a', 'b.mkv'], folder: false), '/a/b.mkv');
    });
  });

  group('errors and retries', () {
    test('5xx retried then succeeds; 404 not retried and typed', () async {
      var n = 0;
      final flaky = H5aiApiClient(
        client: MockClient((r) async {
          n++;
          if (n < 3) return http.Response('busy', 503);
          return http.Response.bytes(fixtureBytes('year_2020_what2.json'), 200);
        }),
        backoffBase: Duration.zero,
      );
      expect((await flaky.getFolder(_yearUrl)).children, isNotEmpty);
      expect(n, 3);
      expect(flaky.requests, 3);

      var m = 0;
      final gone = H5aiApiClient(
        client: MockClient((r) async {
          m++;
          return http.Response('', 404);
        }),
        backoffBase: Duration.zero,
      );
      final e = await gone
          .getFolder(_yearUrl)
          .then<ApiException?>(
            (_) => null,
            onError: (Object e) => e as ApiException,
          );
      expect(e!.reason, ApiFailure.unsupported);
      expect(e.status, 404);
      expect(e.retryable, isFalse);
      expect(m, 1);
    });

    test('gives up after retries; timeout is typed and retryable', () async {
      var n = 0;
      final c = H5aiApiClient(
        client: MockClient((r) {
          n++;
          return Completer<http.Response>().future;
        }),
        timeout: const Duration(milliseconds: 10),
        retries: 2,
        backoffBase: Duration.zero,
      );
      final e = await c
          .getFolder(_yearUrl)
          .then<ApiException?>(
            (_) => null,
            onError: (Object e) => e as ApiException,
          );
      expect(e!.reason, ApiFailure.timeout);
      expect(e.kind, FetchFailure.timeout);
      expect(e.noAnswer, isTrue);
      expect(n, 3);
    });

    test('bad body and missing folder are typed', () async {
      Future<ApiException> err(String body) {
        final c = H5aiApiClient(
          client: MockClient((r) async => http.Response(body, 200)),
        );
        return c
            .getFolder(_yearUrl)
            .then<ApiException>(
              (_) => throw StateError('should fail'),
              onError: (Object e) => e as ApiException,
            );
      }

      expect((await err('<html>')).reason, ApiFailure.badResponse);
      expect((await err('{"items":"x"}')).reason, ApiFailure.badResponse);
      expect((await err('{"items":[1]}')).reason, ApiFailure.badResponse);
      expect((await err('{"items":[]}')).reason, ApiFailure.notFound);
      expect(
        (await err('{"items":[{"href":"/other/","fetched":true}]}')).reason,
        ApiFailure.notFound,
      );
    });
  });

  test('requests honour the shared per-host limiter', () async {
    final f = FakeApi.fixtures({'$_year|2': 'year_2020_what2.json'})
      ..latency = const Duration(milliseconds: 5);
    final lims = HostLimiters(start: 3, min: 3, max: 3);
    final c = _client(f, limiters: lims);
    await Future.wait([for (var i = 0; i < 20; i++) c.getFolder(_yearUrl)]);
    expect(f.maxInFlight, 3);
    expect(f.calls.length, 20);
  });
}
