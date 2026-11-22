import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/series/domain/playlist.dart';

MediaFile f(int id, {int? season, int? ep, int? end, bool playable = true}) =>
    MediaFile(
      id: id,
      titleId: 1,
      seasonId: season,
      name: 'f$id.mkv',
      url: 'http://h/f$id.mkv',
      ext: playable ? 'mkv' : 'rar',
      playable: playable,
      episode: ep,
      episodeEnd: end,
    );

SeasonEpisodes se(int id, int number, List<MediaFile> files, {String? lang}) =>
    SeasonEpisodes(
      season: Season(
        id: id,
        titleId: 1,
        number: number,
        label: 'S$number',
        language: lang,
      ),
      files: files,
    );

List<int> ids(Playlist p) => [for (final x in p.items) x.id];

void main() {
  group('Playlist', () {
    final p = Playlist([f(1), f(2), f(3)], index: 1);
    test('navigation', () {
      expect(p.current.id, 2);
      expect(p.next()!.current.id, 3);
      expect(p.prev()!.current.id, 1);
      expect(p.next()!.next(), isNull);
      expect(p.prev()!.prev(), isNull);
      expect(p.hasNext && p.hasPrev, isTrue);
      expect(p.nextFile!.id, 3);
    });
    test('fromIndex = play from here', () {
      final q = p.fromIndex(1)!;
      expect(ids(q), [2, 3]);
      expect(q.index, 0);
      expect(p.fromIndex(3), isNull);
      expect(p.jumpTo(-1), isNull);
    });
    test('rejects empty / bad index', () {
      expect(() => Playlist([]), throwsArgumentError);
      expect(() => Playlist([f(1)], index: 1), throwsRangeError);
    });
    test('items are unmodifiable', () {
      expect(() => p.items.add(f(9)), throwsUnsupportedError);
    });
  });

  group('PlaylistBuilder', () {
    test('movie: single / one-item list, unplayable dropped', () {
      expect(PlaylistBuilder.single(f(1)).length, 1);
      final pl = PlaylistBuilder.fromFiles([f(1, playable: false), f(2)])!;
      expect(ids(pl), [2]);
      expect(PlaylistBuilder.fromFiles([f(1, playable: false)]), isNull);
    });

    test('fromFiles start id and unknown id', () {
      final fs = [f(1), f(2), f(3)];
      expect(PlaylistBuilder.fromFiles(fs, startFileId: 3)!.index, 2);
      expect(PlaylistBuilder.fromFiles(fs, startFileId: 99)!.index, 0);
    });

    final seasons = [
      se(10, 0, [f(100, season: 10)]),
      se(11, 1, [f(1, season: 11, ep: 1), f(2, season: 11, ep: 2)]),
      se(12, 2, [
        f(3, season: 12, ep: 1),
        f(4, season: 12, ep: 2, playable: false),
        f(5, season: 12, ep: 3, end: 5), // range file: one item
      ]),
    ];

    test('crosses seasons in order, skips unplayable, specials excluded', () {
      final p = PlaylistBuilder.forEpisode(seasons, 2)!;
      expect(ids(p), [1, 2, 3, 5]);
      expect(p.current.id, 2);
      expect(p.items.last.episodeEnd, 5);
    });

    test('specials (season 0) are their own queue', () {
      final p = PlaylistBuilder.forEpisode(seasons, 100)!;
      expect(ids(p), [100]);
    });

    test('forSeason starts at that season first episode', () {
      final p = PlaylistBuilder.forSeason(seasons, 12)!;
      expect(ids(p), [1, 2, 3, 5]);
      expect(p.current.id, 3);
      expect(PlaylistBuilder.forSeason(seasons, 999), isNull);
    });

    test('language variants never mix', () {
      final v = [
        se(1, 1, [f(1, ep: 1), f(2, ep: 2)], lang: 'Hindi'),
        se(2, 1, [f(11, ep: 1), f(12, ep: 2)], lang: 'English'),
        se(3, 2, [f(3, ep: 1)], lang: 'Hindi'),
        se(4, 2, [f(13, ep: 1)], lang: 'English'),
      ];
      expect(ids(PlaylistBuilder.forEpisode(v, 2)!), [1, 2, 3]);
      expect(ids(PlaylistBuilder.forEpisode(v, 12)!), [11, 12, 13]);
      expect(PlaylistBuilder.forEpisode(v, 12)!.current.id, 12);
    });

    test('unsorted seasons are ordered by number, stable within number', () {
      final v = [
        se(2, 2, [f(3, ep: 1)]),
        se(1, 1, [f(1, ep: 1)]),
      ];
      expect(ids(PlaylistBuilder.forEpisode(v, 3)!), [1, 3]);
    });

    test('unknown / unplayable start file -> null', () {
      expect(PlaylistBuilder.forEpisode(seasons, 999), isNull);
      expect(PlaylistBuilder.forEpisode(seasons, 4), isNull);
    });

    test('empty season -> null', () {
      expect(PlaylistBuilder.forSeason([se(1, 1, [])], 1), isNull);
    });
  });
}
