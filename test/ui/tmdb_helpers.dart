import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';

/// A syntactically valid v3 key. Never a real one.
const fakeKey = '0123456789abcdef0123456789abcdef';

http.Response jsonResp(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Answers like TMDB for one movie (id 603); records every request.
MockClient matrixClient(List<Uri> seen) => MockClient((r) async {
  seen.add(r.url);
  final p = r.url.path;
  if (p == '/3/configuration') return jsonResp({'images': <String, Object>{}});
  if (p == '/3/search/movie') {
    return jsonResp({
      'results': [
        {
          'id': 603,
          'title': 'The Matrix',
          'original_title': 'The Matrix',
          'release_date': '1999-03-31',
          'popularity': 80.0,
          'poster_path': '/m.jpg',
        },
        {
          'id': 604,
          'title': 'The Matrix Reloaded',
          'release_date': '2003-05-15',
          'popularity': 50.0,
        },
      ],
    });
  }
  if (p == '/3/search/tv') return jsonResp({'results': <Object>[]});
  if (p == '/3/movie/603') {
    return jsonResp({
      'id': 603,
      'title': 'The Matrix',
      'original_title': 'The Matrix',
      'overview': 'A hacker learns the truth.',
      'release_date': '1999-03-31',
      'runtime': 136,
      'vote_average': 8.2,
      'vote_count': 20000,
      'original_language': 'en',
      'genres': [
        {'id': 28, 'name': 'Action'},
      ],
      'credits': {
        'cast': [
          {'id': 6384, 'name': 'Keanu Reeves', 'character': 'Neo', 'order': 0},
        ],
      },
    });
  }
  return jsonResp({}, 404);
});

TmdbInfo sampleInfo(
  int titleId, {
  TmdbStatus status = TmdbStatus.matched,
  double? rating = 7.8,
}) => TmdbInfo(
  titleId: titleId,
  status: status,
  fetchedAt: DateTime.now(),
  tmdbId: 603,
  mediaType: TmdbMediaType.movie,
  overview: 'A computer hacker learns the truth about his reality.',
  tagline: 'Welcome to the real world.',
  rating: rating,
  voteCount: 20000,
  runtime: 112,
  originalLanguage: 'hi',
  releaseYear: 1999,
  posterPath: '/poster.jpg',
  backdropPath: '/backdrop.jpg',
  genres: const [TmdbGenre(18, 'Drama'), TmdbGenre(28, 'Action')],
  cast: const [
    TmdbCastMember(
      personId: 6384,
      name: 'Keanu Reeves',
      character: 'Neo',
      profilePath: '/k.jpg',
    ),
    TmdbCastMember(personId: 2975, name: 'Laurence Fishburne', order: 1),
  ],
);
