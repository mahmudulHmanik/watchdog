@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';

/// ~35k titles on a real on-disk database (background isolate). Like
/// production (schema v3), only 10% of the titles have file rows loaded
/// (~17k files); the rest are skeletons with stored counts.
void main() {
  test('35k titles / 17k cached files: browse < 50 ms, FTS < 100 ms', () async {
    final dir = Directory.systemTemp.createTempSync('wd_perf');
    final db = openDatabaseAt(File('${dir.path}/p.db'));
    final repo = DriftRepository(db);
    addTearDown(() async {
      await repo.close();
      dir.deleteSync(recursive: true);
    });
    final cats = await repo.upsertCategories([
      for (var i = 0; i < 20; i++)
        CategoryDraft(
          sourceHost: 'h${i % 4}',
          name: 'Category $i',
          url: 'http://h/c$i/',
          language: i % 2 == 0 ? 'English' : 'Hindi',
        ),
    ]);
    final catIds = cats.values.toList();
    const words = [
      'night',
      'river',
      'storm',
      'king',
      'dark',
      'city',
      'love',
      'blood',
      'gold',
      'wild',
      'last',
      'home',
      'fire',
      'lost',
      'iron',
      'moon',
    ];
    final rnd = Random(1);
    final sw = Stopwatch()..start();
    const n = 35000;
    for (var b = 0; b < n; b += 500) {
      final batch = <TitleDraft>[];
      for (var i = b; i < b + 500 && i < n; i++) {
        final name =
            '${words[rnd.nextInt(16)]} ${words[rnd.nextInt(16)]} '
            '${words[rnd.nextInt(16)]} $i';
        final series = i % 4 == 0;
        final url = 'http://h/c${i % 20}/$i/';
        final loaded = i % 10 == 0;
        FileDraft fd(String s) => FileDraft(
          name: s,
          url: '$url$s',
          ext: 'mkv',
          playable: true,
          sizeKb: 1,
        );
        batch.add(
          TitleDraft(
            categoryId: catIds[i % 20],
            name: name,
            kind: series ? TitleKind.series : TitleKind.movie,
            folderUrl: url,
            year: 1950 + rnd.nextInt(75),
            quality: [480, 720, 1080][rnd.nextInt(3)],
            seasons: series
                ? [
                    for (var s = 1; s <= 2; s++)
                      SeasonDraft(
                        number: s,
                        label: 'S$s',
                        folderUrl: '${url}S$s/',
                        episodeCount: 6,
                        files: loaded
                            ? [
                                for (var e = 1; e <= 6; e++)
                                  fd('S$s/s${s}e$e.mkv'),
                              ]
                            : const [],
                      ),
                  ]
                : const [],
            files: series || !loaded ? const [] : [fd('a.mkv'), fd('b.mkv')],
            filesLoaded: loaded,
            fileCount: series ? 12 : 2,
          ),
        );
      }
      await repo.upsertTitles(batch);
    }
    final c = await repo.counts();
    // ignore: avoid_print
    print(
      'insert ${sw.elapsedMilliseconds} ms: ${c.titles} titles, ${c.files} files',
    );
    expect(c.titles, n);
    expect(c.files, greaterThan(n * 4)); // stored counts, not loaded rows

    // TMDB data for 90% of the titles, written in bulk with SQL: 19 genres,
    // 2-3 genres and 12 cast members per title, 20k people.
    sw.reset();
    await db.transaction(() async {
      for (var g = 1; g <= 19; g++) {
        await db.customStatement(
          'INSERT INTO tmdb_genres (id, name) VALUES (?, ?)',
          [g, 'Genre $g'],
        );
      }
      await db.customStatement(
        'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 20000) '
        'INSERT INTO tmdb_people (id, name, profile_path) '
        "SELECT i, CASE i % 8 WHEN 0 THEN 'Anna' WHEN 1 THEN 'John' WHEN 2 THEN 'Keanu' "
        "WHEN 3 THEN 'Maria' WHEN 4 THEN 'Ravi' WHEN 5 THEN 'Sam' WHEN 6 THEN 'Priya' "
        "ELSE 'Omar' END || ' ' || CASE i % 13 WHEN 0 THEN 'Reeves' WHEN 1 THEN 'Khan' "
        "WHEN 2 THEN 'Smith' WHEN 3 THEN 'Kumar' ELSE 'Person' END || ' ' || i, "
        "'/p' || i || '.jpg' FROM n",
      );
      await db.customStatement(
        'INSERT INTO tmdb_meta (title_id, status, tmdb_id, media_type, rating, runtime, '
        'original_language, poster_path, fetched_at) '
        "SELECT id, 0, id, 'movie', (id * 7 % 100) / 10.0, 60 + id % 120, "
        "CASE id % 5 WHEN 0 THEN 'en' WHEN 1 THEN 'hi' WHEN 2 THEN 'ko' WHEN 3 THEN 'ja' "
        "ELSE 'fr' END, '/p' || id || '.jpg', 1700000000 FROM titles WHERE id % 10 != 0",
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO title_genres (title_id, genre_id) '
        'SELECT t.id, 1 + (t.id * k) % 19 FROM titles t JOIN '
        '(SELECT 1 AS k UNION ALL SELECT 3 UNION ALL SELECT 5) ON t.id % 10 != 0',
      );
      await db.customStatement(
        'WITH RECURSIVE k(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM k WHERE i < 11) '
        'INSERT OR IGNORE INTO title_cast (title_id, person_id, ord) '
        'SELECT t.id, 1 + (t.id * 37 + k.i * 1009) % 20000, k.i FROM titles t, k '
        'WHERE t.id % 10 != 0',
      );
    });
    // ignore: avoid_print
    print('tmdb bulk insert ${sw.elapsedMilliseconds} ms');
    expect((await repo.tmdbProgress()).matched, greaterThan(n * 0.85));

    Future<int> time(Future<void> Function() f) async {
      await f(); // warm
      final t = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        await f();
      }
      return t.elapsedMilliseconds ~/ 5;
    }

    final browse = await time(() => repo.browse(const BrowseFilter()));
    final deep = await time(
      () => repo.browse(const BrowseFilter(), offset: 30000),
    );
    final filt = await time(
      () => repo.browse(
        BrowseFilter(
          categoryId: catIds[3],
          year: 1990,
          quality: 1080,
          language: 'Hindi',
        ),
      ),
    );
    // Poster join: results carry tmdb_meta.poster_path (90% matched).
    final posterPage = await repo.browse(const BrowseFilter(), limit: 200);
    expect(
      posterPage.where((t) => t.tmdbPosterPath != null).length,
      greaterThan(150),
    );
    final posterHits = await repo.search('dark rivr');
    expect(posterHits.any((t) => t.tmdbPosterPath != null), isTrue);
    final byYear = await time(
      () => repo.browse(
        const BrowseFilter(sort: BrowseSort.yearDesc),
        offset: 100,
      ),
    );
    final multi = await time(
      () => repo.browse(
        BrowseFilter(
          years: {1990, 2001, 2010},
          yearRanges: const [YearRange(to: 1960)],
          languages: {'Hindi', 'English'},
          qualities: {720, 1080},
        ),
      ),
    );
    final langOnly = await time(
      () => repo.browse(BrowseFilter(languages: {'Hindi'})),
    );
    final yearsFacet = await time(
      () => repo.years(BrowseFilter(languages: {'Hindi'})),
    );
    final cnt = await time(
      () => repo.countTitles(const BrowseFilter(year: 1990)),
    );
    final fts = await time(() => repo.search('dark rivr'));
    final fts2 = await time(
      () => repo.search(
        'night storm',
        filter: const BrowseFilter(language: 'English'),
      ),
    );
    final ftsRare = await time(() => repo.search('moon fire 31337'));

    final gBrowse = await time(
      () => repo.browse(BrowseFilter(genreIds: {3, 7})),
    );
    final gDeep = await time(
      () => repo.browse(BrowseFilter(genreIds: {3}), offset: 5000),
    );
    final gMulti = await time(
      () => repo.browse(
        BrowseFilter(
          genreIds: {3, 7},
          minRating: 7,
          originalLanguages: {'en', 'hi'},
          runtimes: {RuntimeBucket.medium, RuntimeBucket.long},
          languages: {'Hindi'},
          sort: BrowseSort.yearDesc,
        ),
      ),
    );
    final gCount = await time(
      () => repo.countTitles(BrowseFilter(genreIds: {3}, minRating: 5)),
    );
    final pBrowse = await time(
      () => repo.browse(const BrowseFilter(personId: 1234)),
    );
    final gSearch = await time(
      () => repo.search(
        'dark rivr',
        filter: BrowseFilter(genreIds: {3}, minRating: 5),
      ),
    );
    final genresFacet = await time(() => repo.genres());
    final genresScoped = await time(
      () => repo.genres(BrowseFilter(languages: {'Hindi'}, minRating: 5)),
    );
    final langFacet = await time(() => repo.tmdbLanguages());
    final pSearch = await time(() => repo.searchPeople('keanu reeves'));
    final pSearchPrefix = await time(() => repo.searchPeople('kea'));
    final pSearchShort = await time(() => repo.searchPeople('ra'));
    final needing = await time(() => repo.titlesNeedingTmdb());
    final progress = await time(() => repo.tmdbProgress());
    // ignore: avoid_print
    print(
      'genre $gBrowse ms, genre deep $gDeep ms, tmdb multi $gMulti ms, '
      'tmdb count $gCount ms, person browse $pBrowse ms, '
      'search+genre $gSearch ms, genres facet $genresFacet ms '
      '(scoped $genresScoped ms), tmdbLanguages $langFacet ms, '
      'people "keanu reeves" $pSearch ms, "kea" $pSearchPrefix ms, '
      '"ra" $pSearchShort ms, needing $needing ms, progress $progress ms',
    );
    expect(gBrowse, lessThan(50));
    expect(gDeep, lessThan(50));
    expect(gMulti, lessThan(50));
    expect(gCount, lessThan(50));
    expect(pBrowse, lessThan(50));
    expect(gSearch, lessThan(100));
    expect(genresFacet, lessThan(150));
    expect(genresScoped, lessThan(150));
    expect(langFacet, lessThan(100));
    expect(pSearch, lessThan(100));
    expect(pSearchPrefix, lessThan(100));
    expect(pSearchShort, lessThan(100));
    expect(needing, lessThan(100));
    expect(progress, lessThan(100));
    // ignore: avoid_print
    print(
      'browse $browse ms, deep $deep ms, filtered $filt ms, yearDesc $byYear ms, '
      'count $cnt ms, fts $fts ms, fts+filter $fts2 ms, fts rare $ftsRare ms',
    );
    // ignore: avoid_print
    print(
      'multi-facet $multi ms, langOnly $langOnly ms, yearsFacet $yearsFacet ms',
    );
    expect(multi, lessThan(50));
    expect(langOnly, lessThan(50));
    expect(yearsFacet, lessThan(100));
    final browseBig = await time(
      () => repo.browse(const BrowseFilter(), limit: 200),
    );
    // ignore: avoid_print
    print('poster join: browse 200 rows $browseBig ms');
    expect(browseBig, lessThan(50));
    expect(browse, lessThan(50));
    expect(deep, lessThan(50));
    expect(filt, lessThan(50));
    expect(fts, lessThan(100));
    expect(fts2, lessThan(100));
    expect(ftsRare, lessThan(100));
    // Lazy file loading: open a skeleton title, load, look files up, trim.
    final skel = (await repo.browse(
      const BrowseFilter(),
      limit: 200,
    )).firstWhere((t) => !t.filesLoaded && t.kind == TitleKind.series);
    final loadT = await time(
      () => repo.upsertTitleFiles(
        skel.id,
        seasons: [
          for (var s = 1; s <= 2; s++)
            SeasonDraft(
              number: s,
              label: 'S$s',
              folderUrl: '${skel.folderUrl}S$s/',
              files: [
                for (var e = 1; e <= 6; e++)
                  FileDraft(
                    name: 'e$e.mkv',
                    url: '${skel.folderUrl}S$s/e$e.mkv',
                    ext: 'mkv',
                    playable: true,
                  ),
              ],
            ),
        ],
      ),
    );
    final seasonsT = await time(() => repo.seasons(skel.id));
    final byUrlT = await time(
      () => repo.fileByUrl('${skel.folderUrl}S2/e3.mkv'),
    );
    expect(
      (await repo.fileByUrl('${skel.folderUrl}S2/e3.mkv'))!.name,
      'e3.mkv',
    );
    final trimT = await time(() => repo.trimFileCache(maxRows: 5000));
    // ignore: avoid_print
    print(
      'lazy load $loadT ms, seasons $seasonsT ms, fileByUrl $byUrlT ms, '
      'trim $trimT ms',
    );
    expect(loadT, lessThan(100));
    expect(seasonsT, lessThan(50));
    expect(byUrlT, lessThan(50));
    await repo.compact();
    final len = File('${dir.path}/p.db').lengthSync();
    // ignore: avoid_print
    print('db size ${(len / 1048576).toStringAsFixed(1)} MB');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
