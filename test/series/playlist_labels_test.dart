import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/series/domain/playlist.dart';
import 'package:watchdog/features/series/domain/playlist_labels.dart';

MediaFile f(int id, int? season, int? ep, String name, {int? end}) => MediaFile(
  id: id,
  titleId: 1,
  seasonId: season,
  name: name,
  url: 'http://h/$id.mkv',
  ext: 'mkv',
  playable: true,
  episode: ep,
  episodeEnd: end,
);

SeasonEpisodes se(
  int id,
  int number,
  List<MediaFile> files, {
  String? lang,
  String? label,
}) => SeasonEpisodes(
  season: Season(
    id: id,
    titleId: 1,
    number: number,
    label: label ?? 'Season $number',
    language: lang,
  ),
  files: files,
);

List<String> text(List<PlaylistRow> rows) => [
  for (final r in rows)
    switch (r) {
      PlaylistHeaderRow(:final text) => '# $text',
      PlaylistItemRow(:final index, :final number, :final label) =>
        '$index|$number|$label',
    },
];

void main() {
  // Lupin-like: every season restarts at episode 1; names are bare numbers.
  final lupin = [
    se(1, 1, [
      f(1, 1, 1, 'Lupin.S01E01.720p.mkv'),
      f(2, 1, 2, 'Lupin.S01E02.720p.mkv'),
    ]),
    se(2, 2, [
      f(3, 2, 1, 'Lupin.S02E01.720p.mkv'),
      f(4, 2, 2, 'Lupin.S02E02.The.Heist.720p.mkv'),
    ]),
  ];

  group('multi-season with repeating episode numbers', () {
    final pl = PlaylistBuilder.forSeason(lupin, 1)!;
    final l = PlaylistLabels(pl, 'Lupin');

    test('rows are grouped under season headers', () {
      expect(text(l.rows()), [
        '# Season 1',
        '0|1|Episode 1',
        '1|2|Episode 2',
        '# Season 2',
        '2|1|Episode 1',
        '3|2|The Heist',
      ]);
    });
    test('item rows keep playlist indices (headers are not items)', () {
      final idx = [
        for (final r in l.rows())
          if (r is PlaylistItemRow) r.index,
      ];
      expect(idx, [0, 1, 2, 3]);
      expect(pl.length, 4);
    });
    test('line names season and episode, plus real title', () {
      expect(l.line(pl.items[0]), 'Season 1 · Episode 1');
      expect(l.line(pl.items[2]), 'Season 2 · Episode 1');
      expect(l.line(pl.items[3]), 'Season 2 · Episode 2 · The Heist');
    });
    test('play-from-here / navigation keep season info', () {
      final q = pl.fromIndex(2)!;
      final ql = PlaylistLabels(q, 'Lupin');
      expect(text(ql.rows()).first, '# Season 2');
      expect(ql.line(q.current), 'Season 2 · Episode 1');
      expect(
        PlaylistLabels(pl.next()!, 'Lupin').line(pl.next()!.current),
        'Season 1 · Episode 2',
      );
    });
  });

  test('specials get a Specials header and Special N fallback', () {
    final seasons = [
      se(1, 1, [f(1, 1, 1, 'Show.S01E01.mkv')]),
      se(9, 0, [f(2, 9, 1, 'Show.S00E01.mkv')], label: 'Specials'),
    ];
    // Specials are their own queue.
    final pl = PlaylistBuilder.forSeason(seasons, 9)!;
    final l = PlaylistLabels(pl, 'Show');
    expect(text(l.rows()), ['# Specials', '0|1|Special 1']);
    expect(l.line(pl.current), 'Specials · Episode 1');
  });

  test('specific season-0 folder label (OVA) is used, Other is Specials', () {
    final n = seasonNames([
      const Season(id: 1, titleId: 1, number: 0, label: 'OVA'),
      const Season(id: 2, titleId: 1, number: 0, label: 'Other'),
    ]);
    expect(n[1], 'OVA');
    expect(n[2], 'Specials');
  });

  test('language variants of one number stay distinct', () {
    final seasons = [
      se(1, 1, [f(1, 1, 1, 'a.mkv')], lang: 'hindi'),
      se(2, 1, [f(2, 2, 1, 'b.mkv')], lang: 'english'),
      se(3, 2, [f(3, 3, 1, 'c.mkv')], lang: 'hindi'),
    ];
    final n = seasonNames([for (final s in seasons) s.season]);
    expect(n[1], 'Season 1 · Hindi');
    expect(n[2], 'Season 1 · English');
    expect(n[3], 'Season 2'); // unambiguous: no language noise
    final pl = PlaylistBuilder.forSeason(seasons, 1)!;
    expect(text(PlaylistLabels(pl, 'X').rows()).first, '# Season 1 · Hindi');
  });

  test('same number and language falls back to folder label then ordinal', () {
    final n = seasonNames([
      const Season(id: 1, titleId: 1, number: 1, label: 'Season 1'),
      const Season(id: 2, titleId: 1, number: 1, label: 'Season 1 Extended'),
    ]);
    expect(n[1], 'Season 1');
    expect(n[2], 'Season 1 · Season 1 Extended');
  });

  test('single season still shows the season', () {
    final pl = PlaylistBuilder.forSeason([
      se(1, 1, [f(1, 1, 1, 'Show.S01E01.mkv'), f(2, 1, 2, 'Show.S01E02.mkv')]),
    ], 1)!;
    final l = PlaylistLabels(pl, 'Show');
    expect(text(l.rows()), ['# Season 1', '0|1|Episode 1', '1|2|Episode 2']);
    expect(l.line(pl.current), 'Season 1 · Episode 1');
  });

  test('file without episode number: position as number, name in line', () {
    final pl = PlaylistBuilder.forSeason([
      se(1, 1, [
        f(1, 1, 1, 'Show.S01E01.mkv'),
        f(2, 1, null, 'Behind the scenes.mkv'),
      ]),
    ], 1)!;
    final l = PlaylistLabels(pl, 'Show');
    expect(text(l.rows())[2], startsWith('1|2|'));
    expect(l.line(pl.items[1]), 'Season 1 · Behind the scenes');
  });

  test('range file shows the range', () {
    final pl = PlaylistBuilder.forSeason([
      se(1, 1, [f(1, 1, 3, 'Show.S01E03-E05.mkv', end: 5)]),
    ], 1)!;
    final l = PlaylistLabels(pl, 'Show');
    expect(text(l.rows()).last, startsWith('0|3-5|'));
    expect(l.line(pl.current), startsWith('Season 1 · Episode 3-5'));
  });

  test('movie / ad-hoc playlist has no headers and keeps the old label', () {
    final pl = Playlist([
      f(1, null, null, 'Movie.2020.1080p.mkv'),
      f(2, null, null, 'Movie.2020.Extras.mkv'),
    ]);
    final l = PlaylistLabels(pl, 'Movie');
    expect(l.rows().whereType<PlaylistHeaderRow>(), isEmpty);
    expect(l.line(pl.current), 'Movie.2020.1080p');
  });

  test('builder passes every season (all variants) to the playlist', () {
    final seasons = [
      se(1, 1, [f(1, 1, 1, 'a.mkv')], lang: 'hindi'),
      se(2, 1, [f(2, 2, 1, 'b.mkv')], lang: 'english'),
    ];
    final pl = PlaylistBuilder.forEpisode(seasons, 1)!;
    expect(pl.length, 1);
    expect(pl.seasons.keys.toSet(), {1, 2});
    expect(pl.next(), isNull);
  });
}
