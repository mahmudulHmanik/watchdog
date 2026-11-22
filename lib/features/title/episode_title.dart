/// Readable episode titles from release file names. Pure Dart.
library;

final _ext = RegExp(r'\.[A-Za-z0-9]{2,4}$');
final _brackets = RegExp(r'\[[^\]]*\]');

// Technical tokens that end the title part of a release name.
const _techBody =
    r'(?:\d{3,4}p|\d{3,4}x\d{3,4}|4k|uhd|blu-?ray|bdrip|brrip|web-?dl|web-?rip|web-?hd|webrip|hdrip|hdtv|dvdrip|dvdscr|x26[45]|h\.?26[45]|hevc\d?|web-?dl-?rip(?:\d{3,4}p)?|eng(?:lish)?[ -]?(?:subs?|dubs?)|dual|multi[ -]?audio|avc|xvid|aac\d*(?:\.\d)?|ac3|eac3|dd[p+]?\d?|dts|10-?bit|esubs?|msubs?|hardsub|dual[ -]?audio|hindi|nf|amzn|dsnp|\d+\s?mb|\d+(?:\.\d+)?\s?gb)';
final _tokens = RegExp(
  '(?<![A-Za-z0-9])$_techBody(?![A-Za-z0-9])',
  caseSensitive: false,
);
// Upper-case language / quality tags (case-sensitive so real words survive).
final _langTags = RegExp(
  r'(?<![A-Za-z0-9])(?:KOR|ENG|HIN|JPN|JAP|TAM|TEL|BEN|MAL|MULTI|DUAL|SUBS?|ENGSUB|HQ|HD|FHD|BD|DVD)(?![A-Za-z0-9])',
);
final _parens = RegExp(r'\(([^)]*)\)');
final _hashOnly = RegExp(r'^[0-9A-Fa-f]{6,10}$');
final _yearOnly = RegExp(
  r'^\s*(?:19|20)\d{2}(?:\s*[-\u2013]\s*(?:19|20)?\d{2})?\s*$',
);
final _sxe = RegExp(
  r'\bS\d{1,3}(?:\s*[ ._-]?\s*E\d{1,4}[A-Za-z]?(?![A-Za-z0-9])(?:\s*[-\u2013\u2014E]\s*E?\d{1,4})*)?(?![A-Za-z0-9])'
  r'|(?<![A-Za-z0-9])E\d{1,4}[A-Za-z]?(?![A-Za-z0-9])(?:\s*[-\u2013\u2014]\s*E?\d{1,4})*'
  r'|\b\d{1,2}x\d{2,3}\b|\bSeason\s*\d+\b',
  caseSensitive: false,
);
final _leadEpisodeWord = RegExp(
  r'^(?:episode|ep)\.?\s*\d{1,4}\b[\s\-–:.]*',
  caseSensitive: false,
);
final _leadE = RegExp(r'^E\d{1,4}\b[\s\-–:.]*', caseSensitive: false);
final _leadNumDash = RegExp(r'^\d{1,4}\s*[-–:.)]\s*');
final _edge = RegExp(r'^[\s\-–:.,_)\]]+|[\s\-–:.,_(\[]+$');

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Strips the longest leading run of tokens shared with [show] (normalised,
/// so `Yu-Gi-Oh!` vs `Yu Gi Oh` or a show folder with extra tail tokens still
/// match). One shared token is only enough if the show is a single word.
String _stripShowPrefix(String s, String show) {
  final st = [
    for (final m in _word.allMatches(show)) m.group(0)!.toLowerCase(),
  ];
  final fm = _word.allMatches(s).toList();
  var k = 0;
  while (k < st.length &&
      k < fm.length &&
      fm[k].group(0)!.toLowerCase() == st[k]) {
    k++;
  }
  if (k == 0 || (k == 1 && st.length > 1)) return s;
  return s
      .substring(fm[k - 1].end)
      .replaceFirst(RegExp(r'^[^\p{L}\p{N}(\[]+', unicode: true), '');
}

/// Cleaned episode title, or `Episode N` / `Special N` when the name holds
/// no actual title. [episode] is `MediaFile.episode`; [special] for season 0.
String cleanEpisodeTitle(
  String fileName,
  String showName, {
  int? episode,
  bool special = false,
}) {
  String fallback() {
    final n = episode;
    final word = special ? 'Special' : 'Episode';
    return n == null ? word : '$word $n';
  }

  var s = fileName.replaceFirst(_ext, '');
  s = s.replaceAll(_brackets, ' ');
  s = s.replaceAllMapped(_parens, (m) {
    final c = m.group(1)!.trim();
    final junk =
        c.isEmpty ||
        _hashOnly.hasMatch(c) ||
        RegExp(
          r'^(?:e\d+|eng|hin|jpn|kor|sub|dub|raw|uncut)$',
          caseSensitive: false,
        ).hasMatch(c) ||
        _yearOnly.hasMatch(c) ||
        _tokens.hasMatch(c) ||
        _langTags.hasMatch(c);
    return junk ? ' ' : m.group(0)!;
  });
  s = s
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  s = _stripShowPrefix(s, showName);

  s = s.replaceAll(_sxe, ' ');
  final cut = [
    _tokens.firstMatch(s)?.start,
    _langTags.firstMatch(s)?.start,
  ].whereType<int>();
  if (cut.isNotEmpty) s = s.substring(0, cut.reduce((a, b) => a < b ? a : b));
  s = s.replaceAll(RegExp(r'(?:\s[-\u2013:]){2,}'), ' -');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAll(_edge, '');
  s = s.replaceFirst(RegExp(r'\s-\S+$'), ''); // trailing " -Group"
  s = s.replaceAll(_edge, '');

  s = s.replaceFirst(_leadEpisodeWord, '').replaceFirst(_leadE, '');
  s = s.replaceAll(_edge, '');
  final bare = RegExp(r'^(\d{1,4})\b').firstMatch(s);
  if (bare != null) {
    final n = int.parse(bare.group(1)!);
    if (s.length == bare.group(1)!.length ||
        n == episode ||
        _leadNumDash.hasMatch(s)) {
      s = s.replaceFirst(RegExp(r'^\d{1,4}\s*[-–:.)]?\s*'), '');
    }
  }
  s = s.replaceAll(RegExp(r'(?:\s[-\u2013:]){2,}'), ' -').replaceAll(_edge, '');
  return s.isEmpty ? fallback() : s;
}
