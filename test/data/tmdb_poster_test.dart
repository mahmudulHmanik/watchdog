import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';

TmdbDetails details(int id, {String? poster}) => TmdbDetails(
  id: id,
  mediaType: TmdbMediaType.movie,
  title: 't',
  overview: 'ov',
  tagline: null,
  rating: 7,
  voteCount: 10,
  runtime: 100,
  originalLanguage: 'en',
  year: 2000,
  posterPath: poster,
  backdropPath: null,
  genres: const [],
  cast: const [],
);

void main() {
  late AppDatabase db;
  late DriftRepository repo;
  late int cat;
  late Map<String, int> ids;

  Future<int> add(String name) => repo.upsertTitle(
    TitleDraft(
      categoryId: cat,
      name: name,
      kind: TitleKind.movie,
      folderUrl: 'http://h/$name/',
      files: [
        FileDraft(
          name: 'a.mkv',
          url: 'http://h/$name/a.mkv',
          ext: 'mkv',
          playable: true,
        ),
      ],
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
    ]);
    cat = m['http://h/en/']!;
    ids = {
      for (final n in ['Alpha', 'Bravo', 'Charlie', 'Delta']) n: await add(n),
    };
    await repo.saveTmdbMatch(ids['Alpha']!, details(1, poster: '/a.jpg'));
    await repo.saveTmdbMatch(
      ids['Bravo']!,
      details(2, poster: '/b.jpg'),
      manual: true,
    );
    await repo.saveTmdbUnmatched(ids['Charlie']!);
    // Delta: never looked up.
  });
  tearDown(() => repo.close());

  const expected = {
    'Alpha': '/a.jpg',
    'Bravo': '/b.jpg',
    'Charlie': null,
    'Delta': null,
  };

  void check(Iterable<MediaTitle> ts) {
    expect(ts, hasLength(4));
    for (final t in ts) {
      expect(t.tmdbPosterPath, expected[t.name], reason: t.name);
    }
  }

  test('browse', () async {
    check(await repo.browse(const BrowseFilter()));
    check(await repo.browse(const BrowseFilter(sort: BrowseSort.yearDesc)));
    check(
      await repo.browse(const BrowseFilter(sort: BrowseSort.recentlyAdded)),
    );
    expect(
      (await repo.browse(
        const BrowseFilter(),
        offset: 1,
        limit: 1,
      )).single.tmdbPosterPath,
      '/b.jpg',
    );
  });

  test('search', () async {
    for (final e in expected.entries) {
      final r = await repo.search(e.key);
      expect(r.first.name, e.key);
      expect(r.first.tmdbPosterPath, e.value, reason: e.key);
    }
    // Fuzzy path hydrates through the same join.
    expect((await repo.search('alpa')).first.tmdbPosterPath, '/a.jpg');
    // Blank query falls back to browse.
    check(await repo.search('  '));
  });

  test('title, titlesByIds', () async {
    for (final e in expected.entries) {
      expect((await repo.title(ids[e.key]!))!.tmdbPosterPath, e.value);
    }
    check(await repo.titlesByIds(ids.values.toList()));
  });

  test('continueWatching', () async {
    for (final n in ['Alpha', 'Charlie']) {
      final f = (await repo.titleFiles(ids[n]!)).single.id;
      await repo.setProgress(f, positionMs: 10, durationMs: 1000);
    }
    final r = {
      for (final i in await repo.continueWatching()) i.title.name: i.title,
    };
    expect(r['Alpha']!.tmdbPosterPath, '/a.jpg');
    expect(r['Charlie']!.tmdbPosterPath, isNull);
  });

  test('titlesNeedingTmdb leaves it null', () async {
    final r = await repo.titlesNeedingTmdb();
    expect(r.map((t) => t.name), contains('Delta'));
    expect(r.every((t) => t.tmdbPosterPath == null), isTrue);
  });

  test('matched without a poster stays null', () async {
    await repo.saveTmdbMatch(ids['Delta']!, details(4));
    expect((await repo.title(ids['Delta']!))!.tmdbPosterPath, isNull);
  });

  test('updates after saveTmdbMatch, disappears after clearTmdb', () async {
    final id = ids['Charlie']!;
    await repo.saveTmdbMatch(id, details(3, poster: '/c.jpg'));
    expect((await repo.title(id))!.tmdbPosterPath, '/c.jpg');
    await repo.saveTmdbMatch(id, details(3, poster: '/c2.jpg'), manual: true);
    expect(
      (await repo.browse(const BrowseFilter()))
          .firstWhere((t) => t.id == id)
          .tmdbPosterPath,
      '/c2.jpg',
    );
    await repo.clearTmdb();
    final all = await repo.browse(const BrowseFilter());
    expect(all, hasLength(4));
    expect(all.every((t) => t.tmdbPosterPath == null), isTrue);
    expect((await repo.search('alpha')).first.tmdbPosterPath, isNull);
  });
}
