/// Repository contract (C2). UI, search, player and downloads code against
/// this only; the drift implementation lives behind it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tmdb/tmdb_models.dart';
import 'models.dart';

/// Overridden at app start with the real implementation.
final repositoryProvider = Provider<Repository>(
  (ref) => throw UnimplementedError('repositoryProvider not overridden'),
);

abstract class Repository {
  // ---- Browse ----

  Future<List<Category>> categories();

  /// Paged titles matching [filter]. [offset]/[limit] are row based.
  Future<List<MediaTitle>> browse(
    BrowseFilter filter, {
    int offset = 0,
    int limit = 50,
  });

  /// Total rows for [filter] (for paging/"N results").
  Future<int> countTitles([BrowseFilter filter = const BrowseFilter()]);

  /// Distinct values for filter pickers, scoped by [within].
  Future<List<FacetValue<int>>> years([
    BrowseFilter within = const BrowseFilter(),
  ]);
  Future<List<FacetValue<String>>> languages([
    BrowseFilter within = const BrowseFilter(),
  ]);
  Future<List<FacetValue<int>>> qualities([
    BrowseFilter within = const BrowseFilter(),
  ]);

  /// TMDB genre facet (id, name, title count), most used first, scoped by
  /// [within] ignoring its own [BrowseFilter.genreIds].
  Future<List<FacetValue<TmdbGenre>>> genres([
    BrowseFilter within = const BrowseFilter(),
  ]);

  /// TMDB original-language facet (ISO code, title count), most used first,
  /// scoped by [within] ignoring its own [BrowseFilter.originalLanguages].
  Future<List<FacetValue<String>>> tmdbLanguages([
    BrowseFilter within = const BrowseFilter(),
  ]);

  /// Actors by name (partial/prefix, case-insensitive), best match first:
  /// exact name, name prefix, word prefix, other substring, then by number of
  /// library titles. Only people in at least one title. Empty query -> empty.
  Future<List<PersonHit>> searchPeople(String query, {int limit = 8});

  /// One actor with the number of library titles they are in; null if unknown.
  Future<PersonHit?> person(int id);

  // ---- Detail ----

  Future<MediaTitle?> title(int id);

  /// Series playlist: seasons ordered by number, episodes by
  /// (episode, name). Empty for movies. Returns what is STORED: seasons exist
  /// after a skeleton crawl but their `files` are empty until the title's
  /// files are loaded ([MediaTitle.filesLoaded]); stale rows may be returned
  /// until reloaded. [Season.episodeCount] is valid either way.
  Future<List<SeasonEpisodes>> seasons(int titleId);

  /// Files directly under a movie/event title (not in a season). Stored rows
  /// only; empty when the files are not loaded (check
  /// [MediaTitle.filesLoaded] / [titleFilesLoaded]).
  Future<List<MediaFile>> titleFiles(int titleId);

  /// A stored file row; null when unknown OR when the row was dropped
  /// (not loaded / evicted by [trimFileCache]). Ids of rows survive
  /// [upsertTitleFiles] as long as the file's relative path is unchanged.
  Future<MediaFile?> file(int id);

  /// Lookup by absolute file url; same caveat as [file]: only resolves while
  /// the title's file rows are stored.
  Future<MediaFile?> fileByUrl(String url);

  /// Id of the title whose folder contains [url] (a file or folder url), found
  /// without file rows; null when no indexed title contains it. Use it to
  /// protect titles with downloads in [trimFileCache].
  Future<int?> titleIdForUrl(String url);

  /// [fileByUrl], but when the title is indexed and the file row is not
  /// (files not loaded, evicted, or dropped by the v3 migration) a bare row
  /// is created so the file gets a stable id for watch/resume (a later
  /// [upsertTitleFiles] matches it by path and keeps the id). Null when no
  /// indexed title contains [url]. Use before playing a downloaded file.
  Future<MediaFile?> ensureFileByUrl(String url);

  /// True when the title's file rows are loaded and fresh
  /// ([MediaTitle.filesLoaded]). False for unknown ids.
  Future<bool> titleFilesLoaded(int titleId);

