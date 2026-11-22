import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';

import 'support.dart';

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
    final all = [...fixtures, ...noise(400)];
    await repo.upsertTitles([
      for (var i = 0; i < all.length; i++)
        draft(i >= 38 && i < 40 ? hi : (i % 2 == 0 ? en : hi), all[i], i),
    ]);
  });
  tearDown(() => repo.close());

  Future<MediaTitle> top(
    String q, {
    BrowseFilter f = const BrowseFilter(),
  }) async {
    final r = await repo.search(q, filter: f, limit: 5);
    expect(r, isNotEmpty, reason: 'no results for "$q"');
    return r.first;
  }

  // query -> expected top name (and optional year)
  final table = <(String, String, int?)>[
    // punctuation / separators
    ('spider-man homecoming', 'Spider-Man: Homecoming', null),
    ('spider man homecoming', 'Spider-Man: Homecoming', null),
    ('spiderman homecoming', 'Spider-Man: Homecoming', null),
    ('Spider-Man', 'Spider-Man', 2002),
    ('spiderman', 'Spider-Man', 2002),
    ('spider man', 'Spider-Man', 2002),
    ('schindlers list', "Schindler's List", null),
    ('schindler list', "Schindler's List", null),
    ('amelie', 'Amélie', null),
    ('mission impossible fallout', 'Mission: Impossible - Fallout', null),
    // typos: transposition, missing/extra/wrong letter
    ('inceptoin', 'Inception', null),
    ('incepton', 'Inception', null),
    ('intersellar', 'Interstellar', null),
    ('interstelar', 'Interstellar', null),
    ('the dakr knight', 'The Dark Knight', 2008),
    ('godfater', 'The Godfather', 1972),
    ('fihgt club', 'Fight Club', null),
    ('stranger thigns', 'Stranger Things', null),
    ('braking bad', 'Breaking Bad', null),
    ('gmae of thrones', 'Game of Thrones', null),
    ('avengrs endgame', 'Avengers: Endgame', null),
    // word order is not enforced
    ('knight dark', 'The Dark Knight', null),
    ('endgame avengers', 'Avengers: Endgame', null),
    ('heist money', 'Money Heist', null),
    // numerals as titles
    ('1917', '1917', null),
    ('300', '300', 2006),
    ('13 hours', '13 Hours: The Secret Soldiers of Benghazi', null),
    ('12 angry men', '12 Angry Men', null),
    ('se7en', 'Se7en', null),
    // year hint
    ('dune 2021', 'Dune', 2021),
    ('dune 1984', 'Dune', 1984),
    ('lion king 1994', 'The Lion King', 1994),
    ('lion king 2019', 'The Lion King', 2019),
    ('blade runner 2049', 'Blade Runner 2049', 2017),
    ('blade runner', 'Blade Runner', 1982),
    // season / quality tokens ignored
    ('breaking bad s02', 'Breaking Bad', null),
    ('breaking bad season 2', 'Breaking Bad', null),
    ('stranger things s03e04', 'Stranger Things', null),
    ('dune 1080p', 'Dune', 2021),
    // short / prefix
    ('se', 'Se7en', null),
    ('inter', 'Interstellar', null),
    ('matrix', 'The Matrix', 1999),
    ('the matrix', 'The Matrix', 1999),
    ('matrix rel', 'The Matrix Reloaded', null),
    ('dilwale', 'Dilwale Dulhania Le Jayenge', null),
    ('kabhi khushi', 'Kabhi Khushi Kabhie Gham', null),
    (
      'lord rings fellowship',
      'The Lord of the Rings: The Fellowship of the Ring',
      null,
    ),
  ];

  test('query -> top result table', () async {
    final fails = <String>[];
    for (final (q, name, year) in table) {
      final r = await top(q);
      if (r.name != name || (year != null && r.year != year)) {
        fails.add('"$q" -> ${r.name} (${r.year}), want $name ($year)');
      }
    }
    expect(fails, isEmpty, reason: fails.join('\n'));
  });

  test(
    '"the" does not flood: prefix + short titles first, no unrelated',
    () async {
      final r = await repo.search('the', limit: 50);
      expect(r, isNotEmpty);
      expect(r.every((t) => t.name.toLowerCase().contains('the')), isTrue);
      expect(r.first.name.toLowerCase().startsWith('the'), isTrue);
      // shortest "The ..." first
      expect(r.first.name.length <= r[10].name.length, isTrue);
    },
  );

  test('series hint boosts series', () async {
    final r = await repo.search('dune s01', limit: 3);
    expect(r.first.kind, TitleKind.series);
  });

  test('filters combine', () async {
    final r = await repo.search(
      'dune',
      filter: const BrowseFilter(quality: 1080, kind: TitleKind.movie),
    );
    expect(
      r.every((t) => t.kind == TitleKind.movie && t.quality == 1080),
      isTrue,
    );
    expect(r.map((t) => t.year), containsAll([2021, 2024]));
    expect(r.map((t) => t.year), isNot(contains(1984)));
    final y = await repo.search('dune', filter: const BrowseFilter(year: 1984));
    expect(y.map((t) => t.year), [1984]);
    final lang = await repo.search(
      'godfather',
      filter: const BrowseFilter(language: 'Hindi'),
    );
    expect(lang.every((t) => t.language == 'Hindi'), isTrue);
    final cat = await repo.search('dune', filter: BrowseFilter(categoryId: hi));
    expect(cat.every((t) => t.categoryId == hi), isTrue);
  });

  test('year range syntax filters', () async {
    final r = await repo.search('dune 1980-1990');
    expect(r.map((t) => t.year), [1984]);
  });

  test('paging is consistent on the re-ranked list', () async {
    final full = await repo.search('the', limit: 100);
    final pages = <int>[];
    for (var o = 0; o < 100; o += 25) {
      final p = await repo.search('the', offset: o, limit: 25);
      pages.addAll(p.map((t) => t.id));
    }
    expect(pages, full.map((t) => t.id).toList());
    expect(pages.toSet().length, pages.length);
    expect(await repo.search('the', offset: 100000), isEmpty);
  });

  test('gibberish and empty', () async {
    expect(await repo.search('zzqxjv'), isEmpty);
    expect(await repo.search('   ', limit: 5), hasLength(5)); // browse
    expect(await repo.search('%_"\'()*'), isA<List<MediaTitle>>());
    expect(await repo.search('a'), isA<List<MediaTitle>>());
  });

  test('deterministic ordering', () async {
    final a = await repo.search('dark');
    final b = await repo.search('dark');
    expect(a.map((t) => t.id), b.map((t) => t.id));
  });
}
