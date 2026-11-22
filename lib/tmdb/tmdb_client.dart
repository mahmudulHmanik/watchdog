/// Minimal TMDB v3 client on package:http.
///
/// Each user supplies their own credential (see [TmdbAuth.parse]); nothing is
/// bundled with the app. The client does no retrying or throttling: it throws
/// a typed [TmdbException] and the caller (the background worker) decides.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'tmdb_models.dart';
import 'tmdb_secrets.dart';

/// A TMDB credential: the v4 "API Read Access Token" (sent as a Bearer
/// header) or the v3 API key (sent as `api_key`). Both give the same access.
class TmdbAuth {
  const TmdbAuth._(this.value, this.isBearer);

  final String value;
  final bool isBearer;

  static final _v3Key = RegExp(r'^[0-9a-fA-F]{32}$');
  static final _jwt = RegExp(r'^[\w-]+\.[\w-]+\.[\w-]+$');

  /// Null when [input] looks like neither credential.
  static TmdbAuth? parse(String input) {
    final t = input.trim();
    if (_v3Key.hasMatch(t)) return TmdbAuth._(t, false);
    if (t.length > 60 && _jwt.hasMatch(t)) return TmdbAuth._(t, true);
    return null;
  }
}

enum TmdbErrorKind {
  /// 401: missing, wrong or revoked key.
  unauthorized,

  /// 429: slow down; see [TmdbException.retryAfter].
  rateLimited,

  /// 404: no such movie, show or person.
  notFound,

  /// 5xx.
  server,

  /// No connection, DNS failure or timeout.
  network,

  /// Unexpected status or unreadable body.
  badResponse,
}

class TmdbException implements Exception {
  const TmdbException(this.kind, this.message, {this.retryAfter});

  final TmdbErrorKind kind;
  final String message;
  final Duration? retryAfter;

  /// Worth trying again later (as opposed to a key or data problem).
  bool get transient =>
      kind == TmdbErrorKind.rateLimited ||
      kind == TmdbErrorKind.server ||
      kind == TmdbErrorKind.network;

  @override
  String toString() => message;
}

/// The calls the matcher and sync worker need; lets tests use a fake.
abstract interface class TmdbApi {
  Future<List<TmdbHit>> searchMovies(String query, {int? year});
  Future<List<TmdbHit>> searchTv(String query, {int? year});
  Future<TmdbDetails> details(int id, TmdbMediaType type);
}

class TmdbClient implements TmdbApi {
  TmdbClient({
    required this.auth,
    http.Client? client,
    this.language = 'en-US',
    this.timeout = const Duration(seconds: 20),
    this.maxCast = 15,
  }) : _client = client ?? http.Client();

  final TmdbAuth auth;
  final String language;
  final Duration timeout;

  /// Cast members kept per title.
  final int maxCast;
  final http.Client _client;

  static const _host = 'api.themoviedb.org';

  void close() => _client.close();

  /// Throws [TmdbException] if the credential or the connection is bad.
  Future<void> validate() async {
    await _get('/configuration', const {});
  }

  @override
  Future<List<TmdbHit>> searchMovies(String query, {int? year}) async {
    final j = await _get('/search/movie', {
      'query': query,
      'include_adult': 'false',
      'language': language,
      if (year != null) 'year': '$year',
    });
    return _hits(j, TmdbMediaType.movie);
  }

  @override
  Future<List<TmdbHit>> searchTv(String query, {int? year}) async {
    final j = await _get('/search/tv', {
      'query': query,
      'include_adult': 'false',
      'language': language,
      if (year != null) 'first_air_date_year': '$year',
    });
    return _hits(j, TmdbMediaType.tv);
  }

  /// Details plus top cast in one request (`append_to_response=credits`).
  @override
  Future<TmdbDetails> details(int id, TmdbMediaType type) async {
    final path = type == TmdbMediaType.movie ? '/movie/$id' : '/tv/$id';
    final j = await _get(path, {
      'language': language,
      'append_to_response': 'credits',
    });
    try {
      return TmdbDetails.fromJson(j, type, maxCast: maxCast);
    } on TypeError {
      throw const TmdbException(
        TmdbErrorKind.badResponse,
        'Unexpected answer from TMDB',
      );
    }
  }

  List<TmdbHit> _hits(Map<String, dynamic> j, TmdbMediaType type) {
    final out = <TmdbHit>[];
    for (final r in (j['results'] as List?) ?? const []) {
      if (r is! Map<String, dynamic> || r['id'] is! num) continue;
      final hit = TmdbHit.fromJson(r, type);
      if (hit.title.isNotEmpty) out.add(hit);
    }
    return out;
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params,
  ) async {
    final uri = Uri.https(_host, '/3$path', {
      ...params,
      if (!auth.isBearer) 'api_key': auth.value,
    });
    final headers = {
      'Accept': 'application/json',
      // Generic on purpose: no personal details in outside requests.
      'User-Agent': 'watchdog',
      if (auth.isBearer) 'Authorization': 'Bearer ${auth.value}',
    };

    final http.Response res;
    try {
      res = await _client.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      throw const TmdbException(
        TmdbErrorKind.network,
        'TMDB did not answer in time',
      );
    } on SocketException {
      throw const TmdbException(
        TmdbErrorKind.network,
        'Cannot reach TMDB. Check your internet.',
      );
    } on http.ClientException catch (e) {
      // The message often carries the full request URL, key included.
      throw TmdbException(
        TmdbErrorKind.network,
        'Cannot reach TMDB: ${scrubSecrets(e.message, secrets: [auth.value])}',
      );
    } catch (e) {
      // TLS and other transport errors: never let their text through raw.
      throw TmdbException(
        TmdbErrorKind.network,
        'Cannot reach TMDB: ${scrubSecrets('$e', secrets: [auth.value])}',
      );
    }

    switch (res.statusCode) {
      case 200:
        break;
      case 401:
        throw const TmdbException(
          TmdbErrorKind.unauthorized,
          'TMDB rejected the key. Check it in Settings.',
        );
      case 404:
        throw const TmdbException(TmdbErrorKind.notFound, 'Not found on TMDB');
      case 429:
        final secs = int.tryParse(res.headers['retry-after'] ?? '');
        throw TmdbException(
          TmdbErrorKind.rateLimited,
          'TMDB rate limit hit. Slowing down.',
          retryAfter: Duration(seconds: (secs ?? 5).clamp(1, 120)),
        );
      default:
        throw TmdbException(
          res.statusCode >= 500
              ? TmdbErrorKind.server
              : TmdbErrorKind.badResponse,
          'TMDB answered ${res.statusCode}',
        );
    }

    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map<String, dynamic>) return body;
    } on FormatException {
      // fall through
    }
    throw const TmdbException(
      TmdbErrorKind.badResponse,
      'Unreadable answer from TMDB',
    );
  }
}
