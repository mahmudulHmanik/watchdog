// Skeleton classification: h5ai API trees -> neutral title/season values
// (names, years, posters, counts, folder times; no file lists). Pure, no IO,
// no repository types. Reuses the name parsers and the folder rules of the
// full recursive classifier (classifier.dart) so both agree.
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/classifier.dart'
    show FolderNode, NodeFile, isYearBucketName, looksLikeShow;
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/parsing.dart';
import 'package:watchdog/data/models.dart' show TitleKind;

/// Listing-compatible form of an exact UTC time: minute-truncated, wall
/// clock read as local (what the HTML crawler stores). See
/// [ApiItem.timeAsListing].
DateTime toListingTime(DateTime utc) =>
    DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute);

class SkeletonSeason {
  const SkeletonSeason({
    required this.number,
    required this.label,
    required this.folderUrl,
    this.language,
    this.mtime,
    this.episodeCount,
  });

  /// 0 = specials / unparsed season folder name.
  final int number;
  final String label;
  final String? language;

  /// Absolute, percent-encoded, trailing '/'.
  final String folderUrl;

  /// Folder mtime, exact UTC.
  final DateTime? mtime;

  /// Video files directly in the season folder when the tree lists it;
  /// null = unknown (season not listed, or episodes are in nested folders).
  final int? episodeCount;
}

class SkeletonTitle {
  const SkeletonTitle({
    required this.name,
    required this.kind,
    required this.folderUrl,
    this.year,
    this.yearEnd,
    this.quality,
    this.tags = const [],
    this.posterPath,
    this.fileCount = 0,
    this.fileCountExact = true,
    this.archiveCount = 0,
    this.mtime,
    this.fingerprint,
    this.seasons = const [],
  });

  final String name;
  final TitleKind kind;

  /// Absolute, percent-encoded, trailing '/'.
  final String folderUrl;
  final int? year, yearEnd, quality;
  final List<String> tags;

  /// First image in the title folder, as the percent-encoded file name:
  /// poster URL = `folderUrl + posterPath`.
  final String? posterPath;

  /// Movies/events: video files in the folder. Series: known episodes
  /// (sum of season counts, plus loose files).
  final int fileCount;

  /// False when some season's count is unknown ([SkeletonSeason.episodeCount]
  /// null), so [fileCount] is a lower bound.
  final bool fileCountExact;

  /// `.rar/.zip/.7z`: listed but not playable.
  final int archiveCount;

  /// Title folder mtime, exact UTC.
  final DateTime? mtime;

  /// Change fingerprint, exact UTC: [mtime] for movies; for series the max
  /// of the show folder, its seasons and loose files (same rule as the full
  /// classifier's `showFingerprint`).
  final DateTime? fingerprint;
  final List<SkeletonSeason> seasons;

  bool get isSeries => kind == TitleKind.series;

  /// [fingerprint] in the form the HTML crawler stores (see
  /// [toListingTime]); use when comparing with rows indexed from HTML.
  DateTime? get fingerprintAsListing =>
      fingerprint == null ? null : toListingTime(fingerprint!);
}

/// Result of classifying one answer: finished titles plus the child folders
/// that must be fetched (`what = 2`) to learn what they hold.
class SkeletonLevel {
  const SkeletonLevel(this.titles, this.descend);
  final List<SkeletonTitle> titles;
  final List<ApiItem> descend;
}

bool _isMedia(ApiItem f) => isVideo(f.name) || isArchive(f.name);

List<ApiItem> _kids(ApiItem n) => [
  for (final f in n.folders)
    if (!isExtrasFolder(f.name)) f,
];

bool _hasMedia(ApiItem n) => n.files.any(_isMedia);

FolderNode _shallow(ApiItem n) => FolderNode(
  name: n.name,
  url: n.href,
  mtime: n.time,
  files: [
    for (final f in n.files) NodeFile(name: f.name, url: f.href, mtime: f.time),
  ],
  folders: [for (final f in n.folders) FolderNode(name: f.name, url: f.href)],
);

String? _posterPath(ApiItem n) {
  for (final f in n.files) {
    if (isImage(f.name)) return f.href.substring(f.href.lastIndexOf('/') + 1);
  }
  return null;
}

DateTime? _max(DateTime? a, DateTime? b) =>
    a == null ? b : (b == null || a.isAfter(b) ? a : b);

class SkeletonClassifier {
  const SkeletonClassifier({
    required this.origin,
    this.seasonContainersAsSeries = true,
  });

  /// `http://host[:port]`, no trailing slash; prefixed to every href.
  final String origin;

  /// In movie/event categories, a folder with no media whose subfolders are
  /// mostly season folders ("A Haunting/Season 1/...", common in Documentary)
  /// is a series. The full classifier would make each season folder a
  /// separate "title"; set false to reproduce that exactly.
  final bool seasonContainersAsSeries;

  String _url(ApiItem n) => '$origin${n.href}';

  /// Classifies the children of [folder] (an answer from
  /// [H5aiApiClient.getFolder]) for a category laid out as [layout].
  SkeletonLevel classify(
    ApiItem folder, {
    required LayoutKind layout,
    required TitleKind kind,
  }) => layout == LayoutKind.series
      ? classifySeries(folder)
      : classifyMovies(folder, kind: kind);

