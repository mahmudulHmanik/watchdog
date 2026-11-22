import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/classifier.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/crawler/title_files.dart';
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';

import 'fakes.dart';
import 'page_fixture.dart';

const fast = TitleLoadOptions(backoffBase: Duration.zero);
const base = 'http://h/DHAKA/Cat/';
const basePath = '/DHAKA/Cat/';

/// Records trimFileCache calls, then delegates.
class RecRepo extends DriftRepository {
  RecRepo(super.db);
  final trims = <(int, Set<int>)>[];
  @override
  Future<int> trimFileCache({
    int maxRows = 20000,
    Set<int> protectedTitleIds = const {},
  }) {
    trims.add((maxRows, protectedTitleIds));
    return super.trimFileCache(
      maxRows: maxRows,
      protectedTitleIds: protectedTitleIds,
    );
  }
}

/// Skeleton form (no files) of a fully classified title.
TitleDraft skeletonOf(TitleDraft d, {DateTime? mtime, int catId = 0}) =>
    TitleDraft(
      categoryId: catId,
      name: d.name,
      kind: d.kind,
      folderUrl: d.folderUrl,
      year: d.year,
      yearEnd: d.yearEnd,
      quality: d.quality,
      tags: d.tags,
      posterUrl: d.posterUrl,
      folderMtime: mtime ?? d.folderMtime,
      filesLoaded: false,
      fileCount:
          d.files.length + d.seasons.fold(0, (n, s) => n + s.files.length),
      seasons: [
        for (final s in d.seasons)
          SeasonDraft(
            number: s.number,
            label: s.label,
            language: s.language,
            folderUrl: s.folderUrl,
            episodeCount: s.files.length,
          ),
      ],
    );

