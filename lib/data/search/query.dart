/// Query normalisation and parsing (pure Dart, no database).
library;

import '../models.dart';

const _fold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'æ': 'ae',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ď': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ı': 'i',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'œ': 'oe',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ß': 'ss',
  'ť': 't',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ž': 'z',
  'ż': 'z',
};

final _apos = RegExp("['`‘’]");
final _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Lowercase, fold Latin diacritics, drop apostrophes, other punctuation and
/// separators become single spaces.
String normalize(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().replaceAll(_apos, '').runes) {
    final ch = String.fromCharCode(r);
    b.write(_fold[ch] ?? ch);
  }
  return b.toString().replaceAll(_nonAlnum, ' ').trim();
}

final _range = RegExp(
  r'\b((?:19|20)\d{2})\s*(?:-|–|\.\.|to)\s*((?:19|20)\d{2})\b',
);
final _yearTok = RegExp(r'^(19|20)\d{2}$');
final _seasonTok = RegExp(r'^(s\d{1,2}(e\d{1,3})?|e\d{1,3}|season|seasons)$');
final _qualityTok = RegExp(r'^(\d{3,4})p$');
final _numTok = RegExp(r'^\d{1,2}$');

const stopwords = {'the', 'of', 'and', 'a', 'an', 'in', 'to'};

class ParsedQuery {
  ParsedQuery({
    required this.tokens,
    this.yearHint,
    this.yearMin,
    this.yearMax,
    this.qualityHint,
    this.kindHint,
  }) : compact = tokens.join();

  /// Text tokens (normalised) used for title matching.
  final List<String> tokens;

  /// Tokens joined without separators ('spider man' == 'spiderman').
  final String compact;

  /// Soft boost: title year equals this.
  final int? yearHint;

  /// Hard filter from range syntax ('1990-1999').
  final int? yearMin;
  final int? yearMax;
  final int? qualityHint;
  final TitleKind? kindHint;

  bool get hasText => tokens.isNotEmpty;

  static ParsedQuery parse(String raw) {
    var s = raw.toLowerCase();
    int? ymin, ymax;
    final m = _range.firstMatch(s);
    if (m != null) {
      final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
      ymin = a < b ? a : b;
      ymax = a < b ? b : a;
      s = s.replaceRange(m.start, m.end, ' ');
    }
    final raws = normalize(s).split(' ').where((t) => t.isNotEmpty).toList();
    // season markers: 's02', 's02e05', 'season 2', 'seasons'
    TitleKind? kind;
    int? quality;
    final kept = <String>[];
    for (var i = 0; i < raws.length; i++) {
      final t = raws[i];
      final q = _qualityTok.firstMatch(t);
      if (q != null) {
        quality = int.parse(q.group(1)!);
        continue;
      }
      if (_seasonTok.hasMatch(t) && !(t.length == 1)) {
        // 'e5' / 's2' only count when they look like markers; a bare title
        // word such as 'season' needs a number next to count.
        final isWord = t == 'season' || t == 'seasons';
        if (isWord) {
          if (i + 1 < raws.length && _numTok.hasMatch(raws[i + 1])) {
            i++;
            kind = TitleKind.series;
            continue;
          }
          kept.add(t);
          continue;
        }
        kind = TitleKind.series;
        continue;
      }
      kept.add(t);
    }
    int? year;
    final yearIdx = kept.indexWhere(_yearTok.hasMatch);
    if (yearIdx >= 0) {
      year = int.parse(kept[yearIdx]);
      // A lone year ('1917', '2012') is a title; with other text it is a hint.
      if (kept.length > 1) kept.removeAt(yearIdx);
    }
    return ParsedQuery(
      tokens: kept,
      yearHint: year,
      yearMin: ymin,
      yearMax: ymax,
      qualityHint: quality,
      kindHint: kind,
    );
  }
}
