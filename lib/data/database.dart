/// drift database (schema v2) on disk via a background isolate.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'tables.dart';

part 'database.g.dart';

/// FTS5 (trigram tokenizer) over title name + category name, rowid = titles.id,
/// kept in sync by triggers.
const ftsStatements = <String>[
  "CREATE VIRTUAL TABLE titles_fts USING fts5(name, category, tokenize='trigram')",
  '''CREATE TRIGGER titles_fts_ai AFTER INSERT ON titles BEGIN
  INSERT INTO titles_fts(rowid, name, category) VALUES
    (new.id, new.name, (SELECT name FROM categories WHERE id = new.category_id));
END''',
  '''CREATE TRIGGER titles_fts_ad AFTER DELETE ON titles BEGIN
  DELETE FROM titles_fts WHERE rowid = old.id;
END''',
  '''CREATE TRIGGER titles_fts_au AFTER UPDATE OF name, category_id ON titles BEGIN
  DELETE FROM titles_fts WHERE rowid = old.id;
  INSERT INTO titles_fts(rowid, name, category) VALUES
    (new.id, new.name, (SELECT name FROM categories WHERE id = new.category_id));
END''',
  '''CREATE TRIGGER categories_fts_au AFTER UPDATE OF name ON categories BEGIN
  UPDATE titles_fts SET category = new.name
    WHERE rowid IN (SELECT id FROM titles WHERE category_id = new.id);
END''',
];

/// FTS5 (trigram) over actor names, rowid = tmdb_people.id.
const peopleFtsStatements = <String>[
  "CREATE VIRTUAL TABLE people_fts USING fts5(name, tokenize='trigram')",
  '''CREATE TRIGGER people_fts_ai AFTER INSERT ON tmdb_people BEGIN
  INSERT INTO people_fts(rowid, name) VALUES (new.id, new.name);
END''',
  '''CREATE TRIGGER people_fts_ad AFTER DELETE ON tmdb_people BEGIN
  DELETE FROM people_fts WHERE rowid = old.id;
END''',
  '''CREATE TRIGGER people_fts_au AFTER UPDATE OF name ON tmdb_people BEGIN
  DELETE FROM people_fts WHERE rowid = old.id;
  INSERT INTO people_fts(rowid, name) VALUES (new.id, new.name);
END''',
];

@DriftDatabase(
  tables: [
    Sources,
    Categories,
    Titles,
    Seasons,
    Files,
    Watch,
    WatchKeep,
    TmdbMeta,
    TmdbGenres,
    TitleGenres,
    TmdbPeople,
    TitleCast,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// In-memory database for tests only.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final s in [...ftsStatements, ...peopleFtsStatements]) {
        await customStatement(s);
      }
    },
    // Next change: add `if (from < 3) {...}`, bump schemaVersion, run
    // `dart run drift_dev schema dump lib/data/database.dart drift_schemas`
    // and `dart run drift_dev schema generate drift_schemas test/data/generated`,
    // extend test/data/migration_test.dart.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // TMDB metadata, genres, cast (+ actor-name FTS).
        await m.createTable(tmdbMeta);
        await m.createTable(tmdbGenres);
        await m.createTable(titleGenres);
        await m.createTable(tmdbPeople);
        await m.createTable(titleCast);
        // createTable does not create @TableIndex indexes.
        await m.createIndex(idxTmdbMetaStatus);
        await m.createIndex(idxTmdbMetaRating);
        await m.createIndex(idxTmdbMetaLang);
        await m.createIndex(idxTitleGenresGenre);
        await m.createIndex(idxTitleCastPerson);
        for (final s in peopleFtsStatements) {
          await customStatement(s);
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Production database: `<app support dir>/watchdog.db`, WAL, opened in a
/// background isolate so the UI thread is never blocked.
Future<AppDatabase> openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return openDatabaseAt(File(p.join(dir.path, 'watchdog.db')));
}

/// Same as [openDatabase] for an explicit file (tests, tools).
AppDatabase openDatabaseAt(File file) => AppDatabase(
  NativeDatabase.createInBackground(
    file,
    setup: (db) {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA synchronous = NORMAL');
    },
  ),
);
