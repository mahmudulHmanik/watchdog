import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/crawler.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/index/index_meta.dart';
import 'package:watchdog/features/index/index_service.dart';

import '../crawler/fakes.dart';

const fast = CrawlOptions(
  backoffBase: Duration.zero,
  probeTimeout: Duration(milliseconds: 50),
);

class FailingRepo extends DriftRepository {
  FailingRepo(this.failOnCall) : super.memory();
  final int failOnCall;
  int calls = 0;
  @override
  Future<void> upsertTitles(List<TitleDraft> drafts) {
    if (++calls == failOnCall) throw StateError('disk full');
    return super.upsertTitles(drafts);
  }
}

class Rig {
  Rig({DriftRepository? repo, int batch = 200, FakeListingClient? fake})
    : repo = repo ?? DriftRepository.memory(),
      fake = fake ?? FakeListingClient.fromFixtures() {
    meta = MemoryIndexMeta();
    service = IndexService(
      repository: this.repo,
      client: this.fake,
      configOf: () => this.fake.config(),
      meta: meta,
      options: fast,
      batchSize: batch,
      now: () => DateTime.utc(2026, 11, 22),
    );
  }
  final DriftRepository repo;
  final FakeListingClient fake;
  late final MemoryIndexMeta meta;
  late final IndexService service;

  Future<Set<String>> titleNames() async {
    final all = await repo.browse(const BrowseFilter(), limit: 1000);
    return {for (final t in all) t.name};
  }

  Future<MediaTitle> titleNamed(String n) async => (await repo.browse(
    const BrowseFilter(),
    limit: 1000,
  )).firstWhere((t) => t.name == n);
}

