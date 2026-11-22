/// Plain models for the parts of the TMDB v3 API watchdog uses.
library;

enum TmdbMediaType { movie, tv }

/// One search result (`/search/movie` or `/search/tv`).
class TmdbHit {
  const TmdbHit({
    required this.id,
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.year,
    this.popularity = 0,
    this.posterPath,
  });

  final int id;
  final TmdbMediaType mediaType;
  final String title;
  final String? originalTitle;

  /// Release (movie) or first air (tv) year.
  final int? year;
  final double popularity;
  final String? posterPath;

  factory TmdbHit.fromJson(Map<String, dynamic> j, TmdbMediaType type) {
    final movie = type == TmdbMediaType.movie;
    return TmdbHit(
      id: (j['id'] as num).toInt(),
      mediaType: type,
      title: _str(j[movie ? 'title' : 'name']) ?? '',
      originalTitle: _str(j[movie ? 'original_title' : 'original_name']),
      year: yearOf(_str(j[movie ? 'release_date' : 'first_air_date'])),
      popularity: (j['popularity'] as num?)?.toDouble() ?? 0,
      posterPath: _str(j['poster_path']),
    );
  }
}

class TmdbGenre {
  const TmdbGenre(this.id, this.name);
  final int id;
  final String name;
}

class TmdbCastMember {
  const TmdbCastMember({
    required this.personId,
    required this.name,
    this.character,
    this.order = 0,
    this.profilePath,
  });

  final int personId;
  final String name;
  final String? character;
  final int order;
  final String? profilePath;
}

/// Details of one movie or show, with its credits (`append_to_response`).
class TmdbDetails {
  const TmdbDetails({
    required this.id,
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.overview,
    this.tagline,
    this.rating,
    this.voteCount,
    this.runtime,
    this.originalLanguage,
    this.year,
    this.posterPath,
    this.backdropPath,
    this.genres = const [],
    this.cast = const [],
  });

  final int id;
  final TmdbMediaType mediaType;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? tagline;

  /// 0..10, null when nobody voted yet.
  final double? rating;
  final int? voteCount;

  /// Minutes (movie runtime, or the usual episode length for a show).
  final int? runtime;
  final String? originalLanguage;
  final int? year;
  final String? posterPath;
  final String? backdropPath;
  final List<TmdbGenre> genres;

  /// Billing order, at most the client's `maxCast`.
  final List<TmdbCastMember> cast;

  factory TmdbDetails.fromJson(
    Map<String, dynamic> j,
    TmdbMediaType type, {
    int maxCast = 15,
  }) {
    final movie = type == TmdbMediaType.movie;
    final rating = (j['vote_average'] as num?)?.toDouble();
    final votes = (j['vote_count'] as num?)?.toInt();
    int? runtime;
    if (movie) {
      runtime = (j['runtime'] as num?)?.toInt();
    } else {
      final eps = j['episode_run_time'];
      if (eps is List && eps.isNotEmpty && eps.first is num) {
        runtime = (eps.first as num).toInt();
      }
    }
    if (runtime != null && runtime <= 0) runtime = null;

    final genres = <TmdbGenre>[
      for (final g in (j['genres'] as List?) ?? const [])
        if (g is Map<String, dynamic> && g['id'] is num && g['name'] is String)
          TmdbGenre((g['id'] as num).toInt(), g['name'] as String),
    ];

    final cast = <TmdbCastMember>[];
    final credits = j['credits'];
    if (credits is Map<String, dynamic>) {
      for (final c in (credits['cast'] as List?) ?? const []) {
        if (c is! Map<String, dynamic>) continue;
        if (c['id'] is! num || _str(c['name']) == null) continue;
        cast.add(
          TmdbCastMember(
            personId: (c['id'] as num).toInt(),
            name: _str(c['name'])!,
            character: _str(c['character']),
            order: (c['order'] as num?)?.toInt() ?? cast.length,
            profilePath: _str(c['profile_path']),
          ),
        );
      }
      cast.sort((a, b) => a.order.compareTo(b.order));
    }

    return TmdbDetails(
      id: (j['id'] as num).toInt(),
      mediaType: type,
      title: _str(j[movie ? 'title' : 'name']) ?? '',
      originalTitle: _str(j[movie ? 'original_title' : 'original_name']),
      overview: _str(j['overview']),
      tagline: _str(j['tagline']),
      // TMDB reports 0 / 0 for unrated titles.
      rating: (votes == null || votes == 0) ? null : rating,
      voteCount: votes,
      runtime: runtime,
      originalLanguage: _str(j['original_language']),
      year: yearOf(_str(j[movie ? 'release_date' : 'first_air_date'])),
      posterPath: _str(j['poster_path']),
      backdropPath: _str(j['backdrop_path']),
      genres: genres,
      cast: cast.length > maxCast ? cast.sublist(0, maxCast) : cast,
    );
  }
}

/// `1999-03-31` -> 1999; empty or malformed -> null.
int? yearOf(String? date) {
  if (date == null || date.length < 4) return null;
  final y = int.tryParse(date.substring(0, 4));
  return (y == null || y < 1870) ? null : y;
}

/// Non-empty string or null (TMDB sends `""` for missing text).
String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
