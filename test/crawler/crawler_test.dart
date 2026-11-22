import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/crawler.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/data/models.dart';

import 'fakes.dart';

const fast = CrawlOptions(
  backoffBase: Duration.zero,
  probeTimeout: Duration(milliseconds: 50),
  progressInterval: Duration.zero,
);

class Result {
  Result(this.items, this.summary, this.progress);
  final List<CrawlItem> items;
  final CrawlSummary summary;
  final List<CrawlProgress> progress;
  List<TitleDraft> get titles => [
    for (final i in items.whereType<TitleItem>()) i.draft,
  ];
  List<String> get unchanged => [
    for (final i in items.whereType<UnchangedItem>()) i.folderUrl,
  ];
}

Future<Result> crawl(
  FakeListingClient fake, {
  CrawlOptions options = fast,
  Map<String, DateTime> known = const {},
  CancelToken? cancel,
  void Function(CrawlRun run)? onStart,
}) async {
  final run = Crawler(
    fake,
    options: options,
  ).start(fake.config(), known: known, cancel: cancel);
  onStart?.call(run);
  final itemsF = run.items.toList();
  final progress = <CrawlProgress>[];
  final progressDone = Completer<void>();
  run.progress.listen(progress.add, onDone: progressDone.complete);
  final summary = await run.done.timeout(const Duration(seconds: 10));
  final items = await itemsF.timeout(const Duration(seconds: 2));
  await progressDone.future.timeout(const Duration(seconds: 2));
  return Result(items, summary, progress);
}