  /// Movie / event layouts: `[bucket/]Title/files`, containers recurse.
  SkeletonLevel classifyMovies(
    ApiItem folder, {
    TitleKind kind = TitleKind.movie,
  }) {
    final titles = <SkeletonTitle>[];
    final descend = <ApiItem>[];
    for (final c in folder.folders) {
      if (isExtrasFolder(c.name)) continue;
      if (!c.isListed) {
        descend.add(c);
        continue;
      }
      if (_hasMedia(c) && !isYearBucketName(c.name)) {
        titles.add(movie(c, kind: kind));
      } else if (seasonContainersAsSeries &&
          !_hasMedia(c) &&
          _seasonContainer(c)) {
        final s = show(c);
        if (s != null) titles.add(s);
      } else if (_kids(c).isNotEmpty) {
        descend.add(c);
      }
    }
    return SkeletonLevel(titles, descend);
  }

  bool _seasonContainer(ApiItem c) {
    final kids = _kids(c);
    final seasonish = kids.where((f) => parseSeasonFolder(f.name) != null);
    return seasonish.isNotEmpty && seasonish.length * 2 >= kids.length;
  }

  /// Series layout: `[Bucket/]Show/Season/files`; buckets are flattened.
  SkeletonLevel classifySeries(ApiItem folder) {
    final titles = <SkeletonTitle>[];
    final descend = <ApiItem>[];
    for (final c in _kids(folder)) {
      if (!c.isListed) {
        descend.add(c);
      } else if (looksLikeShow(_shallow(c))) {
        final s = show(c);
        if (s != null) titles.add(s);
      } else if (_kids(c).isNotEmpty) {
        descend.add(c);
      }
    }
    return SkeletonLevel(titles, descend);
  }

  /// Movie / event title from a listed folder that directly holds media.
  SkeletonTitle movie(ApiItem n, {TitleKind kind = TitleKind.movie}) {
    final info = parseTitleFolder(n.name);
    var videos = 0, archives = 0;
    for (final f in n.files) {
      if (isVideo(f.name)) {
        videos++;
      } else if (isArchive(f.name)) {
        archives++;
      }
    }
    return SkeletonTitle(
      name: info.name,
      kind: kind,
      folderUrl: _url(n),
      year: info.year,
      yearEnd: info.yearEnd,
      quality: info.quality,
      tags: info.tags,
      posterPath: _posterPath(n),
      fileCount: videos,
      archiveCount: archives,
      mtime: n.time,
      fingerprint: n.time,
    );
  }

  /// Series from a listed show folder; null when it holds nothing playable.
  /// Season folders that are listed and contain no media are dropped (as the
  /// full classifier does); unlisted ones are kept with unknown counts.
  SkeletonTitle? show(ApiItem n) {
    final info = parseTitleFolder(n.name);
    final seasons = <SkeletonSeason>[];
    // Same rule as the full classifier's showFingerprint: every child folder
    // (even extras / empty ones) and every file counts.
    var fp = n.time;
    for (final f in n.folders) {
      fp = _max(fp, f.time);
    }
    for (final f in n.files) {
      fp = _max(fp, f.time);
    }
    var known = 0, exact = true;
    for (final f in _kids(n)) {
      int? count;
      if (f.isListed) {
        final direct = f.files.where((x) => isVideo(x.name)).length;
        final nested = _kids(f).isNotEmpty;
        if (!_hasMedia(f) && !nested) continue; // empty folder
        count = nested ? null : direct;
      }
      final si = parseSeasonFolder(f.name);
      seasons.add(
        SkeletonSeason(
          number: si?.number ?? 0,
          label: si?.label ?? f.name.trim(),
          language: si?.language,
          folderUrl: _url(f),
          mtime: f.time,
          episodeCount: count,
        ),
      );
      if (count == null) {
        exact = false;
      } else {
        known += count;
      }
    }
    final loose = n.files.where(_isMedia).toList();
    if (loose.isNotEmpty) {
      final looseVideos = loose.where((m) => isVideo(m.name)).toList();
      known += looseVideos.length;
      if (seasons.isEmpty) {
        final counts = <int, int>{};
        for (final m in looseVideos) {
          final s = parseEpisode(m.name).season;
          if (s != null) counts[s] = (counts[s] ?? 0) + 1;
        }
        var number = 1, best = 0;
        counts.forEach((s, c) {
          if (c > best) {
            best = c;
            number = s;
          }
        });
        seasons.add(
          SkeletonSeason(
            number: number,
            label: 'Season $number',
            folderUrl: _url(n),
            mtime: n.time,
            episodeCount: looseVideos.length,
          ),
        );
      } else {
        seasons.add(
          SkeletonSeason(
            number: 0,
            label: 'Other',
            folderUrl: _url(n),
            mtime: n.time,
            episodeCount: looseVideos.length,
          ),
        );
      }
    }
    if (seasons.isEmpty) return null;
    seasons.sort((a, b) {
      final c = a.number.compareTo(b.number);
      return c != 0 ? c : a.label.compareTo(b.label);
    });
    return SkeletonTitle(
      name: info.name,
      kind: TitleKind.series,
      folderUrl: _url(n),
      year: info.year,
      yearEnd: info.yearEnd,
      quality: info.quality,
      tags: info.tags,
      posterPath: _posterPath(n),
      fileCount: known,
      fileCountExact: exact,
      archiveCount: loose.where((m) => isArchive(m.name)).length,
      mtime: n.time,
      fingerprint: fp,
      seasons: seasons,
    );
  }
}
