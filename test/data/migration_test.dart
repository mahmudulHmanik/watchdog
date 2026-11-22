import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('fresh v3 database matches the dumped v3 schema', () async {
    final conn = await verifier.startAt(3);
    final db = AppDatabase(conn);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);
  });

  test('v1 database migrates to v3 and validates', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);
  });

  test('v2 database migrates to v3 and validates', () async {
    final schema = await verifier.schemaAt(2);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);
  });

  test('v1 -> v3 keeps data and adds TMDB tables with people FTS', () async {
    final schema = await verifier.schemaAt(1);
    final raw = schema.rawDatabase;
    raw.execute("INSERT INTO sources(host) VALUES ('h')");
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // Opening runs onUpgrade 1 -> 2.
    final names =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE name LIKE '%tmdb%' OR name LIKE 'title_%' OR name LIKE 'people_fts%'",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(
      names,
      containsAll([
        'tmdb_meta',
        'tmdb_genres',
        'title_genres',
        'tmdb_people',
        'title_cast',
        'people_fts',
        'people_fts_ai',
        'people_fts_ad',
        'people_fts_au',
      ]),
    );
    final src = await db.customSelect('SELECT host FROM sources').get();
    expect(src.single.read<String>('host'), 'h');
  });

  test('onCreate builds FTS table and sync triggers', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE name LIKE '%fts%'")
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    expect(
      names,
      containsAll([
        'titles_fts',
        'titles_fts_ai',
        'titles_fts_ad',
        'titles_fts_au',
        'categories_fts_au',
        'people_fts',
      ]),
    );
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), 3);
  });

  group('v2 -> v3 on a populated database', () {
    // Absolute urls as the v2 files table stored them.
    const catUrl = 'http://h/en/';
    const t1 = 'http://h/en/(2019)/Film%20One/';
    const t2 = 'http://h/en/Show/';
    const t3 = 'http://h/en/Film%20Three/';
    const t4 = 'http://h/en/Show%20Two/';

    Future<(AppDatabase, DriftRepository)> openMigrated(
      void Function(dynamic raw) seed,
    ) async {
      final schema = await verifier.schemaAt(2);
      final raw = schema.rawDatabase;
      // v2 had FTS (+ triggers) created by customStatement.
      for (final s in [...ftsStatements, ...peopleFtsStatements]) {
        raw.execute(s);
      }
      seed(raw);
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      return (db, DriftRepository(db));
    }

    void seedV2(dynamic raw) {
      raw.execute("INSERT INTO sources(id, host) VALUES (1, 'h')");
      raw.execute(
        "INSERT INTO categories(id, source_id, name, url, language) "
        "VALUES (1, 1, 'English', '$catUrl', 'English')",
      );
      void title(
        int id,
        String name,
        int kind,
        String url,
        String? poster,
        int seasons,
        int files,
      ) {
        raw.execute(
          'INSERT INTO titles(id, category_id, name, sort_key, kind, folder_url, '
          'year, tags, poster_url, language, folder_mtime, added_at, '
          'season_count, file_count) VALUES (?, 1, ?, ?, ?, ?, 2019, ?, ?, '
          "'English', 1700000000, 1700000000, ?, ?)",
          [
            id,
            name,
            name.toLowerCase(),
            kind,
            url,
            '[]',
            poster,
            seasons,
            files,
          ],
        );
      }

      title(1, 'Film One', 0, t1, '${t1}poster.jpg', 0, 2);
      title(2, 'Show', 1, t2, null, 2, 3);
      title(3, 'Film Three', 0, t3, null, 0, 1);
      title(4, 'Show Two', 1, t4, '${t4}p.jpg', 1, 2);
      void season(int id, int title, int n, String? url, int ord) =>
          raw.execute(
            'INSERT INTO seasons(id, title_id, number, label, language, folder_url, '
            "ord) VALUES (?, ?, ?, 'S', NULL, ?, ?)",
            [id, title, n, url, ord],
          );
      season(10, 2, 1, '${t2}Season%201/', 0);
      season(11, 2, 2, null, 1);
      season(12, 4, 1, '${t4}Season%201/', 0);
      void file(int id, int title, int? season, String url, int? ep) =>
          raw.execute(
            'INSERT INTO files(id, title_id, season_id, name, url, ext, '
            'playable, episode, size_kb, mtime) VALUES (?, ?, ?, ?, ?, ?, 1, '
            '?, 5, 1700000000)',
            [id, title, season, 'n', url, 'mkv', ep],
          );
      file(100, 1, null, '${t1}Film.One.mkv', null);
      file(101, 1, null, '${t1}Film.One.2.mkv', null);
      file(200, 2, 10, '${t2}Season%201/e01.mkv', 1);
      file(201, 2, 10, '${t2}Season%201/e02.mkv', 2);
      file(202, 2, 11, '${t2}e03.mkv', 3);
      file(300, 3, null, '${t3}Three.mkv', null);
      file(400, 4, 12, '${t4}Season%201/e01.mkv', 1);
      file(401, 4, 12, '${t4}Season%201/e02.mkv', 2);
      // Highest id ever used was 999: dropped ids must not come back.
      raw.execute("UPDATE sqlite_sequence SET seq = 999 WHERE name = 'files'");
      raw.execute(
        'INSERT INTO watch(file_id, position_ms, duration_ms, watched, '
        'updated_at) VALUES (100, 5000, 10000, 0, 1700000100), '
        '(201, 0, 0, 1, 1700000200)',
      );
      raw.execute(
        'INSERT INTO watch_keep(url, position_ms, duration_ms, watched, '
        "updated_at) VALUES ('${t3}Three.mkv', 1, 2, 0, 1700000300)",
      );
      raw.execute(
        'INSERT INTO tmdb_meta(title_id, status, tmdb_id, rating, fetched_at) '
        'VALUES (1, 0, 603, 8.1, 1700000000)',
      );
      raw.execute("INSERT INTO tmdb_genres(id, name) VALUES (28, 'Action')");
      raw.execute(
        'INSERT INTO title_genres(title_id, genre_id) VALUES (1, 28)',
      );
      raw.execute(
        "INSERT INTO tmdb_people(id, name) VALUES (6384, 'Keanu Reeves')",
      );
      raw.execute(
        'INSERT INTO title_cast(title_id, person_id, ord) VALUES (1, 6384, 0)',
      );
    }

    test('keeps ids, watch, tmdb, fts; composes the same urls', () async {
      final (db, repo) = await openMigrated(seedV2);
      // Titles: ids, absolute urls and poster compose back unchanged.
      final all = await repo.browse(const BrowseFilter());
      expect(all.map((t) => t.id).toSet(), {1, 2, 3, 4});
      final one = (await repo.title(1))!;
      expect(one.folderUrl, t1);
      expect(one.posterUrl, '${t1}poster.jpg');
      expect((await repo.title(2))!.posterUrl, isNull);
      expect((await repo.title(4))!.posterUrl, '${t4}p.jpg');
      expect(one.fileCount, 2);
      expect((await repo.title(2))!.seasonCount, 2);

      // Titles with watch rows keep their files (loaded); others do not.
      expect(one.filesLoaded, isTrue);
      expect((await repo.title(2))!.filesLoaded, isTrue);
      expect((await repo.title(3))!.filesLoaded, isFalse);
      expect((await repo.title(4))!.filesLoaded, isFalse);
      expect(await repo.titleFilesLoaded(1), isTrue);
      expect(await repo.titleFilesLoaded(3), isFalse);
      expect((await repo.titleFiles(1)).map((f) => f.url).toSet(), {
        '${t1}Film.One.mkv',
        '${t1}Film.One.2.mkv',
      });
      expect(
        (await repo.titleFiles(1)).first.name.startsWith('Film.One'),
        isTrue,
      );
      expect(await repo.titleFiles(3), isEmpty);
      expect(await repo.titleFiles(4), isEmpty);
      final s2 = await repo.seasons(2);
      expect(s2.map((s) => s.season.id), [10, 11]);
      expect(s2[0].season.folderUrl, '${t2}Season%201/');
      expect(s2[1].season.folderUrl, isNull);
      expect(s2.map((s) => s.files.map((f) => f.id).toList()), [
        [200, 201],
        [202],
      ]);
      expect(s2[0].files[0].url, '${t2}Season%201/e01.mkv');
      expect(s2[0].files[0].name, 'e01.mkv');
      expect(s2[1].files[0].url, '${t2}e03.mkv');
      // Season of a dropped title: no files, count kept.
      final s4 = await repo.seasons(4);
      expect(s4.single.files, isEmpty);
      expect(s4.single.season.episodeCount, 2);
      expect(s4.single.season.id, 12);

      // Watch rows still point at the same files.
      expect((await repo.watchState(100))!.positionMs, 5000);
      expect((await repo.watchState(201))!.watched, isTrue);
      expect((await repo.file(100))!.url, '${t1}Film.One.mkv');
      expect((await repo.fileByUrl('${t2}Season%201/e02.mkv'))!.id, 201);
      expect((await repo.continueWatching()).single.file.id, 100);
      expect(await repo.fileByUrl('${t3}Three.mkv'), isNull);

      // TMDB data and FTS survive; triggers keep working.
      expect((await repo.tmdbInfo(1))!.genres.single.name, 'Action');
      expect((await repo.searchPeople('keanu')).single.id, 6384);
      expect((await repo.search('film one')).map((t) => t.id), contains(1));
      expect((await repo.search('show two')).map((t) => t.id), contains(4));
      final fresh = await repo.upsertTitle(
        TitleDraft(
          categoryId: 1,
          name: 'Brand New',
          kind: TitleKind.movie,
          folderUrl: '${catUrl}Brand%20New/',
          files: [
            FileDraft(
              name: 'x.mkv',
              url: '${catUrl}Brand%20New/x.mkv',
              ext: 'mkv',
              playable: true,
            ),
          ],
        ),
      );
      expect(fresh, greaterThan(4));
      expect((await repo.search('brand new')).single.id, fresh);
      final newFile = (await repo.titleFiles(fresh)).single;
      expect(
        newFile.id,
        greaterThan(999),
        reason: 'ids of dropped rows unused',
      );

      // Structure: FK check clean, FTS triggers back, indexes present.
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      final names =
          (await db.customSelect('SELECT name FROM sqlite_master').get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(
        names,
        containsAll([
          'titles_fts_ai',
          'titles_fts_ad',
          'titles_fts_au',
          'categories_fts_au',
          'idx_titles_cat_sort',
          'idx_titles_added',
          'idx_files_title',
          'idx_seasons_title',
        ]),
      );
      expect(names, isNot(contains('idx_files_season')));
      expect(names.where((n) => n.endsWith('_v2')), isEmpty);
      // A stale unique key: (category, folder_rel).
      final dup = db.customStatement(
        "INSERT INTO titles(category_id, name, sort_key, kind, folder_rel, "
        "added_at) VALUES (1, 'x', 'x', 0, '(2019)/Film%20One/', 1)",
      );
      await expectLater(dup, throwsA(anything));
    });

    test(
      'parked watch_keep re-attaches via stub rows on a skeleton crawl',
      () async {
        final (_, repo) = await openMigrated(seedV2);
        // watch_keep url under title 3 (files were dropped by the migration).
        await repo.upsertTitle(
          TitleDraft(
            categoryId: 1,
            name: 'Film Three',
            kind: TitleKind.movie,
            folderUrl: t3,
            filesLoaded: false,
          ),
        );
        final f = (await repo.fileByUrl('${t3}Three.mkv'))!;
        expect((await repo.watchState(f.id))!.positionMs, 1);
      },
    );
  });

  // Needs a copy of a real v2 database: WD_REAL_DB=/path/to/copy.db
  final realPath = Platform.environment['WD_REAL_DB'];
  test(
    'real v2 database copy migrates to a small v3 file',
    () async {
      final dir = Directory.systemTemp.createTempSync('wd_real');
      addTearDown(() => dir.deleteSync(recursive: true));
      final copy = File('${dir.path}/real.db');
      File(realPath!).copySync(copy.path);
      final before = copy.lengthSync();
      final sw = Stopwatch()..start();
      final db = openDatabaseAt(copy);
      final repo = DriftRepository(db);
      final counts = await repo.counts();
      final tMigrate = sw.elapsedMilliseconds;
      await repo.compact();
      final after = copy.lengthSync();
      final wal = File('${copy.path}-wal');
      Future<int> n(String sql) async =>
          (await db.customSelect(sql).getSingle()).data.values.first as int;
      final rows = {
        for (final t in [
          'titles',
          'seasons',
          'files',
          'watch',
          'watch_keep',
          'tmdb_meta',
          'title_cast',
        ])
          t: await n('SELECT COUNT(*) FROM $t'),
      };
      final av = await n('PRAGMA auto_vacuum');
      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      // ignore: avoid_print
      print(
        'real db: ${(before / 1048576).toStringAsFixed(1)} MB -> '
        '${(after / 1048576).toStringAsFixed(1)} MB '
        '(wal ${wal.existsSync() ? wal.lengthSync() : 0} B), '
        'migrate+vacuum $tMigrate ms, auto_vacuum=$av, rows $rows, '
        'counts titles=${counts.titles} files(sum)=${counts.files}',
      );
      expect(fk, isEmpty);
      expect(av, 2);
      expect(after, lessThan(30 * 1048576));
      expect(rows['files'], rows['watch']! > 0 ? greaterThan(0) : 0);
      // Every watch row still resolves to a file with a composed url.
      final w = await db.customSelect('SELECT file_id FROM watch').get();
      for (final r in w) {
        final f = await repo.file(r.read<int>('file_id'));
        expect(f, isNotNull);
        expect(f!.url, startsWith('http'));
        expect((await repo.fileByUrl(f.url))!.id, f.id);
      }
      final hits = await repo.search('the');
      expect(hits, isNotEmpty);
      expect(hits.first.folderUrl, startsWith('http'));
      await repo.close();
    },
    skip: realPath == null ? 'set WD_REAL_DB to a copy of a v2 database' : null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
