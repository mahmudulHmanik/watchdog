/// Plain immutable domain models (contract C1). No drift types here.
library;

import '../tmdb/tmdb_images.dart';
import '../tmdb/tmdb_models.dart';

enum TitleKind { movie, series, event }

/// Outcome of matching a title against TMDB.
enum TmdbStatus {
  /// Matched automatically.
  matched,

  /// Searched, nothing trustworthy found (retry after a while or fix by hand).
  unmatched,

  /// Chosen by the user; the worker never overwrites it.
  manual,
}

/// Top-level DhakaFlix category (e.g. "English Movies"), from a source server.
class Category {
  const Category({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.url,
    this.language,
    this.titleCount = 0,
  });
  final int id;
  final int sourceId;
  final String name;

  /// Absolute category folder URL.
  final String url;

  /// Language derived from the category folder name (not from audio tracks).
  final String? language;
  final int titleCount;
}

/// A movie, series or event folder.
class MediaTitle {
  const MediaTitle({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.kind,
    required this.folderUrl,
    this.year,
    this.yearEnd,
    this.quality,
    this.tags = const [],
    this.posterUrl,
    this.language,
    this.folderMtime,
    required this.addedAt,
    this.seasonCount = 0,
    this.fileCount = 0,
    this.tmdbPosterPath,
    this.filesLoaded = true,
  });
  final int id;
  final int categoryId;
  final String name;
  final TitleKind kind;

  /// Absolute URL of the title folder; unique key for upserts.
  final String folderUrl;
  final int? year;
  final int? yearEnd;

  /// Vertical resolution, e.g. 1080.
  final int? quality;
  final List<String> tags;
  final String? posterUrl;

  /// Inherited from the category.
  final String? language;

  /// Listing mtime of the folder, for incremental crawls.
  final DateTime? folderMtime;

  /// First-seen time, set by the repository on first insert and never
  /// changed by a re-crawl. [BrowseSort.recentlyAdded] sorts by it, desc.
  final DateTime addedAt;

  /// Stored counts; valid even while [filesLoaded] is false (skeleton crawl).
  final int seasonCount;
  final int fileCount;

  /// False until the file/episode rows were loaded for this title (lazy,
  /// on open) or after a re-crawl saw the folder change (stale). While false,
  /// [Repository.seasons]/[Repository.titleFiles] return what is stored (may
  /// be empty or stale): load the title's files, then call
  /// [Repository.upsertTitleFiles].
  final bool filesLoaded;

  /// TMDB poster file path (joined from `tmdb_meta`); null when the title has
  /// no TMDB data. Use [bestPosterUrl] to display.
  final String? tmdbPosterPath;

  /// The server's own poster when there is one, else the TMDB poster (list
  /// size). Null when neither exists.
  String? get bestPosterUrl =>
      posterUrl ?? tmdbImageUrl(tmdbPosterPath, TmdbImageSize.poster);
}

/// A season folder. number 0 = specials / unparsed.
class Season {
  const Season({
    required this.id,
    required this.titleId,
    required this.number,
    required this.label,
    this.language,
    this.folderUrl,
    this.episodeCount = 0,
  });
  final int id;
  final int titleId;
  final int number;
  final String label;

  /// Audio-language variant parsed from the folder name, if any.
  final String? language;

  /// Absolute season folder URL (title folder + stored relative path).
  final String? folderUrl;

  /// Stored count: valid before the title's files are loaded.
  final int episodeCount;
}

/// A file inside a title (movie file or episode).
class MediaFile {
  const MediaFile({
    required this.id,
    required this.titleId,
    required this.name,
    required this.url,
    required this.ext,
    required this.playable,
    this.seasonId,
    this.episode,
    this.episodeEnd,
    this.sizeKb,
    this.mtime,
  });
  final int id;
  final int titleId;
  final int? seasonId;
  final String name;

  /// Absolute, percent-encoded URL.
  final String url;

  /// Lower-case extension without dot.
  final String ext;

  /// False for .rar/.zip etc.
  final bool playable;
  final int? episode;

  /// Last episode for range files (E01-E05).
  final int? episodeEnd;
  final int? sizeKb;
  final DateTime? mtime;
}

