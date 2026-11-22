@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';

/// ~35k titles / ~170k files on a real on-disk database (background isolate).
void main() {
  test('35k titles / 170k files: browse < 50 ms, FTS < 100 ms', () async {
    final dir = Directory.systemTemp.createTempSync('wd_perf');
    final repo = DriftRepository(openDatabaseAt(File('${dir.path}/p.db')));
    addTearDown(() async {
      await repo.close();
      dir.deleteSync(recursive: true);
    });
    final cats = await repo.upsertCategories([
      for (var i = 0; i < 20; i++)
        CategoryDraft(
          sourceHost: 'h${i % 4}',
          name: 'Category $i',
          url: 'http://h/c$i/',
          language: i % 2 == 0 ? 'English' : 'Hindi',
        ),
    ]);
    final catIds = cats.values.toList();
    const words = [
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
    ];
    final rnd = Random(1);
    final sw = Stopwatch()..start();
    const n = 35000;
    for (var b = 0; b < n; b += 500) {
      final batch = <TitleDraft>[];
      for (var i = b; i < b + 500 && i < n; i++) {
        final name =
            '${words[rnd.nextInt(16)]} ${words[rnd.nextInt(16)]} '
            '${words[rnd.nextInt(16)]} $i';
        final series = i % 4 == 0;
        final url = 'http://h/c/${catIds[i % 20]}/$i/';
        FileDraft fd(String s) => FileDraft(
          name: s,
          url: '$url$s',
          ext: 'mkv',
          playable: true,
          sizeKb: 1,
        );
        batch.add(
          TitleDraft(
            categoryId: catIds[i % 20],
            name: name,
            kind: series ? TitleKind.series : TitleKind.movie,
            folderUrl: url,
            year: 1950 + rnd.nextInt(75),
            quality: [480, 720, 1080][rnd.nextInt(3)],
            seasons: series
                ? [
                    for (var s = 1; s <= 2; s++)
                      SeasonDraft(
                        number: s,
                        label: 'S$s',
                        files: [
                          for (var e = 1; e <= 6; e++) fd('s${s}e$e.mkv'),
                        ],
                      ),
                  ]
                : const [],
            files: series ? const [] : [fd('a.mkv'), fd('b.mkv')],
          ),
        );
      }
      await repo.upsertTitles(batch);
    }
    final c = await repo.counts();
    // ignore: avoid_print
    print(
      'insert ${sw.elapsedMilliseconds} ms: ${c.titles} titles, ${c.files} files',
    );
    expect(c.titles, n);

    Future<int> time(Future<void> Function() f) async {
      await f(); // warm
      final t = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        await f();
      }
      return t.elapsedMilliseconds ~/ 5;
    }

    final browse = await time(() => repo.browse(const BrowseFilter()));
    final deep = await time(
      () => repo.browse(const BrowseFilter(), offset: 30000),
    );
    final filt = await time(
      () => repo.browse(
        BrowseFilter(
          categoryId: catIds[3],
          year: 1990,
          quality: 1080,
          language: 'Hindi',
        ),
      ),
    );
    final byYear = await time(
      () => repo.browse(
        const BrowseFilter(sort: BrowseSort.yearDesc),
        offset: 100,
      ),
    );
    final multi = await time(
      () => repo.browse(
        BrowseFilter(
          years: {1990, 2001, 2010},
          yearRanges: const [YearRange(to: 1960)],
          languages: {'Hindi', 'English'},
          qualities: {720, 1080},
        ),
      ),
    );
    final langOnly = await time(
      () => repo.browse(BrowseFilter(languages: {'Hindi'})),
    );
    final yearsFacet = await time(
      () => repo.years(BrowseFilter(languages: {'Hindi'})),
    );
    final cnt = await time(
      () => repo.countTitles(const BrowseFilter(year: 1990)),
    );
    final fts = await time(() => repo.search('dark rivr'));
    final fts2 = await time(
      () => repo.search(
        'night storm',
        filter: const BrowseFilter(language: 'English'),
      ),
    );
    final ftsRare = await time(() => repo.search('moon fire 31337'));
    // ignore: avoid_print
    print(
      'browse $browse ms, deep $deep ms, filtered $filt ms, yearDesc $byYear ms, '
      'count $cnt ms, fts $fts ms, fts+filter $fts2 ms, fts rare $ftsRare ms',
    );
    // ignore: avoid_print
    print(
      'multi-facet $multi ms, langOnly $langOnly ms, yearsFacet $yearsFacet ms',
    );
    expect(multi, lessThan(50));
    expect(langOnly, lessThan(50));
    expect(yearsFacet, lessThan(100));
    expect(browse, lessThan(50));
    expect(deep, lessThan(50));
    expect(filt, lessThan(50));
    expect(fts, lessThan(100));
    expect(fts2, lessThan(100));
    expect(ftsRare, lessThan(100));
    final len = File('${dir.path}/p.db').lengthSync();
    // ignore: avoid_print
    print('db size ${(len / 1048576).toStringAsFixed(1)} MB');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
