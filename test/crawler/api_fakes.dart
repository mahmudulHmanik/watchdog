import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/crawler/listing.dart';

import 'fakes.dart';

const apiFixtureDir = 'test/fixtures/crawl_api';

Uint8List fixtureBytes(String name) =>
    File('$apiFixtureDir/$name').readAsBytesSync();

/// A fake h5ai API host. Records every request as `(href, what)`.
class FakeApi {
  FakeApi(this.handler) {
    client = MockClient((req) async {
      final b = jsonDecode(req.body) as Map;
      final items = b['items'] as Map;
      final href = items['href'] as String;
      final what = items['what'] as int;
      calls.add((href, what));
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      try {
        if (latency > Duration.zero) await Future<void>.delayed(latency);
        return handler(req, href, what);
      } finally {
        inFlight--;
      }
    });
  }

  /// Serves saved real answers by `'$href|$what'`.
  factory FakeApi.fixtures(Map<String, String> byKey) =>
      FakeApi((req, href, what) {
        final f = byKey['$href|$what'];
        if (f == null) return http.Response('{"items":[]}', 200);
        return http.Response.bytes(
          fixtureBytes(f),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

  /// Serves the saved HTML pages (FakeListingClient fixtures) as API answers,
  /// so the full recursive crawl and the skeleton crawl see the same server.
  /// HTML wall-clock times are read as UTC, like the real servers.
  factory FakeApi.fromPages(Map<String, String> pages) {
    final entries = <String, List<Entry>>{
      for (final e in pages.entries)
        Uri.parse(e.key).path: parseListing(e.value),
    };
    Map<String, Object?> item(Entry e, String base, {required bool listed}) {
      final isDir = e.isDir;
      final m = e.modified;
      return {
        'href': Uri.parse(base).resolve(e.href).path,
        'time': m == null
            ? null
            : DateTime.utc(
                m.year,
                m.month,
                m.day,
                m.hour,
                m.minute,
              ).millisecondsSinceEpoch,
        'size': isDir ? null : (e.sizeKb ?? 0) * 1000,
        if (isDir) 'managed': true,
        if (isDir) 'fetched': listed,
      };
    }

    return FakeApi((req, href, what) {
      String norm(String h) => Uri.parse('http://x$h').path;
      final path = norm(href);
      final kids = entries[path];
      if (kids == null) return http.Response('{"items":[]}', 200);
      final out = <Map<String, Object?>>[
        {
          'href': '/',
          'time': 0,
          'size': null,
          'managed': false,
          'fetched': false,
        },
        {
          'href': path,
          'time': 0,
          'size': null,
          'managed': true,
          'fetched': true,
        },
      ];
      for (final k in kids) {
        final abs = Uri.parse('http://x$path').resolve(k.href).path;
        final listed = what >= 2 && entries.containsKey(abs);
        out.add(item(k, path, listed: listed));
        if (listed) {
          for (final g in entries[abs]!) {
            out.add(item(g, abs, listed: false));
          }
        }
      }
      for (final o in out) {
        o.removeWhere((k, v) => k == 'fetched' && v == null);
      }
      return http.Response(
        jsonEncode({'items': out}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  late final http.Client client;
  final calls = <(String, int)>[];
  Duration latency = Duration.zero;
  int inFlight = 0, maxInFlight = 0;
  final http.Response Function(http.Request, String href, int what) handler;
}

FakeListingClient listingFixtures() => FakeListingClient.fromFixtures();
