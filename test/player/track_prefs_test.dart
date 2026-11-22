import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/player/domain/track_prefs.dart';

void main() {
  test('canonicalLanguage', () {
    expect(canonicalLanguage('hi'), 'hin');
    expect(canonicalLanguage('HIN'), 'hin');
    expect(canonicalLanguage('Hindi'), 'hin');
    expect(canonicalLanguage('fre'), 'fra');
    expect(canonicalLanguage('und'), isNull);
    expect(canonicalLanguage(null), isNull);
    expect(canonicalLanguage('xx'), 'xx');
  });

  group('trackMatchesLanguage', () {
    test('tag wins, any alias form', () {
      expect(trackMatchesLanguage('hi', 'mkvCinemas', 'hin'), isTrue);
      expect(trackMatchesLanguage('en', 'mkvCinemas', 'hin'), isFalse);
      expect(trackMatchesLanguage('eng', null, 'en'), isTrue);
      expect(trackMatchesLanguage('en', 'Hindi', 'hin'), isFalse); // tag wins
    });
    test('title words when tag missing or und', () {
      expect(trackMatchesLanguage(null, 'Hindi 2.0', 'hin'), isTrue);
      expect(trackMatchesLanguage('und', 'English 5.1', 'eng'), isTrue);
      expect(trackMatchesLanguage('und', 'English 5.1', 'hin'), isFalse);
      expect(
        trackMatchesLanguage(null, 'Hindi 2.0+English 5.1', 'eng'),
        isTrue,
      );
      expect(trackMatchesLanguage(null, 'Bhindi', 'hin'), isFalse);
    });
    test('no preference / unknown', () {
      expect(trackMatchesLanguage('en', null, ''), isFalse);
      expect(trackMatchesLanguage(null, null, 'eng'), isFalse);
    });
  });

  test('pickPreferredIndex on a dual-audio file (real mpv tags: hi, en)', () {
    final tracks = <(String?, String?)>[
      ('hi', 'mkvCinemas'),
      ('en', 'mkvCinemas'),
    ];
    expect(pickPreferredIndex(tracks, 'hin'), 0);
    expect(pickPreferredIndex(tracks, 'eng'), 1);
    expect(pickPreferredIndex(tracks, 'jpn'), isNull);
    expect(pickPreferredIndex(tracks, null), isNull);
  });

  test('labels', () {
    expect(languageName('hi'), 'Hindi');
    expect(languageName('zz'), 'ZZ');
    expect(languageName('und'), isNull);
    expect(channelLabel('stereo', null), '2.0');
    expect(channelLabel('unknown6', null), '5.1');
    expect(channelLabel('5.1(side)', null), '5.1');
    expect(channelLabel(null, 8), '7.1');
    expect(channelLabel(null, null), isNull);
  });
}
