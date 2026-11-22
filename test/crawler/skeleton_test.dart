import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/skeleton.dart';
import 'package:watchdog/data/models.dart' show TitleKind;

import 'api_fakes.dart';

ApiItem _tree(String fixture, String href) =>
    parseApiTree(fixtureBytes(fixture), href);

SkeletonClassifier _cls(String host, {bool seasons = true}) =>
    SkeletonClassifier(
      origin: 'http://$host',
      seasonContainersAsSeries: seasons,
    );

// ---- synthetic builders (rules only; not server data) -------------------
ApiItem _file(String dir, String name, {int t = 1000000, int size = 1}) =>
    ApiItem(
      name: name,
      href: '$dir${Uri.encodeComponent(name)}',
      isFolder: false,
      time: DateTime.fromMillisecondsSinceEpoch(t, isUtc: true),
      size: size,
    );

ApiItem _dir(
  String parent,
  String name, {
  List<ApiItem>? Function(String href)? kids,
  int t = 1000000,
}) {
  final href = '$parent${Uri.encodeComponent(name)}/';
  return ApiItem(
    name: name,
    href: href,
    isFolder: true,
    time: DateTime.fromMillisecondsSinceEpoch(t, isUtc: true),
    children: kids?.call(href),
  );
}

void main() {
  const tv = '/DHAKA-FLIX-12/TV-WEB-Series/';
  const bucketS = '${tv}TV%20Series%20%E2%99%A6%20%20S%20%20%E2%80%94%20%20Z/';

  group('movie year bucket (English)', () {
    final root = _tree(
      'year_2020_what2.json',
      '/DHAKA-FLIX-7/English%20Movies/%282020%29/',
    );
    final lvl = _cls('172.16.50.7')
        .classify(root, layout: LayoutKind.yearBuckets, kind: TitleKind.movie);

    test('every child with media is a title; nothing to descend', () {
      expect(lvl.titles.length, 11);
      expect(lvl.descend, isEmpty);
    });

    test('name, year, quality, poster, file count, urls, times', () {
      final t = lvl.titles.first;
      expect(t.name, '1 Interrogation');
      expect(t.year, 2020);
      expect(t.quality, 720);
      expect(t.kind, TitleKind.movie);
      expect(t.fileCount, 1);
      expect(t.archiveCount, 0);
      expect(t.posterPath, 'a_AL_.jpg');
      expect(
        t.folderUrl,
        'http://172.16.50.7/DHAKA-FLIX-7/English%20Movies/%282020%29/'
        '1%20Interrogation%20%282020%29%20720p%20WEBRip/',
      );
      expect(t.mtime, t.fingerprint);
      expect(t.mtime!.isUtc, isTrue);
      expect(t.seasons, isEmpty);
    });
  });

  test(
    'English root listed with what=1: years are all unlisted -> descend',
    () {
      final root = _tree(
        'english_root_what1.json',
        '/DHAKA-FLIX-7/English%20Movies/',
      );
      final lvl = _cls(
        '172.16.50.7',
      ).classify(root, layout: LayoutKind.yearBuckets, kind: TitleKind.movie);
      expect(lvl.titles, isEmpty);
      expect(lvl.descend.map((c) => c.name).first, '(1960-1994)');
      expect(lvl.descend.length, 8);
    },
  );

  group('language buckets (Foreign Language Movies)', () {
    test('root what=2: only containers -> descend, no titles', () {
      final root = _tree(
        'foreign_root_what2.json',
        '/DHAKA-FLIX-7/Foreign%20Language%20Movies/',
      );
      final lvl = _cls(
        '172.16.50.7',
      ).classify(root, layout: LayoutKind.yearBuckets, kind: TitleKind.movie);
      expect(lvl.titles, isEmpty);
      expect(lvl.descend.map((c) => c.name), [
        'Bangla Dubbing Movies',
        'Chinese Language',
        'Korean Language',
      ]);
    });

    test('bucket what=2: titles with year/quality/tags', () {
      final root = _tree(
        'foreign_bucket_what2.json',
        '/DHAKA-FLIX-7/Foreign%20Language%20Movies/Chinese%20Language/',
      );
      final lvl = _cls(
        '172.16.50.7',
      ).classify(root, layout: LayoutKind.yearBuckets, kind: TitleKind.movie);
      expect(lvl.titles.length, 6);
      final t = lvl.titles[1];
      expect((t.name, t.year, t.quality), ('14 Blades', 2010, 1080));
      expect(t.tags, contains('dual-audio'));
    });
  });

  group('flat category with mixed content (Documentary)', () {
    final root = _tree(
      'documentary_root_what2.json',
      '/DHAKA-FLIX-10/Documentary/',
    );
    final lvl = _cls('172.16.50.10')
        .classify(root, layout: LayoutKind.flat, kind: TitleKind.movie);

    test(
      'titles directly; a media-less folder with a subfolder is descended',
      () {
        expect(lvl.titles.where((t) => !t.isSeries).length, 5);
        expect(lvl.descend.map((c) => c.name), [
          'Europa-The Last Battle (TV Documentary 2017) 720p',
        ]); // "All Parts" container -> needs its own what=2
      },
    );

    test('season containers become series (default)', () {
      final shows = lvl.titles.where((t) => t.isSeries).toList();
      expect(shows.map((s) => s.name), [
        '9-11 - One Day in America',
        'A Haunting',
        'A Perfect Planet',
      ]);
      final h = shows[1];
      expect(h.year, 2005);
      expect(h.seasons.length, 11);
      expect(h.seasons.map((s) => s.number), List.generate(11, (i) => i + 1));
      expect(h.seasons.first.episodeCount, isNull); // not listed at this depth
      expect(h.fileCountExact, isFalse);
      expect(h.posterPath, 'a_VL_.jpg');
    });

    test('seasonContainersAsSeries=false reproduces the full classifier', () {
      final l = _cls(
        '172.16.50.10',
        seasons: false,
      ).classify(root, layout: LayoutKind.flat, kind: TitleKind.movie);
      expect(l.titles.every((t) => !t.isSeries), isTrue);
      expect(l.titles.length, 5);
      expect(
        l.descend.map((c) => c.name).toSet(),
        containsAll(['A Haunting (TV Documentary 2005– ) 720p']),
      );
    });

    test('.flv counts as a video (Revealed-The Hajj)', () {
      final t = lvl.titles.firstWhere((t) => t.name.startsWith('Revealed'));
      expect(t.fileCount, 1);
      expect(t.tags, ['hindi-dubbed']);
    });
  });

  group('series buckets (TV, Anime)', () {
    test('TV root what=1: four A-Z buckets, unlisted -> descend', () {
      final root = _tree('tv_root_what1.json', tv);
      final lvl = _cls('172.16.50.12')
          .classify(root, layout: LayoutKind.series, kind: TitleKind.series);
      expect(lvl.titles, isEmpty);
      expect(lvl.descend.length, 4);
    });

    test('bucket what=2: shows + seasons + poster; counts unknown', () {
      final root = _tree('tv_bucket_what2.json', bucketS);
      final lvl = _cls('172.16.50.12')
          .classify(root, layout: LayoutKind.series, kind: TitleKind.series);
      expect(lvl.descend, isEmpty);
      expect(lvl.titles.length, 8);
      final swat = lvl.titles.first;
      expect(swat.name, 'S.W.A.T.');
      expect((swat.year, swat.yearEnd, swat.quality), (2017, 2025, 720));
      expect(swat.kind, TitleKind.series);
      expect(swat.posterPath, 'a_AL_.jpg');
      expect(swat.seasons.map((s) => s.number), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(swat.seasons.first.label, 'Season 1');
      expect(swat.seasons.first.folderUrl, endsWith('/Season%201/'));
      expect(swat.seasons.every((s) => s.episodeCount == null), isTrue);
      expect(swat.fileCountExact, isFalse);
      // fingerprint = newest of show and season folders
      final times = [swat.mtime!, ...swat.seasons.map((s) => s.mtime!)]..sort();
      expect(swat.fingerprint, times.last);
    });

    test('season language is read from the folder name', () {
      final root = _tree('tv_bucket_what2.json', bucketS);
      final lvl = _cls('172.16.50.12')
          .classify(root, layout: LayoutKind.series, kind: TitleKind.series);
      final s = lvl.titles.firstWhere(
        (t) => t.name == 'Saas, Bahu Aur Flamingo',
      );
      expect(s.seasons.single.number, 1);
      expect(s.seasons.single.language, 'hindi');
      final z = lvl.titles.firstWhere((t) => t.name == 'Skylines');
      expect(z.seasons.single.language, 'german');
    });

    test('Anime: TV Cartoon year range parsed, nested seasons', () {
      final root = _tree(
        'anime_bucket_what2.json',
        '/DHAKA-FLIX-10/Anime%20%26%20Cartoon%20TV%20Series/'
            'Anime-TV%20Series%20%E2%99%A5%20%20G%20%20%E2%80%94%20%20M/',
      );
      final lvl = _cls('172.16.50.10')
          .classify(root, layout: LayoutKind.series, kind: TitleKind.series);
      final m = lvl.titles.firstWhere((t) => t.name.startsWith('Monogatari'));
      expect((m.year, m.yearEnd), (2009, 2024));
      expect(m.seasons.map((s) => s.number), [1, 2, 3, 4]);
      expect(m.seasons.last.label, 'Season 4 (Off & Monster Season)');
      final g = lvl.titles.firstWhere((t) => t.name == 'Gargoyles');
      expect((g.year, g.yearEnd), (1994, 1996));
    });

    test('show what=2: episode counts known; nested release folders unknown', () {
      final swat = _tree(
        'show_swat_what2.json',
        '${bucketS}S.W.A.T.%20%28TV%20Series%202017%E2%80%932025%29%20720p%20%5BDual%20Audio%5D/',
      );
      final s = _cls('172.16.50.12').show(swat)!;
      expect(s.seasons.map((x) => (x.number, x.episodeCount)), [
        (1, 22),
        (2, 23),
        (3, 21),
      ]);
      expect(s.fileCount, 66);
      expect(s.fileCountExact, isTrue);

      final mono = _tree(
        'show_monogatari_what2.json',
        '/DHAKA-FLIX-10/Anime%20%26%20Cartoon%20TV%20Series/'
            'Anime-TV%20Series%20%E2%99%A5%20%20G%20%20%E2%80%94%20%20M/'
            'Monogatari-The%20Complete%20Series%20%28TV%20Cartoon%202009%E2%80%932024%29%201080p/',
      );
      final m = _cls('172.16.50.10').show(mono)!;
      expect(m.seasons.every((x) => x.episodeCount == null), isTrue);
      expect(m.fileCountExact, isFalse);
    });
  });

  test('events: kind is event, dates in the name give the year', () {
    final root = _tree(
      'events_what2.json',
      '/DHAKA-FLIX-10/WWE%20%26%20AEW%20Wrestling/AEW%20Wrestling/',
    );
    final lvl = _cls('172.16.50.10')
        .classify(root, layout: LayoutKind.events, kind: TitleKind.event);
    expect(lvl.titles.length, 5);
    expect(lvl.titles.every((t) => t.kind == TitleKind.event), isTrue);
    expect(lvl.titles.first.year, 2024);
  });

  group('rules (synthetic trees)', () {
    const p = '/S/Cat/';
    ApiItem folder(List<ApiItem> kids) =>
        ApiItem(name: 'Cat', href: p, isFolder: true, children: kids);

    test('Sample / extras / scoped_dir folders are ignored everywhere', () {
      final f = folder([
        _dir(p, 'Sample', kids: (h) => [_file(h, 'a.mkv')]),
        _dir(p, 'scoped_dir_x', kids: (h) => [_file(h, 'a.mkv')]),
        _dir(p, 'Extras', kids: (h) => [_file(h, 'a.mkv')]),
        _dir(
          p,
          'Real (2000) 720p',
          kids: (h) => [
            _file(h, 'a.mkv'),
            _dir(h, 'Sample', kids: (s) => [_file(s, 's.mkv')]),
          ],
        ),
      ]);
      final l = _cls('h').classifyMovies(f);
      expect(l.titles.map((t) => t.name), ['Real']);
      expect(l.descend, isEmpty);
      final s = _cls('h').classifySeries(
        folder([
          _dir(p, 'Sample', kids: (h) => [_file(h, 'a.mkv')]),
        ]),
      );
      expect(s.titles, isEmpty);
    });

    test('archives are counted but not playable; archive-only title kept', () {
      final f = folder([
        _dir(
          p,
          'Boxed (2001)',
          kids: (h) => [
            _file(h, 'boxed.part1.rar'),
            _file(h, 'boxed.part2.rar'),
            _file(h, 'cover.jpg'),
          ],
        ),
        _dir(
          p,
          'Mixed (2002)',
          kids: (h) => [_file(h, 'm.mkv'), _file(h, 'm.zip')],
        ),
        _dir(p, 'Only Pics (2003)', kids: (h) => [_file(h, 'x.jpg')]),
      ]);
      final l = _cls('h').classifyMovies(f);
      expect(l.titles.map((t) => (t.name, t.fileCount, t.archiveCount)), [
        ('Boxed', 0, 2),
        ('Mixed', 1, 1),
      ]);
      expect(l.titles.first.posterPath, 'cover.jpg');
      expect(l.descend, isEmpty);
    });

    test('year-range bucket holding media is a container, not a title', () {
      final f = folder([
        _dir(
          p,
          '(1960-1994)',
          kids: (h) => [
            _file(h, 'stray.mkv'),
            _dir(h, 'Old (1970)', kids: null),
          ],
        ),
      ]);
      final l = _cls('h').classifyMovies(f);
      expect(l.titles, isEmpty);
      expect(l.descend.single.name, '(1960-1994)');
    });

    test('unlisted children are descended; empty listed folders vanish', () {
      final f = folder([
        _dir(p, 'Unlisted', kids: null),
        _dir(p, 'Empty', kids: (h) => []),
        _dir(
          p,
          'Collection',
          kids: (h) => [_dir(h, 'Part 1 (2001)', kids: null)],
        ),
      ]);
      final l = _cls('h').classifyMovies(f);
      expect(l.titles, isEmpty);
      expect(l.descend.map((c) => c.name), ['Unlisted', 'Collection']);
    });

    test('unparsed season dir => season 0; loose files => one season', () {
      final f = folder([
        _dir(
          p,
          'Show A (TV Series 2010) 720p',
          kids: (h) => [
            _dir(
              h,
              'Behind The Scenes Bonus',
              kids: (b) => [_file(b, 'b.mkv')],
            ),
            _dir(
              h,
              'Season 2',
              kids: (b) => [_file(b, 'A.S02E01.mkv'), _file(b, 'A.S02E02.mkv')],
            ),
          ],
        ),
        _dir(
          p,
          'Show B (TV Series 2011) 720p',
          kids: (h) => [
            _file(h, 'B.S03E01.mkv'),
            _file(h, 'B.S03E02.mkv'),
            _file(h, 'B.S01E01.mkv'),
          ],
        ),
        _dir(
          p,
          'Show C (TV Series 2012) 720p',
          kids: (h) => [
            _dir(h, 'Season 1', kids: (b) => [_file(b, 'c1.mkv')]),
            _file(h, 'c-special.mkv'),
          ],
        ),
      ]);
      final l = _cls('h').classifySeries(f);
      final a = l.titles[0];
      expect(a.seasons.map((s) => (s.number, s.label, s.episodeCount)), [
        (0, 'Behind The Scenes Bonus', 1),
        (2, 'Season 2', 2),
      ]);
      final b = l.titles[1];
      expect(b.seasons.single.number, 3); // majority of parsed season numbers
      expect(b.seasons.single.episodeCount, 3);
      expect(b.fileCount, 3);
      final c = l.titles[2];
      expect(c.seasons.map((s) => (s.number, s.label)), [
        (0, 'Other'),
        (1, 'Season 1'),
      ]);
    });

    test('show fingerprint includes season folders and loose files', () {
      final f = folder([
        _dir(
          p,
          'Show (TV Series 2010)',
          t: 1000,
          kids: (h) => [
            _dir(h, 'Season 1', t: 9000, kids: null),
            _file(h, 'poster.jpg', t: 5000),
            _dir(h, 'Season 2', t: 3000, kids: null),
          ],
        ),
      ]);
      final t = _cls('h').classifySeries(f).titles.single;
      expect(t.mtime!.millisecondsSinceEpoch, 1000);
      expect(t.fingerprint!.millisecondsSinceEpoch, 9000);
      expect(t.seasons.length, 2);
    });

    test('fingerprintAsListing is the HTML form (minute, local)', () {
      final f = folder([
        ApiItem(
          name: 'M (2020)',
          href: '${p}M%20%282020%29/',
          isFolder: true,
          time: DateTime.utc(2020, 11, 17, 2, 57, 58),
          children: [_file('${p}M%20%282020%29/', 'm.mkv')],
        ),
      ]);
      final t = _cls('h').classifyMovies(f).titles.single;
      expect(t.fingerprintAsListing, DateTime(2020, 11, 17, 2, 57));
    });
  });
}