/// Per-file watch progress.
class WatchState {
  const WatchState({
    required this.fileId,
    this.positionMs = 0,
    this.durationMs = 0,
    this.watched = false,
    this.updatedAt,
  });
  final int fileId;
  final int positionMs;
  final int durationMs;
  final bool watched;
  final DateTime? updatedAt;

  /// 0..1; 0 when duration unknown.
  double get fraction =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);
}

/// Resume entry: file with its title, for "continue watching".
class ResumeItem {
  const ResumeItem({
    required this.title,
    required this.file,
    required this.state,
    this.seasonNumber,
  });
  final MediaTitle title;
  final MediaFile file;
  final WatchState state;

  /// Number of the season folder the file is in (0 = specials); null for
  /// files that are not in a season.
  final int? seasonNumber;
}

/// Season with its episodes, in playback order.
class SeasonEpisodes {
  const SeasonEpisodes({required this.season, required this.files});
  final Season season;
  final List<MediaFile> files;
}

/// Inclusive year range; a null bound is open-ended.
class YearRange {
  const YearRange({this.from, this.to});
  final int? from;
  final int? to;

  bool contains(int year) =>
      (from == null || year >= from!) && (to == null || year <= to!);

  @override
  bool operator ==(Object other) =>
      other is YearRange && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
  @override
  String toString() => 'YearRange($from..$to)';
}

// ignore_for_file: prefer_initializing_formals

const _unset = Object();

/// Runtime facet (minutes, from TMDB). Half-open: [minMinutes, maxMinutes).
/// Titles without a known runtime match no bucket.
enum RuntimeBucket {
  short(null, 90, '< 90 min'),
  medium(90, 120, '90-120 min'),
  long(120, 150, '120-150 min'),
  epic(150, null, '150+ min');

  const RuntimeBucket(this.minMinutes, this.maxMinutes, this.label);

  /// Inclusive lower bound, null = open.
  final int? minMinutes;

  /// Exclusive upper bound, null = open.
  final int? maxMinutes;
  final String label;

  bool contains(int minutes) =>
      (minMinutes == null || minutes >= minMinutes!) &&
      (maxMinutes == null || minutes < maxMinutes!);
}

/// Browse/search filter. Semantics: OR within a facet, AND across facets;
/// an empty set/list means no constraint. A title matches the year facet when
/// its year is in [years] OR inside any of [yearRanges]. Value-equal filters
/// compare equal (used as provider keys).
///
/// TMDB facets ([genreIds], [minRating], [originalLanguages], [runtimes],
/// [personId]) only match titles that have TMDB data; titles without it never
/// match while one of them is active.
class BrowseFilter {
  const BrowseFilter({
    this.categoryId,
    Set<int> years = const {},
    this.yearRanges = const [],
    Set<String> languages = const {},
    Set<int> qualities = const {},
    this.kind,
    this.sort = BrowseSort.nameAsc,
    this.genreIds = const {},
    this.minRating,
    this.originalLanguages = const {},
    this.runtimes = const {},
    this.personId,
    @Deprecated('Use years') int? year,
    @Deprecated('Use languages') String? language,
    @Deprecated('Use qualities') int? quality,
  }) : _years = years,
       _languages = languages,
       _qualities = qualities,
       _legacyYear = year,
       _legacyLanguage = language,
       _legacyQuality = quality;

  final int? categoryId;
  final TitleKind? kind;
  final BrowseSort sort;

  final Set<int> _years;
  final Set<String> _languages;
  final Set<int> _qualities;
  final int? _legacyYear;
  final String? _legacyLanguage;
  final int? _legacyQuality;

  /// Exact years (OR).
  Set<int> get years => _legacyYear == null ? _years : {..._years, _legacyYear};

  /// Inclusive ranges (OR with [years]), e.g. 'Older' = `YearRange(to: 2009)`.
  final List<YearRange> yearRanges;
  Set<String> get languages =>
      _legacyLanguage == null ? _languages : {..._languages, _legacyLanguage};
  Set<int> get qualities =>
      _legacyQuality == null ? _qualities : {..._qualities, _legacyQuality};

