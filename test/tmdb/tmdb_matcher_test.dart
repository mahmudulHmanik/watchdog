import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/tmdb/tmdb_matcher.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';

import 'fakes.dart';

const _tv = TmdbMediaType.tv;
const _movie = TmdbMediaType.movie;

void main() {
  late FakeApi api;
  late TmdbMatcher m;
  setUp(() {
    api = FakeApi(DateTime.now);
    m = TmdbMatcher(api);
  });

  /// Both searches return [hits] regardless of year (TMDB's own year filter
  /// is not under test here, the scoring is).
  void serve(List<TmdbHit> hits) => api.results = (_, _, _) => hits;

  Future<int?> idFor(
    String name, {
    int? year,
    TitleKind kind = TitleKind.movie,
    int? yearEnd,
  }) async =>
      (await m.match(title(1, name, kind: kind, year: year, yearEnd: yearEnd)))
          ?.id;

  group('normalizeTitle', () {
    test('folds case, accents, punctuation, articles, and/&', () {
      expect(TmdbMatcher.normalizeTitle('The Amélie!'), 'amelie');
      expect(TmdbMatcher.normalizeTitle('Tom & Jerry'), 'tom jerry');
      expect(TmdbMatcher.normalizeTitle('Tom and Jerry'), 'tom jerry');
      expect(TmdbMatcher.normalizeTitle("Ocean's Eleven"), 'oceans eleven');
      expect(TmdbMatcher.normalizeTitle('Rocky II'), 'rocky 2');
      expect(TmdbMatcher.normalizeTitle('The'), 'the');
    });
  });

  group('sequels and remakes', () {
    test('Toy Story 3 picks the third film, not the first', () async {
      serve([
        hit(862, 'Toy Story', 1995, pop: 90),
        hit(863, 'Toy Story 2', 1999, pop: 60),
        hit(10193, 'Toy Story 3', 2010, pop: 70),
      ]);
      expect(await idFor('Toy Story 3', year: 2010), 10193);
      expect(await idFor('Toy Story 3'), 10193);
    });

    test('Toy Story (no sequel number) never lands on Toy Story 3', () async {
      serve([hit(10193, 'Toy Story 3', 2010)]);
      expect(await idFor('Toy Story', year: 1995), isNull);
      expect(await idFor('Toy Story'), isNull);
    });

    test('roman numerals equal digits', () async {
      serve([hit(1, 'Rocky 2', 1979)]);
      expect(await idFor('Rocky II', year: 1979), 1);
    });

    test('remake: the year decides', () async {
      serve([hit(2, 'Dune', 2021, pop: 200), hit(1, 'Dune', 1984, pop: 40)]);
      expect(await idFor('Dune', year: 1984), 1);
      expect(await idFor('Dune', year: 2021), 2);
    });

    test('no year: equal names fall to popularity', () async {
      serve([hit(1, 'Dune', 1984, pop: 10), hit(2, 'Dune', 2021, pop: 300)]);
      expect(await idFor('Dune'), 2);
    });

    test('Alien is not Aliens even with the right year', () async {
      serve([hit(679, 'Aliens', 1986)]);
      expect(await idFor('Alien', year: 1986), isNull);
    });
  });

  group('titles', () {
    test('subtitle after a colon or dash', () async {
      serve([hit(353081, 'Mission: Impossible - Fallout', 2018)]);
      expect(await idFor('Mission Impossible Fallout', year: 2018), 353081);
      expect(await idFor('Mission Impossible Fallout'), 353081);
    });

    test('folder lacks the subtitle: needs the exact year', () async {
      serve([hit(1, 'Kingsman: The Secret Service', 2014)]);
      expect(await idFor('Kingsman', year: 2014), 1);
      expect(await idFor('Kingsman', year: 2015), isNull); // not exact
      expect(await idFor('Kingsman'), isNull); // no year: never guess
    });

    test('a different film sharing the franchise name is rejected', () async {
      serve([hit(284053, 'Thor: Ragnarok', 2017)]);
      expect(await idFor('Thor', year: 2011), isNull);
    });

    test('& vs and, both directions', () async {
      serve([hit(1, 'Fast & Furious', 2009)]);
      expect(await idFor('Fast and Furious', year: 2009), 1);
      serve([hit(2, 'Tom and Jerry', 2021)]);
      expect(await idFor('Tom & Jerry', year: 2021), 2);
    });

    test('leading article and punctuation are ignored', () async {
      serve([hit(603, 'The Matrix', 1999)]);
      expect(await idFor('Matrix', year: 1999), 603);
      serve([hit(9, 'Spider-Man', 2002)]);
      expect(await idFor('Spiderman', year: 2002), 9);
    });

    test('non-English original title matches too', () async {
      serve([
        hit(
          194,
          'Amélie',
          2001,
          original: "Le Fabuleux Destin d'Amélie Poulain",
        ),
      ]);
      expect(await idFor('Amelie', year: 2001), 194);
      expect(
        await idFor('Le Fabuleux Destin d Amelie Poulain', year: 2001),
        194,
      );
    });

    test(
      'original title in another script, folder uses the English one',
      () async {
        serve([hit(496243, 'Parasite', 2019, original: '기생충')]);
        expect(await idFor('Parasite', year: 2019), 496243);
      },
    );

    test('tv original name', () async {
      serve([
        hit(
          71446,
          'Money Heist',
          2017,
          original: 'La casa de papel',
          type: _tv,
        ),
      ]);
      expect(
        await idFor('La Casa de Papel', year: 2017, kind: TitleKind.series),
        71446,
      );
    });

    test('a typo needs a long title and the exact year', () async {
      serve([hit(98, 'Gladiator', 2000)]);
      expect(await idFor('Gladiater', year: 2000), 98);
      expect(await idFor('Gladiater'), isNull);
      serve([hit(5, 'Heat', 1995)]);
      expect(await idFor('Heet', year: 1995), isNull);
    });

    test('unrelated results give null', () async {
      serve([hit(1, 'Something Else Entirely', 2000)]);
      expect(await idFor('Inception', year: 2010), isNull);
    });

    test('very short name without a year is not guessed', () async {
      serve([hit(1, 'It', 2017)]);
      expect(await idFor('It'), isNull);
      expect(await idFor('It', year: 2017), 1);
    });

    test('empty or punctuation-only name', () async {
      serve([hit(1, 'Anything', 2000)]);
      expect(await idFor('...'), isNull);
      expect(api.calls, isEmpty);
    });
  });

  group('year', () {
    test('off by one is accepted, two is not', () async {
      serve([hit(1, 'Heat Wave', 2010)]);
      expect(await idFor('Heat Wave', year: 2011), 1);
      expect(await idFor('Heat Wave', year: 2009), 1);
      expect(await idFor('Heat Wave', year: 2012), isNull);
    });

    test('exact year beats off-by-one for the same title', () async {
      serve([hit(1, 'Crash', 2005, pop: 5), hit(2, 'Crash', 2004, pop: 5)]);
      expect(await idFor('Crash', year: 2005), 1);
      expect(await idFor('Crash', year: 2004), 2);
    });

    test('TMDB without a date still matches an exact title', () async {
      serve([hit(1, 'Unreleased Thing', null)]);
      expect(await idFor('Unreleased Thing', year: 2024), isNull); // 0.3 year
      expect(await idFor('Unreleased Thing'), 1);
    });

    test('series: year is the start year, yearEnd is a fallback', () async {
      serve([hit(1399, 'Game of Thrones', 2011, type: _tv)]);
      final t = title(
        1,
        'Game of Thrones',
        kind: TitleKind.series,
        year: 2011,
        yearEnd: 2019,
      );
      expect((await m.match(t))?.id, 1399);
      expect(api.calls.first.year, 2011);
      api.calls.clear();
      expect(
        (await m.match(
          title(1, 'Game of Thrones', kind: TitleKind.series, yearEnd: 2011),
        ))?.id,
        1399,
      );
      expect(api.calls.first.year, 2011);
    });

    test(
      'series first aired earlier than the folder year is rejected',
      () async {
        serve([hit(1, 'Doctor Who', 1963, type: _tv)]);
        expect(
          await idFor('Doctor Who', year: 2005, kind: TitleKind.series),
          isNull,
        );
      },
    );
  });

  group('search strategy', () {
    test('year search first, then without year', () async {
      api.results = (kind, q, year) =>
          year == null ? [hit(7, 'Late Bloomer', 2012)] : const [];
      expect(await idFor('Late Bloomer', year: 2012), 7);
      expect([for (final c in api.calls) c.year], [2012, null]);
    });

    test('stops after the year search when it is good enough', () async {
      serve([hit(7, 'Late Bloomer', 2012)]);
      await idFor('Late Bloomer', year: 2012);
      expect(api.calls, hasLength(1));
    });

    test('no year: a single search', () async {
      serve(const []);
      await idFor('Whatever Name');
      expect(api.calls, hasLength(1));
      expect(api.calls.single.year, isNull);
    });

    test('movie uses /search/movie, series uses /search/tv', () async {
      api.results = (kind, q, year) => kind == 'movie'
          ? [hit(1, 'Fargo', 1996)]
          : [hit(2, 'Fargo', 2014, type: _tv)];
      expect(await idFor('Fargo', year: 1996), 1);
      expect(await idFor('Fargo', year: 2014, kind: TitleKind.series), 2);
      // Same name, wrong year for the kind: not cross-matched.
      expect(await idFor('Fargo', year: 2014, kind: TitleKind.movie), isNull);
      expect({for (final c in api.calls) c.kind}, {'movie', 'tv'});
    });

    test('events are never searched', () async {
      serve([hit(1, 'WWE Raw', 2020)]);
      expect(await idFor('WWE Raw', kind: TitleKind.event), isNull);
      expect(api.calls, isEmpty);
    });

    test('matchQuery reports the score; threshold is documented', () async {
      serve([hit(1, 'Heat Wave', 2010)]);
      final r = await m.matchQuery('Heat Wave', _movie, year: 2010);
      expect(r!.score, greaterThanOrEqualTo(0.95));
      expect(TmdbMatcher.defaultThreshold, 0.80);
    });

    test('a stricter threshold rejects borderline matches', () async {
      serve([hit(1, 'Heat Wave', 2010)]);
      final strict = TmdbMatcher(api, threshold: 0.99);
      expect(await strict.matchQuery('Heat Wave', _movie, year: 2011), isNull);
    });
  });
}
