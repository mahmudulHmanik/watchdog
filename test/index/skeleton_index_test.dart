// Index service on the h5ai API path (fixtures only, no network): mapping,
// batching, priorities, fallbacks, resume, incremental runs, cancel.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/crawler.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/index/index_meta.dart';
import 'package:watchdog/features/index/index_service.dart';

import '../crawler/api_fakes.dart';
import '../crawler/fakes.dart';

const fastOpts = CrawlOptions(
  backoffBase: Duration.zero,
  probeTimeout: Duration(milliseconds: 50),
);

/// Counts calls / sizes of batches and can fail the Nth write.
class RecRepo extends DriftRepository {
  RecRepo({this.failOn = -1}) : super.memory();
  final int failOn;
  final batches = <int>[];
  final times = <Duration>[];
  final removed = <int>[];
  int compacts = 0;
  final clock = Stopwatch()..start();
  @override
  Future<void> upsertTitles(List<TitleDraft> drafts) {
    if (batches.length + 1 == failOn) {
      batches.add(-1);
      throw StateError('disk full');
    }
    batches.add(drafts.length);
    times.add(clock.elapsed);
    return super.upsertTitles(drafts);
  }

  @override
  Future<int> removeMissing(int categoryId, Set<String> keep) async {
    final n = await super.removeMissing(categoryId, keep);
    removed.add(n);
    return n;
  }

  @override
  Future<void> compact() {
    compacts++;
    return super.compact();
  }
}

class SwitchClient extends http.BaseClient {
  SwitchClient(this.current);
  FakeApi current;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      current.client.send(request);
}

class Rig {
  Rig({
    RecRepo? repo,
    IndexMetaStore? meta,
    int batch = 200,
    int categoryParallel = 2,
    int crawlParallel = 6,
    Duration maxBatchDelay = const Duration(milliseconds: 250),
    FakeListingClient? html,
    CrawlConfig? config,
    bool withApi = true,
  }) : repo = repo ?? RecRepo(),
       meta = meta ?? MemoryIndexMeta(),
       html = html ?? FakeListingClient.fromFixtures() {
    pages = Map.of(this.html.pages);
    cfg = config ?? this.html.config().migrated();
    server = _server();
    sw = SwitchClient(server);
    api = H5aiApiClient(
      client: sw,
      backoffBase: Duration.zero,
      probeTimeout: const Duration(milliseconds: 200),
    );
    service = IndexService(
      repository: this.repo,
      client: this.html,
      api: withApi ? api : null,
      configOf: () => cfg,
      meta: this.meta,
      options: fastOpts,
      batchSize: batch,
      categoryParallel: categoryParallel,
      crawlParallel: crawlParallel,
      maxBatchDelay: maxBatchDelay,
      progressInterval: const Duration(milliseconds: 20),
      changeThrottle: const Duration(milliseconds: 30),
      now: () => DateTime.utc(2026, 11, 22),
    );
  }

  final RecRepo repo;
  final IndexMetaStore meta;
  final FakeListingClient html;
  late final Map<String, String> pages;
  late CrawlConfig cfg;
  late FakeApi server;
  late final SwitchClient sw;
  late final H5aiApiClient api;
  late final IndexService service;

  /// API paths answered with 404 (-> unsupported), hosts that never answer,
  /// hosts without an API at all.
  final notFound = <String>{};
  final serverError = <String>{};
  final hostsDown = <String>{};
  final noApiHosts = <String>{};
  Duration latency = Duration.zero;

  FakeApi _server() {
    final base = FakeApi.fromPages(pages);
    final s = FakeApi((req, href, what) {
      if (hostsDown.contains(req.url.host)) {
        throw const SocketException('no route to host');
      }
      if (noApiHosts.contains(req.url.host)) {
        return http.Response('not found', 404);
      }
      if (what > 0 && notFound.any(href.startsWith)) {
        return http.Response('not found', 404);
      }
      if (what > 0 && serverError.any(href.startsWith)) {
        return http.Response('boom', 500);
      }
      return base.handler(req, href, what);
    });
    s.latency = latency;
    return s;
  }

