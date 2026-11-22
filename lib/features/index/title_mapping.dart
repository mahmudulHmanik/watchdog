// Crawler values -> repository drafts. Pure.
import 'package:watchdog/crawler/skeleton.dart';
import 'package:watchdog/data/models.dart';

/// Skeleton draft (files are loaded when a title is opened) for an API
/// crawled title.
///
/// Time semantics: [TitleDraft.folderMtime] is the change fingerprint in the
/// form the HTML crawler stores (`fingerprintAsListing`), so it compares equal
/// with rows indexed from HTML (also migrated ones). [TitleDraft.addedAt] is
/// the exact folder time of the title.
TitleDraft draftFromSkeleton(SkeletonTitle t, int categoryId) => TitleDraft(
  categoryId: categoryId,
  name: t.name,
  kind: t.kind,
  folderUrl: t.folderUrl,
  year: t.year,
  yearEnd: t.yearEnd,
  quality: t.quality,
  tags: t.tags,
  posterUrl: t.posterPath == null ? null : '${t.folderUrl}${t.posterPath}',
  folderMtime:
      t.fingerprintAsListing ??
      (t.mtime == null ? null : toListingTime(t.mtime!)),
  seasons: [
    for (final s in t.seasons)
      SeasonDraft(
        number: s.number,
        label: s.label,
        language: s.language,
        folderUrl: s.folderUrl,
        episodeCount: s.episodeCount,
      ),
  ],
  filesLoaded: false,
  fileCount: t.fileCount,
  addedAt: t.mtime,
);

/// Skeleton form of a fully classified (HTML crawled) title: the file lists
/// are dropped, only counts stay, so both crawl paths store the same thing.
TitleDraft skeletonOfFull(TitleDraft d) {
  if (!d.filesLoaded) return d;
  var total = 0;
  final seasons = <SeasonDraft>[];
  for (final s in d.seasons) {
    final n = s.files.where((f) => f.playable).length;
    total += n;
    seasons.add(
      SeasonDraft(
        number: s.number,
        label: s.label,
        language: s.language,
        folderUrl: s.folderUrl,
        episodeCount: n,
      ),
    );
  }
  if (d.kind != TitleKind.series) {
    total = d.files.where((f) => f.playable).length;
  }
  return TitleDraft(
    categoryId: d.categoryId,
    name: d.name,
    kind: d.kind,
    folderUrl: d.folderUrl,
    year: d.year,
    yearEnd: d.yearEnd,
    quality: d.quality,
    tags: d.tags,
    posterUrl: d.posterUrl,
    folderMtime: d.folderMtime,
    seasons: seasons,
    filesLoaded: false,
    fileCount: total,
    addedAt: d.addedAt ?? d.folderMtime,
  );
}
