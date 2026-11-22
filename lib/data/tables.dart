/// drift table definitions (schema v3). Internal to lib/data.
library;

import 'package:drift/drift.dart';

import 'models.dart';

@DataClassName('SourceRow')
class Sources extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get host => text().unique()();
}

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId => integer().references(Sources, #id)();
  TextColumn get name => text()();
  TextColumn get url => text().unique()();
  TextColumn get language => text().nullable()();
}

@DataClassName('TitleRow')
@TableIndex(name: 'idx_titles_cat_sort', columns: {#categoryId, #sortKey})
@TableIndex(name: 'idx_titles_sort', columns: {#sortKey})
@TableIndex(name: 'idx_titles_year', columns: {#year})
@TableIndex(name: 'idx_titles_language', columns: {#language})
@TableIndex(name: 'idx_titles_quality', columns: {#quality})
@TableIndex(name: 'idx_titles_added', columns: {#addedAt})
class Titles extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();

  /// Lower-cased name, indexed for ordering.
  TextColumn get sortKey => text()();
  IntColumn get kind => intEnum<TitleKind>()();

  /// Title folder relative to the category url (percent-encoded, trailing
  /// slash, e.g. `(2019)/Some%20Movie/`). Absolute url = category.url + this.
  TextColumn get folderRel => text()();
  IntColumn get year => integer().nullable()();
  IntColumn get yearEnd => integer().nullable()();
  IntColumn get quality => integer().nullable()();

  /// JSON array of strings.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  /// Poster file relative to the title folder.
  TextColumn get posterRel => text().nullable()();

  /// Denormalised from the category.
  TextColumn get language => text().nullable()();
  DateTimeColumn get folderMtime => dateTime().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  /// Stored counts; valid whether or not file rows are loaded.
  IntColumn get seasonCount => integer().withDefault(const Constant(0))();
  IntColumn get fileCount => integer().withDefault(const Constant(0))();

  /// When the file rows were loaded (LRU key for the file cache). Null =
  /// files never loaded, or stale (rows may remain until reloaded).
  DateTimeColumn get filesLoadedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {categoryId, folderRel},
  ];
}

@DataClassName('SeasonRow')
@TableIndex(name: 'idx_seasons_title', columns: {#titleId})
class Seasons extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get titleId =>
      integer().references(Titles, #id, onDelete: KeyAction.cascade)();
  IntColumn get number => integer()();
  TextColumn get label => text()();
  TextColumn get language => text().nullable()();

  /// Season folder relative to the title folder (e.g. `Season%201/`).
  TextColumn get folderRel => text().nullable()();

  /// Episode count known without file rows (crawl hint / last load).
  IntColumn get episodeCount => integer().nullable()();

  /// Position in the crawl listing (draft order).
  IntColumn get ord => integer().withDefault(const Constant(0))();
}

@DataClassName('FileRow')
@TableIndex(name: 'idx_files_title', columns: {#titleId})
class Files extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get titleId =>
      integer().references(Titles, #id, onDelete: KeyAction.cascade)();
  IntColumn get seasonId => integer().nullable().references(Seasons, #id)();

  /// Path relative to the title folder (percent-encoded, includes season
  /// folder). Name, extension and playable are derived from it.
  TextColumn get rel => text()();
  IntColumn get episode => integer().nullable()();
  IntColumn get episodeEnd => integer().nullable()();
  IntColumn get sizeKb => integer().nullable()();
  DateTimeColumn get mtime => dateTime().nullable()();
}

@DataClassName('WatchRow')
class Watch extends Table {
  IntColumn get fileId =>
      integer().references(Files, #id, onDelete: KeyAction.cascade)();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  BoolColumn get watched => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {fileId};
}

/// Watch state parked by url while the index is cleared (re-attached on
/// re-crawl when the file reappears).
@DataClassName('WatchKeepRow')
class WatchKeep extends Table {
  TextColumn get url => text()();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  BoolColumn get watched => boolean()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {url};
}

// ---------------------------------------------------------------- TMDB (v2)

/// TMDB metadata for one title. Absent row = never looked up.
@DataClassName('TmdbMetaRow')
@TableIndex(name: 'idx_tmdb_meta_status', columns: {#status})
@TableIndex(name: 'idx_tmdb_meta_rating', columns: {#rating})
@TableIndex(name: 'idx_tmdb_meta_lang', columns: {#originalLanguage})
class TmdbMeta extends Table {
  IntColumn get titleId =>
      integer().references(Titles, #id, onDelete: KeyAction.cascade)();
  IntColumn get status => intEnum<TmdbStatus>()();

  /// Null when [status] is unmatched.
  IntColumn get tmdbId => integer().nullable()();

  /// `movie` or `tv`.
  TextColumn get mediaType => text().nullable()();
  TextColumn get overview => text().nullable()();
  TextColumn get tagline => text().nullable()();

  /// 0..10.
  RealColumn get rating => real().nullable()();
  IntColumn get voteCount => integer().nullable()();

  /// Minutes.
  IntColumn get runtime => integer().nullable()();
  TextColumn get originalLanguage => text().nullable()();
  IntColumn get releaseYear => integer().nullable()();
  TextColumn get posterPath => text().nullable()();
  TextColumn get backdropPath => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {titleId};
}

/// TMDB genre (movie and tv genres have separate ids, kept as TMDB has them).
@DataClassName('TmdbGenreRow')
class TmdbGenres extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TitleGenreRow')
@TableIndex(name: 'idx_title_genres_genre', columns: {#genreId})
class TitleGenres extends Table {
  IntColumn get titleId =>
      integer().references(Titles, #id, onDelete: KeyAction.cascade)();
  IntColumn get genreId => integer().references(TmdbGenres, #id)();

  @override
  Set<Column> get primaryKey => {titleId, genreId};
}

/// Actor. [id] is the TMDB person id, so it doubles as the FTS rowid.
@DataClassName('TmdbPersonRow')
class TmdbPeople extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get profilePath => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Top-billed cast of a title.
@DataClassName('TitleCastRow')
@TableIndex(name: 'idx_title_cast_person', columns: {#personId})
class TitleCast extends Table {
  IntColumn get titleId =>
      integer().references(Titles, #id, onDelete: KeyAction.cascade)();
  IntColumn get personId => integer().references(TmdbPeople, #id)();

  /// Billing order, 0 = lead.
  IntColumn get ord => integer().withDefault(const Constant(0))();
  TextColumn get character => text().nullable()();

  @override
  Set<Column> get primaryKey => {titleId, personId};
}
