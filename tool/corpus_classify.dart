// ignore_for_file: avoid_print
// Replays the saved crawl through the classifier and prints counts.
// Usage: dart run tool/corpus_classify.dart <dir with tv.json,all.json>
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/classifier.dart';
import 'package:watchdog/data/models.dart';

import 'corpus_loader.dart';

void main(List<String> args) {
  final corpus = loadCorpus(args.isEmpty ? '.' : args[0]);
  if (corpus == null) {
    print('corpus not found');
    return;
  }
  var movies = 0, events = 0, shows = 0, seasons = 0, season0 = 0, eps = 0;
  var files = 0, unplayable = 0, noYear = 0, noPoster = 0, noEp = 0;
  final per = <String, int>{};
  final s0 = <String>[];
  corpus.forEach((cat, root) {
    final (layout, kind) =
        corpusCategories[cat] ?? (LayoutKind.yearBuckets, TitleKind.movie);
    final ts = classifyCategory(
      root,
      layout: layout,
      kind: kind,
      categoryId: 0,
    );
    per[cat] = ts.length;
    for (final t in ts) {
      switch (t.kind) {
        case TitleKind.movie:
          movies++;
        case TitleKind.event:
          events++;
        case TitleKind.series:
          shows++;
      }
      if (t.year == null) noYear++;
      if (t.posterUrl == null) noPoster++;
      for (final f in t.files) {
        files++;
        if (!f.playable) unplayable++;
      }
      for (final s in t.seasons) {
        seasons++;
        if (s.number == 0) {
          season0++;
          if (s0.length < 15) s0.add('${t.name} / ${s.label}');
        }
        for (final f in s.files) {
          eps++;
          if (!f.playable) unplayable++;
          if (f.playable && f.episode == null) noEp++;
        }
      }
    }
  });
  per.forEach((k, v) => print('  $k: $v'));
  print(
    'movie titles: $movies, events: $events (movie-ish ${movies + events})',
  );
  print('series: $shows, seasons: $seasons (season 0: $season0)');
  print(
    'movie/event files: $files, episode files: $eps, unplayable: $unplayable',
  );
  print(
    'no year: $noYear, no poster: $noPoster, episodes without number: $noEp',
  );
  print('season-0 samples:');
  for (final s in s0) {
    print('  $s');
  }
}
