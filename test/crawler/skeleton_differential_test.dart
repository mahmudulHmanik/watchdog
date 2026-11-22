// The skeleton crawl (API, folder by folder) must agree with the existing
// full recursive HTML crawl on the same (fixture) server.
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/crawler.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/skeleton.dart';
import 'package:watchdog/crawler/skeleton_crawler.dart';
import 'package:watchdog/data/models.dart';

import 'api_fakes.dart';
import 'fakes.dart';

void main() {
  late FakeListingClient listing;
  late Map<String, TitleDraft> full; // folderUrl -> draft
  late Map<String, SkeletonTitle> skel;
  late Map<String, String> catOf; // folderUrl -> category name
  late FakeApi api;
  final summaries = <String, SkeletonSummary>{};

  setUpAll(() async {
    listing = FakeListingClient.fromFixtures();
    final cfg = listing.config();
    final run = Crawler(
      listing,
      options: const CrawlOptions(backoffBase: Duration.zero),
    ).start(cfg);
    full = {};
    await for (final i in run.items) {
      if (i is TitleItem) full[i.draft.folderUrl] = i.draft;
    }
    expect((await run.done).complete, isTrue);

    api = FakeApi.fromPages(listing.pages);
    final client = H5aiApiClient(
      client: api.client,
      backoffBase: Duration.zero,
    );
    final crawler = SkeletonCrawler(client);
    skel = {};
    catOf = {};
    for (final (s, c) in cfg.enabledCategories) {
      final r = crawler.crawlCategory(s.host, c);
      await for (final t in r.titles) {
        skel[t.folderUrl] = t;
        catOf[t.folderUrl] = c.name;
      }
      summaries[c.name] = await r.done;
    }
  });

  test('every category completes without issues', () {
    for (final e in summaries.entries) {
      expect(e.value.complete, isTrue, reason: '${e.key} ${e.value.issues}');
      expect(e.value.needsHtmlFallback, isFalse);
    }
  });

  test('same set of titles', () {
    expect(skel.keys.toSet(), full.keys.toSet());
    expect(skel.length, 11);
    expect(
      {for (final e in summaries.entries) e.key: e.value.titles}.values
          .fold<int>(0, (a, b) => a + b),
      11,
    );
  });

  test('names, years, quality, tags, kind, poster, mtime agree', () {
    for (final u in full.keys) {
      final d = full[u]!, s = skel[u]!;
      final why = 'for $u';
      expect(s.name, d.name, reason: why);
      expect(s.year, d.year, reason: why);
      expect(s.yearEnd, d.yearEnd, reason: why);
      expect(s.quality, d.quality, reason: why);
      expect(s.tags, d.tags, reason: why);
      expect(s.kind, d.kind, reason: why);
      expect(
        s.posterPath == null ? null : '${s.folderUrl}${s.posterPath}',
        d.posterUrl,
        reason: 'poster $why',
      );
      expect(s.fingerprintAsListing, d.folderMtime, reason: 'mtime $why');
    }
  });

  test('movie / event file counts agree (playable vs archive)', () {
    var n = 0;
    for (final d in full.values.where((d) => d.kind != TitleKind.series)) {
      final s = skel[d.folderUrl]!;
      expect(s.fileCount, d.files.where((f) => f.playable).length);
      expect(s.archiveCount, d.files.where((f) => !f.playable).length);
      n++;
    }
    expect(n, greaterThan(5));
  });

  test('series seasons: numbers, labels, languages; known counts agree', () {
    var shows = 0, known = 0;
    for (final d in full.values.where((d) => d.kind == TitleKind.series)) {
      final s = skel[d.folderUrl]!;
      expect(
        [
          for (final x in s.seasons)
            (x.number, x.label, x.language, x.folderUrl),
        ],
        [
          for (final x in d.seasons)
            (x.number, x.label, x.language, x.folderUrl),
        ],
        reason: d.folderUrl,
      );
      for (var i = 0; i < d.seasons.length; i++) {
        final c = s.seasons[i].episodeCount;
        if (c != null) {
          known++;
          expect(c, d.seasons[i].files.where((f) => f.playable).length);
        }
      }
      shows++;
    }
    expect(shows, greaterThan(3));
    expect(known, greaterThanOrEqualTo(0));
  });

  test('request count: skeleton uses few, only what=1/2 on small folders', () {
    expect(api.calls.every((c) => c.$2 == 1 || c.$2 == 2), isTrue);
    expect(api.calls.length, lessThan(listing.requests.length + 10));
  });

  test(
    'show listed with what=2: season episode counts agree where known',
    () async {
      final client = H5aiApiClient(
        client: api.client,
        backoffBase: Duration.zero,
      );
      var withCounts = 0, nested = 0;
      for (final d in full.values.where((d) => d.kind == TitleKind.series)) {
        final u = Uri.parse(d.folderUrl);
        final folder = await client.getFolder(u);
        final s = SkeletonClassifier(origin: 'http://${u.host}').show(folder)!;
        expect(s.seasons.length, d.seasons.length, reason: d.folderUrl);
        for (var i = 0; i < d.seasons.length; i++) {
          final c = s.seasons[i].episodeCount;
          if (c == null) {
            nested++;
          } else {
            withCounts++;
            expect(c, d.seasons[i].files.where((f) => f.playable).length);
          }
        }
      }
      expect(withCounts, greaterThan(0));
      expect(nested, greaterThan(0)); // Monogatari / Bubblegum: nested releases
    },
  );
}