  /// Re-reads [pages] (after the test edited them) into a new fake server.
  void republish() {
    server = _server();
    sw.current = server;
  }

  List<String> callsUnder(String path) => [
    for (final (h, w) in server.calls)
      if (h.startsWith(path)) '$h|$w',
  ];

  Future<Set<String>> titleNames() async => {
    for (final t in await repo.browse(const BrowseFilter(), limit: 1000))
      t.name,
  };

  Future<MediaTitle> titleNamed(String n) async => (await repo.browse(
    const BrowseFilter(),
    limit: 1000,
  )).firstWhere((t) => t.name == n);
}

const en = '/DHAKA-FLIX-7/English%20Movies/';
const fo = '/DHAKA-FLIX-7/Foreign%20Language%20Movies/';
const ko = '/DHAKA-FLIX-14/KOREAN%20TV%20%26%20WEB%20Series/';
const an = '/DHAKA-FLIX-10/Anime%20%26%20Cartoon%20TV%20Series/';
const ww = '/DHAKA-FLIX-10/WWE%20%26%20AEW%20Wrestling/';

String pageOf(FakeListingClient f, String contains) =>
    f.pages.keys.firstWhere((u) => u.contains(contains) && u.endsWith('/'));

final folderRow = RegExp(
  r'<tr><td class="fb-i"><img[^>]*alt="folder"/></td>.*?</tr>',
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('first run', () {
    test(
      'API crawl stores skeleton titles; the HTML crawler is not used',
      () async {
        final r = Rig();
        final res = await r.service.reindex();
        expect(res.outcome, IndexOutcome.success, reason: res.message);
        expect(res.titlesWritten, 11);
        expect((await r.repo.counts()).titles, 11);
        expect((await r.repo.categories()).length, 5);
        expect(r.html.requests, isEmpty);
        expect(await r.meta.lastIndexedAt(), DateTime.utc(2026, 11, 22));
        expect(r.repo.compacts, 1);
        expect(res.requests, r.server.calls.length);
        expect(res.bytes, greaterThan(0));
        // Same names as the HTML crawl produces for the same pages.
        final h = Rig(withApi: false);
        await h.service.reindex();
        expect(await r.titleNames(), await h.titleNames());

        final t = await r.titleNamed('Cypher');
        expect(t.filesLoaded, isFalse);
        expect(t.fileCount, greaterThan(0));
        expect(t.folderUrl, startsWith('http://172.16.50.7$en'));
        expect(t.year, 2002);
        final hc = await h.titleNamed('Cypher');
        expect(t.folderMtime, hc.folderMtime); // listing time semantics
        expect(t.fileCount, hc.fileCount);
        final series = await r.titleNamed('Monogatari-The Complete Series');
        expect(series.kind, TitleKind.series);
        expect((await r.repo.seasons(series.id)), isNotEmpty);
      },
    );

    test(
      'hasUsableData flips after the first committed batch; isFirstRun',
      () async {
        final r = Rig(batch: 1);
        r.server.latency = const Duration(milliseconds: 5);
        final states = <IndexState>[];
        r.service.states.listen(states.add);
        final f = r.service.reindex();
        await Future<void>.delayed(const Duration(milliseconds: 2));
        expect(r.service.state.hasUsableData, isFalse);
        expect(r.service.state.isFirstRun, isTrue);
        await f;
        final first = states.indexWhere((s) => s.hasUsableData);
        expect(first, greaterThan(0));
        expect(states[first].phase, IndexPhase.crawling);
        expect(states[first].titlesWritten, greaterThan(0));
        expect(states[first].titlesWritten, lessThan(11));
        expect(states.where((s) => s.isFirstRun).length, greaterThan(1));
        expect(r.service.state.isFirstRun, isFalse);
        expect(r.service.state.outcome, IndexOutcome.success);
        expect(r.service.state.titlesIndexed, 11);
        final res = await r.service.reindex();
        expect(res.firstBatchAfter, isNull); // nothing written
      },
    );

    test('result and state report timings, estimates and categories', () async {
      final r = Rig();
      final res = await r.service.reindex();
      expect(res.firstBatchAfter, isNotNull);
      expect(res.firstBatchAfter! <= res.elapsed, isTrue);
      final s = r.service.state;
      expect(s.categories.length, 5);
      expect(
        s.categories.every((c) => c.status == CategoryStatus.done),
        isTrue,
      );
      expect(s.categories.fold<int>(0, (a, c) => a + c.titles), 11);
      expect(s.estimatedTotal, 11);
      expect(s.progress, 1);
      expect(s.errors, 0);
      expect(s.elapsed, greaterThan(Duration.zero));
      final en = s.categories.firstWhere((c) => c.name == 'English Movies');
      expect(en.estimatedTotal, isNotNull);
      expect(en.host, '172.16.50.7');
    });

    test('commit cadence: batch size, and time based commits', () async {
      final a = Rig(batch: 3);
      await a.service.reindex();
      expect(a.repo.batches.every((n) => n <= 3), isTrue);
      expect(a.repo.batches.fold<int>(0, (x, y) => x + y), 11);

      // Large batch size but responses trickle in: a commit per burst.
      final b = Rig(
        batch: 1000,
        crawlParallel: 1,
        categoryParallel: 1,
        maxBatchDelay: const Duration(milliseconds: 5),
      );
      b.server.latency = const Duration(milliseconds: 40);
      final res = await b.service.reindex();
      expect(b.repo.batches.fold<int>(0, (x, y) => x + y), 11);
      expect(
        b.repo.batches.length,
        greaterThan(5),
        reason: '${b.repo.batches}',
      );
      // The first commit came long before the run ended.
      expect(
        res.firstBatchAfter!,
        lessThan(res.elapsed - const Duration(milliseconds: 60)),
      );
    });

    test('priority: year-bucket movies, then series, then events', () async {
      final base = Rig().cfg;
      // Reverse the .10 server's order (events first in the config).
      final s10 = base.servers.firstWhere((s) => s.host == '172.16.50.10');
      final r = Rig(
        categoryParallel: 1,
        config: CrawlConfig(
          servers: [
            for (final s in base.servers)
              s.host == s10.host
                  ? s.copyWith(categories: s.categories.reversed.toList())
                  : s,
          ],
        ),
      );
      expect(
        r.cfg.servers
            .firstWhere((s) => s.host == s10.host)
            .categories
            .first
            .kind,
        TitleKind.event,
      );
      await r.service.reindex();
      final firstIdx = {
        for (final p in [an, ww])
          p: r.server.calls.indexWhere((c) => c.$1.startsWith(p)),
      };
      expect(firstIdx[an]!, lessThan(firstIdx[ww]!));
      // English (buckets) before Foreign? both rank 0: config order holds.
      expect(
        r.server.calls.indexWhere((c) => c.$1.startsWith(en)),
        lessThan(r.server.calls.indexWhere((c) => c.$1.startsWith(fo))),
      );
    });

    test(
      'unsupported API on a host: its categories use the HTML crawler',
      () async {
        final r = Rig();
        r.noApiHosts.add('172.16.50.10');
        r.republish();
        final res = await r.service.reindex();
        expect(res.outcome, IndexOutcome.success, reason: res.message);
        expect((await r.repo.counts()).titles, 11);
        expect(
          r.html.requests.every((u) => u.contains('172.16.50.10')),
          isTrue,
        );
        expect(r.html.requests, isNotEmpty);
        final cs = {for (final c in r.service.state.categories) c.name: c};
        expect(cs['Anime & Cartoon']!.htmlFallback, isTrue);
        expect(cs['English Movies']!.htmlFallback, isFalse);
        // HTML fallback stores skeletons too.
        final t = await r.titleNamed('Monogatari-The Complete Series');
        expect(t.filesLoaded, isFalse);
        expect(t.fileCount, greaterThan(0));
      },
    );

    test(
      'API fails on one category: only that one falls back to HTML',
      () async {
        final r = Rig();
        r.notFound.add(an);
        r.republish();
        final res = await r.service.reindex();
        expect(res.outcome, IndexOutcome.success, reason: res.message);
        expect((await r.repo.counts()).titles, 11);
        expect(
          r.html.requests.every((u) => u.contains('172.16.50.10')),
          isTrue,
        );
        expect(r.html.requests, isNotEmpty);
        final cs = {for (final c in r.service.state.categories) c.name: c};
        expect(cs['Anime & Cartoon']!.htmlFallback, isTrue);
        expect(cs['WWE & AEW']!.htmlFallback, isFalse);
      },
    );

    test('no API client at all: everything via HTML', () async {
      final r = Rig(withApi: false);
      final res = await r.service.reindex();
      expect(res.outcome, IndexOutcome.success);
      expect(r.server.calls, isEmpty);
      expect((await r.repo.counts()).titles, 11);
    });

    test('off BDIX with the API: fast, nothing created', () async {
      final r = Rig();
      r.hostsDown.addAll(['172.16.50.7', '172.16.50.10', '172.16.50.14']);
      r.republish();
      final sw = Stopwatch()..start();
      final res = await r.service.reindex();
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      expect(res.outcome, IndexOutcome.offBdix);
      expect(res.message, contains('BDIX'));
      expect(r.service.state.offBdix, isTrue);
      expect(r.service.state.phase, IndexPhase.failed);
      expect(r.html.requests, isEmpty);
      expect(await r.repo.categories(), isEmpty);
      expect(await r.meta.lastIndexedAt(), isNull);
    });

    test(
      'one host down: others indexed, marker not set, titles untouched',
      () async {
        final r = Rig();
        await r.service.reindex();
        await r.meta.setLastIndexedAt(null);
        r.hostsDown.add('172.16.50.7');
        r.republish();
        final res = await r.service.reindex(full: true);
        expect(res.outcome, IndexOutcome.partial);
        expect(res.titlesRemoved, 0);
        expect((await r.repo.counts()).titles, 11);
        expect(await r.meta.lastIndexedAt(), isNull);
        expect(
          r.service.state.categories
              .where((c) => c.status == CategoryStatus.unreachable)
              .length,
          2,
        );
      },
    );

    test('probe results are not remembered between runs', () async {
      final r = Rig();
      r.hostsDown.addAll(['172.16.50.7', '172.16.50.10', '172.16.50.14']);
      r.republish();
      expect((await r.service.reindex()).outcome, IndexOutcome.offBdix);
      r.hostsDown.clear();
      r.republish();
      expect((await r.service.reindex()).outcome, IndexOutcome.success);
    });
  });

  group('resume', () {
    test(
      'killed mid-run: the second run finishes, no duplicates, no repeats',
      () async {
        final meta = MemoryIndexMeta();
        final repo1 = RecRepo(failOn: 4); // "kill" at the 4th commit
        final r1 = Rig(repo: repo1, meta: meta, categoryParallel: 1);
        final res1 = await r1.service.reindex();
        expect(res1.outcome, IndexOutcome.failed);
        expect(res1.message, contains('disk full'));
        expect(await meta.lastIndexedAt(), isNull); // not "indexed" yet
        final m1 = await meta.read();
        final doneUrls = [
          for (final e in m1.categories.entries)
            if (e.value.completedAt != null) e.key,
        ];
        expect(doneUrls, isNotEmpty);
        expect(doneUrls.length, lessThan(5));
        final before = (await repo1.counts()).titles;
        expect(before, lessThan(11));

        // New process: same database and meta, fresh service.
        final r2 = Rig(repo: repo1, meta: meta);
        final res2 = await r2.service.reindex();
        expect(res2.outcome, IndexOutcome.success, reason: res2.message);
        expect((await repo1.counts()).titles, 11);
        expect(await meta.lastIndexedAt(), DateTime.utc(2026, 11, 22));
        final skipped = r2.service.state.categories
            .where((c) => c.status == CategoryStatus.skipped)
            .map((c) => c.url)
            .toSet();
        expect(skipped, doneUrls.toSet());
        // Finished categories were not requested again.
        for (final u in doneUrls) {
          expect(r2.callsUnder(Uri.parse(u).path), isEmpty, reason: u);
        }
        // Rerun: no duplicates, everything unchanged.
        final res3 = await r2.service.reindex();
        expect(res3.titlesWritten, 0);
        expect((await repo1.counts()).titles, 11);
      },
    );

    test('state reports isFirstRun until every category completed', () async {
      final r = Rig();
      r.notFound.add(ww); // the WWE root fails (and so does the HTML retry)
      r.republish();
      r.html.pages.remove(r.html.roots['WWE & AEW']!);
      final res = await r.service.reindex();
      expect(res.outcome, IndexOutcome.partial);
      expect(await r.meta.lastIndexedAt(), isNull);
      expect(r.service.state.isFirstRun, isTrue);
      expect(r.service.state.hasUsableData, isTrue);
      expect((await r.repo.counts()).titles, 10);
      // A fresh service sees the unfinished first run from the stored meta.
      final again = Rig(repo: r.repo, meta: r.meta);
      final st = await again.service.loadStatus();
      expect(st.isFirstRun, isTrue);
      expect(st.hasUsableData, isTrue);
      expect(again.service.isRunning, isFalse);
    });

    test('a wiped index starts over even though the meta says done', () async {
      final r = Rig();
      await r.service.reindex();
      await r.repo.clearIndex();
      final res = await r.service.reindex();
      expect(res.outcome, IndexOutcome.success);
      expect((await r.repo.counts()).titles, 11);
      expect(
        r.service.state.categories.any(
          (c) => c.status == CategoryStatus.skipped,
        ),
        isFalse,
      );
    });
  });

  group('incremental', () {
    test('nothing changed: a few requests, nothing written', () async {
      final r = Rig();
      await r.service.reindex();
      final writes = r.repo.batches.length;
      r.server.calls.clear();
      final res = await r.service.reindex();
      expect(res.outcome, IndexOutcome.success, reason: res.message);
      expect(r.repo.batches.length, writes);
      expect(res.titlesWritten, 0);
      expect(res.titlesRemoved, 0);
      expect(res.titlesUnchanged, 11);
      expect(res.firstBatchAfter, isNull);
      // Bucketed categories: exactly the one probe each.
      expect(r.callsUnder(en), ['$en|2']);
      expect(r.callsUnder(fo), ['$fo|2']);
      expect(r.callsUnder(ww), ['$ww|2']);
      expect(r.repo.removed.where((n) => n > 0), isEmpty);
      expect(r.repo.compacts, 2);
      expect(res.requests, r.server.calls.length);
      // 3 host probes + 5 category roots + 2 anime buckets.
      expect(res.requests, 10, reason: '${r.server.calls}');
    });

    test(
      'a changed title is rewritten and keeps (staling) its loaded files',
      () async {
        final r = Rig();
        await r.service.reindex();
        final changed = await r.titleNamed('Cypher');
        final other = await r.titleNamed('12 Angry Men');
        for (final t in [changed, other]) {
          await r.repo.upsertTitleFiles(
            t.id,
            files: [
              FileDraft(
                name: 'x',
                url: '${t.folderUrl}film.mkv',
                ext: 'mkv',
                playable: true,
              ),
            ],
          );
        }
        final fileId = (await r.repo.titleFiles(changed.id)).single.id;
        await r.repo.setProgress(fileId, positionMs: 7, durationMs: 100);

        final p2002 = pageOf(r.html, '%282002%29');
        r.pages[p2002] = r.pages[p2002]!.replaceFirst(
          RegExp(r'<td class="fb-d">\d{4}[^<]*</td>'),
          '<td class="fb-d">2030-01-01 00:00</td>',
        );
        r.republish();
        final writes = r.repo.batches.length;
        final res = await r.service.reindex();
        expect(res.outcome, IndexOutcome.success, reason: res.message);
        expect(res.titlesWritten, 1);
        expect(r.repo.batches.length, writes + 1);
        expect(res.titlesUnchanged, 10);
        // Only the changed year bucket was read again (plus the probe).
        expect(r.callsUnder(en).toSet(), {
          '$en|2',
          '$en|1',
          '$en%282002%29/|2',
        });
        final after = await r.titleNamed('Cypher');
        expect(after.id, changed.id);
        expect(after.folderMtime, DateTime(2030));
        expect(await r.repo.titleFilesLoaded(changed.id), isFalse); // stale
        expect((await r.repo.titleFiles(changed.id)).single.id, fileId);
        expect((await r.repo.watchState(fileId))!.positionMs, 7);
        expect(await r.repo.titleFilesLoaded(other.id), isTrue);
      },
    );

    test(
      'a new title appears; a vanished one is removed (complete crawl)',
      () async {
        final r = Rig();
        await r.service.reindex();
        final p2010 = pageOf(r.html, '%282010%29');
        r.pages[p2010] = r.pages[p2010]!.replaceAll(folderRow, '');
        r.republish();
        final res = await r.service.reindex();
        expect(res.titlesRemoved, 1);
        expect(await r.titleNames(), isNot(contains('Going the Distance')));
        expect((await r.repo.counts()).titles, 10);
        expect(r.repo.removed.where((n) => n > 0), [1]);
      },
    );

    test('removeMissing only after a complete crawl of the category', () async {
      final r = Rig();
      await r.service.reindex();
      final before = await r.titleNames();
      await r.meta.setLastIndexedAt(DateTime.utc(2020));
      // A title vanished in 2010, but the 1999 bucket now fails to list.
      final p2010 = pageOf(r.html, '%282010%29');
      r.pages[p2010] = r.pages[p2010]!.replaceAll(folderRow, '');
      r.republish();
      r.serverError.add('$en%281999%29/');
      r.republish();
      // Force the bucket reads (signatures changed for 2010 only, so also
      // break the 2010 listing path to be sure the English crawl is partial).
      final res = await r.service.reindex(full: true);
      expect(res.outcome, IndexOutcome.partial);
      expect(res.titlesRemoved, 0);
      expect(await r.titleNames(), before);
      final c = r.service.state.categories.firstWhere(
        (c) => c.name == 'English Movies',
      );
      expect(c.status, CategoryStatus.failed);
      expect(c.errors, greaterThan(0));
      expect(await r.meta.lastIndexedAt(), DateTime.utc(2020)); // untouched
      // Other categories were processed normally.
      expect(
        r.service.state.categories
            .where((c) => c.status == CategoryStatus.done)
            .length,
        4,
      );
    });

    test(
      'shrunken or empty "complete" listing does not wipe a category',
      () async {
        final r = Rig();
        await r.service.reindex();
        // Every WWE event vanishes at once.
        final sub = pageOf(r.html, 'AEW%20Wrestling/');
        r.pages[sub] = r.pages[sub]!.replaceAll(folderRow, '');
        r.republish();
        final res = await r.service.reindex();
        expect(res.titlesRemoved, 0);
        expect((await r.repo.counts()).titles, 11);
      },
    );

    test('full re-crawl ignores stored times and signatures', () async {
      final r = Rig();
      await r.service.reindex();
      r.server.calls.clear();
      final res = await r.service.reindex(full: true);
      expect(res.titlesWritten, 11);
      expect(res.titlesUnchanged, 0);
      expect(r.callsUnder(en).length, greaterThan(2));
    });

    test('a series change is detected through its fingerprint', () async {
      final r = Rig();
      await r.service.reindex();
      // New time on the Season folder inside the Korean show.
      final show = pageOf(r.html, 'Arang');
      r.pages[show] = r.pages[show]!.replaceFirst(
        RegExp(r'<td class="fb-d">\d{4}[^<]*</td>'),
        '<td class="fb-d">2031-02-03 04:05</td>',
      );
      r.republish();
      final res = await r.service.reindex();
      expect(res.titlesWritten, 1);
      expect(res.titlesUnchanged, 10);
    });
  });

  group('control', () {
    test(
      'cancel(): outcome cancelled, nothing deleted, marker untouched',
      () async {
        final r = Rig(batch: 1);
        r.server.latency = const Duration(milliseconds: 10);
        final f = r.service.reindex();
        await Future<void>.delayed(const Duration(milliseconds: 35));
        r.service.cancel();
        final res = await f;
        expect(res.outcome, IndexOutcome.cancelled);
        expect(await r.meta.lastIndexedAt(), isNull);
        expect(r.service.isRunning, isFalse);
        final n = (await r.repo.counts()).titles;
        expect(n, lessThan(11));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect((await r.repo.counts()).titles, n); // nothing written afterwards
        // And it can be run again.
        final res2 = await r.service.reindex();
        expect(res2.outcome, IndexOutcome.success);
        expect((await r.repo.counts()).titles, 11);
      },
    );

    test('cancel through the token', () async {
      final r = Rig();
      r.server.latency = const Duration(milliseconds: 10);
      final t = CancelToken();
      Timer(const Duration(milliseconds: 25), t.cancel);
      final res = await r.service.reindex(cancel: t);
      expect(res.outcome, IndexOutcome.cancelled);
    });

    test('a write failure stops the run and deletes nothing', () async {
      final r = Rig(repo: RecRepo(failOn: 2));
      final res = await r.service.reindex();
      expect(res.outcome, IndexOutcome.failed);
      expect(res.titlesRemoved, 0);
      expect(await r.meta.lastIndexedAt(), isNull);
      expect(r.service.state.phase, IndexPhase.failed);
    });

    test('concurrent calls join one run', () async {
      final r = Rig();
      final a = r.service.reindex();
      final b = r.service.reindex();
      expect(identical(a, b), isTrue);
      await a;
    });

    test(
      'ensureIndexed: runs when unfinished, skips when fresh, force',
      () async {
        final r = Rig();
        final first = await r.service.ensureIndexed();
        expect(first.outcome, IndexOutcome.success);
        expect(r.server.calls, isNotEmpty);
        r.server.calls.clear();
        final second = await r.service.ensureIndexed();
        expect(second.message, 'Index is up to date.');
        expect(r.server.calls, isEmpty);
        expect(r.service.state.isFirstRun, isFalse);
        expect(r.service.state.hasUsableData, isTrue);
        final third = await r.service.ensureIndexed(force: true);
        expect(third.titlesWritten, 0);
        expect(r.server.calls, isNotEmpty);
      },
    );

    test('state events are throttled', () async {
      // 2000 titles in one answer.
      final items = <Map<String, Object?>>[
        {
          'href': '/',
          'time': 0,
          'size': null,
          'managed': false,
          'fetched': false,
        },
        {
          'href': '/C/',
          'time': 0,
          'size': null,
          'managed': true,
          'fetched': true,
        },
      ];
      for (var i = 0; i < 2000; i++) {
        items
          ..add({
            'href': '/C/T$i%20%282020%29/',
            'time': 1000 + i,
            'managed': true,
            'fetched': true,
          })
          ..add({'href': '/C/T$i%20%282020%29/a.mkv', 'time': 1, 'size': 5});
      }
      final body = {'items': items};
      final server = FakeApi(
        (req, href, what) => http.Response(jsonEncode(body), 200),
      );
      final repo = RecRepo();
      final api = H5aiApiClient(client: server.client);
      final svc = IndexService(
        repository: repo,
        client: FakeListingClient.fromFixtures(),
        api: api,
        configOf: () => CrawlConfig(
          servers: [
            ServerConfig(
              host: 'h',
              categories: [
                CategoryConfig(
                  name: 'C',
                  url: 'http://h/C/',
                  layout: LayoutKind.flat,
                  kind: TitleKind.movie,
                ),
              ],
            ),
          ],
        ),
        batchSize: 100,
        options: fastOpts,
      );
      var n = 0;
      svc.states.listen((_) => n++);
      final sw = Stopwatch()..start();
      final res = await svc.reindex();
      expect(res.titlesWritten, 2000);
      final perSecond = n / (sw.elapsedMilliseconds / 1000);
      expect(
        n,
        lessThan(25),
        reason: '$n states in ${sw.elapsedMilliseconds} ms',
      );
      expect(perSecond, lessThan(50));
      expect(repo.batches.length, 20);
    });
  });
}
