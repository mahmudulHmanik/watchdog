/// drift database (schema v3) on disk via a background isolate.
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
const ftsTableStatement =
    "CREATE VIRTUAL TABLE titles_fts USING fts5(name, category, tokenize='trigram')";

/// The sync triggers of [ftsTableStatement]; they reference titles(name,
/// category_id), so drop/recreate them around any rebuild of `titles`.
const ftsTriggerNames = [
  'titles_fts_ai',
  'titles_fts_ad',
  'titles_fts_au',
  'categories_fts_au',
];

const ftsStatements = <String>[ftsTableStatement, ...ftsTriggerStatements];

const ftsTriggerStatements = <String>[
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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final s in [...ftsStatements, ...peopleFtsStatements]) {
        await customStatement(s);
      }
    },
    // Next change: add `if (from < 4) {...}`, bump schemaVersion, run
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
      if (from < 3) await _toV3(m);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      final before = details.versionBefore;
      if (before != null && before < 3) {
        // The v3 migration dropped most rows; give the pages back. VACUUM
        // cannot run inside onUpgrade's transaction. Setting auto_vacuum
        // first makes this VACUUM switch the file to INCREMENTAL mode.
        await customStatement('PRAGMA auto_vacuum = INCREMENTAL');
        await customStatement('VACUUM');
        await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      }
    },
  );

  /// v2 -> v3: relative paths, no per-file name/ext/playable/url, lazy files.
  /// Keeps every id, watch/watch_keep, tmdb_*, and the FILE ROWS of titles that
  /// have watch rows (so watch.file_id still points at the right file); all
  /// other file rows are dropped (files_loaded_at NULL, counts kept).
  Future<void> _toV3(Migrator m) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Skips the "schema is inconsistent" check of RENAME while tables are
    // missing; foreign keys are off during migrations.
    await customStatement('PRAGMA legacy_alter_table = 1');
    for (final t in ftsTriggerNames) {
      await customStatement('DROP TRIGGER IF EXISTS $t');
    }
    for (final t in ['files', 'seasons', 'titles']) {
      await customStatement('ALTER TABLE $t RENAME TO ${t}_v2');
    }
    await m.createTable(titles);
    await m.createTable(seasons);
    await m.createTable(files);
    await customStatement('''
INSERT INTO titles (id, category_id, name, sort_key, kind, folder_rel, year,
  year_end, quality, tags, poster_rel, language, folder_mtime, added_at,
  season_count, file_count, files_loaded_at)
SELECT t.id, t.category_id, t.name, t.sort_key, t.kind,
  CASE WHEN substr(t.folder_url, 1, length(c.url)) = c.url
    THEN substr(t.folder_url, length(c.url) + 1) ELSE t.folder_url END,
  t.year, t.year_end, t.quality, t.tags,
  CASE WHEN t.poster_url IS NULL THEN NULL
    WHEN substr(t.poster_url, 1, length(t.folder_url)) = t.folder_url
    THEN substr(t.poster_url, length(t.folder_url) + 1) ELSE t.poster_url END,
  t.language, t.folder_mtime, t.added_at, t.season_count, t.file_count,
  CASE WHEN t.id IN (SELECT f.title_id FROM watch w
                     JOIN files_v2 f ON f.id = w.file_id)
    THEN $now ELSE NULL END
FROM titles_v2 t JOIN categories c ON c.id = t.category_id''');
    await customStatement('''
INSERT INTO seasons (id, title_id, number, label, language, folder_rel,
  episode_count, ord)
SELECT s.id, s.title_id, s.number, s.label, s.language,
  CASE WHEN s.folder_url IS NULL THEN NULL
    WHEN substr(s.folder_url, 1, length(t.folder_url)) = t.folder_url
    THEN substr(s.folder_url, length(t.folder_url) + 1) ELSE s.folder_url END,
  (SELECT COUNT(*) FROM files_v2 f WHERE f.season_id = s.id), s.ord
FROM seasons_v2 s JOIN titles_v2 t ON t.id = s.title_id''');
    await customStatement(
      '''
INSERT INTO files (id, title_id, season_id, rel, episode, episode_end,
  size_kb, mtime)
SELECT f.id, f.title_id, f.season_id,
  CASE WHEN substr(f.url, 1, length(t.folder_url)) = t.folder_url
    THEN substr(f.url, length(t.folder_url) + 1) ELSE f.url END,
  f.episode, f.episode_end, f.size_kb, f.mtime
FROM files_v2 f JOIN titles_v2 t ON t.id = f.title_id
WHERE f.title_id IN (SELECT id FROM titles WHERE files_loaded_at IS NOT NULL)''',
    );
    // AUTOINCREMENT high-water marks: ids of dropped rows must never be reused
    // (download task metadata still holds old file ids).
    for (final t in ['files', 'seasons', 'titles']) {
      await customStatement('DELETE FROM sqlite_sequence WHERE name = ?', [t]);
      await customStatement(
        'INSERT INTO sqlite_sequence (name, seq) '
        "SELECT ?, seq FROM sqlite_sequence WHERE name = '${t}_v2'",
        [t],
      );
    }
    for (final t in ['files', 'seasons', 'titles']) {
      await customStatement('DROP TABLE ${t}_v2'); // takes its indexes along
    }
    // createTable does not create @TableIndex indexes.
    await m.createIndex(idxTitlesCatSort);
    await m.createIndex(idxTitlesSort);
    await m.createIndex(idxTitlesYear);
    await m.createIndex(idxTitlesLanguage);
    await m.createIndex(idxTitlesQuality);
    await m.createIndex(idxTitlesAdded);
    await m.createIndex(idxSeasonsTitle);
    await m.createIndex(idxFilesTitle);
    for (final s in ftsTriggerStatements) {
      await customStatement(s);
    }
    await customStatement('PRAGMA legacy_alter_table = 0');
  }
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
      // Only takes effect on a new file (an old file converts on its VACUUM
      // after the v3 migration); lets compact() return freed pages.
      db.execute('PRAGMA auto_vacuum = INCREMENTAL');
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA synchronous = NORMAL');
    },
  ),
);
