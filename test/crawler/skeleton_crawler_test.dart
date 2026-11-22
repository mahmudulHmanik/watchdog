import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/skeleton_crawler.dart';
import 'package:watchdog/data/models.dart';

import 'api_fakes.dart';

const _doc = '/DHAKA-FLIX-10/Documentary/';
final _docCat = CategoryConfig(
  name: 'Documentary',
  url: 'http://172.16.50.10$_doc',
  layout: LayoutKind.flat,
  kind: TitleKind.movie,
);

/// A synthetic folder with [n] one-file titles (rules/backpressure only).
http.Response _many(int n) {
  final items = <Map<String, Object?>>[
    {'href': '/', 'time': 0, 'size': null, 'managed': false, 'fetched': false},
    {'href': '/C/', 'time': 0, 'size': null, 'managed': true, 'fetched': true},
  ];
  for (var i = 0; i < n; i++) {
    items
      ..add({
        'href': '/C/T$i%20%282020%29/',
        'time': 1000 + i,
        'size': null,
        'managed': true,
        'fetched': true,
      })
      ..add({'href': '/C/T$i%20%282020%29/a.mkv', 'time': 1, 'size': 5});
  }
  return http.Response(jsonEncode({'items': items}), 200);
}

void main() {
  test(
    'flat category: titles stream, container left unfetched is an issue',
    () async {
      final api = FakeApi.fixtures({'$_doc|2': 'documentary_root_what2.json'});
      final c = SkeletonCrawler(
        H5aiApiClient(client: api.client, backoffBase: Duration.zero),
      );
      final run = c.crawlCategory('172.16.50.10', _docCat);
      final names = [await for (final t in run.titles) t.name];
      final s = await run.done;
      expect(names.length, 8);
      expect(s.titles, 8);
      // Europa's container needs a what=2 we have no fixture for -> not found.
      expect(api.calls.map((x) => x.$2).toSet(), {2});
      expect(api.calls.length, 2);
      expect(s.complete, isFalse);
      expect(s.issues.single.reason, ApiFailure.notFound);
      expect(s.needsHtmlFallback, isFalse);
      expect(s.requests, 2);
    },
  );

  test('year-bucket root is listed with what=1, years with what=2', () async {
    final api = FakeApi.fixtures({
      '/DHAKA-FLIX-7/English%20Movies/|1': 'english_root_what1.json',
    });
    final c = SkeletonCrawler(
      H5aiApiClient(client: api.client, backoffBase: Duration.zero),
    );
    final run = c.crawlCategory(
      '172.16.50.7',
      CategoryConfig(
        name: 'English',
        url: 'http://172.16.50.7/DHAKA-FLIX-7/English%20Movies/',
        layout: LayoutKind.yearBuckets,
        kind: TitleKind.movie,
      ),
    );
    final n = (await run.titles.toList()).length;
    final s = await run.done;
    expect(n, 0); // no fixtures for the 8 years: each answers "not found"
    expect(api.calls.first, ('/DHAKA-FLIX-7/English%20Movies/', 1));
    expect(api.calls.where((x) => x.$2 == 2).length, 8);
    expect(s.complete, isFalse);
    expect(s.issues.length, 8);
  });

  test('unsupported API -> issue + needsHtmlFallback', () async {
    final api = FakeApi((r, h, w) => http.Response('not found', 404));
    final c = SkeletonCrawler(
      H5aiApiClient(client: api.client, backoffBase: Duration.zero),
    );
    final run = c.crawlCategory('172.16.50.10', _docCat);
    expect(await run.titles.toList(), isEmpty);
    final s = await run.done;
    expect(s.complete, isFalse);
    expect(s.needsHtmlFallback, isTrue);
  });

  test('slow consumer: all titles arrive in order, nothing lost', () async {
    final api = FakeApi((r, h, w) => _many(300));
    final c = SkeletonCrawler(H5aiApiClient(client: api.client), buffer: 4);
    final run = c.crawlCategory(
      'h',
      CategoryConfig(
        name: 'C',
        url: 'http://h/C/',
        layout: LayoutKind.flat,
        kind: TitleKind.movie,
      ),
    );
    var n = 0;
    await for (final t in run.titles) {
      expect(t.name, 'T$n');
      if (n++ % 50 == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
    expect(n, 300);
    expect((await run.done).complete, isTrue);
  });

  test('consumer stops listening -> crawl ends, summary incomplete', () async {
    final api = FakeApi((r, h, w) => _many(300));
    final c = SkeletonCrawler(H5aiApiClient(client: api.client), buffer: 2);
    final run = c.crawlCategory(
      'h',
      CategoryConfig(
        name: 'C',
        url: 'http://h/C/',
        layout: LayoutKind.flat,
        kind: TitleKind.movie,
      ),
    );
    await run.titles.first;
    final s = await run.done.timeout(const Duration(seconds: 5));
    expect(s.complete, isFalse);
  });

  test('explicit cancel', () async {
    final api = FakeApi((r, h, w) => _many(300));
    final c = SkeletonCrawler(H5aiApiClient(client: api.client), buffer: 2);
    final run = c.crawlCategory(
      'h',
      CategoryConfig(
        name: 'C',
        url: 'http://h/C/',
        layout: LayoutKind.flat,
        kind: TitleKind.movie,
      ),
    );
    var n = 0;
    await for (final _ in run.titles) {
      if (++n == 3) run.cancel();
    }
    expect(n, lessThan(300));
    expect((await run.done).complete, isFalse);
  });

  test(
    'only: restricts the first level; onRoot sees the root answer',
    () async {
      final api = FakeApi.fixtures({
        '/DHAKA-FLIX-7/English%20Movies/|1': 'english_root_what1.json',
      });
      final c = SkeletonCrawler(
        H5aiApiClient(client: api.client, backoffBase: Duration.zero),
      );
      ApiItem? seen;
      final run = c.crawlCategory(
        '172.16.50.7',
        CategoryConfig(
          name: 'English',
          url: 'http://172.16.50.7/DHAKA-FLIX-7/English%20Movies/',
          layout: LayoutKind.yearBuckets,
          kind: TitleKind.movie,
        ),
        only: (h) => h.contains('1997'),
        onRoot: (r) => seen = r,
      );
      await run.titles.toList();
      await run.done;
      expect(seen, isNotNull);
      expect(seen!.folders.length, greaterThan(1));
      // Root (what=1) + only the accepted bucket (what=2).
      expect(api.calls.length, 2);
      expect(api.calls.last.$1, contains('1997'));
      expect(api.calls.last.$2, 2);
    },
  );
}