  /// Titles for [ids], in the order of [ids]; unknown ids are skipped.
  Future<List<MediaTitle>> titlesByIds(List<int> ids);

  /// Search titles (FTS + fuzzy), implemented by the search layer.
  Future<List<MediaTitle>> search(
    String query, {
    BrowseFilter filter = const BrowseFilter(),
    int offset = 0,
    int limit = 50,
  });

  /// Next playable episode after [fileId]. Playlist order: season number,
  /// then language group in listing order, then episode (range files sort by
  /// their start episode), then name. "Next" stays within the same language
  /// variant, rolling into the next season number of the same language;
  /// null when none.
  Future<MediaFile?> nextEpisode(int fileId);

  // ---- Watch progress ----

  Future<WatchState?> watchState(int fileId);
  Future<Map<int, WatchState>> watchStates(Iterable<int> fileIds);

  /// Stores progress. Auto-marks watched when durationMs > 0 and
  /// positionMs / durationMs >= 0.9.
  Future<void> setProgress(
    int fileId, {
    required int positionMs,
    required int durationMs,
  });

  /// markWatched(false) also resets position to 0.
  Future<void> markWatched(int fileId, {bool watched = true});

  /// Mark every file of a title (or one season) watched/unwatched.
  Future<void> markTitleWatched(
    int titleId, {
    int? seasonId,
    bool watched = true,
  });

  /// Files with positionMs > 0 and not watched, newest updatedAt first, at
  /// most one item per title (its most recently updated file).
  Future<List<ResumeItem>> continueWatching({int limit = 20});

  // ---- Crawler write side ----

  /// Insert/update categories (and sources) by url; returns url -> id.
  Future<Map<String, int>> upsertCategories(List<CategoryDraft> categories);

  /// Upsert by (categoryId, folderUrl). Returns the title id.
  /// [TitleDraft.validate] MUST be called; throws [ArgumentError] on
  /// violation. addedAt is set on first insert. Urls are stored relative to
  /// their parent (title folder to the category url; seasons, files and
  /// poster to the title folder); one that is not under its parent is kept
  /// absolute (works, but costs space).
  ///
  /// Full draft ([TitleDraft.filesLoaded] true): replaces the title's
  /// seasons/files, marks the files loaded and the counts exact.
  ///
  /// Skeleton draft (false): metadata and seasons are upserted, no file rows
  /// are written. For an EXISTING title with loaded files: if the draft's
  /// folderMtime equals the stored one the loaded files are kept untouched
  /// (still loaded); otherwise (changed, or either mtime unknown) they are
  /// marked stale (filesLoaded false) but their rows and ids are kept until
  /// the next [upsertTitleFiles]. Counts: [TitleDraft.fileCount] /
  /// [SeasonDraft.episodeCount] hints when given, else the stored values.
  ///
  /// Season identity: (titleId, folder) when SeasonDraft.folderUrl != null,
  /// else (titleId, number, language, label). File identity: (titleId, path
  /// relative to the title folder). Season ids and file ids MUST be preserved
  /// for identity matches, so MediaFile.seasonId and watch state never
  /// dangle.
  Future<int> upsertTitle(TitleDraft draft);

  /// Batch [upsertTitle] in a single transaction (bulk crawl speed). Same
  /// rules; one invalid draft aborts the whole batch.
  Future<void> upsertTitles(List<TitleDraft> drafts);

  /// Load a title's files (lazy, when the title is opened): REPLACES the
  /// title's file rows with [files] (movie/event) or the files of [seasons]
  /// (series; series must pass [files] empty, others [seasons] empty, else
  /// [ArgumentError]). Rows are matched by relative path, so ids (and watch
  /// state, season links) of unchanged files are preserved; rows not listed are
  /// deleted. Seasons are matched like [upsertTitle] (new ones created,
  /// unlisted ones removed). Sets filesLoaded, the exact file/season counts
  /// and the LRU timestamp. Unknown titleId -> [ArgumentError]. Emits
  /// [changes].
  Future<void> upsertTitleFiles(
    int titleId, {
    List<FileDraft> files = const [],
    List<SeasonDraft> seasons = const [],
  });

