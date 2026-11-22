// ignore_for_file: avoid_print
// Dev tool: run parsers over a saved crawl (tv.json / all.json) and report misses.
// Usage: dart run tool/corpus_check.dart <dir containing tv.json and all.json>
import 'dart:convert';
import 'dart:io';

import 'package:watchdog/crawler/parsing.dart';

void main(List<String> args) {
  final dir = args.isEmpty ? '.' : args[0];
  final tv = jsonDecode(File('$dir/tv.json').readAsStringSync()) as List;
  final all = jsonDecode(File('$dir/all.json').readAsStringSync()) as Map;
  all['TV-WEB-Series'] = tv;

  var epFiles = 0, epMissing = 0, seasonDirs = 0, seasonMissing = 0;
  final missEp = <String>[], missSeason = <String>[], missYear = <String>[];
  var titles = 0, titleNoYear = 0;

  void walk(Map n, bool seriesCtx) {
    final kids = (n['kids'] as List? ?? []).cast<Map>();
    final hasVideo = kids.any((k) => k['t'] != 'folder' && isVideo(k['name']));
    if (n['t'] == 'folder' && hasVideo) {
      final name = n['name'] as String;
      final isSeason = parseSeasonFolder(name) != null;
      if (seriesCtx) {
        seasonDirs++;
        if (!isSeason && !isExtrasFolder(name)) {
          seasonMissing++;
          if (missSeason.length < 12) missSeason.add(name);
        }
      } else if (!isExtrasFolder(name)) {
        titles++;
        if (parseTitleFolder(name).year == null) {
          titleNoYear++;
          if (missYear.length < 12) missYear.add(name);
        }
      }
    }
    for (final k in kids) {
      if (k['t'] == 'folder') {
        walk(k, seriesCtx);
      } else if (seriesCtx && isVideo(k['name'])) {
        epFiles++;
        if (parseEpisode(k['name']).episode == null) {
          epMissing++;
          if (missEp.length < 15) missEp.add(k['name']);
        }
      }
    }
  }

  const seriesCats = {'TV-WEB-Series', 'Korean Series', 'Anime & Cartoon'};
  all.forEach((cat, items) {
    for (final i in (items as List).cast<Map>()) {
      walk(i, seriesCats.contains(cat));
    }
  });
  print('movie-ish title folders: $titles, no year: $titleNoYear');
  print('series season dirs: $seasonDirs, unparsed: $seasonMissing');
  print('episode files: $epFiles, no episode#: $epMissing');
  print('\nno-year titles:');
  for (final s in missYear) {
    print('  $s');
  }
  print('\nunparsed season dirs:');
  for (final s in missSeason) {
    print('  $s');
  }
  print('\nno-episode files:');
  for (final s in missEp) {
    print('  $s');
  }
}
