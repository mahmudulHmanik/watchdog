/// drift database (schema v1) on disk via a background isolate.
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

@DriftDatabase(
  tables: [Sources, Categories, Titles, Seasons, Files, Watch, WatchKeep],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// In-memory database for tests only.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final s in ftsStatements) {
        await customStatement(s);
      }
    },
    // Add `if (from < 2) {...}` steps here when the schema changes; bump
    // schemaVersion, run `dart run drift_dev schema dump`, extend
    // test/data/migration_test.dart.
    onUpgrade: (m, from, to) async {},
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