  @Deprecated('Use years')
  int? get year => years.length == 1 && yearRanges.isEmpty ? years.first : null;
  @Deprecated('Use languages')
  String? get language => languages.length == 1 ? languages.first : null;
  @Deprecated('Use qualities')
  int? get quality => qualities.length == 1 ? qualities.first : null;

  bool get hasYearFilter => years.isNotEmpty || yearRanges.isNotEmpty;

  /// TMDB genre ids (OR).
  final Set<int> genreIds;

  /// Minimum TMDB rating (0..10), inclusive.
  final double? minRating;

  /// TMDB `original_language` ISO codes (OR), e.g. `{'en', 'hi'}`.
  final Set<String> originalLanguages;

  /// Runtime buckets (OR).
  final Set<RuntimeBucket> runtimes;

  /// Only titles whose stored cast includes this TMDB person id.
  final int? personId;

  bool get hasGenreFilter => genreIds.isNotEmpty;
  bool get hasRatingFilter => minRating != null;
  bool get hasOriginalLanguageFilter => originalLanguages.isNotEmpty;
  bool get hasRuntimeFilter => runtimes.isNotEmpty;
  bool get hasPersonFilter => personId != null;

  /// Number of active TMDB facets (0..5).
  int get tmdbFilterCount =>
      (hasGenreFilter ? 1 : 0) +
      (hasRatingFilter ? 1 : 0) +
      (hasOriginalLanguageFilter ? 1 : 0) +
      (hasRuntimeFilter ? 1 : 0) +
      (hasPersonFilter ? 1 : 0);

  bool get hasTmdbFilter => tmdbFilterCount > 0;

  /// Number of active facets: category, year, language, quality + TMDB ones.
  /// [kind] and [sort] are not counted.
  int get activeCount =>
      (categoryId != null ? 1 : 0) +
      (hasYearFilter ? 1 : 0) +
      (languages.isNotEmpty ? 1 : 0) +
      (qualities.isNotEmpty ? 1 : 0) +
      tmdbFilterCount;

  /// Copy with changes. [categoryId] and [kind] may be set to null explicitly.
  BrowseFilter copyWith({
    Object? categoryId = _unset,
    Set<int>? years,
    List<YearRange>? yearRanges,
    Set<String>? languages,
    Set<int>? qualities,
    Object? kind = _unset,
    BrowseSort? sort,
    Set<int>? genreIds,
    Object? minRating = _unset,
    Set<String>? originalLanguages,
    Set<RuntimeBucket>? runtimes,
    Object? personId = _unset,
  }) => BrowseFilter(
    categoryId: identical(categoryId, _unset)
        ? this.categoryId
        : categoryId as int?,
    years: years ?? this.years,
    yearRanges: yearRanges ?? this.yearRanges,
    languages: languages ?? this.languages,
    qualities: qualities ?? this.qualities,
    kind: identical(kind, _unset) ? this.kind : kind as TitleKind?,
    sort: sort ?? this.sort,
    genreIds: genreIds ?? this.genreIds,
    minRating: identical(minRating, _unset)
        ? this.minRating
        : minRating as double?,
    originalLanguages: originalLanguages ?? this.originalLanguages,
    runtimes: runtimes ?? this.runtimes,
    personId: identical(personId, _unset) ? this.personId : personId as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is BrowseFilter &&
      other.categoryId == categoryId &&
      other.kind == kind &&
      other.sort == sort &&
      other.minRating == minRating &&
      other.personId == personId &&
      _setEq(other.genreIds, genreIds) &&
      _setEq(other.originalLanguages, originalLanguages) &&
      _setEq(other.runtimes, runtimes) &&
      _setEq(other.years, years) &&
      _setEq(other.languages, languages) &&
      _setEq(other.qualities, qualities) &&
      _setEq(other.yearRanges.toSet(), yearRanges.toSet());

  @override
  int get hashCode => Object.hash(
    categoryId,
    kind,
    sort,
    Object.hashAllUnordered(years),
    Object.hashAllUnordered(languages),
    Object.hashAllUnordered(qualities),
    Object.hashAllUnordered(yearRanges),
    minRating,
    personId,
    Object.hashAllUnordered(genreIds),
    Object.hashAllUnordered(originalLanguages),
    Object.hashAllUnordered(runtimes),
  );
}

bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

/// Year picker preset: one exact year or a range.
class YearBucket {
  const YearBucket(this.label, {this.years = const {}, this.ranges = const []});
  final String label;
  final Set<int> years;
  final List<YearRange> ranges;

