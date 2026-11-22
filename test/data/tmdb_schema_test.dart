import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/models.dart';

void main() {
  late AppDatabase db;
  late int titleId;

  setUp(() async {
    db = AppDatabase.memory();
    final src = await db
        .into(db.sources)
        .insert(SourcesCompanion.insert(host: '172.16.50.7'));
    final cat = await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(sourceId: src, name: 'English', url: 'u'),
        );
    titleId = await db
        .into(db.titles)
        .insert(
          TitlesCompanion.insert(
            categoryId: cat,
            name: 'The Matrix',
            sortKey: 'the matrix',
            kind: TitleKind.movie,
            folderRel: 'f/',
            addedAt: DateTime(2026),
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> seed() async {
    await db
        .into(db.tmdbMeta)
        .insert(
          TmdbMetaCompanion.insert(
            titleId: Value(titleId),
            status: TmdbStatus.matched,
            tmdbId: const Value(603),
            mediaType: const Value('movie'),
            rating: const Value(8.2),
            fetchedAt: DateTime(2026),
          ),
        );
    await db
        .into(db.tmdbGenres)
        .insert(
          TmdbGenresCompanion.insert(id: const Value(28), name: 'Action'),
        );
    await db
        .into(db.titleGenres)
        .insert(TitleGenresCompanion.insert(titleId: titleId, genreId: 28));
    await db
        .into(db.tmdbPeople)
        .insert(
          TmdbPeopleCompanion.insert(
            id: const Value(6384),
            name: 'Keanu Reeves',
          ),
        );
    await db
        .into(db.titleCast)
        .insert(
          TitleCastCompanion.insert(
            titleId: titleId,
            personId: 6384,
            character: const Value('Neo'),
          ),
        );
  }

  test(
    'deleting a title cascades to its TMDB rows, not to shared ones',
    () async {
      await seed();
      await (db.delete(db.titles)..where((t) => t.id.equals(titleId))).go();
      expect(await db.select(db.tmdbMeta).get(), isEmpty);
      expect(await db.select(db.titleGenres).get(), isEmpty);
      expect(await db.select(db.titleCast).get(), isEmpty);
      // Genre and person rows are shared between titles and stay.
      expect(await db.select(db.tmdbGenres).get(), hasLength(1));
      expect(await db.select(db.tmdbPeople).get(), hasLength(1));
    },
  );

  test(
    'people_fts finds actors by partial or misspelled-prefix name',
    () async {
      await seed();
      Future<List<int>> find(String q) async =>
          (await db
                  .customSelect(
                    'SELECT rowid FROM people_fts WHERE people_fts MATCH ?',
                    variables: [Variable<String>(q)],
                  )
                  .get())
              .map((r) => r.read<int>('rowid'))
              .toList();
      expect(await find('"keanu"'), [6384]);
      expect(await find('"eeve"'), [6384]);
      expect(await find('"nobody"'), isEmpty);
    },
  );

  test('people_fts follows renames and deletes', () async {
    await seed();
    await (db.update(db.tmdbPeople)..where((p) => p.id.equals(6384))).write(
      const TmdbPeopleCompanion(name: Value('Neo Anderson')),
    );
    Future<int> count(String q) async =>
        (await db
                .customSelect(
                  'SELECT rowid FROM people_fts WHERE people_fts MATCH ?',
                  variables: [Variable<String>(q)],
                )
                .get())
            .length;
    expect(await count('"keanu"'), 0);
    expect(await count('"anderson"'), 1);
    await (db.delete(db.titleCast)).go();
    await (db.delete(db.tmdbPeople)).go();
    expect(await count('"anderson"'), 0);
  });
}
