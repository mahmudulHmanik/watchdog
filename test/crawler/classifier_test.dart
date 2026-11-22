import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/classifier.dart';
import 'package:watchdog/data/models.dart';

import 'fakes.dart';

TitleDraft byName(List<TitleDraft> ts, String prefix) => ts.firstWhere(
  (t) => t.name.startsWith(prefix),
  orElse: () => fail('no $prefix'),
);

FolderNode folder(
  String name, {
  List<String> files = const [],
  List<FolderNode> kids = const [],
}) => FolderNode(
  name: name,
  url: 'http://h/$name/',
  files: [for (final f in files) NodeFile(name: f, url: 'http://h/$name/$f')],
  folders: kids,
);

void main() {
  final fake = FakeListingClient.fromFixtures();

  group('movies (fixtures)', () {
    late List<TitleDraft> titles;
    setUpAll(() {
      titles = classifyCategory(
        fake.tree(fake.roots['English Movies']!),
        layout: LayoutKind.yearBuckets,
        kind: TitleKind.movie,
        categoryId: 7,
      );
    });

    test('year buckets are containers; each film is a title', () {
      expect(titles.map((t) => t.name), [
        '12 Angry Men',
        'The Cider House Rules',
        'Cypher',
        'Going the Distance',
      ]);
      expect(
        titles.every((t) => t.kind == TitleKind.movie && t.categoryId == 7),
        isTrue,
      );
      final t = byName(titles, '12 Angry');
      expect(t.year, 1957);
      expect(t.quality, 720);
      expect(t.posterUrl, endsWith('.jpg'));
      expect(t.files.single.playable, isTrue);
      expect(t.files.single.episode, isNull);
      expect(t.folderUrl, startsWith('http://172.16.50.7/'));
    });

    test(
      'Subs/scoped_dir folders, subtitles and non-media files are dropped',
      () {
        for (final t in titles) {
          expect(
            t.files.every((f) => f.ext == 'mkv' || f.ext == 'mp4'),
            isTrue,
            reason: t.name,
          );
        }
        expect(
          byName(titles, 'Cypher').files.single.name,
          'Cypherout-muxed (1).mp4',
        );
        expect(byName(titles, 'Going the').files.length, 1);
      },
    );
  });

  test(
    'collection / language bucket: each child film becomes its own title',
    () {
      final t = classifyCategory(
        fake.tree(fake.roots['Foreign Language Movies']!),
        layout: LayoutKind.flat,
        kind: TitleKind.movie,
        categoryId: 1,
      );
      expect(t.map((x) => x.name), ['12 Golden Ducks', '14 Blades']);
      expect(t[1].quality, 1080);
      expect(t[1].tags, contains('dual-audio'));
    },
  );

  test('events keep kind=event', () {
    final t = classifyCategory(
      fake.tree(fake.roots['WWE & AEW']!),
      layout: LayoutKind.events,
      kind: TitleKind.event,
      categoryId: 1,
    );
    expect(t.single.kind, TitleKind.event);
    expect(t.single.year, 2024);
  });

  group('series (fixtures)', () {
    test(
      'flat series: season language, archive unplayable, episode numbers',
      () {
        final t = classifyCategory(
          fake.tree(fake.roots['Korean Series']!),
          layout: LayoutKind.series,
          kind: TitleKind.series,
          categoryId: 1,
        ).single;
        expect(t.kind, TitleKind.series);
        expect(t.name, 'Arang and the Magistrate');
        expect(t.seasons.single.number, 1);
        expect(t.seasons.single.language, 'korean');
        final fs = t.seasons.single.files;
        expect(fs.where((f) => f.playable).map((f) => f.episode), [1, 2]);
        expect(fs.where((f) => !f.playable), isNotEmpty);
        expect(
          fs
              .where((f) => !f.playable)
              .every((f) => f.ext == 'rar' || f.ext == 'zip'),
          isTrue,
        );
        expect(t.posterUrl, isNotNull);
      },
    );

    late List<TitleDraft> anime;
    setUpAll(() {
      anime = classifyCategory(
        fake.tree(fake.roots['Anime & Cartoon']!),
        layout: LayoutKind.series,
        kind: TitleKind.series,
        categoryId: 1,
      );
    });

    test('A-Z buckets are flattened, not shows', () {
      expect(anime.map((t) => t.name).toSet(), {
        'Monogatari-The Complete Series',
        'Bubblegum Crisis',
        'Captain Tsubasa',
      });
    });

    test('unparsed season dir => season 0 labelled with folder name', () {
      final b = byName(anime, 'Bubblegum');
      expect(b.seasons.map((s) => s.number), [0, 0]);
      expect(b.seasons.first.label, startsWith('01 - OVA'));
      final c = byName(anime, 'Captain');
      expect(c.seasons.single.number, 0);
      expect(c.seasons.single.label, 'Season All');
    });

    test('nested release folders under a season are flattened', () {
      final m = byName(anime, 'Monogatari');
      expect(m.seasons.length, 1);
      expect(m.seasons.single.number, 1);
      expect(m.seasons.single.files.length, greaterThan(2));
      expect(
        m.seasons.single.folderUrl,
        endsWith('Season%201%20%28First%20Season%29/'),
      );
    });
  });

  group('synthetic edge cases', () {
    test('year-range folder with loose video is not a title', () {
      final root = folder(
        'cat',
        kids: [
          folder(
            '(1960-1994)',
            files: ['stray.mkv'],
            kids: [
              folder('Heat (1995)', files: ['heat.mkv']),
            ],
          ),
        ],
      );
      final t = classifyMovieTree(root, categoryId: 0);
      expect(t.single.name, 'Heat');
    });

    test('a film literally named like a year is still a title', () {
      final root = folder(
        'cat',
        kids: [
          folder('1984 (1984) 720p', files: ['a.mkv']),
        ],
      );
      expect(classifyMovieTree(root, categoryId: 0).single.year, 1984);
    });

    test('archive-only title is kept, unplayable', () {
      final root = folder(
        'cat',
        kids: [
          folder('X (2001)', files: ['x.rar', 'x.nfo']),
        ],
      );
      final t = classifyMovieTree(root, categoryId: 0).single;
      expect(t.files.single.playable, isFalse);
      expect(t.files.single.ext, 'rar');
    });

    test('empty and extras-only folders yield nothing', () {
      final root = folder(
        'cat',
        kids: [
          folder('Empty (2000)'),
          folder('Sample', files: ['s.mkv']),
          folder(
            'Only Subs (2001)',
            kids: [
              folder('Subs', files: ['a.srt']),
            ],
          ),
        ],
      );
      expect(classifyMovieTree(root, categoryId: 0), isEmpty);
    });

    test('bucket holding a show named like a season is still a bucket', () {
      final show = folder(
        'Foo Season 2 (TV Series 2020)',
        kids: [
          folder('Season 1', files: ['Foo.S01E01.mkv']),
        ],
      );
      final other = folder(
        'Bar (TV Series 2019)',
        kids: [
          folder('Season 1', files: ['Bar.S01E01.mkv']),
        ],
      );
      final other2 = folder(
        'Baz (TV Series 2018)',
        kids: [
          folder('Season 1', files: ['Baz.S01E01.mkv']),
        ],
      );
      final bucket = folder('TV Series F - G', kids: [show, other, other2]);
      expect(looksLikeShow(bucket), isFalse);
      final t = classifySeriesTree(
        folder('root', kids: [bucket]),
        categoryId: 0,
      );
      expect(t.length, 3);
    });

    test('show with only loose episodes gets one season from filenames', () {
      final show = folder(
        'Quux (TV Series 2021)',
        files: ['Quux.S02E01.mkv', 'Quux.S02E02.mkv', 'a.jpg'],
      );
      final t = classifySeriesTree(
        folder('root', kids: [show]),
        categoryId: 0,
      ).single;
      expect(t.seasons.single.number, 2);
      expect(t.seasons.single.files.map((f) => f.episode), [1, 2]);
    });

    test(
      'show with only unparsed season dirs is still a show when it has a year',
      () {
        final show = folder(
          'Quux (TV Series 2021)',
          kids: [
            folder('Complete', files: ['e1.mkv']),
          ],
        );
        expect(looksLikeShow(show), isTrue);
        expect(classifyShow(show, categoryId: 0)!.seasons.single.number, 0);
      },
    );

    test('show fingerprint is the newest of show and season folders', () {
      final a = DateTime(2024, 1, 1), b = DateTime(2025, 1, 1);
      final n = FolderNode(
        name: 'S',
        url: 'http://h/S/',
        mtime: a,
        folders: [FolderNode(name: 'Season 1', url: 'http://h/S/1/', mtime: b)],
      );
      expect(showFingerprint(n), b);
    });
  });
}
