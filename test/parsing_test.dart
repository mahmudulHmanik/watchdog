import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/listing.dart';
import 'package:watchdog/crawler/parsing.dart';

void main() {
  group('parseYear', () {
    final cases = <String, (int?, int?)>{
      'Alice in Wonderland (2010) 720p [Dual Audio]': (2010, null),
      'Senseless [1998]': (1998, null),
      'Out of Sight 1998 720p': (1998, null),
      'Tracks 2013 1080p': (2013, null),
      'The Legend Of Hercules 2014) 1080p [3D]': (2014, null),
      'Hero The Action Man (2013 (Hindi Dubbed)': (2013, null),
      'No 1 Judwa ( 2012) (Hindi Dubbed)': (2012, null),
      'Peaky Blinders (TV Series 2013–2022) 1080p': (2013, 2022),
      'A Bloody Lucky Day (TV Series 2023– ) 720p': (2023, null),
      'Mad Unicorn (TV Mini Series 2025) 720p': (2025, null),
      '#Cats_The_Mewvie (TV Documentary 2020) 720p WEBRip': (2020, null),
      'Fighter 2011 DvDRip 720p': (2011, null),
      'Aadhavan-2009.Tamil.DvDRip': (2009, null),
      'Some Title 720p': (null, null),
    };
    cases.forEach((k, v) => test(k, () => expect(parseYear(k), v)));
  });

  group('parseTitleFolder', () {
    test('strips year/quality/brackets', () {
      final t = parseTitleFolder(
        'Alice in Wonderland (2010) 720p [Dual Audio]',
      );
      expect(t.name, 'Alice in Wonderland');
      expect(t.year, 2010);
      expect(t.quality, 720);
      expect(t.tags, contains('dual-audio'));
    });
    test('series', () {
      final t = parseTitleFolder(
        '1000 Babies (TV Series 2024– ) 720p [Dual Audio]',
      );
      expect(t.name, '1000 Babies');
      expect(t.year, 2024);
    });
    test('bare year', () {
      expect(parseTitleFolder('Out of Sight 1998 720p').name, 'Out of Sight');
    });
    test('keeps numeric titles', () {
      expect(parseTitleFolder('127 Hours (2010) 720p').name, '127 Hours');
      expect(parseTitleFolder('13 (2010) 720p').name, '13');
    });
  });

  group('parseSeasonFolder', () {
    test('plain', () => expect(parseSeasonFolder('Season 1')!.number, 1));
    test(
      'zero padded',
      () => expect(parseSeasonFolder('Season 04')!.number, 4),
    );
    test('language', () {
      final s = parseSeasonFolder('Season 2 (Hindi Language)')!;
      expect((s.number, s.language), (2, 'hindi'));
    });
    test('typos', () {
      expect(parseSeasonFolder('Seazon 1')!.number, 1);
      expect(parseSeasonFolder('Ssason 05')!.number, 5);
    });
    test(
      'prefixed',
      () => expect(parseSeasonFolder('NCIS Season 07')!.number, 7),
    );
    test(
      'episode range',
      () => expect(
        parseSeasonFolder('Season 1 [E001–E099] (Hindi Dubbed)')!.number,
        1,
      ),
    );
    test('specials', () {
      for (final n in [
        'Specials',
        'Special',
        'Spesial',
        'Specials & Extras',
        'OVA',
        'OVAs',
        'OVA + Special',
      ]) {
        expect(parseSeasonFolder(n)!.number, 0, reason: n);
      }
    });
    test('non season', () => expect(parseSeasonFolder('Sample'), isNull));
  });

  group('parseEpisode', () {
    test('SxxExx', () {
      final e = parseEpisode(
        'Peaky Blinders S01E02  1080p BluRay x265 HEVC ESub [Dual Audio][Hindi 2.0+English 5.1] -KmHD.mkv',
      );
      expect((e.season, e.episode, e.episodeEnd), (1, 2, null));
    });
    test('range', () {
      final e = parseEpisode(
        'The Verdict-State vs Nanavati S01 E01-E05 Hindi 720p WEBRip x264 AAC - mkvCinemas.mkv',
      );
      expect((e.season, e.episode, e.episodeEnd), (1, 1, 5));
    });
    test('dotted', () {
      final e = parseEpisode(
        'Bones.S03E13.The.Verdict.In.the.Story.720p.WEB-DL.x264.300MB-Pahe.in.mkv',
      );
      expect((e.season, e.episode), (3, 13));
    });
    test('NxNN', () {
      final e = parseEpisode('Angel.3x21.Benediction.x264.mkv');
      expect((e.season, e.episode), (3, 21));
    });
    test('Episode N', () {
      final e = parseEpisode(
        'Episode 178 Jaimini predicts the future [DDR].mp4',
      );
      expect((e.season, e.episode), (null, 178));
    });
    test('underscore', () {
      final e = parseEpisode(
        'Arrow_S02E14_1080p.BluRay.x265.HEVC.10bit.5.1.AAC-30NAMA.mkv',
      );
      expect((e.season, e.episode), (2, 14));
    });
    test('s01x06', () {
      final e = parseEpisode('Traveler.s01x06.720p.hdtv.x264.[Dual.Audio].mkv');
      expect((e.season, e.episode), (1, 6));
    });
    final bare = <String, int>{
      'Naruto Shippuden - 442 [Dual Audio][1080p WEB-DL x265 HEVC MSubs] [Marshall].mkv':
          442,
      'Arang and Magistrate 04.mkv': 4,
      'Personal.Taste.14.KOR.720p.NF.WEB-DL.x264-Pahe.mkv': 14,
      '[HorribleSubs] World Trigger - 32 [720p].mkv': 32,
      '[DB]Ace of the Diamond_-_43_(10bit_720p_x265).mkv': 43,
      '05 Sorcerer Hunters.mkv': 5,
      'School Rumble 10.mkv': 10,
    };
    bare.forEach(
      (k, v) => test('bare: \$k', () => expect(parseEpisode(k).episode, v)),
    );
    test('none', () => expect(parseEpisode('movie.mkv').episode, isNull));
  });

  group('helpers', () {
    test('extras', () {
      expect(isExtrasFolder('Sample'), isTrue);
      expect(isExtrasFolder('scoped_dir_4768_20470'), isTrue);
      expect(isExtrasFolder('Season 1'), isFalse);
    });
    test('types', () {
      expect(isVideo('a.MKV'), isTrue);
      expect(isArchive('a.rar'), isTrue);
      expect(isVideo('a.rar'), isFalse);
    });
  });

  group('parseListing (real h5ai fixtures)', () {
    test('movie folder', () {
      final es = parseListing(
        File('test/fixtures/movie_folder.html').readAsStringSync(),
      );
      expect(es.length, 2);
      final v = es.firstWhere((e) => e.name.endsWith('.mkv'));
      expect(v.isDir, isFalse);
      expect(v.sizeKb, 1209994);
      expect(v.modified, DateTime(2024, 12, 23, 17, 25));
      expect(v.href, contains('%20'));
    });
    test('season folder', () {
      final es = parseListing(
        File('test/fixtures/season_folder.html').readAsStringSync(),
      );
      expect(es.where((e) => isVideo(e.name)).length, greaterThan(5));
      expect(
        es.any((e) => e.name == '..' || e.name == 'Parent Directory'),
        isFalse,
      );
    });
  });
}
