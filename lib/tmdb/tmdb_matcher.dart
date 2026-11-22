/// Picks the TMDB entry that belongs to a library title, or nothing.
///
/// Pure scoring plus an injected [TmdbApi]; the only I/O is the searches.
/// Network errors are not caught here: the caller decides what to do.
library;

import 'dart:math' as math;

import '../data/models.dart';
import '../data/search/query.dart' show normalize;
import '../data/search/ranker.dart' show damerau;
import 'tmdb_client.dart';
import 'tmdb_models.dart';

/// A hit and how sure we are (0..1).
class TmdbMatch {
  const TmdbMatch(this.hit, this.score);
  final TmdbHit hit;
  final double score;
}

/// How scoring works, so the numbers below are not magic:
///
///   total = 0.70 * titleSim + 0.25 * yearScore + 0.05 * popularity
///
/// * titleSim (0..1) compares normalised titles (lowercase, accents folded,
///   punctuation gone, "&" = "and", leading article and "and" dropped,
///   spaces ignored) against BOTH the localised and the original title. An
///   exact match is 1; a typo-sized difference is 0.9 and only allowed on
///   long titles (>= 9 letters), so "Alien" never matches "Aliens". Numbers
///   in the name must agree ("Toy Story" is not "Toy Story 3"), and the
///   part before a colon of the TMDB title ("Mission: Impossible - Fallout"
///   -> "Mission") counts at 0.9 x. Anything under [minTitleSim] is out.
/// * yearScore: same year 1, off by one 0.6, no year on the folder 0.5, TMDB
///   has no date 0.3. Further than one year away when the folder has a year
///   is rejected outright (remakes, same-name shows).
/// * popularity is only a tie-break: log-scaled to 0..1, worth at most 0.05.
///
/// A candidate is accepted at total >= [threshold] (0.80). That is: an exact
/// title with the right year always passes (0.95+), an exact title off by one
/// year passes (0.85), an exact title with no year on either side passes on
/// its own (>= 0.825), a typo-level title needs the exact year (0.88), and
/// the colon-prefix variant needs the exact year too (0.88). Anything vaguer
/// returns null: an unmatched title is cheaper than a wrong poster.
class TmdbMatcher {
  TmdbMatcher(this.api, {this.threshold = defaultThreshold});

  static const defaultThreshold = 0.80;
  static const minTitleSim = 0.80;

  final TmdbApi api;
  final double threshold;

  /// Movie -> /search/movie, series -> /search/tv, events are never looked up.
  /// First search with the year; if nothing is acceptable, search without it.
  Future<TmdbHit?> match(MediaTitle t) async {
    final type = switch (t.kind) {
      TitleKind.movie => TmdbMediaType.movie,
      TitleKind.series => TmdbMediaType.tv,
      TitleKind.event => null,
    };
    if (type == null) return null;
    return (await matchQuery(t.name, type, year: t.year ?? t.yearEnd))?.hit;
  }

  /// [year] is the release year (movie) or the first-air year (series).
  Future<TmdbMatch?> matchQuery(
    String name,
    TmdbMediaType type, {
    int? year,
  }) async {
    if (normalizeTitle(name).replaceAll(' ', '').isEmpty) return null;
    Future<List<TmdbHit>> search(int? y) => type == TmdbMediaType.movie
        ? api.searchMovies(name, year: y)
        : api.searchTv(name, year: y);

    if (year != null) {
      final m = pick(await search(year), name, year);
      if (m != null) return m;
    }
    return pick(await search(null), name, year);
  }

  /// Best acceptable hit among [hits], or null. Pure.
  TmdbMatch? pick(List<TmdbHit> hits, String name, int? year) {
    TmdbMatch? best;
    for (final h in hits) {
      final s = score(name, year, h);
      if (s == null || s < threshold) continue;
      if (best == null || s > best.score) best = TmdbMatch(h, s);
    }
    return best;
  }

  /// Total score of [h] for a folder called [name], or null when rejected.
  static double? score(String name, int? year, TmdbHit h) {
    final qn = normalizeTitle(name);
    if (qn.replaceAll(' ', '').isEmpty) return null;
    // A one or two letter name with no year is too ambiguous to trust.
    if (year == null && qn.replaceAll(' ', '').length < 3) return null;

    final sim = math.max(
      _variantSim(qn, h.title),
      h.originalTitle == null ? 0.0 : _variantSim(qn, h.originalTitle!),
    );
    if (sim < minTitleSim) return null;

    final double ys;
    if (year == null) {
      ys = 0.5;
    } else if (h.year == null) {
      ys = 0.3;
    } else {
      final d = (h.year! - year).abs();
      if (d > 1) return null;
      ys = d == 0 ? 1.0 : 0.6;
    }
    final pop = math.min(
      1.0,
      math.log(1 + math.max(0, h.popularity)) / math.ln10 / 3,
    );
    return 0.70 * sim + 0.25 * ys + 0.05 * pop;
  }

  static final _colon = RegExp(r'\s*(?::|\s-\s|\s–\s)\s*');

  /// Similarity of normalised query [qn] to a raw TMDB title, also trying the
  /// part before the first colon or dash at 0.9 x.
  static double _variantSim(String qn, String raw) {
    var best = _sim(qn, normalizeTitle(raw));
    final i = raw.indexOf(_colon);
    if (i > 0) {
      final head = normalizeTitle(raw.substring(0, i));
      if (head.replaceAll(' ', '').length >= 3) {
        best = math.max(best, 0.9 * _sim(qn, head));
      }
    }
    return best;
  }

  /// Both inputs already normalised with [normalizeTitle].
  static double _sim(String a, String b) {
    final ca = a.replaceAll(' ', ''), cb = b.replaceAll(' ', '');
    if (ca.isEmpty || cb.isEmpty) return 0;
    // Sequel numbers must agree: "toy story" != "toy story 3".
    if (!_sameNumbers(a, b)) return 0;
    if (ca == cb) return 1;
    final len = math.max(ca.length, cb.length);
    final allowed = len >= 15 ? 2 : (len >= 9 ? 1 : 0);
    final d = damerau(ca, cb, allowed + 1);
    if (d <= allowed) return 0.9;
    return math.min(0.6, 1 - d / len);
  }

  static bool _sameNumbers(String a, String b) {
    Set<String> nums(String s) => {
      for (final t in s.split(' '))
        if (t.contains(RegExp(r'\d'))) t,
    };
    final x = nums(a), y = nums(b);
    return x.length == y.length && x.containsAll(y);
  }

  static const _roman = {
    'ii': '2',
    'iii': '3',
    'iv': '4',
    'vi': '6',
    'vii': '7',
    'viii': '8',
    'ix': '9',
  };

  /// Lowercase, accents folded, punctuation dropped, "&" read as "and", then
  /// a leading article and every "and" removed, roman numerals ii..ix turned
  /// into digits (when not the only word). Space-separated tokens.
  static String normalizeTitle(String s) {
    final toks = normalize(s.replaceAll('&', ' and '))
        .split(' ')
        .where((t) => t.isNotEmpty && t != 'and')
        .toList();
    if (toks.length > 1 && const {'the', 'a', 'an'}.contains(toks.first)) {
      toks.removeAt(0);
    }
    if (toks.length > 1) {
      for (var i = 1; i < toks.length; i++) {
        toks[i] = _roman[toks[i]] ?? toks[i];
      }
    }
    return toks.join(' ');
  }
}
