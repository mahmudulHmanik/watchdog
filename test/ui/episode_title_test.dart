import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/title/episode_title.dart';

void main() {
  String c(String f, String show, {int? ep, bool special = false}) =>
      cleanEpisodeTitle(f, show, episode: ep, special: special);

  test('release names with no episode title fall back', () {
    expect(
      c(
        'Peaky Blinders S01E02  1080p BluRay x265 HEVC ESub [Dual Audio][Hindi 2.0+English 5.1] -KmHD.mkv',
        'Peaky Blinders',
        ep: 2,
      ),
      'Episode 2',
    );
    expect(
      c(
        'Naruto Shippuden - 442 [Dual Audio][1080p WEB-DL x265 HEVC MSubs] [Marshall].mkv',
        'Naruto Shippuden',
        ep: 442,
      ),
      'Episode 442',
    );
  });

  test('keeps the real episode title', () {
    expect(
      c(
        'Bones.S03E13.The.Verdict.In.the.Story.720p.WEB-DL.x264.300MB-Pahe.in.mkv',
        'Bones',
        ep: 13,
      ),
      'The Verdict In the Story',
    );
    expect(
      c('Episode 178 Jaimini predicts the future [DDR].mp4', 'CID', ep: 178),
      'Jaimini predicts the future',
    );
  });

  test('misc shapes', () {
    expect(
      c('Show.Name.S02E05.Hello.World.mkv', 'Show Name', ep: 5),
      'Hello World',
    );
    expect(
      c('Show Name - S02E05 - Hello World.mkv', 'Show Name', ep: 5),
      'Hello World',
    );
    expect(c('Show.S01E01.1080p.mkv', 'Show', ep: 1), 'Episode 1');
    expect(c('Show.S00E01.mkv', 'Show', ep: 1, special: true), 'Special 1');
    expect(c('weird.mkv', 'Show'), 'weird');
    expect(c('Show.mkv', 'Show'), 'Episode');
    expect(c('01 - Pilot.mkv', 'Show', ep: 1), 'Pilot');
    expect(
      c(
        'Spider-Man Origins S01E03 Ünïcode Tïtle 720p.mkv',
        'Spider-Man Origins',
        ep: 3,
      ),
      'Ünïcode Tïtle',
    );
    expect(c('Show S01E01-E03 Opening 1080p.mkv', 'Show', ep: 1), 'Opening');
  });

  test('leaks seen in the real corpus', () {
    // letter-suffixed episode
    expect(
      c('Codename S03E05a Hidden Truth 720p.mkv', 'Codename', ep: 5),
      'Hidden Truth',
    );
    expect(c('Codename S03E05a 720p.mkv', 'Codename', ep: 5), 'Episode 5');
    // parenthesised tech tokens
    expect(
      c('Show S01E02 Pilot (1920x1080 HEVC2 AAC).mkv', 'Show', ep: 2),
      'Pilot',
    );
    expect(
      c('Show S01E02 (1080p AMZN WEB-DL x265 LION).mkv', 'Show', ep: 2),
      'Episode 2',
    );
    // hash-only
    expect(c('Show S01E02 (1B35AACB).mkv', 'Show', ep: 2), 'Episode 2');
    expect(c('[Grp] Show - 03 [1B35AACB].mkv', 'Show', ep: 3), 'Episode 3');
    // language tags
    expect(c('Show S01E02 Pilot KOR 1080p.mkv', 'Show', ep: 2), 'Pilot');
    expect(c('Show S01E02 DUAL HIN ENG.mkv', 'Show', ep: 2), 'Episode 2');
    expect(c('Show S01E02 Title Eng Sub.mkv', 'Show', ep: 2), 'Title');
    // show folder differs slightly from the file prefix
    expect(
      c(
        'The Royle Family S01E01  540p WEB-DL x265.mp4',
        'The Royle Family 540p',
        ep: 1,
      ),
      'Episode 1',
    );
    expect(
      c("Yu-Gi-Oh! 5D's - 12 - Title.mkv", "Yu Gi Oh 5D's", ep: 12),
      'Title',
    );
    // trailing -N-
    expect(c('Yu-Gi-Oh! -134-.mkv', 'Yu-Gi-Oh!', ep: 134), 'Episode 134');
    // en-dash ranges and standalone E tokens
    expect(
      c(
        'Anne of Green Gables (1985) E01\u2013E02 720p BluRay x264.mkv',
        'Anne of Green Gables',
        ep: 1,
      ),
      'Episode 1',
    );
    expect(
      c('Show S02 E01\u2013E04 Hindi 720p WEBRip.mkv', 'Show', ep: 1),
      'Episode 1',
    );
    expect(
      c('Show.s03.e01.(e65).WEB-DLRip720p.mkv', 'Show', ep: 1),
      'Episode 1',
    );
    // orphan paren from show name with a parenthesised tail
    expect(
      c(
        'The Office (US) (2005) - S02E03 - Office Olympics (1080p AMZN WEB-DL x265 LION).mkv',
        'The Office US',
        ep: 3,
      ),
      'Office Olympics',
    );
    expect(c('01) Great Sword.mkv', 'X', ep: 1), 'Great Sword');
  });
}
