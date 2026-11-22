import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/models.dart';

void main() {
  filterTests();
  test('WatchState.fraction', () {
    expect(const WatchState(fileId: 1).fraction, 0);
    expect(
      const WatchState(fileId: 1, positionMs: 50, durationMs: 100).fraction,
      0.5,
    );
    expect(
      const WatchState(fileId: 1, positionMs: 500, durationMs: 100).fraction,
      1,
    );
  });

  test('TitleDraft.validate', () {
    const f = FileDraft(name: 'a.mkv', url: 'u', ext: 'mkv', playable: true);
    const s = SeasonDraft(number: 1, label: 'S1');
    TitleDraft d(
      TitleKind k, {
      List<SeasonDraft> se = const [],
      List<FileDraft> fi = const [],
    }) => TitleDraft(
      categoryId: 1,
      name: 'x',
      kind: k,
      folderUrl: 'u',
      seasons: se,
      files: fi,
    );
    expect(d(TitleKind.series, se: [s]).validate, returnsNormally);
    expect(d(TitleKind.movie, fi: [f]).validate, returnsNormally);
    expect(d(TitleKind.series, fi: [f]).validate, throwsArgumentError);
    expect(d(TitleKind.movie, se: [s]).validate, throwsArgumentError);
    expect(d(TitleKind.event, se: [s]).validate, throwsArgumentError);
  });
}

void filterTests() {
  group('BrowseFilter', () {
    test('equality and hashCode cover all fields', () {
      BrowseFilter mk() => BrowseFilter(
        categoryId: 1,
        years: {2020, 2021},
        yearRanges: const [
          YearRange(from: 2010, to: 2019),
          YearRange(to: 1989),
        ],
        languages: {'Hindi', 'English'},
        qualities: {1080},
        kind: TitleKind.movie,
      );
      expect(mk(), mk());
      expect(mk().hashCode, mk().hashCode);
      expect(
        BrowseFilter(years: {1, 2}),
        BrowseFilter(years: {2, 1}),
      ); // order-free
      expect(mk(), isNot(mk().copyWith(years: {2020})));
      expect(mk(), isNot(mk().copyWith(yearRanges: const [])));
      expect(mk(), isNot(mk().copyWith(languages: {'Hindi'})));
      expect(mk(), isNot(mk().copyWith(qualities: {720})));
      expect(mk(), isNot(mk().copyWith(kind: null)));
      expect(mk(), isNot(mk().copyWith(categoryId: 2)));
      expect(mk(), isNot(mk().copyWith(sort: BrowseSort.yearDesc)));
    });

    test('copyWith can clear categoryId and kind', () {
      final f = const BrowseFilter(categoryId: 3, kind: TitleKind.series);
      expect(f.copyWith(categoryId: null).categoryId, isNull);
      expect(f.copyWith(kind: null).kind, isNull);
      expect(f.copyWith().categoryId, 3);
    });

    test('deprecated shims map onto the new sets', () {
      // ignore: deprecated_member_use_from_same_package
      const f = BrowseFilter(year: 1999, language: 'Hindi', quality: 720);
      expect(f.years, {1999});
      expect(f.languages, {'Hindi'});
      expect(f.qualities, {720});
      // ignore: deprecated_member_use_from_same_package
      expect((f.year, f.language, f.quality), (1999, 'Hindi', 720));
      expect(
        f,
        BrowseFilter(years: {1999}, languages: {'Hindi'}, qualities: {720}),
      );
      // ignore: deprecated_member_use_from_same_package
      expect(BrowseFilter(years: {1, 2}).year, isNull);
    });
  });

  group('YearBucket', () {
    test('presets for 2026', () {
      final p = YearBucket.presets(2026);
      expect(p.map((b) => b.label), [
        '2026',
        '2025',
        '2024',
        '2023',
        '2022',
        '2021',
        '2020s',
        '2010s',
        '2000s',
        '1990s',
        'Older',
      ]);
      expect(p[0].years, {2026});
      expect(p[6].ranges.single, const YearRange(from: 2020, to: 2020));
      expect(p[7].ranges.single, const YearRange(from: 2010, to: 2019));
      expect(p.last.ranges.single, const YearRange(to: 1989));
    });
    test('presets for 2025 have no 2020s bucket', () {
      final p = YearBucket.presets(2025);
      expect(p.map((b) => b.label).skip(6), [
        '2010s',
        '2000s',
        '1990s',
        'Older',
      ]);
    });
    test('every year 1900..now falls in exactly one bucket', () {
      for (final now in [2024, 2025, 2026, 2027, 2030]) {
        final p = YearBucket.presets(now);
        for (var y = 1900; y <= now; y++) {
          final hits = p.where(
            (b) => b.years.contains(y) || b.ranges.any((r) => r.contains(y)),
          );
          expect(hits.length, 1, reason: '$y for now=$now');
        }
      }
    });
    test('merge unions selection', () {
      final p = YearBucket.presets(2025);
      final m = YearBucket.merge([p[0], p[1], p.last]);
      expect(m.years, {2025, 2024});
      expect(m.ranges, [const YearRange(to: 1989)]);
    });
  });
}