  /// Cache cap: while more than [maxRows] file rows are stored, drop the
  /// rows of the least recently loaded titles (stale ones first) and mark
  /// them not loaded (counts kept). NEVER evicts a title that has watch rows
  /// or is in [protectedTitleIds] (use for titles with downloads). Returns the
  /// number of file rows deleted. May leave more than [maxRows] rows when
  /// everything left is protected.
  Future<int> trimFileCache({
    int maxRows = 20000,
    Set<int> protectedTitleIds = const {},
  });

  /// Reclaim disk space after bulk writes: WAL checkpoint (truncate) and
  /// incremental vacuum of freed pages. Cheap; call after a crawl/trim.
  Future<void> compact();

  /// Existing folderUrl (absolute) -> folderMtime for a category (incremental
  /// crawl). A null mtime means the folder must always be re-crawled.
  Future<Map<String, DateTime?>> knownFolders(int categoryId);

  /// Delete titles in [categoryId] whose folderUrl is not in [keep].
  /// Returns the number removed.
  ///
  /// WARNING: [keep] must contain EVERY folderUrl that still exists in the
  /// category, including folders skipped as unchanged. Call only after a
  /// fully successful crawl of that category; a failed or partial crawl must
  /// never call it.
  Future<int> removeMissing(int categoryId, Set<String> keep);

  /// Wipe the whole index (watch state is kept unless [includeWatch]).
  Future<void> clearIndex({bool includeWatch = false});

  // ---- TMDB metadata ----

  /// Stored TMDB data (with genres and cast) for [titleId]; null when the
  /// title was never looked up.
  Future<TmdbInfo?> tmdbInfo(int titleId);

  /// Replace the title's TMDB meta, genres and cast with [d]. A `manual` row
  /// is only overwritten when [manual] is true. Upserts shared genre and
  /// person rows. Bulk background writes must not spam [changes]: emit at
  /// most once per call and let the UI debounce.
  Future<void> saveTmdbMatch(int titleId, TmdbDetails d, {bool manual = false});

  /// Record "searched, nothing found" so the title is not retried at once.
  /// No-op when the title already has a matched or manual row.
  Future<void> saveTmdbUnmatched(int titleId);

  /// Next batch for the background worker: movies and series with no meta
  /// row, or with an unmatched row older than [retryUnmatchedAfter]. Newest
  /// `addedAt` first.
  Future<List<MediaTitle>> titlesNeedingTmdb({
    int limit = 50,
    Duration retryUnmatchedAfter = const Duration(days: 30),
    TmdbQueueCursor? after,
  });

  /// Fires after TMDB data was written (match, unmatched, clear). Separate
  /// from [changes] on purpose: a background sync writes several times per
  /// second and must not refresh crawl-driven lists. Consumers throttle it.
  Stream<void> get tmdbChanges;

  /// Unmatched rows older than [retryUnmatchedAfter] count as pending again,
  /// in step with [titlesNeedingTmdb].
  Future<TmdbProgress> tmdbProgress({
    Duration retryUnmatchedAfter = const Duration(days: 30),
  });

  /// Delete all TMDB meta, genres, cast and people (keeps the crawl index).
  Future<void> clearTmdb();

  // ---- Counts ----

  /// [IndexCounts.files] sums the stored per-title file counts (not just the
  /// loaded rows).
  Future<IndexCounts> counts();

  /// Emits whenever the index changes (crawl finished, etc.).
  Stream<void> get changes;
}

/// Optional capability of a repository: coalesce [Repository.changes] while a
/// bulk write (the index run) is in progress. Not part of [Repository] so
/// existing fakes keep compiling.
abstract interface class ChangeThrottling {
  /// Emit [Repository.changes] at most once per [every] (leading edge
  /// immediately, trailing edge when something changed meanwhile); null
  /// restores immediate emission (and flushes a pending emit).
  void throttleChanges(Duration? every);
}

class IndexCounts {
  const IndexCounts({
    this.categories = 0,
    this.titles = 0,
    this.series = 0,
    this.files = 0,
    this.watched = 0,
  });
  final int categories;
  final int titles;
  final int series;
  final int files;
  final int watched;
}
