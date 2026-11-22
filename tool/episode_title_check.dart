// ignore_for_file: avoid_print
// Dev tool: run cleanEpisodeTitle over the saved TV crawl and report leaks.
// Usage: dart run tool/episode_title_check.dart <dir containing tv.json> [-v]
import 'dart:convert';
import 'dart:io';

import 'package:watchdog/crawler/parsing.dart';
import 'package:watchdog/features/title/episode_title.dart';

final leak = RegExp(
  r'(?<![A-Za-z0-9])(?:KOR|ENG|HIN|DUAL|MULTI|HQ|HEVC\d|x26\d|\d{3,4}x\d{3,4}|S\d{1,2}E\d+[a-z]?|E\d{2,}|[0-9A-F]{8}|S\d{1,3}\s*E\d{1,4}|x26[45]|h\.?26[45]|hevc|\d{3,4}p|\d{3,4}x\d{3,4}|web-?dl|webrip|blu-?ray|bdrip|hdtv|aac\d?|ac3|esubs?|msubs?)(?![A-Za-z0-9])',
  caseSensitive: false,
);
final unbalanced = RegExp(r'^[^(]*\)|\([^)]*$|^[\s\-–:.]|[\s\-–:.]$');

void main(List<String> args) {
  final dir = args.isEmpty ? '.' : args[0];
  final verbose = args.contains('-v');
  final tv = jsonDecode(File('$dir/tv.json').readAsStringSync()) as List;
  var n = 0, leaked = 0, fallback = 0;
  final samples = <String>[];
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
        if (RegExp(r'^(Episode|Special)( \d+)?$').hasMatch(out)) fallback++;
        if (leak.hasMatch(out) || unbalanced.hasMatch(out)) {
          leaked++;
          if (samples.length < (verbose ? 400 : 25)) {
            samples.add('$name  =>  $out   [show: $show]');
          }
        }
      }
    }
  }

  for (final top in tv.cast<Map>()) {
    walk(top, parseTitleFolder(top['name'] as String).name);
  }
  final allFile = File('$dir/all.json');
  if (allFile.existsSync()) {
    final all = jsonDecode(allFile.readAsStringSync()) as Map;
    for (final cat in const ['Korean Series', 'Anime & Cartoon']) {
      for (final top in ((all[cat] as List?) ?? const []).cast<Map>()) {
        walk(top, parseTitleFolder(top['name'] as String).name);
      }
    }
  }
  print('files: $n, fallback titles: $fallback, still leaking tokens: $leaked');
  samples.forEach(print);
}