void main() {
  test('full crawl yields drafts for every fixture category', () async {
    final fake = FakeListingClient.fromFixtures();
    final r = await crawl(fake);
    expect(r.summary.complete, isTrue, reason: '${r.summary.issues}');
    expect(r.titles.length, 4 + 2 + 1 + 3 + 1);
    expect(r.summary.results.length, 5);
    expect(r.summary.results.every((c) => c.complete), isTrue);
    final kinds = {for (final t in r.titles) t.kind};
    expect(kinds, TitleKind.values.toSet());
    // Sample/Subs/scoped_dir folders are never requested.
    expect(fake.requests.where((u) => u.contains('scoped_dir')), isEmpty);
    expect(fake.requests.where((u) => u.contains('/Subs/')), isEmpty);
    // Category id default: index in config order.
    expect(r.titles.first.categoryId, 0);
  });

  test(
    'large listings are parsed off-isolate with identical results',
    () async {
      final a = await crawl(FakeListingClient.fromFixtures());
      final b = await crawl(
        FakeListingClient.fromFixtures(),
        options: const CrawlOptions(
          backoffBase: Duration.zero,
          probeTimeout: Duration(milliseconds: 50),
          parseOffloadBytes: 0,
        ),
      );
      expect(b.summary.complete, isTrue);
      expect(
        b.titles.map((t) => t.folderUrl).toSet(),
        a.titles.map((t) => t.folderUrl).toSet(),
      );
    },
  );

  test('categoryIdFor is used', () async {
    final fake = FakeListingClient.fromFixtures();
    final run = Crawler(
      fake,
      options: fast,
    ).start(fake.config(), categoryIdFor: (c) => c.name.length);
    final items = await run.items.toList();
    final english = items.whereType<TitleItem>().firstWhere(
      (i) => i.category.name == 'English Movies',
    );
    expect(english.draft.categoryId, 'English Movies'.length);
    expect(english.category.sourceHost, '172.16.50.7');
    expect(english.category.language, 'english');
  });

  test('progress stream reports counters and ends finished', () async {
    final fake = FakeListingClient.fromFixtures();
    final r = await crawl(fake);
    expect(r.progress, isNotEmpty);
    final last = r.progress.last;
    expect(last.finished, isTrue);
    expect(last.titlesFound, r.titles.length);
    expect(last.foldersFetched, r.summary.foldersFetched);
    expect(last.errors, 0);
    expect(
      r.progress.map((p) => p.foldersFetched),
      orderedEquals([...r.progress.map((p) => p.foldersFetched)]..sort()),
    );
  });

  test('concurrency never exceeds the bound', () async {
    final fake = FakeListingClient.fromFixtures()
      ..latency = const Duration(milliseconds: 5);
    final r = await crawl(
      fake,
      options: const CrawlOptions(concurrency: 2, backoffBase: Duration.zero),
    );
    expect(r.summary.complete, isTrue);
    // 3 host probes run before the walk (outside the pool); walking is capped at 2.
    expect(fake.maxInFlight, 3);
    final seq = FakeListingClient.fromFixtures()
      ..latency = const Duration(milliseconds: 1);
    final r1 = await crawl(
      seq,
      options: const CrawlOptions(concurrency: 1, backoffBase: Duration.zero),
    );
    expect(r1.titles.length, r.titles.length);
    expect(seq.maxInFlight, 3); // probes only
  });

  group('retries', () {
    test('transient failures are retried with success', () async {
      final fake = FakeListingClient.fromFixtures();
      final url = fake.roots['English Movies']!;
      fake.failures[url] = [
        FetchException(Uri.parse(url), FetchFailure.timeout, 'timed out'),
        FetchException(
          Uri.parse(url),
          FetchFailure.http,
          'HTTP 503',
          status: 503,
        ),
        FetchException(Uri.parse(url), FetchFailure.connect, 'reset'),
      ];
      final r = await crawl(fake);
      expect(r.summary.complete, isTrue);
      expect(r.progress.last.retries, 3);
      expect(fake.requests.where((u) => u == url).length, 4);
    });

    test(
      'gives up after 3 retries; category incomplete, others fine',
      () async {
        final fake = FakeListingClient.fromFixtures();
        final url = fake.roots['English Movies']!;
        fake.failures[url] = [
          for (var i = 0; i < 9; i++)
            FetchException(Uri.parse(url), FetchFailure.timeout, 'timed out'),
        ];
        final r = await crawl(fake);
        expect(fake.requests.where((u) => u == url).length, 4);
        expect(r.summary.complete, isFalse);
        final eng = r.summary.results.firstWhere(
          (c) => c.category.name == 'English Movies',
        );
        expect(eng.complete, isFalse);
        expect(r.summary.results.where((c) => c.complete).length, 4);
        expect(r.summary.issues.single.url, url);
        expect(r.titles.length, 2 + 1 + 3 + 1);
      },
    );

    test(
      '404 is not retried and marks only that category incomplete',
      () async {
        final fake = FakeListingClient.fromFixtures();
        final url = fake.roots['WWE & AEW']!;
        fake.pages.remove(url);
        final r = await crawl(fake);
        expect(fake.requests.where((u) => u == url).length, 1);
        expect(
          r.summary.results.where((c) => !c.complete).single.category.name,
          'WWE & AEW',
        );
      },
    );

    test(
      'a failing sub-folder marks the category incomplete but keeps the rest',
      () async {
        final fake = FakeListingClient.fromFixtures();
        final bad = fake.pages.keys.firstWhere((u) => u.contains('Cypher'));
        fake.pages.remove(bad);
        final r = await crawl(fake);
        final eng = r.summary.results.firstWhere(
          (c) => c.category.name == 'English Movies',
        );
        expect(eng.complete, isFalse);
        expect(eng.titles, 3);
      },
    );
  });

  group('off-BDIX', () {
    test('all hosts unreachable: fails fast with a clear message', () async {
      final fake = FakeListingClient.fromFixtures()
        ..downHosts.addAll(['172.16.50.7', '172.16.50.10', '172.16.50.14']);
      final sw = Stopwatch()..start();
      final r = await crawl(fake);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      expect(r.summary.offBdix, isTrue);
      expect(r.summary.failureMessage, contains('BDIX'));
      expect(r.summary.failureMessage, contains('172.16.50.7'));
      expect(r.titles, isEmpty);
      expect(r.summary.results.every((c) => !c.complete), isTrue);
      // Only the three probes went out.
      expect(fake.requests.length, 3);
      expect(r.summary.issues.every((i) => i.unreachable), isTrue);
    });

    test(
      'one host down: others still crawled, its categories incomplete',
      () async {
        final fake = FakeListingClient.fromFixtures()
          ..downHosts.add('172.16.50.7');
        final r = await crawl(fake);
        expect(r.summary.offBdix, isFalse);
        expect(r.summary.unreachableHosts, ['172.16.50.7']);
        expect(r.titles.length, 1 + 3 + 1);
        expect(r.summary.results.where((c) => !c.complete).length, 2);
        expect(r.summary.complete, isFalse);
      },
    );

    test(
      'host that stops answering mid-crawl is cut off, never hangs',
      () async {
        final fake = FakeListingClient.fromFixtures()
          ..flakyHosts.add('172.16.50.7');
        final r = await crawl(
          fake,
          options: const CrawlOptions(
            backoffBase: Duration.zero,
            probeTimeout: Duration(milliseconds: 50),
            deadHostAfter: 2,
          ),
        );
        expect(r.summary.unreachableHosts, isEmpty); // probe succeeded
        expect(r.summary.issues.any((i) => i.unreachable), isTrue);
        expect(r.summary.complete, isFalse);
        // 2 roots x 4 attempts at most before the breaker stops requests.
        expect(
          fake.requests.where((u) => u.contains('172.16.50.7/DHAKA')).length,
          lessThanOrEqualTo(8),
        );
      },
    );
  });

  test('cancel stops the crawl and marks categories incomplete', () async {
    final fake = FakeListingClient.fromFixtures()
      ..latency = const Duration(milliseconds: 5);
    final cancel = CancelToken();
    final r = await crawl(
      fake,
      cancel: cancel,
      onStart: (run) => Timer(const Duration(milliseconds: 12), run.cancel),
    );
    expect(r.summary.cancelled, isTrue);
    expect(r.summary.complete, isFalse);
    expect(r.titles.length, lessThan(11));
    expect(r.progress.last.finished, isTrue);
  });

  group('incremental', () {
    test(
      'known mtimes skip unchanged titles; changed ones are recrawled',
      () async {
        final fake = FakeListingClient.fromFixtures();
        final first = await crawl(fake);
        final known = {
          for (final t in first.titles)
            if (t.folderMtime != null) t.folderUrl: t.folderMtime!,
        };
        expect(known.length, first.titles.length);

        // Make one movie look changed and one show look changed.
        final movie = first.titles.firstWhere((t) => t.name == 'Cypher');
        final show = first.titles.firstWhere(
          (t) => t.name == 'Bubblegum Crisis',
        );
        known[movie.folderUrl] = DateTime(2000);
        known[show.folderUrl] = DateTime(2000);

        final fake2 = FakeListingClient.fromFixtures();
        final second = await crawl(fake2, known: known);
        expect(second.titles.map((t) => t.name).toSet(), {
          'Cypher',
          'Bubblegum Crisis',
        });
        expect(second.unchanged.length, first.titles.length - 2);
        expect(second.summary.complete, isTrue);
        expect(
          second.summary.results.fold<int>(0, (a, c) => a + c.unchanged),
          second.unchanged.length,
        );
        // Unchanged movie folders cost no request at all.
        final unchangedMovie = first.titles.firstWhere(
          (t) => t.name == '12 Angry Men',
        );
        expect(fake2.requests, isNot(contains(unchangedMovie.folderUrl)));
        // Unchanged shows cost only their own listing, not their seasons.
        final unchangedShow = first.titles.firstWhere(
          (t) => t.name == 'Captain Tsubasa',
        );
        expect(fake2.requests, contains(unchangedShow.folderUrl));
        expect(
          fake2.requests.where(
            (u) =>
                u.startsWith(unchangedShow.folderUrl) &&
                u != unchangedShow.folderUrl,
          ),
          isEmpty,
        );
        expect(fake2.requests.length, lessThan(fake.requests.length));
      },
    );

    test('empty known map = full crawl', () async {
      final fake = FakeListingClient.fromFixtures();
      final r = await crawl(fake, known: const {});
      expect(r.unchanged, isEmpty);
    });
  });

  group('empty listings', () {
    final emptyPage =
        '<html><body><div id="fallback"><table></table></div></body></html>';

    test(
      'known title that re-lists empty is kept, flagged, category incomplete',
      () async {
        final fake = FakeListingClient.fromFixtures();
        final first = await crawl(fake);
        final known = {
          for (final t in first.titles)
            if (t.folderMtime != null) t.folderUrl: DateTime(2000),
        };
        final cypher = first.titles.firstWhere((t) => t.name == 'Cypher');
        final fake2 = FakeListingClient.fromFixtures();
        fake2.pages[cypher.folderUrl] = emptyPage;
        final r = await crawl(fake2, known: known);
        expect(r.unchanged, contains(cypher.folderUrl));
        expect(r.titles.map((t) => t.name), isNot(contains('Cypher')));
        expect(r.summary.issues.any((i) => i.url == cypher.folderUrl), isTrue);
        final eng = r.summary.results.firstWhere(
          (c) => c.category.name == 'English Movies',
        );
        expect(eng.complete, isFalse);
        // retried once before accepting
        expect(fake2.requests.where((u) => u == cypher.folderUrl).length, 2);
      },
    );

    test('transient empty page recovers on the retry', () async {
      final fake = FakeListingClient.fromFixtures();
      final first = await crawl(fake);
      final cypher = first.titles.firstWhere((t) => t.name == 'Cypher');
      final real = fake.pages[cypher.folderUrl]!;
      final fake2 = FakeListingClient.fromFixtures();
      var n = 0;
      fake2.pages[cypher.folderUrl] = real;
      fake2.pages[cypher.folderUrl] = emptyPage;
      final c = FlakyOnce(fake2, cypher.folderUrl, real);
      final run = Crawler(
        c,
        options: fast,
      ).start(fake2.config(), known: {cypher.folderUrl: DateTime(2000)});
      final items = await run.items.toList();
      final s = await run.done;
      n = items
          .whereType<TitleItem>()
          .where((i) => i.draft.name == 'Cypher')
          .length;
      expect(n, 1);
      expect(s.complete, isTrue);
    });

    test('unknown empty folder yields nothing and is not an error', () async {
      final fake = FakeListingClient.fromFixtures();
      final cypherUrl = fake.pages.keys.firstWhere((u) => u.contains('Cypher'));
      fake.pages[cypherUrl] = emptyPage;
      final r = await crawl(fake);
      expect(r.titles.map((t) => t.name), isNot(contains('Cypher')));
      expect(r.summary.issues, isEmpty);
      expect(r.summary.complete, isTrue);
    });
  });
}

/// Serves an empty page for [url] on its first request, the real one after.
class FlakyOnce implements ListingClient {
  FlakyOnce(this.inner, this.url, this.real);
  final FakeListingClient inner;
  final String url;
  final String real;
  bool served = false;
  @override
  Future<String> fetch(Uri u, {required Duration timeout}) {
    if (u.toString() == url && !served) {
      served = true;
      return inner.fetch(u, timeout: timeout);
    }
    if (u.toString() == url) {
      inner.pages[url] = real;
    }
    return inner.fetch(u, timeout: timeout);
  }

  @override
  void close() {}
}
