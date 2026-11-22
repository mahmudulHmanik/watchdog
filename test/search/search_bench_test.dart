@Tags(['perf'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/parsing.dart';
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';

import 'support.dart';

/// Saved crawl (all.json). Set WATCHDOG_CORPUS to the directory that holds it;
/// the real-names benchmark is skipped when it is absent.
final _crawl = '${Platform.environment['WATCHDOG_CORPUS'] ?? ''}/all.json';

const _a = [
  'night',
  'river',
  'storm',
  'king',
  'dark',
  'city',
  'love',
  'blood',
  'gold',
  'wild',
  'last',
  'home',
  'fire',
  'lost',
  'iron',
  'moon',
  'ghost',
  'shadow',
  'silent',
  'broken',
  'garden',
  'winter',
  'summer',
  'empire',
  'dragon',
  'secret',
  'bridge',
  'island',
  'hunter',
  'angel',
  'rose',
  'tower',
  'man',
  'war',
  'world',
  'time',
  'life',
  'death',
  'day',
  'girl',
  'boy',
  'house',
];

/// ~35k realistic names: 'The X of Y', 'X Y', 'X and Y 2', sequels, etc.
List<String> synthNames(int n) {
  final r = Random(7);
  String w() {
    final s = _a[r.nextInt(_a.length)];
    return s[0].toUpperCase() + s.substring(1);
  }

  return [
    for (var i = 0; i < n; i++)
      switch (r.nextInt(5)) {
        0 => 'The ${w()} of ${w()}',
        1 => '${w()} ${w()}',
        2 => '${w()} and the ${w()} $i',
        3 => 'The ${w()} ${w()}: Part ${1 + r.nextInt(4)} $i',
        _ => '${w()}-${w()} ${w()} $i',
      },
  ];
}

List<(String, int?, TitleKind, int?)> realTitles() {
  final f = File(_crawl);
  if (!f.existsSync()) return const [];
  final all = jsonDecode(f.readAsStringSync()) as Map;
  final out = <(String, int?, TitleKind, int?)>[];
  void walk(Map n, String cat) {
    final kids = (n['kids'] as List? ?? []).cast<Map>();
    if (n['t'] == 'folder' &&
        kids.any((k) => k['t'] != 'folder' && isVideo(k['name']))) {
      final i = parseTitleFolder(n['name'] as String);
      out.add((i.name, i.year, TitleKind.movie, i.quality));
    }
    for (final k in kids) {
      if (k['t'] == 'folder') walk(k, cat);
    }
  }

  all.forEach((cat, items) {
    for (final i in (items as List).cast<Map>()) {
      walk(i, cat as String);
    }
  });
  return out;
}

void main() {
  const queries = [
    'dark river',
    'the',
    'the dark',
    'night',
    'st',
    'drk rivr',
    'darkriver',
    'dark-river',
    'moon fire 31337',
    'storm 1999',
    'iron man s02',
    'ghost',
    'the lst city',
    'shadow of the',
    'love',
    'winter summer',
    'dragon 1080p',
    'bridge and the island',
    'a',
    '1917',
  ];

  Future<void> bench(
    String label,
    List<(String, int?, TitleKind, int?)> data,
  ) async {
    final dir = Directory.systemTemp.createTempSync('wd_sbench');
    final repo = DriftRepository(openDatabaseAt(File('${dir.path}/s.db')));
    addTearDown(() async {
      await repo.close();
      dir.deleteSync(recursive: true);
    });
    final cats = await repo.upsertCategories([
      for (var i = 0; i < 10; i++)
        CategoryDraft(
          sourceHost: 'h',
          name: 'C$i',
          url: 'http://h/c$i/',
          language: i.isEven ? 'English' : 'Hindi',
        ),
    ]);
    final ids = cats.values.toList();
    for (var b = 0; b < data.length; b += 500) {
      await repo.upsertTitles([
        for (var i = b; i < b + 500 && i < data.length; i++)
          draft(ids[i % 10], data[i], i),
      ]);
    }
    final times = <int>[];
    final report = StringBuffer('$label (${data.length} titles)\n');
    for (final q in queries) {
      await repo.search(q); // warm
      final sw = Stopwatch();
      final runs = <int>[];
      for (var i = 0; i < 5; i++) {
        sw
          ..reset()
          ..start();
        await repo.search(q, limit: 50);
        runs.add(sw.elapsedMicroseconds);
      }
      runs.sort();
      final med = runs[2];
      times.add(med);
      report.writeln(
        '  ${q.padRight(24)} ${(med / 1000).toStringAsFixed(1)} ms',
      );
    }
    // filtered + deep page
    for (final f in [
      (const BrowseFilter(language: 'English', year: 1999), 'dark'),
      (const BrowseFilter(kind: TitleKind.series, quality: 1080), 'the'),
    ]) {
      final sw = Stopwatch()..start();
      await repo.search(f.$2, filter: f.$1);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
      report.writeln(
        '  filtered "${f.$2}" ${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms',
      );
    }
    times.sort();
    final p95 = times[(times.length * 0.95).ceil() - 1] / 1000;
    report.writeln(
      '  p95 ${p95.toStringAsFixed(1)} ms, max ${(times.last / 1000).toStringAsFixed(1)} ms',
    );
    // ignore: avoid_print
    print(report);
    expect(p95, lessThan(100));
  }

  test('35k synthetic titles: p95 < 100 ms', () async {
    final names = synthNames(35000);
    final r = Random(3);
    await bench('synthetic', [
      for (final n in names)
        (
          n,
          1950 + r.nextInt(75),
          r.nextInt(5) == 0 ? TitleKind.series : TitleKind.movie,
          const [480, 720, 1080][r.nextInt(3)],
        ),
    ]);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'real crawl folder names (skipped when absent)',
    () async {
      final real = realTitles();
      await bench('real', real);
    },
    skip: File(_crawl).existsSync() ? false : 'crawl fixture absent',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
