import 'package:watchdog/data/models.dart';

/// (name, year, kind, quality) fixtures with realistic names.
typedef Fx = (String, int?, TitleKind, int?);

const M = TitleKind.movie;
const S = TitleKind.series;

const fixtures = <Fx>[
  ('Spider-Man: Homecoming', 2017, M, 1080),
  ('Spider-Man', 2002, M, 720),
  ('Spider-Man: No Way Home', 2021, M, 1080),
  ('The Amazing Spider-Man', 2012, M, 1080),
  ('The Dark Knight', 2008, M, 1080),
  ('The Dark Knight Rises', 2012, M, 1080),
  ('Dune', 2021, M, 1080),
  ('Dune', 1984, M, 720),
  ('Dune: Part Two', 2024, M, 1080),
  ('1917', 2019, M, 1080),
  ('300', 2006, M, 1080),
  ('300: Rise of an Empire', 2014, M, 1080),
  ('13 Hours: The Secret Soldiers of Benghazi', 2016, M, 1080),
  ('12 Angry Men', 1957, M, 720),
  ('Inception', 2010, M, 1080),
  ('Interstellar', 2014, M, 1080),
  ('The Godfather', 1972, M, 1080),
  ('The Godfather Part II', 1974, M, 1080),
  ('The Matrix', 1999, M, 1080),
  ('The Matrix Reloaded', 2003, M, 1080),
  ('Avengers: Endgame', 2019, M, 1080),
  ("Schindler's List", 1993, M, 1080),
  ('Amélie', 2001, M, 720),
  ('Se7en', 1995, M, 1080),
  ('The Lord of the Rings: The Fellowship of the Ring', 2001, M, 1080),
  ('Fight Club', 1999, M, 1080),
  ('The Lion King', 1994, M, 1080),
  ('The Lion King', 2019, M, 1080),
  ('Blade Runner 2049', 2017, M, 1080),
  ('Blade Runner', 1982, M, 1080),
  ('Breaking Bad', 2008, S, 1080),
  ('Game of Thrones', 2011, S, 1080),
  ('Stranger Things', 2016, S, 1080),
  ('The Office', 2005, S, 720),
  ('Money Heist', 2017, S, 1080),
  ('Dune: Prophecy', 2024, S, 1080),
  ('The Mandalorian', 2019, S, 1080),
  ('Mission: Impossible - Fallout', 2018, M, 1080),
  ('Dilwale Dulhania Le Jayenge', 1995, M, 720),
  ('Kabhi Khushi Kabhie Gham', 2001, M, 720),
];

const _w = [
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
];

/// Deterministic noise names, many starting with "The".
List<Fx> noise(int n) {
  var x = 12345;
  int r(int m) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    return (x >> 8) % m;
  }

  return [
    for (var i = 0; i < n; i++)
      (
        '${i % 3 == 0 ? 'The ' : ''}${_cap(_w[r(_w.length)])} '
            '${_cap(_w[r(_w.length)])}${i % 5 == 0 ? ' ${_cap(_w[r(_w.length)])}' : ''}',
        1950 + r(75),
        i % 6 == 0 ? S : M,
        const [480, 720, 1080][r(3)],
      ),
  ];
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

TitleDraft draft(int cat, Fx f, int i) {
  final url = 'http://h/c$cat/$i/';
  final file = FileDraft(
    name: 'a.mkv',
    url: '${url}a.mkv',
    ext: 'mkv',
    playable: true,
    sizeKb: 1,
  );
  final series = f.$3 == TitleKind.series;
  return TitleDraft(
    categoryId: cat,
    name: f.$1,
    kind: f.$3,
    folderUrl: url,
    year: f.$2,
    quality: f.$4,
    seasons: series
        ? [
            SeasonDraft(number: 1, label: 'S1', files: [file]),
          ]
        : const [],
    files: series ? const [] : [file],
  );
}
