import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';

FileDraft f(
  String name, {
  int? ep,
  int? epEnd,
  bool playable = true,
  String? base,
}) => FileDraft(
  name: name,
  url: '${base ?? 'http://h/x'}/$name',
  ext: name.split('.').last,
  playable: playable,
  episode: ep,
  episodeEnd: epEnd,
  sizeKb: 100,
);

void main() {
  late DriftRepository repo;
  late int cat, catHi;
  setUp(() async {
    repo = DriftRepository.memory();
    final m = await repo.upsertCategories(const [
      CategoryDraft(
        sourceHost: '172.16.50.7',
        name: 'English Movies',
        url: 'http://h/en/',
        language: 'English',
      ),
      CategoryDraft(
        sourceHost: '172.16.50.14',
        name: 'Hindi Movies',
        url: 'http://h/hi/',
        language: 'Hindi',
      ),
    ]);
    cat = m['http://h/en/']!;
    catHi = m['http://h/hi/']!;
  });
  tearDown(() => repo.close());

  TitleDraft movie(String name, {int? year, int? q, int? c, String? url}) =>
      TitleDraft(
        categoryId: c ?? cat,
        name: name,
        kind: TitleKind.movie,
        folderUrl: url ?? 'http://h/en/$name/',
        year: year,
        quality: q,
        tags: const ['WEB-DL'],
        files: [f('$name.mkv', base: url ?? 'http://h/en/$name')],
      );

  TitleDraft series(String name, List<SeasonDraft> seasons) => TitleDraft(
    categoryId: cat,
    name: name,
    kind: TitleKind.series,
    folderUrl: 'http://h/tv/$name/',
    seasons: seasons,
  );

  test('categories, counts, upsertCategories idempotent', () async {
    await repo.upsertTitle(movie('A', year: 2000));
    final again = await repo.upsertCategories(const [
      CategoryDraft(
        sourceHost: '172.16.50.7',
        name: 'English Movies',
        url: 'http://h/en/',
        language: 'English',
      ),
    ]);
    expect(again['http://h/en/'], cat);
    final cs = await repo.categories();
    expect(cs.length, 2);
    expect(cs.firstWhere((c) => c.id == cat).titleCount, 1);
    final n = await repo.counts();
    expect((n.categories, n.titles, n.series, n.files), (2, 1, 0, 1));
  });

  test('browse filters, sort, paging, facets', () async {
    await repo.upsertTitles([
      movie('B', year: 2001, q: 1080),
      movie('a', year: 2000, q: 720),
      movie('C', year: 2001, q: 1080, c: catHi, url: 'http://h/hi/C/'),
      movie('D'),
    ]);
    final all = await repo.browse(const BrowseFilter());
    expect(all.map((t) => t.name), ['a', 'B', 'C', 'D']); // case-insens.
    expect(all.first.language, 'English');
    expect(all.first.tags, ['WEB-DL']);
    expect(
      (await repo.browse(
        const BrowseFilter(),
        offset: 1,
        limit: 2,
      )).map((t) => t.name),
      ['B', 'C'],
    );
    expect(await repo.countTitles(const BrowseFilter(year: 2001)), 2);
    expect(await repo.countTitles(const BrowseFilter(language: 'Hindi')), 1);
    expect(
      await repo.countTitles(const BrowseFilter(quality: 1080, categoryId: 1)),
      1,
    );
    expect(
      await repo.countTitles(const BrowseFilter(kind: TitleKind.series)),
      0,
    );
    final byYear = await repo.browse(
      const BrowseFilter(sort: BrowseSort.yearDesc),
    );
    expect(byYear.map((t) => t.name), ['B', 'C', 'a', 'D']); // null last
    final yrs = await repo.years();
    expect(yrs.map((e) => (e.value, e.count)), [(2001, 2), (2000, 1)]);
    final langs = await repo.languages(const BrowseFilter(year: 2001));
    expect(langs.map((e) => (e.value, e.count)), [
      ('English', 1),
      ('Hindi', 1),
    ]);
    expect((await repo.qualities()).map((e) => e.value), [1080, 720]);
  });

  test(
    'recentlyAdded sorts by addedAt; re-crawl never changes addedAt',
    () async {
      final id1 = await repo.upsertTitle(movie('X'));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final id2 = await repo.upsertTitle(movie('Y'));
      final first = (await repo.title(id1))!.addedAt;
      await repo.upsertTitle(movie('X', year: 1999));
      expect((await repo.title(id1))!.addedAt, first);
      expect((await repo.title(id1))!.year, 1999);
      final r = await repo.browse(
        const BrowseFilter(sort: BrowseSort.recentlyAdded),
      );
      expect(r.map((t) => t.id), [id2, id1]);
    },
  );

  test('titlesByIds keeps order, skips unknown', () async {
    final a = await repo.upsertTitle(movie('A'));
    final b = await repo.upsertTitle(movie('B'));
    expect((await repo.titlesByIds([b, 999, a])).map((t) => t.id), [b, a]);
    expect(await repo.titlesByIds([]), isEmpty);
  });

  test('movie detail, file lookups', () async {
    final id = await repo.upsertTitle(movie('M'));
    final files = await repo.titleFiles(id);
    expect(files.single.seasonId, isNull);
    expect((await repo.file(files.single.id))!.name, 'M.mkv');
    expect((await repo.fileByUrl(files.single.url))!.id, files.single.id);
    expect(await repo.fileByUrl('nope'), isNull);
    expect(await repo.seasons(id), isEmpty);
    expect(await repo.nextEpisode(files.single.id), isNull);
    expect((await repo.title(id))!.fileCount, 1);
  });

  test(
    'series playlist: range episodes order, null episode last, rar kept',
    () async {
      final id = await repo.upsertTitle(
        series('S', [
          SeasonDraft(
            number: 2,
            label: 'Season 2',
            files: [f('s2e1.mkv', ep: 1, base: 'u2')],
          ),
          SeasonDraft(
            number: 1,
            label: 'Season 1',
            files: [
              f('z.mkv'),
              f('e06-e10.mkv', ep: 6, epEnd: 10, base: 'u1'),
              f('e01-e05.mkv', ep: 1, epEnd: 5, base: 'u1'),
              f('e11.rar', ep: 11, playable: false, base: 'u1'),
              f('e11.mkv', ep: 11, base: 'u1'),
            ],
          ),
        ]),
      );
      final ss = await repo.seasons(id);
      expect(ss.map((s) => s.season.number), [1, 2]);
      expect(ss[0].files.map((x) => x.name), [
        'e01-e05.mkv',
        'e06-e10.mkv',
        'e11.mkv',
        'e11.rar',
        'z.mkv',
      ]);
      expect(ss[0].season.episodeCount, 5);
      // next: skips unplayable, rolls into season 2
      final byName = {for (final x in ss.expand((s) => s.files)) x.name: x};
      expect(
        (await repo.nextEpisode(byName['e01-e05.mkv']!.id))!.name,
        'e06-e10.mkv',
      );
      expect(
        (await repo.nextEpisode(byName['e06-e10.mkv']!.id))!.name,
        'e11.mkv',
      );
      expect((await repo.nextEpisode(byName['e11.mkv']!.id))!.name, 'z.mkv');
      expect((await repo.nextEpisode(byName['z.mkv']!.id))!.name, 's2e1.mkv');
      expect(await repo.nextEpisode(byName['s2e1.mkv']!.id), isNull);
      expect((await repo.title(id))!.seasonCount, 2);
    },
  );

  test('two same-number seasons with different languages', () async {
    final id = await repo.upsertTitle(
      series('L', [
        SeasonDraft(
          number: 1,
          label: 'S1 Hindi',
          language: 'Hindi',
          files: [
            f('h1.mkv', ep: 1, base: 'h'),
            f('h2.mkv', ep: 2, base: 'h'),
          ],
        ),
        SeasonDraft(
          number: 1,
          label: 'S1 English',
          language: 'English',
          files: [
            f('e1.mkv', ep: 1, base: 'e'),
            f('e2.mkv', ep: 2, base: 'e'),
          ],
        ),
        SeasonDraft(
          number: 2,
          label: 'S2 Hindi',
          language: 'Hindi',
          files: [f('h3.mkv', ep: 1, base: 'h2')],
        ),
      ]),
    );
    final ss = await repo.seasons(id);
    expect(ss.map((s) => s.season.label), [
      'S1 Hindi',
      'S1 English',
      'S2 Hindi',
    ]);
    final m = {for (final x in ss.expand((s) => s.files)) x.name: x};
    expect((await repo.nextEpisode(m['h1.mkv']!.id))!.name, 'h2.mkv');
    expect((await repo.nextEpisode(m['h2.mkv']!.id))!.name, 'h3.mkv');
    expect((await repo.nextEpisode(m['e2.mkv']!.id)), isNull);
    // ids preserved through re-crawl in a different order
    final ids = {for (final s in ss) s.season.label: s.season.id};
    await repo.upsertTitle(
      series('L', [
        SeasonDraft(
          number: 1,
          label: 'S1 English',
          language: 'English',
          files: [
            f('e1.mkv', ep: 1, base: 'e'),
            f('e2.mkv', ep: 2, base: 'e'),
          ],
        ),
        SeasonDraft(
          number: 1,
          label: 'S1 Hindi',
          language: 'Hindi',
          files: [
            f('h1.mkv', ep: 1, base: 'h'),
            f('h2.mkv', ep: 2, base: 'h'),
          ],
        ),
      ]),
    );
    final after = await repo.seasons(id);
    expect(
      {for (final s in after) s.season.label: s.season.id},
      {'S1 Hindi': ids['S1 Hindi'], 'S1 English': ids['S1 English']},
    );
    expect((await repo.file(m['h1.mkv']!.id))!.seasonId, ids['S1 Hindi']);
    expect(await repo.file(m['h3.mkv']!.id), isNull); // dropped with S2
  });

  test('season identity by folderUrl survives rename', () async {
    SeasonDraft sd(String label) => SeasonDraft(
      number: 1,
      label: label,
      folderUrl: 'http://h/tv/N/s1/',
      files: [f('a.mkv', ep: 1, base: 'n')],
    );
    final id = await repo.upsertTitle(series('N', [sd('Season 1')]));
    final sid = (await repo.seasons(id)).single.season.id;
    await repo.upsertTitle(series('N', [sd('Season One')]));
    final s = (await repo.seasons(id)).single.season;
    expect((s.id, s.label), (sid, 'Season One'));
  });

  test(
    're-crawl keeps watch state and file ids; removed file loses it',
    () async {
      final id = await repo.upsertTitle(
        series('W', [
          SeasonDraft(
            number: 1,
            label: 'S1',
            files: [
              f('a.mkv', ep: 1, base: 'w'),
              f('b.mkv', ep: 2, base: 'w'),
            ],
          ),
        ]),
      );
      final fs = (await repo.seasons(id)).single.files;
      await repo.setProgress(fs[0].id, positionMs: 100, durationMs: 1000);
      await repo.setProgress(fs[1].id, positionMs: 100, durationMs: 1000);
      await repo.upsertTitle(
        series('W', [
          SeasonDraft(
            number: 1,
            label: 'S1',
            files: [f('a.mkv', ep: 1, base: 'w')],
          ),
        ]),
      );
      final a = (await repo.seasons(id)).single.files.single;
      expect(a.id, fs[0].id);
      expect((await repo.watchState(a.id))!.positionMs, 100);
      expect(await repo.watchState(fs[1].id), isNull);
    },
  );

  test('upsert validation and batch abort', () async {
    final bad = TitleDraft(
      categoryId: cat,
      name: 'bad',
      kind: TitleKind.series,
      folderUrl: 'http://h/bad/',
      files: [f('x.mkv')],
    );
    expect(() => repo.upsertTitle(bad), throwsArgumentError);
    expect(() => repo.upsertTitles([movie('ok'), bad]), throwsArgumentError);
    expect(await repo.countTitles(), 0);
    // failure inside the transaction rolls the batch back
    final unknownCat = movie('ghost', c: 9999, url: 'http://h/g/');
    await expectLater(
      repo.upsertTitles([movie('ok'), unknownCat]),
      throwsArgumentError,
    );
    expect(await repo.countTitles(), 0);
  });

  test('watch: auto-watched at 0.9, reset, resume rules', () async {
    final a = await repo.upsertTitle(movie('A'));
    final b = await repo.upsertTitle(movie('B'));
    final fa = (await repo.titleFiles(a)).single.id;
    final fb = (await repo.titleFiles(b)).single.id;
    await repo.setProgress(fa, positionMs: 500, durationMs: 1000);
    expect((await repo.watchState(fa))!.watched, isFalse);
    expect((await repo.continueWatching()).single.file.id, fa);
    await repo.setProgress(fa, positionMs: 900, durationMs: 1000);
    expect((await repo.watchState(fa))!.watched, isTrue);
    expect(await repo.continueWatching(), isEmpty);
    await repo.setProgress(fb, positionMs: 50, durationMs: 0); // no duration
    expect((await repo.watchState(fb))!.watched, isFalse);
    await repo.markWatched(fa, watched: false);
    final s = (await repo.watchState(fa))!;
    expect((s.watched, s.positionMs), (false, 0));
    expect((await repo.continueWatching()).map((r) => r.file.id), [fb]);
    await repo.markWatched(fb);
    expect((await repo.watchState(fb))!.watched, isTrue);
    expect((await repo.counts()).watched, 1);
    expect((await repo.watchStates([fa, fb, 12345])).keys.toSet(), {fa, fb});
    await repo.setProgress(7777, positionMs: 1, durationMs: 2); // no such file
    expect(await repo.watchState(7777), isNull);
  });

  test('continueWatching: one per title, newest first, limit', () async {
    final id = await repo.upsertTitle(
      series('C', [
        SeasonDraft(
          number: 1,
          label: 'S1',
          files: [
            f('a.mkv', ep: 1, base: 'c'),
            f('b.mkv', ep: 2, base: 'c'),
          ],
        ),
      ]),
    );
    final other = await repo.upsertTitle(movie('O'));
    final fs = (await repo.seasons(id)).single.files;
    final fo = (await repo.titleFiles(other)).single.id;
    await repo.setProgress(fs[0].id, positionMs: 10, durationMs: 1000);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await repo.setProgress(fo, positionMs: 10, durationMs: 1000);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await repo.setProgress(fs[1].id, positionMs: 10, durationMs: 1000);
    final r = await repo.continueWatching();
    expect(r.map((e) => e.file.id), [fs[1].id, fo]);
    expect((await repo.continueWatching(limit: 1)).length, 1);
  });

  test('markTitleWatched whole title / one season, skips unplayable', () async {
    final id = await repo.upsertTitle(
      series('T', [
        SeasonDraft(
          number: 1,
          label: 'S1',
          files: [
            f('a.mkv', ep: 1, base: 't1'),
            f('r.rar', ep: 2, playable: false, base: 't1'),
          ],
        ),
        SeasonDraft(
          number: 2,
          label: 'S2',
          files: [f('b.mkv', ep: 1, base: 't2')],
        ),
      ]),
    );
    final ss = await repo.seasons(id);
    await repo.markTitleWatched(id, seasonId: ss[0].season.id);
    final ids = ss.expand((s) => s.files).map((x) => x.id).toList();
    var w = await repo.watchStates(ids);
    expect(w.length, 1);
    await repo.markTitleWatched(id);
    w = await repo.watchStates(ids);
    expect(w.length, 2);
    expect(w.values.every((x) => x.watched), isTrue);
    await repo.markTitleWatched(id, watched: false);
    expect(
      (await repo.watchStates(ids)).values.every((x) => !x.watched),
      isTrue,
    );
  });

  test('knownFolders and removeMissing', () async {
    final t = DateTime.utc(2024, 1, 2, 3, 4);
    await repo.upsertTitles([
      TitleDraft(
        categoryId: cat,
        name: 'K1',
        kind: TitleKind.movie,
        folderUrl: 'http://h/en/K1/',
        folderMtime: t,
        files: [f('a.mkv', base: 'k1')],
      ),
      movie('K2'),
      movie('H', c: catHi, url: 'http://h/hi/H/'),
    ]);
    final k = await repo.knownFolders(cat);
    expect(k.keys.toSet(), {'http://h/en/K1/', 'http://h/en/K2/'});
    expect(k['http://h/en/K1/']!.isAtSameMomentAs(t), isTrue);
    expect(k['http://h/en/K2/'], isNull);
    final f1 = (await repo.fileByUrl('k1/a.mkv'))!;
    expect(await repo.removeMissing(cat, {'http://h/en/K1/'}), 1);
    expect((await repo.knownFolders(cat)).keys, ['http://h/en/K1/']);
    expect(
      await repo.countTitles(const BrowseFilter(categoryId: 2)),
      1,
    ); // other cat safe
    expect(await repo.file(f1.id), isNotNull);
    expect(await repo.search('K2'), isEmpty); // fts cleaned
    expect(await repo.removeMissing(cat, {'http://h/en/K1/'}), 0);
  });

  test('clearIndex keeps watch by url and restores on re-crawl', () async {
    final id = await repo.upsertTitle(movie('R'));
    final fid = (await repo.titleFiles(id)).single.id;
    await repo.setProgress(fid, positionMs: 40, durationMs: 100);
    await repo.clearIndex();
    expect((await repo.counts()).titles, 0);
    final m = await repo.upsertCategories(const [
      CategoryDraft(
        sourceHost: '172.16.50.7',
        name: 'English Movies',
        url: 'http://h/en/',
      ),
    ]);
    final id2 = await repo.upsertTitle(movie('R', c: m['http://h/en/']));
    final f2 = (await repo.titleFiles(id2)).single;
    expect((await repo.watchState(f2.id))!.positionMs, 40);
    await repo.clearIndex(includeWatch: true);
    final m2 = await repo.upsertCategories(const [
      CategoryDraft(
        sourceHost: '172.16.50.7',
        name: 'English Movies',
        url: 'http://h/en/',
      ),
    ]);
    final id3 = await repo.upsertTitle(movie('R', c: m2['http://h/en/']));
    expect(
      await repo.watchState((await repo.titleFiles(id3)).single.id),
      isNull,
    );
  });

  test('changes stream fires on index mutations', () async {
    var n = 0;
    final sub = repo.changes.listen((_) => n++);
    await repo.upsertTitle(movie('E'));
    await repo.upsertTitles([movie('F')]);
    await repo.removeMissing(cat, {});
    await Future<void>.delayed(Duration.zero);
    expect(n, 3);
    await sub.cancel();
  });

  group('search', () {
    setUp(() async {
      await repo.upsertTitles([
        movie('Pather Panchali', year: 1955),
        movie('Pather Panchali Remastered', year: 2015),
        movie('The Matrix', year: 1999, c: catHi, url: 'http://h/hi/Matrix/'),
        movie('Up'),
      ]);
    });
    test('typo tolerant, ranked', () async {
      final r = await repo.search('Pather Pancali');
      expect(r.first.name, startsWith('Pather Panchali'));
      expect(r.map((t) => t.name), contains('Pather Panchali'));
    });
    test('filters and paging', () async {
      expect(
        (await repo.search(
          'matrix',
          filter: const BrowseFilter(language: 'Hindi'),
        )).length,
        1,
      );
      expect(
        await repo.search(
          'matrix',
          filter: const BrowseFilter(language: 'English'),
        ),
        isEmpty,
      );
      expect((await repo.search('pather', limit: 1)).length, 1);
      final all = await repo.search('pather');
      expect((await repo.search('pather', offset: 1)).length, all.length - 1);
    });
    test(
      'matches category name; short query uses substring; empty browses',
      () async {
        expect((await repo.search('hindi movies')).first.name, 'The Matrix');
        expect((await repo.search('up')).single.name, 'Up');
        expect((await repo.search('  ')).length, 4);
        expect(await repo.search('"\' zzzq'), isEmpty);
      },
    );
  });
}
