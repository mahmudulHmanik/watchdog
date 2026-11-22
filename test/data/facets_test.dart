import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';

void main() {
  late DriftRepository repo;
  late int en, hi;
  setUp(() async {
    repo = DriftRepository.memory();
    final m = await repo.upsertCategories(const [
      CategoryDraft(
        sourceHost: 'h',
        name: 'English Movies',
        url: 'http://h/en/',
        language: 'English',
      ),
      CategoryDraft(
        sourceHost: 'h',
        name: 'Hindi Movies',
        url: 'http://h/hi/',
        language: 'Hindi',
      ),
    ]);
    en = m['http://h/en/']!;
    hi = m['http://h/hi/']!;
    var n = 0;
    TitleDraft t(String name, int c, int? year, int? q) {
      n++;
      return TitleDraft(
        categoryId: c,
        name: name,
        kind: TitleKind.movie,
        folderUrl: 'http://h/$n/',
        year: year,
        quality: q,
        files: [
          FileDraft(
            name: 'a.mkv',
            url: 'http://h/$n/a.mkv',
            ext: 'mkv',
            playable: true,
          ),
        ],
      );
    }

    await repo.upsertTitles([
      t('Dune Old', en, 1984, 720),
      t('Dune A', en, 2012, 1080),
      t('Dune B', hi, 2015, 1080),
      t('Dune C', hi, 2019, 720),
      t('Dune D', en, 2024, 1080),
      t('Dune E', hi, 2025, 480),
      t('Dune NoYear', en, null, null),
    ]);
  });
  tearDown(() => repo.close());

  Future<List<String>> names(BrowseFilter f) async =>
      (await repo.browse(f)).map((e) => e.name).toList()..sort();

  test('several years OR, ranges, open-ended', () async {
    expect(await names(BrowseFilter(years: {2024, 2025})), [
      'Dune D',
      'Dune E',
    ]);
    expect(
      await names(
        const BrowseFilter(yearRanges: [YearRange(from: 2010, to: 2019)]),
      ),
      ['Dune A', 'Dune B', 'Dune C'],
    );
    expect(await names(const BrowseFilter(yearRanges: [YearRange(to: 2009)])), [
      'Dune Old',
    ]);
    expect(
      await names(const BrowseFilter(yearRanges: [YearRange(from: 2020)])),
      ['Dune D', 'Dune E'],
    );
    expect(
      await names(
        BrowseFilter(years: {2025}, yearRanges: const [YearRange(to: 2009)]),
      ),
      ['Dune E', 'Dune Old'],
    );
    expect(
      await repo.countTitles(
        BrowseFilter(years: {2025}, yearRanges: const [YearRange(to: 2009)]),
      ),
      2,
    );
  });

  test('languages OR, qualities OR, combined AND', () async {
    expect(
      (await names(BrowseFilter(languages: {'English', 'Hindi'}))).length,
      7,
    );
    expect(await names(BrowseFilter(qualities: {480, 720})), [
      'Dune C',
      'Dune E',
      'Dune Old',
    ]);
    final f = BrowseFilter(
      languages: {'Hindi'},
      qualities: {1080, 720},
      yearRanges: const [YearRange(from: 2010, to: 2019)],
    );
    expect(await names(f), ['Dune B', 'Dune C']);
    expect(await repo.countTitles(f), 2);
    expect(await names(f.copyWith(years: {2015})), [
      'Dune B',
      'Dune C',
    ]); // years OR ranges
    expect(await names(f.copyWith(kind: TitleKind.series)), isEmpty);
    expect(await names(f.copyWith(categoryId: en)), isEmpty);
    expect(hi, isNot(en));
  });

  test('deprecated single-value members still filter', () async {
    // ignore: deprecated_member_use_from_same_package
    expect(await names(const BrowseFilter(year: 2015)), ['Dune B']);
    // ignore: deprecated_member_use_from_same_package
    expect(
      (await names(const BrowseFilter(language: 'Hindi', quality: 1080))),
      ['Dune B'],
    );
  });

  test('facet counts ignore own selection but respect the others', () async {
    final f = BrowseFilter(
      years: {2024},
      languages: {'English'},
      qualities: {1080},
    );
    // years: language English + quality 1080 -> 2012, 2024
    expect((await repo.years(f)).map((e) => (e.value, e.count)), [
      (2024, 1),
      (2012, 1),
    ]);
    // languages: years {2024} + quality 1080 -> English only
    expect((await repo.languages(f)).map((e) => (e.value, e.count)), [
      ('English', 1),
    ]);
    final g = f.copyWith(languages: {'Hindi'}, years: const {});
    // qualities: language Hindi (own facet skipped) -> 480, 720, 1080
    expect((await repo.qualities(g)).map((e) => e.value), [1080, 720, 480]);
    // languages ignores its own selection
    expect((await repo.languages(g)).map((e) => (e.value, e.count)), [
      ('English', 2),
      ('Hindi', 1),
    ]);
    // year ranges are skipped for the years facet too
    final r = const BrowseFilter(yearRanges: [YearRange(to: 2009)]);
    expect((await repo.years(r)).length, 6);
    // years count excludes NULL year
    expect((await repo.years()).fold<int>(0, (a, e) => a + e.count), 6);
  });

  test('search honours multi-select filters', () async {
    final all = await repo.search('dune');
    expect(all.length, 7);
    final r = await repo.search(
      'dune',
      filter: BrowseFilter(
        languages: {'Hindi'},
        yearRanges: const [YearRange(from: 2010, to: 2019)],
      ),
    );
    expect(r.map((e) => e.name).toSet(), {'Dune B', 'Dune C'});
    final r2 = await repo.search(
      'dune',
      filter: BrowseFilter(years: {2012, 2025}, qualities: {1080}),
    );
    expect(r2.map((e) => e.name), ['Dune A']);
    final r3 = await repo.search(
      'dune',
      filter: const BrowseFilter(yearRanges: [YearRange(to: 2009)]),
    );
    expect(r3.map((e) => e.name), ['Dune Old']);
  });

  test('plain year in query text is only a boost, never a filter', () async {
    final r = await repo.search('dune 2012');
    expect(r.length, 7);
    expect(r.first.name, 'Dune A');
  });

  test('range syntax in query still filters; combines with facets', () async {
    final r = await repo.search('dune 2010-2019');
    expect(r.map((e) => e.name).toSet(), {'Dune A', 'Dune B', 'Dune C'});
    final r2 = await repo.search(
      'dune 2010-2019',
      filter: BrowseFilter(languages: {'Hindi'}),
    );
    expect(r2.map((e) => e.name).toSet(), {'Dune B', 'Dune C'});
  });
}
