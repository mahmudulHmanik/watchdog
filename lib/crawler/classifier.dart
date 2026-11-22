// Pure classifier: listed folder tree -> id-free drafts. No IO.
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/listing.dart';
import 'package:watchdog/crawler/parsing.dart';
import 'package:watchdog/data/models.dart';

/// A file entry with an absolute URL.
class NodeFile {
  const NodeFile({
    required this.name,
    required this.url,
    this.sizeKb,
    this.mtime,
  });
  final String name;
  final String url;
  final int? sizeKb;
  final DateTime? mtime;
}

/// One listed folder. Child [folders] may be unlisted stubs (empty lists).
class FolderNode {
  const FolderNode({
    required this.name,
    required this.url,
    this.mtime,
    this.files = const [],
    this.folders = const [],
  });

  final String name;

  /// Absolute, percent-encoded, trailing '/'.
  final String url;
  final DateTime? mtime;
  final List<NodeFile> files;
  final List<FolderNode> folders;

  /// Builds a node from a parsed listing of [url]; child hrefs are resolved
  /// against [url]. Child folders become unlisted stubs.
  factory FolderNode.fromListing(
    String url,
    List<Entry> entries, {
    String? name,
    DateTime? mtime,
  }) {
    final base = Uri.parse(url);
    final files = <NodeFile>[];
    final folders = <FolderNode>[];
    for (final e in entries) {
      final abs = base.resolve(e.href).toString();
      if (e.isDir) {
        folders.add(
          FolderNode(
            name: e.name,
            url: abs.endsWith('/') ? abs : '$abs/',
            mtime: e.modified,
          ),
        );
      } else {
        files.add(
          NodeFile(name: e.name, url: abs, sizeKb: e.sizeKb, mtime: e.modified),
        );
      }
    }
    return FolderNode(
      name:
          name ??
          Uri.decodeComponent(
            base.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => ''),
          ),
      url: url,
      mtime: mtime,
      files: files,
      folders: folders,
    );
  }
}

bool _isMedia(NodeFile f) => isVideo(f.name) || isArchive(f.name);

/// Direct media (video or archive) in this folder.
bool hasMedia(FolderNode n) => n.files.any(_isMedia);

/// Media anywhere below (ignores extras folders).
bool hasMediaDeep(FolderNode n) =>
    hasMedia(n) ||
    n.folders.any((f) => !isExtrasFolder(f.name) && hasMediaDeep(f));

List<FolderNode> _kids(FolderNode n) => [
  for (final f in n.folders)
    if (!isExtrasFolder(f.name)) f,
];

final _yearRange = RegExp(r'^\(?\s*\d{4}\s*[-–]\s*\d{4}\s*\)?$');
final _andBefore = RegExp(
  r'&\s*(before|earlier|older)\b',
  caseSensitive: false,
);

/// "(1960-1994)", "(1995) & Before": year buckets, never titles.
bool isYearBucketName(String name) =>
    _yearRange.hasMatch(name.trim()) || _andBefore.hasMatch(name);

/// A folder with direct media is a title, except range buckets.
bool isMovieTitleFolder(FolderNode n) =>
    hasMedia(n) && !isYearBucketName(n.name);

FileDraft _file(NodeFile f, {bool episodes = false}) {
  final playable = isVideo(f.name);
  final ep = (episodes && playable) ? parseEpisode(f.name) : null;
  return FileDraft(
    name: f.name,
    url: f.url,
    ext: extOf(f.name),
    playable: playable,
    episode: ep?.episode,
    episodeEnd: ep?.episodeEnd,
    sizeKb: f.sizeKb,
    mtime: f.mtime,
  );
}

String? _poster(FolderNode n) {
  for (final f in n.files) {
    if (isImage(f.name)) return f.url;
  }
  return null;
}

/// Movie / event title from a single folder that directly holds media.
/// Subfolders are ignored. Subtitles and other files are dropped.
TitleDraft classifyMovieFolder(
  FolderNode n, {
  required int categoryId,
  TitleKind kind = TitleKind.movie,
}) {
  final info = parseTitleFolder(n.name);
  return TitleDraft(
    categoryId: categoryId,
    name: info.name,
    kind: kind,
    folderUrl: n.url,
    year: info.year,
    yearEnd: info.yearEnd,
    quality: info.quality,
    tags: info.tags,
    posterUrl: _poster(n),
    folderMtime: n.mtime,
    files: [for (final f in n.files.where(_isMedia)) _file(f)],
  );
}

