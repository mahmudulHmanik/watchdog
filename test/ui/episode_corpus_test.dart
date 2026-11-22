// Opt-in: WATCHDOG_CORPUS=<dir with tv.json[, all.json]> flutter test <this>
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/parsing.dart';
import 'package:watchdog/features/title/episode_title.dart';

final _leak = RegExp(
  r'(?<![A-Za-z0-9])(?:KOR|ENG|HIN|DUAL|MULTI|HQ|HEVC\d|x26\d|\d{3,4}x\d{3,4}|S\d{1,2}E\d+[a-z]?|E\d{2,}|[0-9A-F]{8}|S\d{1,3}\s*E\d{1,4}|h\.?26[45]|hevc|\d{3,4}p|web-?dl|webrip|blu-?ray|bdrip|hdtv|aac\d?|ac3|esubs?|msubs?)(?![A-Za-z0-9])',
  caseSensitive: false,
);

void main() {
  final dir = Platform.environment['WATCHDOG_CORPUS'];
  test('cleanEpisodeTitle leaks on the real corpus stay under 50', () {
    final tv = jsonDecode(File('$dir/tv.json').readAsStringSync()) as List;
    var n = 0, leaked = 0;
    void walk(Map node, String show) {
      for (final k in (node['kids'] as List? ?? []).cast<Map>()) {
        if (k['t'] == 'folder') {
          walk(k, show);
        } else if (isVideo(k['name'] as String)) {
          final name = k['name'] as String;
          final out = cleanEpisodeTitle(
            name,
            show,
            episode: parseEpisode(name).episode,
          );
          n++;
          if (_leak.hasMatch(out)) leaked++;
        }
      }
    }

    for (final t in tv.cast<Map>()) {
      walk(t, parseTitleFolder(t['name'] as String).name);
    }
    final all = File('$dir/all.json');
    if (all.existsSync()) {
      final m = jsonDecode(all.readAsStringSync()) as Map;
      for (final cat in const ['Korean Series', 'Anime & Cartoon']) {
        for (final t in ((m[cat] as List?) ?? const []).cast<Map>()) {
          walk(t, parseTitleFolder(t['name'] as String).name);
        }
      }
    }
    // ignore: avoid_print
    print('corpus files: $n, leaking: $leaked');
    expect(leaked, lessThan(50));
  }, skip: dir == null ? 'set WATCHDOG_CORPUS to run' : false);
}
