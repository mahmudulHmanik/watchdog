import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/skeleton.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/index/title_mapping.dart';

void main() {
  const base = 'http://172.16.50.7/DHAKA-FLIX-7/English%20Movies/(2020)/Film/';

  test('movie: fields, poster url, mtime semantics, skeleton flags', () {
    final t = SkeletonTitle(
      name: 'Film',
      kind: TitleKind.movie,
      folderUrl: base,
      year: 2020,
      quality: 1080,
      tags: const ['BluRay'],
      posterPath: 'poster%20a.jpg',
      fileCount: 3,
      archiveCount: 1,
      mtime: DateTime.utc(2024, 3, 5, 10, 20, 45),
      fingerprint: DateTime.utc(2024, 3, 5, 10, 20, 45),
    );
    final d = draftFromSkeleton(t, 7);
    d.validate();
    expect(d.categoryId, 7);
    expect(d.name, 'Film');
    expect(d.kind, TitleKind.movie);
    expect(d.folderUrl, base);
    expect(d.year, 2020);
    expect(d.quality, 1080);
    expect(d.tags, ['BluRay']);
    expect(d.posterUrl, '${base}poster%20a.jpg');
    expect(d.filesLoaded, isFalse);
    expect(d.fileCount, 3); // archives are not playable files
    expect(d.files, isEmpty);
    expect(d.seasons, isEmpty);
    // Stored like the HTML crawler stores it: minute-truncated wall clock.
    expect(d.folderMtime, DateTime(2024, 3, 5, 10, 20));
    expect(d.folderMtime!.isUtc, isFalse);
    // addedAt keeps the exact instant of the folder time.
    expect(d.addedAt, DateTime.utc(2024, 3, 5, 10, 20, 45));
  });

  test('no poster, no times', () {
    final d = draftFromSkeleton(
      const SkeletonTitle(name: 'X', kind: TitleKind.event, folderUrl: base),
      1,
    );
    expect(d.posterUrl, isNull);
    expect(d.folderMtime, isNull);
    expect(d.addedAt, isNull);
    expect(d.kind, TitleKind.event);
  });

  test('series: seasons with counts; the change fingerprint is the mtime', () {
    final show = 'http://h/c/Show/';
    final t = SkeletonTitle(
      name: 'Show',
      kind: TitleKind.series,
      folderUrl: show,
      fileCount: 5,
      fileCountExact: false,
      mtime: DateTime.utc(2020, 1, 1),
      fingerprint: DateTime.utc(2024, 6, 7, 8, 9, 10),
      seasons: [
        SkeletonSeason(
          number: 1,
          label: 'Season 1',
          language: 'korean',
          folderUrl: '${show}Season%201/',
          mtime: DateTime.utc(2024),
          episodeCount: 5,
        ),
        SkeletonSeason(
          number: 0,
          label: 'Specials',
          folderUrl: '${show}Specials/',
        ),
      ],
    );
    final d = draftFromSkeleton(t, 2);
    d.validate();
    expect(d.folderMtime, DateTime(2024, 6, 7, 8, 9));
    expect(d.addedAt, DateTime.utc(2020, 1, 1));
    expect(d.fileCount, 5);
    expect([for (final s in d.seasons) s.number], [1, 0]);
    expect(d.seasons.first.language, 'korean');
    expect(d.seasons.first.folderUrl, '${show}Season%201/');
    expect(d.seasons.first.episodeCount, 5);
    expect(d.seasons.last.episodeCount, isNull); // unknown, not zero
    expect(d.seasons.every((s) => s.files.isEmpty), isTrue);
  });

  test('HTML drafts become skeletons: counts kept, files dropped', () {
    FileDraft f(String n, {bool play = true}) => FileDraft(
      name: n,
      url: '${base}Season%201/$n',
      ext: 'mkv',
      playable: play,
    );
    final full = TitleDraft(
      categoryId: 3,
      name: 'S',
      kind: TitleKind.series,
      folderUrl: base,
      folderMtime: DateTime(2022, 2, 2),
      posterUrl: '${base}p.jpg',
      seasons: [
        SeasonDraft(
          number: 1,
          label: 'Season 1',
          folderUrl: '${base}Season%201/',
          files: [f('a.mkv'), f('b.mkv'), f('c.rar', play: false)],
        ),
      ],
    );
    final s = skeletonOfFull(full);
    s.validate();
    expect(s.filesLoaded, isFalse);
    expect(s.fileCount, 2);
    expect(s.seasons.single.episodeCount, 2);
    expect(s.seasons.single.files, isEmpty);
    expect(s.addedAt, DateTime(2022, 2, 2));
    expect(s.posterUrl, '${base}p.jpg');
    final movie = TitleDraft(
      categoryId: 3,
      name: 'M',
      kind: TitleKind.movie,
      folderUrl: base,
      files: [f('a.mkv'), f('x.rar', play: false)],
    );
    expect(skeletonOfFull(movie).fileCount, 1);
    final already = draftFromSkeleton(
      const SkeletonTitle(name: 'Z', kind: TitleKind.movie, folderUrl: 'u/'),
      1,
    );
    expect(identical(skeletonOfFull(already), already), isTrue);
  });
}