/// Walks a category root: media folders are titles, folders with only
/// subfolders are containers (year buckets, collections, language buckets).
List<TitleDraft> classifyMovieTree(
  FolderNode root, {
  required int categoryId,
  TitleKind kind = TitleKind.movie,
}) {
  final out = <TitleDraft>[];
  void visit(FolderNode n) {
    if (isExtrasFolder(n.name)) return;
    if (isMovieTitleFolder(n)) {
      out.add(classifyMovieFolder(n, categoryId: categoryId, kind: kind));
      return;
    }
    n.folders.forEach(visit);
  }

  root.folders.forEach(visit);
  return out;
}

/// Shallow check (names + direct files only): is this folder a show rather
/// than an A-Z / alphabet bucket?
bool looksLikeShow(FolderNode n) {
  if (hasMedia(n)) return true;
  final kids = _kids(n);
  // Majority, not any: a bucket may hold a show named like "Foo Season 2".
  final seasonish = kids.where((f) => parseSeasonFolder(f.name) != null).length;
  if (seasonish > 0 && seasonish * 2 >= kids.length) return true;
  return kids.isNotEmpty && parseTitleFolder(n.name).year != null;
}

/// Fingerprint used as a show's `folderMtime`: the newest mtime of the show
/// folder and its direct children (season folders), so a new episode in a
/// season invalidates it. Computable from the show's own listing.
DateTime? showFingerprint(FolderNode n) {
  DateTime? best = n.mtime;
  for (final f in n.folders) {
    final m = f.mtime;
    if (m != null && (best == null || m.isAfter(best))) best = m;
  }
  for (final f in n.files) {
    final m = f.mtime;
    if (m != null && (best == null || m.isAfter(best))) best = m;
  }
  return best;
}

List<NodeFile> _collectMedia(FolderNode n) => [
  ...n.files.where(_isMedia),
  for (final k in _kids(n)) ..._collectMedia(k),
];

/// Series title from a fully listed show tree. Null when it holds no media.
TitleDraft? classifyShow(FolderNode n, {required int categoryId}) {
  final info = parseTitleFolder(n.name);
  final seasons = <SeasonDraft>[];
  for (final f in _kids(n)) {
    final media = _collectMedia(f);
    if (media.isEmpty) continue;
    final si = parseSeasonFolder(f.name);
    seasons.add(
      SeasonDraft(
        number: si?.number ?? 0,
        label: si?.label ?? f.name.trim(),
        language: si?.language,
        folderUrl: f.url,
        files: [for (final m in media) _file(m, episodes: true)],
      ),
    );
  }
  final loose = n.files.where(_isMedia).toList();
  if (loose.isNotEmpty) {
    final drafts = [for (final m in loose) _file(m, episodes: true)];
    if (seasons.isEmpty) {
      final counts = <int, int>{};
      for (final m in loose.where((m) => isVideo(m.name))) {
        final s = parseEpisode(m.name).season;
        if (s != null) counts[s] = (counts[s] ?? 0) + 1;
      }
      var number = 1;
      var best = 0;
      counts.forEach((s, c) {
        if (c > best) {
          best = c;
          number = s;
        }
      });
      seasons.add(
        SeasonDraft(number: number, label: 'Season $number', files: drafts),
      );
    } else {
      seasons.add(SeasonDraft(number: 0, label: 'Other', files: drafts));
    }
  }
  if (seasons.isEmpty) return null;
  seasons.sort((a, b) {
    final c = a.number.compareTo(b.number);
    return c != 0 ? c : a.label.compareTo(b.label);
  });
  return TitleDraft(
    categoryId: categoryId,
    name: info.name,
    kind: TitleKind.series,
    folderUrl: n.url,
    year: info.year,
    yearEnd: info.yearEnd,
    quality: info.quality,
    tags: info.tags,
    posterUrl: _poster(n),
    folderMtime: showFingerprint(n),
    seasons: seasons,
  );
}

/// Walks a series category root, flattening buckets.
List<TitleDraft> classifySeriesTree(
  FolderNode root, {
  required int categoryId,
}) {
  final out = <TitleDraft>[];
  void visit(FolderNode n) {
    if (looksLikeShow(n)) {
      final t = classifyShow(n, categoryId: categoryId);
      if (t != null) out.add(t);
      return;
    }
    _kids(n).forEach(visit);
  }

  _kids(root).forEach(visit);
  return out;
}

/// Entry point: classify a fully listed category tree according to [layout].
List<TitleDraft> classifyCategory(
  FolderNode root, {
  required LayoutKind layout,
  required TitleKind kind,
  required int categoryId,
}) => layout == LayoutKind.series
    ? classifySeriesTree(root, categoryId: categoryId)
    : classifyMovieTree(root, categoryId: categoryId, kind: kind);
