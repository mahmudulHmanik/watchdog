/// Dart-side re-ranking of FTS candidates (pure, no database).
library;

import '../models.dart';
import 'query.dart';

class Candidate {
  Candidate({
    required this.id,
    required this.name,
    this.year,
    required this.kind,
    this.quality,
    this.category = '',
  });
  final int id;
  final String name;
  final int? year;
  final TitleKind kind;
  final int? quality;

  /// Category name; a weak fallback match target ('hindi movies').
  final String category;
}

/// Optimal string alignment (Damerau, adjacent transpositions) distance.
int damerau(String a, String b, [int cap = 1 << 20]) {
  if (a == b) return 0;
  final n = a.length, m = b.length;
  if ((n - m).abs() > cap) return cap + 1;
  if (n == 0) return m;
  if (m == 0) return n;
  var prev2 = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (j) => j);
  var cur = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    cur[0] = i;
    final ac = a.codeUnitAt(i - 1);
    for (var j = 1; j <= m; j++) {
      final bc = b.codeUnitAt(j - 1);
      final cost = ac == bc ? 0 : 1;
      var v = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      if (ins < v) v = ins;
      final sub = prev[j - 1] + cost;
      if (sub < v) v = sub;
      if (i > 1 &&
          j > 1 &&
          ac == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == bc) {
        final t = prev2[j - 2] + 1;
        if (t < v) v = t;
      }
      cur[j] = v;
    }
    final t = prev2;
    prev2 = prev;
    prev = cur;
    cur = t;
  }
  return prev[m];
}

Set<String> trigrams(String s) => {
  for (var i = 0; i + 3 <= s.length; i++) s.substring(i, i + 3),
};

int _allowed(int len) => len <= 3 ? 0 : (len <= 5 ? 1 : (len <= 8 ? 2 : 3));

/// Score of one normalised token against the title tokens, 0..1.
double _tokenMatch(String qt, List<String> title) {
  var best = 0.0;
  final allow = _allowed(qt.length);
  for (final tt in title) {
    double s = 0;
    if (tt == qt) {
      return 1;
    } else if (tt.startsWith(qt)) {
      s = 0.95;
    } else if (qt.length >= 3 && tt.contains(qt)) {
      s = 0.8;
    } else if (allow > 0) {
      var d = damerau(qt, tt, allow);
      if (d <= allow) s = (1 - d / qt.length) * 0.9;
      if (tt.length > qt.length) {
        d = damerau(qt, tt.substring(0, qt.length), allow);
        if (d <= allow) {
          final p = (1 - d / qt.length) * 0.8;
          if (p > s) s = p;
        }
      }
    }
    if (s > best) best = s;
  }
  return best;
}

const minScore = 200.0;

/// Score (higher is better) or null when the candidate is not a match.
double? scoreCandidate(ParsedQuery q, Candidate c) {
  final ntitle = normalize(c.name);
  final ttoks = ntitle.split(' ').where((t) => t.isNotEmpty).toList();
  // A year hint that was split out of the query text ('blade runner 2049')
  // matches a trailing year token in the title; compare without it.
  var yearInName = false;
  if (q.yearHint != null && !q.tokens.contains('${q.yearHint}')) {
    yearInName = ttoks.remove('${q.yearHint}');
  }
  final compact = ttoks.join();
  double base;
  if (!q.hasText) {
    base = 500;
  } else if (compact == q.compact) {
    base = 1000;
  } else if (compact.startsWith(q.compact)) {
    base = 900;
  } else {
    final cover = [for (final t in q.tokens) _tokenMatch(t, ttoks)];
    final cov = cover.reduce((a, b) => a + b) / cover.length;
    final minCover = cover.reduce((a, b) => a < b ? a : b);
    base = 0;
    if (minCover >= 0.8) {
      base = 600 + 200 * cov;
    } else {
      // whole-string fuzzy (handles merged/split words and typos)
      final ql = q.compact.length;
      final allow = _allowed(ql);
      if (allow > 0) {
        var d = damerau(q.compact, compact, allow);
        var p = d <= allow ? 650 * (1 - d / ql) : 0.0;
        if (compact.length > ql) {
          d = damerau(q.compact, compact.substring(0, ql), allow);
          if (d <= allow) {
            final pp = 640 * (1 - d / ql);
            if (pp > p) p = pp;
          }
        }
        if (p > base) base = p;
      }
      if (cov >= 0.6 && 600 * cov > base) base = 600 * cov;
      if (base < minScore) {
        final a = trigrams(q.compact), b = trigrams(compact);
        if (a.isNotEmpty && b.isNotEmpty) {
          final inter = a.intersection(b).length;
          final j = inter / (a.length + b.length - inter);
          if (j >= 0.35 && 400 * j > base) base = 400 * j;
        }
      }
    }
    if (base < minScore) {
      // Weak fallback: every query token appears in name + category.
      final all = [...ttoks, ...normalize(c.category).split(' ')];
      final ok = q.tokens.every((t) => _tokenMatch(t, all) >= 0.8);
      if (!ok) return null;
      base = 450;
    }
  }
  var s = base;
  if (q.yearHint != null) {
    if (c.year == q.yearHint) s += 40;
    if (yearInName) s += 80;
  }
  if (q.kindHint != null && c.kind == q.kindHint) s += 150;
  if (q.qualityHint != null && c.quality == q.qualityHint) s += 20;
  final len = compact.length < 80 ? compact.length : 80;
  return s - len * 0.25;
}

/// Ranked ids: score desc, then shorter name, then name, then id (stable).
List<Candidate> rank(ParsedQuery q, Iterable<Candidate> cands) {
  final scored = <(double, Candidate)>[];
  for (final c in cands) {
    final s = scoreCandidate(q, c);
    if (s != null) scored.add((s, c));
  }
  scored.sort((a, b) {
    final d = b.$1.compareTo(a.$1);
    if (d != 0) return d;
    final l = a.$2.name.length.compareTo(b.$2.name.length);
    if (l != 0) return l;
    final n = a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
    return n != 0 ? n : a.$2.id.compareTo(b.$2.id);
  });
  return [for (final e in scored) e.$2];
}
