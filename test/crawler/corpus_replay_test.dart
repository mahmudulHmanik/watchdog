// Replays the saved full crawl (tv.json / all.json) through the classifier.
// Set WATCHDOG_CORPUS to the directory holding both files; skipped otherwise.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/classifier.dart';
import 'package:watchdog/data/models.dart';

import '../../tool/corpus_loader.dart';

void main() {
  final dir = Platform.environment['WATCHDOG_CORPUS'];
  final corpus = dir == null ? null : loadCorpus(dir);

  test('corpus replay reproduces plausible counts', () {
    final per = <String, List<TitleDraft>>{};
    corpus!.forEach((cat, root) {
      final (layout, kind) =
          corpusCategories[cat] ?? (LayoutKind.yearBuckets, TitleKind.movie);
      per[cat] = classifyCategory(
        root,
        layout: layout,
        kind: kind,
        categoryId: 0,
      );
    });
    final movieish = per.entries
        .where(
          (e) => !const {
            'TV-WEB-Series',
            'Korean Series',
            'Anime & Cartoon',
          }.contains(e.key),
        )
        .fold<int>(0, (a, e) => a + e.value.length);
    expect(movieish, inInclusiveRange(34600, 34800)); // ~34.7k
    expect(
      per['TV-WEB-Series']!.length,
      inInclusiveRange(2380, 2383),
    ); // 2383 shows
    expect(per['Korean Series']!.length, 767);
    expect(per['Anime & Cartoon']!.length, inInclusiveRange(1990, 1997));
    final yearless = per.values
        .expand((l) => l)
        .where((t) => t.year == null)
        .length;
    expect(yearless, lessThan(1000));
  }, skip: corpus == null ? 'corpus not found (set WATCHDOG_CORPUS)' : false);
}
