import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';

const cat = 'http://h/en/';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late DriftRepository repo;
  late int catId;
  setUp(() async {
    repo = DriftRepository.memory();
    catId = (await repo.upsertCategories(const [
      CategoryDraft(
        sourceHost: 'h',
        name: 'English',
        url: cat,
        language: 'english',
      ),
    ]))[cat]!;
  });
  tearDown(() => repo.close());

  TitleDraft movie(
    String name, {
    DateTime? mtime,
    DateTime? added,
    int count = 1,
  }) => TitleDraft(
    categoryId: catId,
    name: name,
    kind: TitleKind.movie,
    folderUrl: '$cat(2020)/$name/',
    year: 2020,
    posterUrl: '$cat(2020)/$name/p.jpg',
    folderMtime: mtime,
    filesLoaded: false,
    fileCount: count,
    addedAt: added,
  );

  TitleDraft show(String name, {DateTime? mtime}) => TitleDraft(
    categoryId: catId,
    name: name,
    kind: TitleKind.series,
    folderUrl: '$cat$name/',
    folderMtime: mtime,
    filesLoaded: false,
    fileCount: 7,
    seasons: [
      SeasonDraft(
        number: 1,
        label: 'Season 1',
        folderUrl: '$cat$name/Season%201/',
        episodeCount: 4,
      ),
      SeasonDraft(
        number: 2,
        label: 'Season 2',
        folderUrl: '$cat$name/Season%202/',
        episodeCount: 3,
      ),
      const SeasonDraft(number: 0, label: 'Other'),
    ],
  );

  group('addedAt hint', () {
    test('used on first insert only, never changed afterwards', () async {
      final a = DateTime(2020, 5, 1, 12);
      await repo.upsertTitles([movie('A', added: a)]);
      var t = (await repo.browse(const BrowseFilter())).single;
      expect(t.addedAt, a);
      // Re-crawl with another hint (and a full draft): unchanged.
      await repo.upsertTitles([movie('A', added: DateTime(2023))]);
      await repo.upsertTitle(
        TitleDraft(
          categoryId: catId,
          name: 'A',
          kind: TitleKind.movie,
          folderUrl: '$cat(2020)/A/',
          addedAt: DateTime(2024),
          files: [
            FileDraft(
              name: 'x',
              url: '$cat(2020)/A/f.mkv',
              ext: 'mkv',
              playable: true,
            ),
          ],
        ),
      );
      t = (await repo.browse(const BrowseFilter())).single;
      expect(t.addedAt, a);
    });

    test('no hint = now; future hint is clamped to now', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 2));
      await repo.upsertTitles([
        movie('N'),
        movie('F', added: DateTime.now().add(const Duration(days: 30))),
      ]);
      await repo.upsertTitle(
        TitleDraft(
          categoryId: catId,
          name: 'S',
          kind: TitleKind.movie,
          folderUrl: '${cat}S/',
        ),
      );
      for (final t in await repo.browse(const BrowseFilter())) {
        expect(t.addedAt.isAfter(before), isTrue, reason: t.name);
        expect(
          t.addedAt.isBefore(DateTime.now().add(const Duration(seconds: 2))),
          isTrue,
        );
      }
    });

    test('recently added sorts by the hint', () async {
      await repo.upsertTitles([
        movie('Old', added: DateTime(2010)),
        movie('New', added: DateTime(2024)),
        movie('Mid', added: DateTime(2018)),
      ]);
      final r = await repo.browse(
        const BrowseFilter(sort: BrowseSort.recentlyAdded),
      );
      expect([for (final t in r) t.name], ['New', 'Mid', 'Old']);
    });
  });

  group('fast skeleton insert', () {
    test('new movies and series: rows, seasons, counts, poster', () async {
      final m = DateTime(2021, 3, 4, 5, 6);
      await repo.upsertTitles([movie('A', mtime: m, count: 3), show('Show')]);
      final all = await repo.browse(const BrowseFilter(), limit: 10);
      final a = all.firstWhere((t) => t.name == 'A');
      expect(a.folderUrl, '$cat(2020)/A/');
      expect(a.posterUrl, '$cat(2020)/A/p.jpg');
      expect(a.fileCount, 3);
      expect(a.filesLoaded, isFalse);
      expect(a.folderMtime, m);
      expect(a.language, 'english');
      final s = all.firstWhere((t) => t.name == 'Show');
      expect(s.seasonCount, 3);
      expect(s.fileCount, 7);
      final seasons = await repo.seasons(s.id);
      expect([for (final x in seasons) x.season.number], [0, 1, 2]);
      expect([for (final x in seasons) x.season.episodeCount], [0, 4, 3]);
      expect((await repo.counts()).files, 10);
      // FTS trigger ran.
      expect((await repo.search('Show')).map((t) => t.name), contains('Show'));
    });

    test('mixed batch: existing titles take the per-title path', () async {
      final m = DateTime(2021, 1, 1);
      await repo.upsertTitles([movie('A', mtime: m), show('Show', mtime: m)]);
      final before = await repo.browse(const BrowseFilter(), limit: 10);
      final idA = before.firstWhere((t) => t.name == 'A').id;
      final idS = before.firstWhere((t) => t.name == 'Show').id;
      final seasonIds = [for (final x in await repo.seasons(idS)) x.season.id];
      // A changed, Show unchanged, B new, plus a repeated folder in the batch.
      await repo.upsertTitles([
        movie('A', mtime: DateTime(2022), count: 5),
        show('Show', mtime: m),
        movie('B'),
        movie('B', count: 9),
      ]);
      final after = await repo.browse(const BrowseFilter(), limit: 10);
      expect(after.length, 3);
      expect(after.firstWhere((t) => t.name == 'A').id, idA);
      expect(after.firstWhere((t) => t.name == 'A').fileCount, 5);
      expect(after.firstWhere((t) => t.name == 'Show').id, idS);
      expect(after.firstWhere((t) => t.name == 'B').fileCount, 9);
      expect([for (final x in await repo.seasons(idS)) x.season.id], seasonIds);
    });

    test('loaded files survive an unchanged skeleton re-crawl', () async {
      final m = DateTime(2021, 1, 1);
      await repo.upsertTitles([movie('A', mtime: m)]);
      final id = (await repo.browse(const BrowseFilter())).single.id;
      await repo.upsertTitleFiles(
        id,
        files: [
          FileDraft(
            name: 'f',
            url: '$cat(2020)/A/f.mkv',
            ext: 'mkv',
            playable: true,
          ),
        ],
      );
      await repo.upsertTitles([movie('A', mtime: m)]);
      expect(await repo.titleFilesLoaded(id), isTrue);
      await repo.upsertTitles([movie('A', mtime: DateTime(2022))]);
      expect(await repo.titleFilesLoaded(id), isFalse);
      expect((await repo.titleFiles(id)).length, 1); // rows kept, stale
    });

    test('unknown category and invalid drafts throw', () async {
      expect(
        () => repo.upsertTitles([
          TitleDraft(
            categoryId: 999,
            name: 'X',
            kind: TitleKind.movie,
            folderUrl: 'http://h/x/X/',
            filesLoaded: false,
          ),
        ]),
        throwsArgumentError,
      );
      expect((await repo.counts()).titles, 0);
    });

    test('a batch of 1200 inserts in one go', () async {
      await repo.upsertTitles([
        for (var i = 0; i < 1200; i++) movie('T$i', count: i),
      ]);
      final c = await repo.counts();
      expect(c.titles, 1200);
      expect(c.files, 1199 * 1200 ~/ 2);
    });

    test('rows parked in watch_keep: per-title path re-attaches', () async {
      await repo.upsertTitles([movie('A')]);
      final id = (await repo.browse(const BrowseFilter())).single.id;
      await repo.upsertTitleFiles(
        id,
        files: [
          FileDraft(
            name: 'f',
            url: '$cat(2020)/A/f.mkv',
            ext: 'mkv',
            playable: true,
          ),
        ],
      );
      final f = (await repo.titleFiles(id)).single;
      await repo.setProgress(f.id, positionMs: 5, durationMs: 10);
      await repo.clearIndex();
      catId = (await repo.upsertCategories(const [
        CategoryDraft(sourceHost: 'h', name: 'English', url: cat),
      ]))[cat]!;
      await repo.upsertTitles([movie('A')]);
      final id2 = (await repo.browse(const BrowseFilter())).single.id;
      final f2 = (await repo.titleFiles(id2)).single;
      expect((await repo.watchState(f2.id))!.positionMs, 5);
    });
  });

  group('changes throttle', () {
    test(
      'leading edge, then at most one per window, flush on release',
      () async {
        final repo2 = DriftRepository.memory();
        addTearDown(repo2.close);
        final cid = (await repo2.upsertCategories(const [
          CategoryDraft(sourceHost: 'h', name: 'E', url: cat),
        ]))[cat]!;
        TitleDraft t(int i) => TitleDraft(
          categoryId: cid,
          name: 'T$i',
          kind: TitleKind.movie,
          folderUrl: '${cat}T$i/',
          filesLoaded: false,
        );
        var n = 0;
        repo2.changes.listen((_) => n++);
        (repo2 as ChangeThrottling).throttleChanges(
          const Duration(milliseconds: 150),
        );
        for (var i = 0; i < 6; i++) {
          await repo2.upsertTitles([t(i)]);
        }
        await Future<void>.delayed(Duration.zero);
        expect(n, 1); // leading only
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(n, 2); // one trailing for the other five
        await repo2.upsertTitles([t(10)]);
        await repo2.upsertTitles([t(11)]);
        repo2.throttleChanges(null); // flushes pending
        await Future<void>.delayed(Duration.zero);
        expect(n, 3);
        await repo2.upsertTitles([t(12)]);
        await Future<void>.delayed(Duration.zero);
        expect(n, 4); // immediate again
      },
    );
  });
}