  /// Presets for the year sheet: [now] back to now-5 individually, then
  /// decade buckets ('2010s', '2000s', '1990s'; clipped so nothing overlaps
  /// the individual years and no year is skipped), then 'Older' (before 1990).
  static List<YearBucket> presets([int? now]) {
    final cur = now ?? DateTime.now().year;
    final out = <YearBucket>[
      for (var y = cur; y > cur - 6; y--) YearBucket('$y', years: {y}),
    ];
    var upper = cur - 6;
    for (final dec in const [2020, 2010, 2000, 1990]) {
      if (upper < dec) continue;
      final to = upper < dec + 9 ? upper : dec + 9;
      out.add(
        YearBucket(
          '${dec}s',
          ranges: [YearRange(from: dec, to: to)],
        ),
      );
      upper = dec - 1;
    }
    out.add(YearBucket('Older', ranges: [YearRange(to: upper)]));
    return out;
  }

  /// Union of the selected buckets as filter fields.
  static ({Set<int> years, List<YearRange> ranges}) merge(
    Iterable<YearBucket> selected,
  ) => (
    years: {for (final b in selected) ...b.years},
    ranges: [for (final b in selected) ...b.ranges],
  );

  @override
  bool operator ==(Object other) =>
      other is YearBucket &&
      other.label == label &&
      _setEq(other.years, years) &&
      _setEq(other.ranges.toSet(), ranges.toSet());
  @override
  int get hashCode => Object.hash(label, Object.hashAllUnordered(years));
}

/// recentlyAdded = [MediaTitle.addedAt] descending.
enum BrowseSort { nameAsc, yearDesc, recentlyAdded }

/// Distinct filter values with counts, for filter chips/pickers.
class FacetValue<T> {
  const FacetValue(this.value, this.count);
  final T value;
  final int count;
}

/// Actor search result.
class PersonHit {
  const PersonHit({
    required this.id,
    required this.name,
    this.profilePath,
    this.titleCount = 0,
  });

  /// TMDB person id (use with [BrowseFilter.personId]).
  final int id;
  final String name;
  final String? profilePath;

  /// Library titles whose stored cast includes this person.
  final int titleCount;
}

// ---- Crawler input (no ids; identity = folderUrl / url) ----

/// File input. Identity = url (stored relative to the title folder, must be
/// under the title's folderUrl). [name], [ext] and [playable] are NOT stored:
/// the repository derives them from the url (decoded last segment, extension,
/// playable-extension list); they stay here so existing crawler code compiles.
class FileDraft {
  const FileDraft({
    required this.name,
    required this.url,
    required this.ext,
    required this.playable,
    this.episode,
    this.episodeEnd,
    this.sizeKb,
    this.mtime,
  });
  final String name;
  final String url;
  final String ext;
  final bool playable;
  final int? episode;
  final int? episodeEnd;
  final int? sizeKb;
  final DateTime? mtime;
}

/// Season identity: (titleId, folderUrl) when [folderUrl] != null, otherwise
/// (titleId, number, language, label).
class SeasonDraft {
  const SeasonDraft({
    required this.number,
    required this.label,
    this.language,
    this.folderUrl,
    this.files = const [],
    this.episodeCount,
  });
  final int number;
  final String label;
  final String? language;

  /// Absolute season folder url; must be under the title's folderUrl.
  final String? folderUrl;
  final List<FileDraft> files;