String pageOf(FakeListingClient f, String contains) =>
    f.pages.keys.firstWhere((u) => u.contains(contains) && u.endsWith('/'));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test('first full crawl writes everything, in batches', () async {
    final r = Rig(batch: 4);
    final states = <IndexPhase>[];
    r.service.states.listen((s) => states.add(s.phase));
    final res = await r.service.reindex();
    expect(res.outcome, IndexOutcome.success, reason: '${res.summary?.issues}');
    expect(res.titlesWritten, 11);
    expect(res.batches, 3); // 4 + 4 + 3
    expect(res.titlesRemoved, 0);
    expect((await r.repo.counts()).titles, 11);
    expect((await r.repo.categories()).length, 5);
    expect(await r.meta.lastIndexedAt(), DateTime.utc(2026, 11, 22));
    expect(
      states,
      containsAll([
        IndexPhase.probing,
        IndexPhase.crawling,
        IndexPhase.writing,
        IndexPhase.done,
      ]),
    );
    expect(r.service.state.phase, IndexPhase.done);
    expect(r.service.state.titlesWritten, 11);
  });

  test('incremental: changed, removed and unchanged titles', () async {
    final r = Rig();
    await r.service.reindex();

    // Watch progress on an unchanged title and on a title that will change.
    final unchanged = await r.titleNamed('12 Angry Men');
    final changed = await r.titleNamed('Cypher');
    final f1 = (await r.repo.titleFiles(unchanged.id)).first;
    final f2 = (await r.repo.titleFiles(changed.id)).first;
    await r.repo.setProgress(f1.id, positionMs: 1000, durationMs: 2000);
    await r.repo.markWatched(f2.id);

    // Server side: Cypher's folder mtime changes; Going the Distance vanishes.
    final p2002 = pageOf(r.fake, '%282002%29');
    r.fake.pages[p2002] = r.fake.pages[p2002]!.replaceFirst(
      RegExp(r'<td class="fb-d">\d{4}[^<]*</td>'),
      '<td class="fb-d">2030-01-01 00:00</td>',
    );
    final p2010 = pageOf(r.fake, '%282010%29');
    r.fake.pages[p2010] = r.fake.pages[p2010]!.replaceAll(
      RegExp(r'<tr><td class="fb-i"><img[^>]*alt="folder"/></td>.*?</tr>'),
      '',
    );
    r.fake.requests.clear();

    final res = await r.service.reindex();
    expect(res.outcome, IndexOutcome.success, reason: '${res.summary?.issues}');
    expect(res.titlesWritten, 1); // only Cypher rewritten
    expect(res.titlesUnchanged, 9);
    expect(res.titlesRemoved, 1);
    expect(await r.titleNames(), isNot(contains('Going the Distance')));
    expect((await r.repo.counts()).titles, 10);

    // Watch state survives for both the unchanged and the re-upserted title.
    expect((await r.repo.watchState(f1.id))!.positionMs, 1000);
    final f2b = (await r.repo.titleFiles(changed.id)).first;
    expect(f2b.id, f2.id);
    expect((await r.repo.watchState(f2.id))!.watched, isTrue);
    // Unchanged movies were not requested at all.
    expect(r.fake.requests.where((u) => u == unchanged.folderUrl), isEmpty);
  });

  test('full=true re-crawls everything', () async {
    final r = Rig();
    await r.service.reindex();
    final res = await r.service.reindex(full: true);
    expect(res.titlesWritten, 11);
    expect(res.titlesUnchanged, 0);
  });

  test(
    'partial crawl deletes nothing (failing subfolder + failing category)',
    () async {
      final r = Rig();
      await r.service.reindex();
      final before = await r.titleNames();

      // Server lost a title, but another English folder now fails to list, and
      // the whole WWE category root fails too.
      final p2010 = pageOf(r.fake, '%282010%29');
      r.fake.pages[p2010] = r.fake.pages[p2010]!.replaceAll(
        RegExp(r'<tr><td class="fb-i"><img[^>]*alt="folder"/></td>.*?</tr>'),
        '',
      );
      r.fake.pages.remove(pageOf(r.fake, '%281999%29')); // 404
      r.fake.pages.remove(r.fake.roots['WWE & AEW']!); // 404

      final res = await r.service.reindex(full: true);
      expect(res.outcome, IndexOutcome.partial);
      expect(res.titlesRemoved, 0);
      expect(res.categoriesIncomplete, 2);
      expect(await r.titleNames(), before); // incl. vanished + unreachable ones
      // Complete categories were still processed normally.
      expect(res.categoriesComplete, 3);
    },
  );

  test(
    'a category that completes still prunes its own vanished titles',
    () async {
      final r = Rig();
      await r.service.reindex();
      r.fake.pages.remove(pageOf(r.fake, '%281999%29')); // English fails
      final p = r.fake.roots['Foreign Language Movies']!;
      // Foreign: drop one film from the language bucket (complete category).
      final chinese = pageOf(r.fake, 'Chinese%20Language');
      r.fake.pages[chinese] = r.fake.pages[chinese]!.replaceFirst(
        RegExp(r'<tr><td class="fb-i"><img[^>]*alt="folder"/></td>.*?</tr>'),
        '',
      );
      expect(p, isNotEmpty);
      final res = await r.service.reindex();
      expect(res.titlesRemoved, 1);
      expect(await r.titleNames(), contains('The Cider House Rules'));
      expect(await r.titleNames(), isNot(contains('12 Golden Ducks')));
    },
  );

  test('cancelled crawl keeps old data and deletes nothing', () async {
    final r = Rig();
    await r.service.reindex();
    final before = await r.titleNames();
    // Server now lists nothing new; cancel mid-way through a full recrawl.
    r.fake.latency = const Duration(milliseconds: 5);
    final token = CancelToken();
    Timer(const Duration(milliseconds: 12), token.cancel);
    final res = await r.service.reindex(full: true, cancel: token);
    expect(res.outcome, IndexOutcome.cancelled);
    expect(res.titlesRemoved, 0);
    expect(await r.titleNames(), before);
    expect(r.service.isRunning, isFalse);
  });

  test('service.cancel() cancels the current run', () async {
    final r = Rig();
    r.fake.latency = const Duration(milliseconds: 5);
    final f = r.service.reindex();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    r.service.cancel();
    final res = await f;
    expect(res.outcome, IndexOutcome.cancelled);
    expect(await r.meta.lastIndexedAt(), isNull);
  });

  test('off BDIX: returns fast, index untouched, lastIndexedAt kept', () async {
    final r = Rig();
    await r.service.reindex();
    final before = await r.titleNames();
    final cats = await r.repo.categories();
    r.fake.downHosts.addAll(['172.16.50.7', '172.16.50.10', '172.16.50.14']);
    r.fake.requests.clear();
    final sw = Stopwatch()..start();
    final res = await r.service.reindex();
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(res.outcome, IndexOutcome.offBdix);
    expect(res.offBdix, isTrue);
    expect(res.message, contains('BDIX'));
    expect(r.service.state.offBdix, isTrue);
    expect(r.service.state.phase, IndexPhase.failed);
    expect(r.fake.requests.length, 3); // probes only
    expect(await r.titleNames(), before);
    expect((await r.repo.categories()).length, cats.length);
    expect(await r.service.lastIndexedAt(), DateTime.utc(2026, 11, 22));
  });

  test('off BDIX on a fresh install creates nothing', () async {
    final r = Rig();
    r.fake.downHosts.addAll(['172.16.50.7', '172.16.50.10', '172.16.50.14']);
    final res = await r.service.reindex();
    expect(res.offBdix, isTrue);
    expect((await r.repo.categories()), isEmpty);
    expect(await r.service.lastIndexedAt(), isNull);
  });

  test('one host down: others indexed, its titles untouched', () async {
    final r = Rig();
    await r.service.reindex();
    r.fake.downHosts.add('172.16.50.7');
    final res = await r.service.reindex(full: true);
    expect(res.outcome, IndexOutcome.partial);
    expect(res.titlesRemoved, 0);
    expect((await r.repo.counts()).titles, 11);
  });

  test(
    'write failure mid-run keeps earlier batches, deletes nothing',
    () async {
      final ok = Rig();
      await ok.service.reindex();
      final repo = FailingRepo(3);
      final r = Rig(repo: repo, batch: 3);
      final res = await r.service.reindex();
      expect(res.outcome, IndexOutcome.failed);
      expect(res.message, contains('disk full'));
      expect(res.titlesRemoved, 0);
      expect((await repo.counts()).titles, 6); // two batches of 3 committed
      expect(r.service.state.phase, IndexPhase.failed);
      expect(await r.meta.lastIndexedAt(), isNull);
    },
  );

  test('concurrent reindex calls join the running one', () async {
    final r = Rig();
    final a = r.service.reindex();
    final b = r.service.reindex();
    expect(identical(a, b), isTrue);
    await a;
  });

  test('suspicious empty "complete" crawl does not wipe a category', () async {
    final r = Rig();
    await r.service.reindex();
    // WWE root now lists one folder with nothing in it: complete but empty.
    final root = r.fake.roots['WWE & AEW']!;
    final sub = r.fake.pages.keys.firstWhere(
      (u) => u.endsWith('AEW%20Wrestling/'),
    );
    r.fake.pages[sub] = r.fake.pages[sub]!.replaceAll(
      RegExp(r'<tr><td class="fb-i"><img[^>]*alt="folder"/></td>.*?</tr>'),
      '',
    );
    expect(root, isNotEmpty);
    final res = await r.service.reindex(full: true);
    expect(res.titlesRemoved, 0);
    expect((await r.repo.counts()).titles, 11);
  });

  test('FileIndexMeta round trip and corrupt file', () async {
    final dir = await Directory.systemTemp.createTemp('meta');
    addTearDown(() => dir.delete(recursive: true));
    final m = FileIndexMeta(File('${dir.path}/sub/m.json'));
    expect(await m.lastIndexedAt(), isNull);
    await m.setLastIndexedAt(DateTime.utc(2026, 1, 2, 3));
    expect(await m.lastIndexedAt(), DateTime.utc(2026, 1, 2, 3));
    await File('${dir.path}/sub/m.json').writeAsString('{oops');
    expect(await m.lastIndexedAt(), isNull);
  });
}
