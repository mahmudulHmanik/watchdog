import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/tmdb/tmdb_client.dart';
import 'package:watchdog/tmdb/tmdb_images.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';

const _key = '0123456789abcdef0123456789abcdef';
final _token = 'eyJhbGciOiJIUzI1NiJ9.${'a' * 40}.${'b' * 30}';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

TmdbClient _client(MockClientHandler h, {String? credential}) => TmdbClient(
  auth: TmdbAuth.parse(credential ?? _key)!,
  client: MockClient(h),
);

void main() {
  group('TmdbAuth.parse', () {
    test('v3 key', () {
      final a = TmdbAuth.parse('  $_key ')!;
      expect(a.isBearer, isFalse);
      expect(a.value, _key);
    });
    test('v4 read access token', () {
      expect(TmdbAuth.parse(_token)!.isBearer, isTrue);
    });
    test('garbage', () {
      expect(TmdbAuth.parse(''), isNull);
      expect(TmdbAuth.parse('hello'), isNull);
      expect(TmdbAuth.parse('${_key}zz'), isNull);
    });
  });

  group('requests', () {
    test('v3 key goes in api_key, no Authorization header', () async {
      late http.Request seen;
      final c = _client((r) async {
        seen = r;
        return _json({'results': []});
      });
      await c.searchMovies('The Matrix', year: 1999);
      expect(seen.url.host, 'api.themoviedb.org');
      expect(seen.url.path, '/3/search/movie');
      expect(seen.url.queryParameters['api_key'], _key);
      expect(seen.url.queryParameters['query'], 'The Matrix');
      expect(seen.url.queryParameters['year'], '1999');
      expect(seen.url.queryParameters['include_adult'], 'false');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('token goes in Bearer header, never in the URL', () async {
      late http.Request seen;
      final c = _client((r) async {
        seen = r;
        return _json({'results': []});
      }, credential: _token);
      await c.searchTv('Dark', year: 2017);
      expect(seen.url.path, '/3/search/tv');
      expect(seen.url.queryParameters['first_air_date_year'], '2017');
      expect(seen.url.queryParameters.containsKey('api_key'), isFalse);
      expect(seen.headers['Authorization'], 'Bearer $_token');
      expect(seen.url.toString(), isNot(contains(_token)));
    });

    test('user agent carries no personal details', () async {
      late http.Request seen;
      final c = _client((r) async {
        seen = r;
        return _json({});
      });
      await c.validate();
      expect(seen.url.path, '/3/configuration');
      expect(seen.headers['User-Agent'], 'watchdog');
    });

    test('details asks for credits in the same request', () async {
      late http.Request seen;
      final c = _client((r) async {
        seen = r;
        return _json({'id': 603, 'title': 'The Matrix'});
      });
      await c.details(603, TmdbMediaType.movie);
      expect(seen.url.path, '/3/movie/603');
      expect(seen.url.queryParameters['append_to_response'], 'credits');
    });
  });

  group('parsing', () {
    test('movie search hits', () async {
      final c = _client(
        (r) async => _json({
          'results': [
            {
              'id': 603,
              'title': 'The Matrix',
              'original_title': 'The Matrix',
              'release_date': '1999-03-31',
              'popularity': 90.5,
              'poster_path': '/m.jpg',
            },
            {'id': 604, 'title': '', 'release_date': ''},
            {'title': 'no id'},
          ],
        }),
      );
      final hits = await c.searchMovies('matrix');
      expect(hits, hasLength(1));
      expect(hits.single.id, 603);
      expect(hits.single.year, 1999);
      expect(hits.single.mediaType, TmdbMediaType.movie);
      expect(hits.single.posterPath, '/m.jpg');
    });

    test('tv search uses name / first_air_date', () async {
      final c = _client(
        (r) async => _json({
          'results': [
            {
              'id': 70523,
              'name': 'Dark',
              'original_name': 'Dark',
              'first_air_date': '2017-12-01',
            },
          ],
        }),
      );
      final h = (await c.searchTv('dark')).single;
      expect(h.title, 'Dark');
      expect(h.year, 2017);
      expect(h.mediaType, TmdbMediaType.tv);
    });

    test('movie details with genres and trimmed, ordered cast', () async {
      final c = TmdbClient(
        auth: TmdbAuth.parse(_key)!,
        maxCast: 2,
        client: MockClient(
          (r) async => _json({
            'id': 603,
            'title': 'The Matrix',
            'original_title': 'The Matrix',
            'overview': 'A hacker learns the truth.',
            'tagline': '',
            'runtime': 136,
            'vote_average': 8.2,
            'vote_count': 25000,
            'original_language': 'en',
            'release_date': '1999-03-31',
            'poster_path': '/p.jpg',
            'backdrop_path': null,
            'genres': [
              {'id': 28, 'name': 'Action'},
              {'id': 878, 'name': 'Science Fiction'},
            ],
            'credits': {
              'cast': [
                {
                  'id': 2975,
                  'name': 'Laurence Fishburne',
                  'character': 'Morpheus',
                  'order': 1,
                },
                {
                  'id': 6384,
                  'name': 'Keanu Reeves',
                  'character': 'Neo',
                  'order': 0,
                  'profile_path': '/k.jpg',
                },
                {'id': 530, 'name': 'Carrie-Anne Moss', 'order': 2},
              ],
            },
          }),
        ),
      );
      final d = await c.details(603, TmdbMediaType.movie);
      expect(d.title, 'The Matrix');
      expect(d.tagline, isNull);
      expect(d.backdropPath, isNull);
      expect(d.runtime, 136);
      expect(d.rating, 8.2);
      expect(d.year, 1999);
      expect(d.originalLanguage, 'en');
      expect(d.genres.map((g) => g.name), ['Action', 'Science Fiction']);
      expect(d.cast.map((m) => m.name), ['Keanu Reeves', 'Laurence Fishburne']);
      expect(d.cast.first.character, 'Neo');
      expect(d.cast.first.profilePath, '/k.jpg');
    });

    test(
      'tv details: episode run time, unrated show has null rating',
      () async {
        final c = _client(
          (r) async => _json({
            'id': 1,
            'name': 'Some Show',
            'first_air_date': '2020-05-05',
            'episode_run_time': [45, 50],
            'vote_average': 0,
            'vote_count': 0,
            'genres': <Object>[],
          }),
        );
        final d = await c.details(1, TmdbMediaType.tv);
        expect(d.runtime, 45);
        expect(d.rating, isNull);
        expect(d.cast, isEmpty);
      },
    );

    test('empty episode_run_time and zero runtime become null', () async {
      final tv = await _client(
        (r) async => _json({'id': 1, 'name': 'x', 'episode_run_time': <int>[]}),
      ).details(1, TmdbMediaType.tv);
      expect(tv.runtime, isNull);
      final movie = await _client(
        (r) async => _json({'id': 2, 'title': 'y', 'runtime': 0}),
      ).details(2, TmdbMediaType.movie);
      expect(movie.runtime, isNull);
    });

    test('yearOf', () {
      expect(yearOf('1999-03-31'), 1999);
      expect(yearOf(''), isNull);
      expect(yearOf(null), isNull);
      expect(yearOf('0000-00-00'), isNull);
    });
  });

  group('errors', () {
    Future<TmdbException> failWith(MockClientHandler h) async {
      try {
        await _client(h).validate();
      } on TmdbException catch (e) {
        return e;
      }
      fail('expected TmdbException');
    }

    test('401 -> unauthorized, not transient', () async {
      final e = await failWith((r) async => _json({}, 401));
      expect(e.kind, TmdbErrorKind.unauthorized);
      expect(e.transient, isFalse);
    });

    test('404 -> notFound', () async {
      final e = await failWith((r) async => _json({}, 404));
      expect(e.kind, TmdbErrorKind.notFound);
    });

    test('429 honours Retry-After, transient', () async {
      final e = await failWith(
        (r) async => http.Response('{}', 429, headers: {'retry-after': '7'}),
      );
      expect(e.kind, TmdbErrorKind.rateLimited);
      expect(e.retryAfter, const Duration(seconds: 7));
      expect(e.transient, isTrue);
    });

    test('429 without a header still backs off', () async {
      final e = await failWith((r) async => _json({}, 429));
      expect(e.retryAfter, const Duration(seconds: 5));
    });

    test('5xx -> server, transient', () async {
      final e = await failWith((r) async => _json({}, 503));
      expect(e.kind, TmdbErrorKind.server);
      expect(e.transient, isTrue);
    });

    test('other statuses and bad bodies -> badResponse', () async {
      expect(
        (await failWith((r) async => _json({}, 400))).kind,
        TmdbErrorKind.badResponse,
      );
      expect(
        (await failWith((r) async => http.Response('<html>', 200))).kind,
        TmdbErrorKind.badResponse,
      );
      expect(
        (await failWith((r) async => http.Response('[1,2]', 200))).kind,
        TmdbErrorKind.badResponse,
      );
    });

    test('socket and client errors -> network, transient', () async {
      final a = await failWith((r) => throw const SocketException('down'));
      expect(a.kind, TmdbErrorKind.network);
      expect(a.transient, isTrue);
      final b = await failWith((r) => throw http.ClientException('reset'));
      expect(b.kind, TmdbErrorKind.network);
    });

    test('timeout -> network', () async {
      final c = TmdbClient(
        auth: TmdbAuth.parse(_key)!,
        timeout: const Duration(milliseconds: 20),
        client: MockClient(
          (r) => Future.delayed(
            const Duration(milliseconds: 300),
            () => _json({}),
          ),
        ),
      );
      await expectLater(
        c.validate(),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.kind,
            'kind',
            TmdbErrorKind.network,
          ),
        ),
      );
    });
  });

  test('tmdbImageUrl', () {
    expect(
      tmdbImageUrl('/a.jpg', TmdbImageSize.posterLarge),
      'https://image.tmdb.org/t/p/w500/a.jpg',
    );
    expect(
      tmdbImageUrl('a.jpg', TmdbImageSize.backdrop),
      'https://image.tmdb.org/t/p/w780/a.jpg',
    );
    expect(tmdbImageUrl(null, TmdbImageSize.poster), isNull);
    expect(tmdbImageUrl('', TmdbImageSize.poster), isNull);
  });
}
