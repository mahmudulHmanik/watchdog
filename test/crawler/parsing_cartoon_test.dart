import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/parsing.dart';

void main() {
  // Real Anime folder names: "(TV Cartoon ...)" was not recognised, so the
  // year came from a stray number before the quality.
  test('TV Cartoon year / range', () {
    expect(parseYear('Gargoyles (TV Cartoon 1994–1996) 480p'), (1994, 1996));
    expect(
      parseYear('Monogatari-The Complete Series (TV Cartoon 2009–2024) 1080p'),
      (2009, 2024),
    );
    expect(
      parseYear('Garo-Vanishing Line (TV Cartoon 2017– ) 1080p [Dual Audio]'),
      (2017, null),
    );
    expect(parseYear('Immoral Guild (TV Cartoon 2022) 1080p'), (2022, null));
    final t = parseTitleFolder('Gargoyles (TV Cartoon 1994–1996) 480p');
    expect(
      (t.name, t.year, t.yearEnd, t.quality),
      ('Gargoyles', 1994, 1996, 480),
    );
  });
}
