import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';

TmdbCastMember cast(int id, String name, int order, {String? profile}) =>
    TmdbCastMember(
      personId: id,
      name: name,
      order: order,
      character: 'c$id',
      profilePath: profile,
    );

TmdbDetails details({
  int id = 1,
  TmdbMediaType type = TmdbMediaType.movie,
  double? rating,
  int? runtime,
  String? lang,
  List<TmdbGenre> genres = const [],
  List<TmdbCastMember> cast = const [],
  String title = 't',
}) => TmdbDetails(
  id: id,
  mediaType: type,
  title: title,
  overview: 'ov $id',
  tagline: 'tag',
  rating: rating,
  voteCount: 10,
  runtime: runtime,
  originalLanguage: lang,
  year: 2000,
  posterPath: '/p$id.jpg',
  backdropPath: '/b$id.jpg',
  genres: genres,
  cast: cast,
);

const action = TmdbGenre(28, 'Action');
const drama = TmdbGenre(18, 'Drama');
const comedy = TmdbGenre(35, 'Comedy');

void main() {
  late AppDatabase db;
  late DriftRepository repo;
  late int en, hi;
  late Map<String, int> ids; // title name -> id

  Future<int> add(String name, int cat, TitleKind kind, {int? year, int? q}) =>
      repo.upsertTitle(
        TitleDraft(
          categoryId: cat,
          name: name,
          kind: kind,
          folderUrl: 'http://h/${name.replaceAll(' ', '_')}/',
          year: year,
          quality: q,
          files: kind == TitleKind.series
              ? const []
              : [
                  FileDraft(
                    name: 'a.mkv',
                    url: 'http://h/${name.replaceAll(' ', '_')}/a.mkv',
                    ext: 'mkv',
                    playable: true,
                  ),
                ],
          seasons: kind == TitleKind.series
              ? [
                  SeasonDraft(
                    number: 1,
                    label: 'S1',
                    files: [
                      FileDraft(
                        name: 'e1.mkv',
                        url: 'http://h/${name.replaceAll(' ', '_')}/e1.mkv',
                        ext: 'mkv',
                        playable: true,
                        episode: 1,
                      ),
                    ],
                  ),
                ]
              : const [],
        ),
      );

  setUp(() async {
    db = AppDatabase.memory();
    repo = DriftRepository(db);
    final m = await repo.upsertCategories(const [
      CategoryDraft(
        sourceHost: 'h',
        name: 'English Movies',
        url: 'http://h/en/',
        language: 'English',
      ),
      CategoryDraft(
        sourceHost: 'h',
        name: 'Hindi Movies',
        url: 'http://h/hi/',
        language: 'Hindi',
      ),
    ]);
    en = m['http://h/en/']!;
    hi = m['http://h/hi/']!;
    ids = {
      'Alpha': await add('Alpha', en, TitleKind.movie, year: 1999, q: 1080),
      'Bravo': await add('Bravo', en, TitleKind.movie, year: 2010, q: 720),
      'Charlie': await add('Charlie', hi, TitleKind.movie, year: 2015, q: 1080),
      'Delta': await add('Delta', hi, TitleKind.series, year: 2020, q: 1080),
      'Echo': await add('Echo', en, TitleKind.movie, year: 2021),
      'Event': await add('Event', en, TitleKind.event),
    };
  });
  tearDown(() => repo.close());

  Future<void> seed() async {
    await repo.saveTmdbMatch(
      ids['Alpha']!,
      details(
        id: 11,
        rating: 8.5,
        runtime: 85,
        lang: 'en',
        genres: [action, drama],
        cast: [cast(1, 'Keanu Reeves', 0), cast(2, 'Carrie Moss', 1)],
      ),
    );
    await repo.saveTmdbMatch(
      ids['Bravo']!,
      details(
        id: 12,
        rating: 6.0,
        runtime: 100,
        lang: 'en',
        genres: [comedy],
        cast: [cast(1, 'Keanu Reeves', 0)],
      ),
    );
    await repo.saveTmdbMatch(
      ids['Charlie']!,
      details(
        id: 13,
        rating: 7.2,
        runtime: 130,
        lang: 'hi',
        genres: [drama],
        cast: [cast(3, 'Shah Rukh', 0)],
      ),
    );
    await repo.saveTmdbMatch(
      ids['Delta']!,
      details(
        id: 14,
        type: TmdbMediaType.tv,
        rating: 9.0,
        runtime: 160,
        lang: 'ko',
        genres: [action],
      ),
    );
    await repo.saveTmdbUnmatched(ids['Echo']!); // no data
  }

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  group('saveTmdbMatch / tmdbInfo', () {
    test('round trip with genres and cast in billing order', () async {
      expect(await repo.tmdbInfo(ids['Alpha']!), isNull);
      await repo.saveTmdbMatch(
        ids['Alpha']!,
        details(
          id: 603,
          rating: 8.2,
          runtime: 136,
          lang: 'en',
          genres: [drama, action],
          cast: [
            cast(2, 'Second', 1, profile: '/s.jpg'),
            cast(1, 'First', 0),
          ],
        ),
      );
      final i = (await repo.tmdbInfo(ids['Alpha']!))!;
      expect(i.status, TmdbStatus.matched);
      expect(i.tmdbId, 603);
      expect(i.mediaType, TmdbMediaType.movie);
      expect(i.rating, 8.2);
      expect(i.runtime, 136);
      expect(i.originalLanguage, 'en');
      expect(i.posterPath, '/p603.jpg');
      expect(i.genres.map((g) => g.name), ['Drama', 'Action']);
      expect(i.cast.map((c) => c.name), ['First', 'Second']);
      expect(i.cast.last.profilePath, '/s.jpg');
      expect(i.cast.first.character, 'c1');
    });

    test(
      'replaces genres and cast, drops orphans, keeps shared rows',
      () async {
        await seed();
        expect(await count('tmdb_people'), 3);
        await repo.saveTmdbMatch(
          ids['Alpha']!,
          details(id: 11, genres: [comedy], cast: [cast(9, 'New Guy', 0)]),
        );
        final i = (await repo.tmdbInfo(ids['Alpha']!))!;
        expect(i.genres.map((g) => g.id), [35]);
        expect(i.cast.map((c) => c.personId), [9]);
        // Carrie (only in Alpha) is gone; Keanu stays (Bravo); Drama stays
        // (Charlie).
        expect((await repo.searchPeople('carrie')), isEmpty);
        expect((await repo.searchPeople('keanu')).single.titleCount, 1);
        expect(await count('tmdb_people'), 3); // Keanu, Shah, New Guy
        expect(await count('people_fts'), 3);
        expect(await count('tmdb_genres'), 3);
      },
    );

    test('same person reused: one row, profile kept when later null', () async {
      await repo.saveTmdbMatch(
        ids['Alpha']!,
        details(cast: [cast(1, 'Keanu', 0, profile: '/k.jpg')]),
      );
      await repo.saveTmdbMatch(
        ids['Bravo']!,
        details(id: 2, cast: [cast(1, 'Keanu', 0)]),
      );
      expect(await count('tmdb_people'), 1);
      final p = (await repo.person(1))!;
      expect(p.profilePath, '/k.jpg');
      expect(p.titleCount, 2);
    });

    test('duplicate genres/cast in input do not break the write', () async {
      await repo.saveTmdbMatch(
        ids['Alpha']!,
        details(
          genres: [action, action],
          cast: [cast(1, 'A', 0), cast(1, 'A', 1)],
        ),
      );
      final i = (await repo.tmdbInfo(ids['Alpha']!))!;
      expect(i.genres, hasLength(1));
      expect(i.cast, hasLength(1));
    });

    test('manual rows survive automatic writes, manual overwrites', () async {
      final id = ids['Alpha']!;
      await repo.saveTmdbMatch(
        id,
        details(id: 1, genres: [action], cast: [cast(1, 'A', 0)]),
        manual: true,
      );
      expect((await repo.tmdbInfo(id))!.status, TmdbStatus.manual);
      await repo.saveTmdbMatch(id, details(id: 2, genres: [drama]));
      await repo.saveTmdbUnmatched(id);
      var i = (await repo.tmdbInfo(id))!;
      expect(i.status, TmdbStatus.manual);
      expect(i.tmdbId, 1);
      expect(i.genres.map((g) => g.id), [28]);
      expect(i.cast, hasLength(1));
      await repo.saveTmdbMatch(id, details(id: 3), manual: true);
      i = (await repo.tmdbInfo(id))!;
      expect(i.tmdbId, 3);
      expect(i.genres, isEmpty);
      expect(i.cast, isEmpty);
    });

    test('unmatched then matched; matched is not downgraded', () async {
      final id = ids['Alpha']!;
      await repo.saveTmdbUnmatched(id);
      var i = (await repo.tmdbInfo(id))!;
      expect(i.status, TmdbStatus.unmatched);
      expect(i.tmdbId, isNull);
      await repo.saveTmdbMatch(id, details(id: 5));
      await repo.saveTmdbUnmatched(id);
      i = (await repo.tmdbInfo(id))!;
      expect(i.status, TmdbStatus.matched);
      expect(i.tmdbId, 5);
    });

    test('unknown title is a silent no-op', () async {
      await repo.saveTmdbMatch(99999, details());
      await repo.saveTmdbUnmatched(99999);
      expect(await count('tmdb_meta'), 0);
    });

    test('emits on changes at most once per call', () async {
      var n = 0;
      final sub = repo.changes.listen((_) => n++);
      await repo.saveTmdbMatch(
        ids['Alpha']!,
        details(
          genres: [action, drama],
          cast: [for (var i = 0; i < 15; i++) cast(i + 1, 'P$i', i)],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(n, 1);
      await repo.saveTmdbMatch(ids['Alpha']!, details(), manual: false);
      await Future<void>.delayed(Duration.zero);
      expect(n, 2);
      await sub.cancel();
    });

    test(
      'titles deleted by the crawler leave no orphan people/genres',
      () async {
        await seed();
        final cat = await repo.categories();
        expect(cat, isNotEmpty);
        await repo.removeMissing(en, {'http://h/Echo/'}); // drops Alpha, Bravo
        expect(await repo.searchPeople('carrie'), isEmpty);
        expect(await repo.person(2), isNull);
        expect(await count('tmdb_people'), 1); // Shah Rukh only
        expect(
          await count('tmdb_genres'),
          2,
        ); // Drama (Charlie), Action (Delta)
      },
    );
  });

  group('titlesNeedingTmdb / tmdbProgress', () {
    test('movies and series only, newest addedAt first', () async {
      // Pin addedAt so order is deterministic.
      final t0 = DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      var k = 0;
      for (final n in ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Event']) {
        await db.customStatement(
          'UPDATE titles SET added_at = ? WHERE id = ?',
          [t0 + (n == 'Charlie' ? 100 : k++), ids[n]],
        );
      }
      final r = await repo.titlesNeedingTmdb();
      expect(r.map((t) => t.name), [
        'Charlie',
        'Echo',
        'Delta',
        'Bravo',
        'Alpha',
      ]);
      expect((await repo.titlesNeedingTmdb(limit: 2)).map((t) => t.name), [
        'Charlie',
        'Echo',
      ]);
      expect(r.first.categoryId, hi);
      expect(r.first.tags, isEmpty);
    });

    test(
      'matched/manual are skipped; unmatched wait for the retry window',
      () async {
        await repo.saveTmdbMatch(ids['Alpha']!, details());
        await repo.saveTmdbMatch(ids['Bravo']!, details(), manual: true);
        await repo.saveTmdbUnmatched(ids['Charlie']!);
        var names = (await repo.titlesNeedingTmdb()).map((t) => t.name).toSet();
        expect(names, {'Delta', 'Echo'});
        // Age Charlie's unmatched row beyond 30 days.
        final old =
            DateTime.now()
                .subtract(const Duration(days: 31))
                .millisecondsSinceEpoch ~/
            1000;
        await db.customStatement(
          'UPDATE tmdb_meta SET fetched_at = ? WHERE title_id = ?',
          [old, ids['Charlie']],
        );
        names = (await repo.titlesNeedingTmdb()).map((t) => t.name).toSet();
        expect(names, {'Charlie', 'Delta', 'Echo'});
        // A custom window.
        names = (await repo.titlesNeedingTmdb(
          retryUnmatchedAfter: const Duration(days: 60),
        )).map((t) => t.name).toSet();
        expect(names, {'Delta', 'Echo'});
        // Matched rows are never retried, however old.
        await db.customStatement('UPDATE tmdb_meta SET fetched_at = ?', [old]);
        names = (await repo.titlesNeedingTmdb()).map((t) => t.name).toSet();
        expect(names, {'Charlie', 'Delta', 'Echo'});
      },
    );

    test('progress', () async {
      var p = await repo.tmdbProgress();
      expect((p.eligible, p.matched, p.unmatched, p.pending), (5, 0, 0, 5));
      await repo.saveTmdbMatch(ids['Alpha']!, details());
      await repo.saveTmdbMatch(ids['Bravo']!, details(), manual: true);
      await repo.saveTmdbUnmatched(ids['Charlie']!);
      p = await repo.tmdbProgress();
      expect((p.eligible, p.matched, p.unmatched, p.pending), (5, 2, 1, 2));
      final old =
          DateTime.now()
              .subtract(const Duration(days: 31))
              .millisecondsSinceEpoch ~/
          1000;
      await db.customStatement(
        'UPDATE tmdb_meta SET fetched_at = ? WHERE title_id = ?',
        [old, ids['Charlie']],
      );
      p = await repo.tmdbProgress();
      expect((p.matched, p.unmatched, p.pending), (2, 0, 3));
    });

    test('query plan is an index walk plus PK probes', () async {
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT t.* FROM titles t LEFT JOIN tmdb_meta m '
            'ON m.title_id = t.id WHERE t.kind IN (0, 1) AND (m.title_id IS NULL '
            'OR (m.status = 1 AND m.fetched_at <= 5)) '
            'ORDER BY t.added_at DESC, t.id DESC LIMIT 50',
          )
          .get();
      final text = plan.map((r) => r.read<String>('detail')).join('\n');
      expect(text, contains('idx_titles_added'));
      expect(text, isNot(contains('USE TEMP B-TREE')));
    });
  });

  group('clear', () {
    test('clearTmdb wipes TMDB tables only', () async {
      await seed();
      await repo.clearTmdb();
      for (final t in [
        'tmdb_meta',
        'title_genres',
        'title_cast',
        'tmdb_genres',
        'tmdb_people',
        'people_fts',
      ]) {
        expect(await count(t), 0, reason: t);
      }
      expect((await repo.counts()).titles, 6);
      expect(await repo.tmdbInfo(ids['Alpha']!), isNull);
      expect(await repo.tmdbProgress().then((p) => p.pending), 5);
    });

    test('clearIndex leaves no orphan TMDB rows', () async {
      await seed();
      await repo.clearIndex();
      for (final t in [
        'titles',
        'tmdb_meta',
        'title_genres',
        'title_cast',
        'tmdb_genres',
        'tmdb_people',
        'people_fts',
      ]) {
        expect(await count(t), 0, reason: t);
      }
    });
  });

  group('TMDB filters', () {
    setUp(seed);

    Future<List<String>> names(BrowseFilter f) async =>
        (await repo.browse(f)).map((e) => e.name).toList()..sort();

    test('genre ids: OR within', () async {
      expect(await names(BrowseFilter(genreIds: {28})), ['Alpha', 'Delta']);
      expect(await names(BrowseFilter(genreIds: {18})), ['Alpha', 'Charlie']);
      expect(await names(BrowseFilter(genreIds: {28, 35})), [
        'Alpha',
        'Bravo',
        'Delta',
      ]);
      expect(await names(BrowseFilter(genreIds: {999})), isEmpty);
    });

    test('min rating, inclusive', () async {
      expect(await names(const BrowseFilter(minRating: 8.5)), [
        'Alpha',
        'Delta',
      ]);
      expect(await names(const BrowseFilter(minRating: 6.5)), [
        'Alpha',
        'Charlie',
        'Delta',
      ]);
      expect(await names(const BrowseFilter(minRating: 9.5)), isEmpty);
    });

    test('original languages', () async {
      expect(await names(BrowseFilter(originalLanguages: {'en'})), [
        'Alpha',
        'Bravo',
      ]);
      expect(await names(BrowseFilter(originalLanguages: {'hi', 'ko'})), [
        'Charlie',
        'Delta',
      ]);
    });

    test('runtime buckets are half-open', () async {
      expect(await names(BrowseFilter(runtimes: {RuntimeBucket.short})), [
        'Alpha',
      ]);
      expect(await names(BrowseFilter(runtimes: {RuntimeBucket.medium})), [
        'Bravo',
      ]);
      expect(await names(BrowseFilter(runtimes: {RuntimeBucket.long})), [
        'Charlie',
      ]);
      expect(await names(BrowseFilter(runtimes: {RuntimeBucket.epic})), [
        'Delta',
      ]);
      expect(
        await names(
          BrowseFilter(runtimes: {RuntimeBucket.short, RuntimeBucket.epic}),
        ),
        ['Alpha', 'Delta'],
      );
      // Boundaries: 90 is medium, 120 long, 150 epic.
      await repo.saveTmdbMatch(ids['Echo']!, details(id: 50, runtime: 90));
      expect(await names(BrowseFilter(runtimes: {RuntimeBucket.medium})), [
        'Bravo',
        'Echo',
      ]);
      await repo.saveTmdbMatch(ids['Echo']!, details(id: 50, runtime: 150));
      expect(await names(BrowseFilter(runtimes: {RuntimeBucket.epic})), [
        'Delta',
        'Echo',
      ]);
    });

    test('person id', () async {
      expect(await names(const BrowseFilter(personId: 1)), ['Alpha', 'Bravo']);
      expect(await names(const BrowseFilter(personId: 3)), ['Charlie']);
      expect(await names(const BrowseFilter(personId: 404)), isEmpty);
    });

    test(
      'titles without TMDB data never match an active TMDB filter',
      () async {
        // Echo is unmatched, Event has no row; both absent from every filter.
        for (final f in [
          BrowseFilter(genreIds: {28, 18, 35}),
          const BrowseFilter(minRating: 0),
          BrowseFilter(originalLanguages: {'en', 'hi', 'ko'}),
          BrowseFilter(runtimes: RuntimeBucket.values.toSet()),
        ]) {
          final n = await names(f);
          expect(n, isNot(contains('Echo')));
          expect(n, isNot(contains('Event')));
        }
        expect(await repo.countTitles(), 6);
      },
    );

    test('combined with each other and with existing filters', () async {
      expect(await names(BrowseFilter(genreIds: {18}, minRating: 8)), [
        'Alpha',
      ]);
      expect(
        await names(
          BrowseFilter(genreIds: {28}, originalLanguages: {'ko'}, personId: 1),
        ),
        isEmpty,
      );
      expect(await names(BrowseFilter(categoryId: hi, genreIds: {18, 28})), [
        'Charlie',
        'Delta',
      ]);
      expect(await names(BrowseFilter(languages: {'English'}, minRating: 7)), [
        'Alpha',
      ]);
      expect(
        await names(
          BrowseFilter(
            years: {2010, 2015, 2020},
            qualities: {1080},
            kind: TitleKind.series,
            minRating: 5,
          ),
        ),
        ['Delta'],
      );
      expect(
        await names(
          const BrowseFilter(yearRanges: [YearRange(to: 2012)], personId: 1),
        ),
        ['Alpha', 'Bravo'],
      );
    });

    test('countTitles agrees with browse; paging is stable', () async {
      final f = BrowseFilter(genreIds: {18, 28}, minRating: 7);
      expect(await repo.countTitles(f), 3);
      expect((await repo.browse(f, limit: 2)).map((t) => t.name), [
        'Alpha',
        'Charlie',
      ]);
      expect((await repo.browse(f, offset: 2, limit: 2)).map((t) => t.name), [
        'Delta',
      ]);
    });

    test('search applies TMDB filters in SQL', () async {
      for (final n in ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']) {
        expect(await repo.search(n.substring(0, 3)), isNotEmpty);
      }
      Future<List<String>> s(String q, BrowseFilter f) async =>
          (await repo.search(q, filter: f)).map((t) => t.name).toList();
      expect(await s('alp', BrowseFilter(genreIds: {28})), ['Alpha']);
      expect(await s('alp', BrowseFilter(genreIds: {35})), isEmpty);
      expect(await s('bra', const BrowseFilter(personId: 1)), ['Bravo']);
      expect(await s('cha', const BrowseFilter(minRating: 8)), isEmpty);
      expect(await s('cha', const BrowseFilter(minRating: 7)), ['Charlie']);
      expect(await s('del', BrowseFilter(originalLanguages: {'ko'})), [
        'Delta',
      ]);
      // Empty query falls back to browse with the filter.
      expect(await s('', BrowseFilter(runtimes: {RuntimeBucket.long})), [
        'Charlie',
      ]);
    });

    test('search filter is applied before the candidate cap', () async {
      // 300 "mega" titles; only the last one has TMDB data. Unfiltered it
      // would sit beyond the 200-candidate cap.
      final last = <int>[];
      for (var i = 0; i < 300; i++) {
        last.add(
          await add(
            'Mega title ${i.toString().padLeft(3, '0')}',
            en,
            TitleKind.movie,
          ),
        );
      }
      await repo.saveTmdbMatch(
        last.last,
        details(id: 700, genres: [const TmdbGenre(99, 'Rare')]),
      );
      final r = await repo.search(
        'mega title',
        filter: BrowseFilter(genreIds: {99}),
      );
      expect(r.single.id, last.last);
    });

    test('facets are scoped by the other filters, not their own', () async {
      var g = await repo.genres();
      expect({for (final f in g) f.value.id: f.count}, {28: 2, 18: 2, 35: 1});
      expect(g.first.count, 2);
      // Own selection ignored.
      g = await repo.genres(BrowseFilter(genreIds: {28}));
      expect(g.map((f) => f.value.id).toSet(), {28, 18, 35});
      // Other filters scope.
      g = await repo.genres(BrowseFilter(originalLanguages: {'en'}));
      expect({for (final f in g) f.value.id: f.count}, {28: 1, 18: 1, 35: 1});
      g = await repo.genres(const BrowseFilter(minRating: 8));
      expect({for (final f in g) f.value.id: f.count}, {28: 2, 18: 1});
      expect(g.firstWhere((f) => f.value.id == 28).value.name, 'Action');

      var l = await repo.tmdbLanguages();
      expect(
        {for (final f in l) f.value: f.count},
        {'en': 2, 'hi': 1, 'ko': 1},
      );
      expect(l.first.value, 'en');
      l = await repo.tmdbLanguages(BrowseFilter(originalLanguages: {'hi'}));
      expect(l, hasLength(3));
      l = await repo.tmdbLanguages(BrowseFilter(genreIds: {28}));
      expect({for (final f in l) f.value: f.count}, {'en': 1, 'ko': 1});
      l = await repo.tmdbLanguages(BrowseFilter(categoryId: hi));
      expect({for (final f in l) f.value: f.count}, {'hi': 1, 'ko': 1});
    });

    test('existing facets honour TMDB filters', () async {
      final y = await repo.years(BrowseFilter(genreIds: {28}));
      expect(y.map((f) => f.value), [2020, 1999]);
    });
  });

  group('people', () {
    setUp(() async {
      await seed();
      // Extra people for ranking.
      await repo.saveTmdbMatch(
        ids['Echo']!,
        details(
          id: 21,
          cast: [
            cast(10, 'Keanu', 0),
            cast(11, 'Reeves Keanu', 1),
            cast(12, 'Anna Keane', 2),
            cast(13, 'Al Pacino', 3),
            cast(14, 'Alan Arkin', 4),
            cast(15, 'X', 5),
          ],
        ),
      );
      await repo.saveTmdbMatch(
        ids['Delta']!,
        details(id: 14, cast: [cast(1, 'Keanu Reeves', 0)]),
      );
    });

    test('exact, then prefix, then by title count', () async {
      final r = await repo.searchPeople('keanu');
      // Exact "Keanu" first; then prefix "Keanu Reeves" (3 titles) ahead of
      // word-prefix/substring hits.
      expect(r.map((p) => p.name), ['Keanu', 'Keanu Reeves', 'Reeves Keanu']);
      expect(r[1].titleCount, 3);
      expect(r[1].id, 1);
    });

    test('case-insensitive, multi-token in any order', () async {
      expect((await repo.searchPeople('KEANU REEVES')).first.id, 1);
      expect((await repo.searchPeople('reeves keanu')).map((p) => p.id), [
        11,
        1,
      ]);
      expect(
        (await repo.searchPeople('  keanu   reeves ')).first.name,
        'Keanu Reeves',
      );
    });

    test('substring and typo-free partials', () async {
      expect((await repo.searchPeople('eeve')).map((p) => p.id).toSet(), {
        1,
        11,
      });
      expect(await repo.searchPeople('zzzz'), isEmpty);
      expect(await repo.searchPeople(''), isEmpty);
      expect(await repo.searchPeople('   '), isEmpty);
    });

    test('1-2 char queries use LIKE; word prefix beats substring', () async {
      expect((await repo.searchPeople('x')).map((p) => p.name), contains('X'));
      // "al": prefix hits (Al Pacino, Alan Arkin) before substrings
      // (Shah Rukh? no; "Keanu Reeves" has no 'al').
      final r = await repo.searchPeople('al');
      expect(r.take(2).map((p) => p.name).toSet(), {'Al Pacino', 'Alan Arkin'});
      expect(r.first.name, 'Al Pacino'); // exact-prefix tie -> name order
      // Mixed long and short tokens.
      expect((await repo.searchPeople('al pac')).single.name, 'Al Pacino');
    });

    test('limit and wildcard characters', () async {
      expect(await repo.searchPeople('keanu', limit: 1), hasLength(1));
      expect(await repo.searchPeople('%'), isEmpty);
      expect(await repo.searchPeople('_'), isEmpty);
      expect(await repo.searchPeople('"; DROP'), isEmpty);
      expect(await repo.searchPeople('a"b"c'), isEmpty);
    });

    test('person(id)', () async {
      final p = (await repo.person(1))!;
      expect((p.name, p.titleCount), ('Keanu Reeves', 3));
      expect(await repo.person(123456), isNull);
    });

    test('results are usable as a personId filter', () async {
      final hit = (await repo.searchPeople('keanu reeves')).first;
      expect(
        (await repo.browse(BrowseFilter(personId: hit.id))).map((t) => t.name),
        ['Alpha', 'Bravo', 'Delta'],
      );
    });
  });

  test(
    'raw variable binding sanity (no SQL injection via language code)',
    () async {
      await seed();
      expect(
        await repo.countTitles(
          BrowseFilter(originalLanguages: {"x') OR 1=1 --"}),
        ),
        0,
      );
    },
  );
}