  /// Skeleton hint: episodes in this season when [files] is empty because
  /// files are not loaded. Ignored when files are given (their count wins).
  final int? episodeCount;
}

/// Rules: kind == series => all files live in [seasons] and [files] must be
/// empty; movie/event => [seasons] must be empty. [filesLoaded] == false is a
/// SKELETON draft: no file lists anywhere (seasons keep only their
/// identity and an optional [SeasonDraft.episodeCount]). The repository
/// implementation MUST call [validate] and throw [ArgumentError] on violation.
class TitleDraft {
  const TitleDraft({
    required this.categoryId,
    required this.name,
    required this.kind,
    required this.folderUrl,
    this.year,
    this.yearEnd,
    this.quality,
    this.tags = const [],
    this.posterUrl,
    this.folderMtime,
    this.seasons = const [],
    this.files = const [],
    this.filesLoaded = true,
    this.fileCount,
    this.addedAt,
  });
  final int categoryId;
  final String name;
  final TitleKind kind;
  final String folderUrl;
  final int? year;
  final int? yearEnd;
  final int? quality;
  final List<String> tags;
  final String? posterUrl;
  final DateTime? folderMtime;

  /// Series: seasons with their episode files.
  final List<SeasonDraft> seasons;

  /// Movies/events: files directly under the title.
  final List<FileDraft> files;

  /// True (default): the draft carries the complete file lists and replaces
  /// the title's stored files. False: skeleton draft, no files; see
  /// [Repository.upsertTitle] for what happens to already loaded files.
  final bool filesLoaded;

  /// Skeleton hint: number of files in the title. Used as
  /// [MediaTitle.fileCount] when [filesLoaded] is false (else the stored value
  /// is kept, 0 for a new title). Ignored when files are given.
  final int? fileCount;

  /// "Recently added" hint, used ONLY when the title is first inserted (never
  /// changed afterwards); null = now. Crawlers pass the folder mtime so the
  /// first full run does not stamp every title with the same moment. Values in
  /// the future are clamped to now by the repository.
  final DateTime? addedAt;

  /// Throws [ArgumentError] if the series/movie/event rule is violated.
  void validate() {
    if (!filesLoaded &&
        (files.isNotEmpty || seasons.any((s) => s.files.isNotEmpty))) {
      throw ArgumentError(
        '"$name": skeleton draft (filesLoaded: false) must '
        'not carry files',
      );
    }
    if (kind == TitleKind.series) {
      if (files.isNotEmpty) {
        throw ArgumentError('series "$name": files must be empty, use seasons');
      }
    } else if (seasons.isNotEmpty) {
      throw ArgumentError('${kind.name} "$name": seasons must be empty');
    }
  }
}

class CategoryDraft {
  const CategoryDraft({
    required this.sourceHost,
    required this.name,
    required this.url,
    this.language,
  });
  final String sourceHost;
  final String name;
  final String url;
  final String? language;
}

/// TMDB metadata stored for one title (contract between the TMDB sync worker,
/// the data layer and the UI).
class TmdbInfo {
  const TmdbInfo({
    required this.titleId,
    required this.status,
    required this.fetchedAt,
    this.tmdbId,
    this.mediaType,
    this.overview,
    this.tagline,
    this.rating,
    this.voteCount,
    this.runtime,
    this.originalLanguage,
    this.releaseYear,
    this.posterPath,
    this.backdropPath,
    this.genres = const [],
    this.cast = const [],
  });

  final int titleId;
  final TmdbStatus status;
  final DateTime fetchedAt;
  final int? tmdbId;
  final TmdbMediaType? mediaType;
  final String? overview;
  final String? tagline;

  /// 0..10.
  final double? rating;
  final int? voteCount;

  /// Minutes.
  final int? runtime;
  final String? originalLanguage;
  final int? releaseYear;
  final String? posterPath;
  final String? backdropPath;
  final List<TmdbGenre> genres;

  /// Billing order, lead first.
  final List<TmdbCastMember> cast;
}

/// How much of the library has been looked up on TMDB.
class TmdbProgress {
  const TmdbProgress({this.eligible = 0, this.matched = 0, this.unmatched = 0});

  /// Movies and series (events and collections are not looked up).
  final int eligible;

  /// matched + manual.
  final int matched;
  final int unmatched;

  /// Not looked up yet (or due for a retry).
  int get pending => eligible - matched - unmatched;
}

/// Keyset position in the TMDB work queue (newest `addedAt` first, then id
/// descending). Pass the last title of the previous batch as [after].
class TmdbQueueCursor {
  const TmdbQueueCursor({required this.addedAt, required this.id});
  final DateTime addedAt;
  final int id;
}
