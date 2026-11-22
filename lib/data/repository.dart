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
  /// (episode, name). Empty for movies.
  Future<List<SeasonEpisodes>> seasons(int titleId);

  /// Files directly under a movie/event title (not in a season).
  Future<List<MediaFile>> titleFiles(int titleId);

  Future<MediaFile?> file(int id);

  /// Lookup by absolute file url (files identity).
  Future<MediaFile?> fileByUrl(String url);

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

  /// Upsert by folderUrl, replacing the title's seasons/files. Returns the
  /// title id. [TitleDraft.validate] MUST be called; throws [ArgumentError]
  /// on violation. addedAt is set on first insert only.
  ///
  /// Season identity: (titleId, folderUrl) when SeasonDraft.folderUrl != null,
  /// else (titleId, number, language, label). File identity: url. Season ids
  /// and file ids MUST be preserved for identity matches, so
  /// MediaFile.seasonId and watch state never dangle.
  Future<int> upsertTitle(TitleDraft draft);

  /// Batch [upsertTitle] in a single transaction (bulk crawl speed). Same
  /// rules; one invalid draft aborts the whole batch.
  Future<void> upsertTitles(List<TitleDraft> drafts);

  /// Existing folderUrl -> folderMtime for a category (incremental crawl).
  /// A null mtime means the folder must always be re-crawled.
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
  });

  /// Unmatched rows older than [retryUnmatchedAfter] count as pending again,
  /// in step with [titlesNeedingTmdb].
  Future<TmdbProgress> tmdbProgress({
    Duration retryUnmatchedAfter = const Duration(days: 30),
  });

  /// Delete all TMDB meta, genres, cast and people (keeps the crawl index).
  Future<void> clearTmdb();

  // ---- Counts ----

  Future<IndexCounts> counts();

  /// Emits whenever the index changes (crawl finished, etc.).
  Stream<void> get changes;
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
