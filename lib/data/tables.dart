/// drift table definitions (schema v1). Internal to lib/data.
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
  TextColumn get folderUrl => text().unique()();
  IntColumn get year => integer().nullable()();
  IntColumn get yearEnd => integer().nullable()();
  IntColumn get quality => integer().nullable()();

  /// JSON array of strings.
  TextColumn get tags => text().withDefault(const Constant('[]'))();
  TextColumn get posterUrl => text().nullable()();

  /// Denormalised from the category.
  TextColumn get language => text().nullable()();
  DateTimeColumn get folderMtime => dateTime().nullable()();
  DateTimeColumn get addedAt => dateTime()();
  IntColumn get seasonCount => integer().withDefault(const Constant(0))();
  IntColumn get fileCount => integer().withDefault(const Constant(0))();
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
  TextColumn get folderUrl => text().nullable()();

  /// Position in the crawl listing (draft order).
  IntColumn get ord => integer().withDefault(const Constant(0))();
}

@DataClassName('FileRow')
@TableIndex(name: 'idx_files_title', columns: {#titleId})
@TableIndex(name: 'idx_files_season', columns: {#seasonId})
class Files extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get titleId =>
      integer().references(Titles, #id, onDelete: KeyAction.cascade)();
  IntColumn get seasonId => integer().nullable().references(Seasons, #id)();
  TextColumn get name => text()();
  TextColumn get url => text().unique()();
  TextColumn get ext => text()();
  BoolColumn get playable => boolean()();
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