void main() {
  late RecRepo repo;
  late int catId;

  setUp(() async {
    repo = RecRepo(AppDatabase.memory());
    final m = await repo.upsertCategories([
      const CategoryDraft(sourceHost: 'h', name: 'Cat', url: base),
    ]);
    catId = m[base]!;
  });
  tearDown(() => repo.close());

  TitleFilesLoader loaderFor(
    ListingClient c, {
    Future<Set<int>> Function()? protectedIds,
  }) => TitleFilesLoader(
    repo: repo,
    client: c,
    options: fast,
    protectedTitleIds: protectedIds,
  );

  // ---- every fixture layout equals the full classifier ----

  group('fixture layouts match the full classifier', () {
    final probe = FakeListingClient.fromFixtures();
    final cfg = probe.config();
    final cats = [for (final (_, c) in cfg.enabledCategories) c];
    for (final c in cats) {
      final root = probe.tree(c.url, name: c.name);
      final drafts = classifyCategory(
        root,
        layout: c.layout,
        kind: c.kind,
        categoryId: 0,
      );
      for (final full in drafts) {
        test('${c.name} / ${full.name}', () async {
          final fake = FakeListingClient.fromFixtures();
          // Own category per title url prefix.
          final cid = (await repo.upsertCategories([
            CategoryDraft(sourceHost: 'h', name: c.name, url: c.url),
          ]))[c.url]!;
          final id = await repo.upsertTitle(skeletonOf(full, catId: cid));
          expect((await repo.title(id))!.filesLoaded, isFalse);
          final r = await loaderFor(fake).load(id);
          expect(r.fromNetwork, isTrue);
          final t = (await repo.title(id))!;
          expect(t.filesLoaded, isTrue);
          if (full.kind == TitleKind.series) {
            final got = await repo.seasons(id);
            expect(got.length, full.seasons.length);
            for (final (i, s) in full.seasons.indexed) {
              final g = got.firstWhere(
                (x) => x.season.label == s.label && x.season.number == s.number,
                orElse: () => got[i],
              );
              expect(
                {for (final f in g.files) f.url},
                {for (final f in s.files) f.url},
                reason: s.label,
              );
              expect(g.season.id, isPositive);
            }
          } else {
            expect(
              {for (final f in await repo.titleFiles(id)) f.url},
              {for (final f in full.files) f.url},
            );
          }
          // Sample/Subs/scoped_dir are never requested.
          expect(
            fake.requests.where(
              (u) => u.contains('scoped_dir') || u.contains('/Subs/'),
            ),
            isEmpty,
          );
        });
      }
    }
  });

  // ---- synthetic layouts ----

  String showPath(String n) => '$basePath${Uri.encodeComponent(n)}/';
  String showUrl(String n) => 'http://h${showPath(n)}';

  TitleDraft skeletonShow(
    String name,
    List<(String label, int count, String? folder)> seasons,
  ) => TitleDraft(
    categoryId: catId,
    name: name,
    kind: TitleKind.series,
    folderUrl: showUrl(name),
    filesLoaded: false,
    seasons: [
      for (final (i, s) in seasons.indexed)
        SeasonDraft(
          number: i + 1,
          label: s.$1,
          folderUrl: s.$3 == null ? showUrl(name) : '${showUrl(name)}${s.$3}/',
          episodeCount: s.$2,
        ),
    ],
  );

  test('movie: nested release folders flattened, Sample/extras ignored, '
      'posters and subs dropped', () async {
    final url = showUrl('Film (2020)');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Film (2020)'), [
        f('Film.2020.mkv'),
        f('poster.jpg'),
        f('Film.srt'),
        d('Sample'),
        d('Extras'),
        d('Part 2'),
      ]),
      '${url}Part%202/': h5aiPage('${showPath('Film (2020)')}Part%202/', [
        f('Film.part2.mp4'),
        f('Film.part2.zip'),
      ]),
    });
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        filesLoaded: false,
        fileCount: 1,
      ),
    );
    await loaderFor(c).load(id);
    final files = await repo.titleFiles(id);
    expect(files.map((f) => f.name).toSet(), {
      'Film.2020.mkv',
      'Film.part2.mp4',
      'Film.part2.zip',
    });
    expect(files.where((f) => f.name.endsWith('.zip')).single.playable, false);
    expect(c.requests.any((u) => u.contains('Sample')), isFalse);
    expect(c.requests.any((u) => u.contains('Extras')), isFalse);
    expect((await repo.title(id))!.fileCount, 3);
  });

  test('series: loose episodes (season = the show folder) keep the stored '
      'season id; seasons run in parallel', () async {
    final url = showUrl('Loose Show');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Loose Show'), [
        f('Loose.Show.S02E01.mkv'),
        f('Loose.Show.S02E02.mkv'),
      ]),
    });
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Loose Show',
        kind: TitleKind.series,
        folderUrl: url,
        filesLoaded: false,
        seasons: [
          SeasonDraft(
            number: 2,
            label: 'Season 2',
            folderUrl: url,
            episodeCount: 2,
          ),
        ],
      ),
    );
    final before = (await repo.seasons(id)).single.season.id;
    await loaderFor(c).load(id);
    final s = (await repo.seasons(id)).single;
    expect(s.season.id, before);
    expect(s.files.map((f) => f.episode), [1, 2]);
    expect(c.requests, [url]);
  });

  test('series: season ids stable across reloads, new episode keeps ids, '
      'watch state survives', () async {
    final url = showUrl('Show');
    final s1 = '${url}Season%201/';
    final s2 = '${url}Season%202%20(Hindi)/';
    final c = ScriptedClient({
      url: h5aiPage(showPath('Show'), [d('Season 1'), d('Season 2 (Hindi)')]),
      s1: h5aiPage('${showPath('Show')}Season%201/', [
        f('Show.S01E01.mkv'),
        f('Show.S01E02.mkv'),
      ]),
      s2: h5aiPage('${showPath('Show')}Season%202%20(Hindi)/', [
        f('Show.S02E01.mkv'),
      ]),
    });
    final id = await repo.upsertTitle(
      skeletonShow('Show', [
        ('Season 1', 2, 'Season%201'),
        ('Season 2', 1, 'Season%202%20(Hindi)'),
      ]),
    );
    final stored = await repo.seasons(id);
    final storedIds = [for (final s in stored) s.season.id];
    expect(stored.every((s) => s.files.isEmpty), isTrue);

    final l = loaderFor(c);
    await l.load(id);
    var got = await repo.seasons(id);
    expect([for (final s in got) s.season.id], storedIds);
    expect(got.map((s) => s.files.length), [2, 1]);
    final ep2 = got.first.files.last;
    await repo.setProgress(ep2.id, positionMs: 5000, durationMs: 100000);
    final ids = {for (final f in got.expand((s) => s.files)) f.url: f.id};

    // A new episode appears; reload by force.
    c.pages[s1] = h5aiPage('${showPath('Show')}Season%201/', [
      f('Show.S01E01.mkv'),
      f('Show.S01E02.mkv'),
      f('Show.S01E03.mkv'),
    ]);
    c.requests.clear();
    await l.load(id, force: true);
    got = await repo.seasons(id);
    expect([for (final s in got) s.season.id], storedIds);
    for (final f in got.expand((s) => s.files)) {
      if (ids.containsKey(f.url)) expect(f.id, ids[f.url], reason: f.name);
    }
    expect(got.first.files.length, 3);
    expect((await repo.watchState(ep2.id))!.positionMs, 5000);
    // Show + 2 season folders, in one go.
    expect(c.requests.toSet(), {url, s1, s2});
  });

  test('series: season percent-encoding differing from the skeleton still '
      'matches the stored season', () async {
    final url = showUrl('Enc');
    // The skeleton (h5ai API) stored %28/%29; the HTML listing writes ( ).
    final listed = '${url}Season%201%20(X)/';
    final c = ScriptedClient({
      url: h5aiPage(showPath('Enc'), [d('Season 1 (X)')]),
      listed: h5aiPage('${showPath('Enc')}Season%201%20(X)/', [
        f('Enc.S01E01.mkv'),
      ]),
    });
    final id = await repo.upsertTitle(
      skeletonShow('Enc', [('Season 1 (X)', 1, 'Season%201%20%28X%29')]),
    );
    final before = (await repo.seasons(id)).single.season.id;
    await loaderFor(c).load(id);
    final after = await repo.seasons(id);
    expect(after, hasLength(1));
    expect(after.single.season.id, before);
    expect(after.single.files, hasLength(1));
  });

  // ---- cache / freshness ----

  test('loaded and fresh -> served from the DB with no request; stale '
      '(folder changed) reloads', () async {
    final url = showUrl('Film');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Film'), [f('Film.mkv')]),
    });
    TitleDraft sk(DateTime? m) => TitleDraft(
      categoryId: catId,
      name: 'Film',
      kind: TitleKind.movie,
      folderUrl: url,
      folderMtime: m,
      filesLoaded: false,
      fileCount: 1,
    );
    final id = await repo.upsertTitle(sk(DateTime(2024, 1, 1)));
    final l = loaderFor(c);
    expect((await l.load(id)).fromNetwork, isTrue);
    expect(c.requests, hasLength(1));

    // Same mtime in a re-crawl: still fresh.
    await repo.upsertTitle(sk(DateTime(2024, 1, 1)));
    expect((await l.load(id)).fromNetwork, isFalse);
    expect(c.requests, hasLength(1), reason: 'no network when fresh');

    // Folder changed: stale -> reloaded on open.
    await repo.upsertTitle(sk(DateTime(2024, 2, 2)));
    expect((await repo.title(id))!.filesLoaded, isFalse);
    c.pages[url] = h5aiPage(showPath('Film'), [f('Film.mkv'), f('Film2.mkv')]);
    expect((await l.load(id)).fromNetwork, isTrue);
    expect(await repo.titleFiles(id), hasLength(2));
    expect(c.requests, hasLength(2));
  });

  test('ids stay stable when a stale movie is reloaded', () async {
    final url = showUrl('Film');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Film'), [f('A.mkv'), f('B.mkv')]),
    });
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        filesLoaded: false,
      ),
    );
    final l = loaderFor(c);
    await l.load(id);
    final first = {for (final f in await repo.titleFiles(id)) f.name: f.id};
    await l.load(id, force: true);
    final second = {for (final f in await repo.titleFiles(id)) f.name: f.id};
    expect(second, first);
  });

  test('concurrent loads of one title share one run', () async {
    final url = showUrl('Film');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Film'), [f('Film.mkv')]),
    })..latency = const Duration(milliseconds: 20);
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        filesLoaded: false,
      ),
    );
    final l = loaderFor(c);
    final rs = await Future.wait([
      l.load(id),
      l.load(id),
      l.load(id, force: true),
    ]);
    expect(rs.every((r) => r.fromNetwork), isTrue);
    expect(c.requests, hasLength(1));
    expect(l.isLoading(id), isFalse);
    expect(await repo.titleFiles(id), hasLength(1));
  });

  // ---- failures ----

  test('transient failures are retried; exhausted retries throw the fetch '
      'error and leave the title unloaded; a later load recovers', () async {
    final url = showUrl('Film');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Film'), [f('Film.mkv')]),
    });
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        filesLoaded: false,
      ),
    );
    Uri u() => Uri.parse(url);
    c.failures[url] = [
      FetchException(u(), FetchFailure.timeout, 't'),
      FetchException(u(), FetchFailure.http, 'HTTP 503', status: 503),
    ];
    final l = loaderFor(c);
    await l.load(id); // two failures, third attempt succeeds
    expect(c.requests, hasLength(3));
    await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        folderMtime: DateTime(2030),
        filesLoaded: false,
      ),
    );
    c.requests.clear();
    c.failures[url] = [
      for (var i = 0; i < 3; i++)
        FetchException(u(), FetchFailure.timeout, 't'),
    ];
    await expectLater(
      l.load(id),
      throwsA(
        isA<FetchException>().having((e) => e.noAnswer, 'noAnswer', true),
      ),
    );
    expect(c.requests, hasLength(3));
    expect((await repo.title(id))!.filesLoaded, isFalse);
    expect(l.isLoading(id), isFalse);
    // Retry after the error.
    await l.load(id);
    expect((await repo.title(id))!.filesLoaded, isTrue);
  });

  test('404 is not retried', () async {
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Gone',
        kind: TitleKind.movie,
        folderUrl: showUrl('Gone'),
        filesLoaded: false,
      ),
    );
    final c = ScriptedClient();
    await expectLater(
      loaderFor(c).load(id),
      throwsA(isA<FetchException>().having((e) => e.status, 'status', 404)),
    );
    expect(c.requests, hasLength(1));
  });

  test(
    'off-BDIX: every host down -> noAnswer error, nothing written',
    () async {
      final id = await repo.upsertTitle(
        TitleDraft(
          categoryId: catId,
          name: 'Film',
          kind: TitleKind.movie,
          folderUrl: showUrl('Film'),
          filesLoaded: false,
        ),
      );
      final c = ScriptedClient()..down = true;
      await expectLater(
        loaderFor(c).load(id),
        throwsA(
          isA<FetchException>().having((e) => e.noAnswer, 'noAnswer', true),
        ),
      );
      expect((await repo.title(id))!.filesLoaded, isFalse);
    },
  );

  test('a client that throws something else counts as no answer', () async {
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: showUrl('Film'),
        filesLoaded: false,
      ),
    );
    final l = TitleFilesLoader(repo: repo, client: _Throwing(), options: fast);
    await expectLater(
      l.load(id),
      throwsA(
        isA<FetchException>().having((e) => e.noAnswer, 'noAnswer', true),
      ),
    );
  });

  test('an empty listing is an error, not "no files"; a listing without '
      'media is loaded and empty', () async {
    final url = showUrl('Film');
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        filesLoaded: false,
      ),
    );
    final c = ScriptedClient({url: h5aiPage(showPath('Film'), [])});
    final l = loaderFor(c);
    await expectLater(l.load(id), throwsA(isA<FetchException>()));
    expect(c.requests, hasLength(2), reason: 'one retry for a blank page');
    c.pages[url] = h5aiPage(showPath('Film'), [f('poster.jpg'), f('a.srt')]);
    await l.load(id);
    expect((await repo.title(id))!.filesLoaded, isTrue);
    expect(await repo.titleFiles(id), isEmpty);
  });

  test('unknown title id -> TitleNotFound', () async {
    await expectLater(
      loaderFor(ScriptedClient()).load(999),
      throwsA(isA<TitleNotFound>()),
    );
  });

  // ---- cancellation ----

  test('cancel detaches the caller; the run stops when nobody is left and '
      'writes nothing', () async {
    final url = showUrl('Film');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Film'), [f('Film.mkv')]),
    })..gate = Completer<void>();
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        filesLoaded: false,
      ),
    );
    final l = loaderFor(c);
    final cancel = LoadCancel();
    final f1 = l.load(id, cancel: cancel);
    final f1e = expectLater(f1, throwsA(isA<TitleLoadCancelled>()));
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    await f1e;
    c.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await repo.title(id))!.filesLoaded, isFalse);
    expect(l.isLoading(id), isFalse);
    // A new caller starts a fresh run.
    await l.load(id);
    expect((await repo.title(id))!.filesLoaded, isTrue);
  });

  test('one of two callers cancelling does not stop the shared run', () async {
    final url = showUrl('Film');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Film'), [f('Film.mkv')]),
    })..gate = Completer<void>();
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        filesLoaded: false,
      ),
    );
    final l = loaderFor(c);
    final cancel = LoadCancel();
    final a = l.load(id, cancel: cancel);
    final aE = expectLater(a, throwsA(isA<TitleLoadCancelled>()));
    final b = l.load(id);
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    await aE;
    c.gate!.complete();
    expect((await b).fromNetwork, isTrue);
    expect((await repo.title(id))!.filesLoaded, isTrue);
    expect(c.requests, hasLength(1));
  });

  // ---- cache bound ----

  test('after a load the cache is trimmed with the downloads protected set '
      'plus the title just loaded', () async {
    final url = showUrl('Film');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Film'), [f('Film.mkv')]),
    });
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        filesLoaded: false,
      ),
    );
    final l = loaderFor(c, protectedIds: () async => {777});
    await l.load(id);
    await l.trimIdle;
    expect(repo.trims, hasLength(1));
    expect(repo.trims.single.$1, 20000);
    expect(repo.trims.single.$2, {777, id});
    // Cache hits do not trim.
    await l.load(id);
    await l.trimIdle;
    expect(repo.trims, hasLength(1));
  });

  test('protected-set lookup failing skips the trim (never trims '
      'unprotected)', () async {
    final url = showUrl('Film');
    final c = ScriptedClient({
      url: h5aiPage(showPath('Film'), [f('Film.mkv')]),
    });
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: url,
        filesLoaded: false,
      ),
    );
    final l = loaderFor(c, protectedIds: () async => throw StateError('x'));
    await l.load(id);
    await l.trimIdle;
    expect(repo.trims, isEmpty);
    expect((await repo.title(id))!.filesLoaded, isTrue);
  });

  test('alignSeasons: identity from stored seasons, no reuse', () {
    const t = 'http://h/a/Show/';
    final stored = [
      const Season(
        id: 1,
        titleId: 1,
        number: 1,
        label: 'Season 1',
        folderUrl: '${t}S%C3%A9/',
      ),
      const Season(
        id: 2,
        titleId: 1,
        number: 1,
        label: 'Season 1',
        folderUrl: '${t}Other/',
      ),
    ];
    final out = alignSeasons(
      [
        const SeasonDraft(number: 1, label: 'S', folderUrl: '${t}Other/'),
        const SeasonDraft(number: 1, label: 'S', folderUrl: '${t}New/'),
      ],
      stored,
      t,
    );
    expect(out[0].folderUrl, '${t}Other/');
    expect(out[0].label, 'Season 1'); // stored identity wins
    expect(out[1].folderUrl, '${t}New/'); // unmatched keeps its own
  });
}

class _Throwing implements ListingClient {
  @override
  Future<String> fetch(Uri url, {required Duration timeout}) =>
      Future.error(Exception('boom'));
  @override
  void close() {}
}
