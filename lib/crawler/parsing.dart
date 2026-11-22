//  Pure name parsers. No IO. Rules derived from real DhakaFlix listings.

const videoExts = {
  'mkv',
  'mp4',
  'avi',
  'm4v',
  'ts',
  'webm',
  'mov',
  'wmv',
  'flv',
};
const imageExts = {'jpg', 'jpeg', 'png', 'webp', 'jfif', 'jpe'};
const subExts = {'srt', 'ass', 'ssa', 'vtt', 'sub'};
const archiveExts = {'rar', 'zip', '7z'};

String extOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

bool isVideo(String name) => videoExts.contains(extOf(name));
bool isImage(String name) => imageExts.contains(extOf(name));
bool isSubtitle(String name) => subExts.contains(extOf(name));
bool isArchive(String name) => archiveExts.contains(extOf(name));

/// Folders that hold side material, never a title of their own.
final _extrasRe = RegExp(
  r'^(sample|samples|extras?|subs?|subtitles?|featurettes?|scoped_dir.*)$',
  caseSensitive: false,
);
bool isExtrasFolder(String name) => _extrasRe.hasMatch(name.trim());

class TitleInfo {
  const TitleInfo({
    required this.name,
    this.year,
    this.yearEnd,
    this.quality,
    this.tags = const [],
  });
  final String name;
  final int? year;
  final int? yearEnd;
  final int? quality;
  final List<String> tags;
}

final _yearFrom = 1900;
final _yearTo = DateTime.now().year + 1;
bool _plausible(int y) => y >= _yearFrom && y <= _yearTo;

// (2010) [2010] ( 2012) (2013 …  and  TV Series 2013–2022 / 2024– / TV Mini Series 2021
final _yearRes = <RegExp>[
  RegExp(
    r'TV (?:Mini )?(?:Series|Documentary|Movie|Special)\s+(\d{4})(?:\s*[–-]\s*(\d{4}))?',
  ),
  RegExp(r'[\(\[]\s*(\d{4})(?:\s*[–-]\s*(\d{4}))?\s*[\)\]]'),
  RegExp(r'[\(\[]\s*(\d{4})\b'), // unclosed: "(2013 (Hindi Dubbed)"
  RegExp(r'\b(\d{4})\s*\)'), // missing opener: "2014)"
  RegExp(
    r'\b((?:19|20)\d{2})\b(?=\s+\d{3,4}p|\s*$)',
  ), // bare: "Out of Sight 1998 720p"
  // last resort, needs text before it: "Fighter 2011 DvDRip", "Aadhavan-2009.Tamil"
  RegExp(r'(?<=[A-Za-z][\s._-])((?:19|20)\d{2})(?![A-Za-z0-9])'),
];

(int?, int?) parseYear(String s) {
  for (final re in _yearRes) {
    for (final m in re.allMatches(s)) {
      final y = int.parse(m[1]!);
      if (!_plausible(y)) continue;
      int? e;
      if (m.groupCount >= 2 && m[2] != null) {
        final ey = int.parse(m[2]!);
        if (_plausible(ey)) e = ey;
      }
      return (y, e);
    }
  }
  return (null, null);
}

int? parseQuality(String s) {
  final m = RegExp(
    r'\b(2160|1080|720|576|480|360)p\b',
    caseSensitive: false,
  ).firstMatch(s);
  if (m != null) return int.parse(m[1]!);
  if (RegExp(r'\b4K\b').hasMatch(s)) return 2160;
  return null;
}

List<String> parseTags(String s) {
  final t = <String>[];
  void add(String tag, RegExp re) {
    if (re.hasMatch(s)) t.add(tag);
  }

  add(
    'dual-audio',
    RegExp(r'dual[\s._-]*(audio|language)', caseSensitive: false),
  );
  add('hindi-dubbed', RegExp(r'hindi[\s._-]*dubbed', caseSensitive: false));
  add('hevc', RegExp(r'\b(x265|hevc|h\.?265)\b', caseSensitive: false));
  add('3d', RegExp(r'\b3D\b'));
  add('esub', RegExp(r'\b[em]?subs?\b', caseSensitive: false));
  return t;
}

/// Title folder name -> clean title + year/quality/tags.
TitleInfo parseTitleFolder(String folder) {
  final (y, ye) = parseYear(folder);
  var name = folder;
  name = name.replaceAll(
    RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'),
    ' ',
  ); // bracket groups
  name = name.replaceAll(RegExp(r'\s*\((?:[^)]*)$'), ' '); // unclosed "(2013 …"
  name = name.replaceAll(
    RegExp(r'\b(2160|1080|720|576|480|360)p\b.*$', caseSensitive: false),
    ' ',
  );
  name = name.replaceAll(RegExp(r'\s+(?:19|20)\d{2}\s*\)?\s*$'), ' ');
  name = name.replaceAll(RegExp(r'\s+(?:19|20)\d{2}\s*\)?(?=\s|$)'), ' ');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty) name = folder.trim();
  return TitleInfo(
    name: name,
    year: y,
    yearEnd: ye,
    quality: parseQuality(folder),
    tags: parseTags(folder),
  );
}

class SeasonInfo {
  const SeasonInfo({required this.number, this.language, required this.label});
  final int number; // 0 = specials
  final String? language;
  final String label;
}

final _langRe = RegExp(
  r'\(?\[?\s*(Hindi|English|Chinese|Spanish|Japanese|German|Danish|Turkish|French|Italian|Norwegian|Finnish|Dutch|Thai|Hebrew|Icelandic|Korean|Bengali|Bangla|Tamil|Telugu|Russian|Swedish|Polish|Arabic|Portuguese)\b[^\)\]]*[\)\]]?',
  caseSensitive: false,
);

/// Season folder name -> number (+ language). Null when it isn't a season folder.
SeasonInfo? parseSeasonFolder(String folder) {
  final f = folder.trim();
  if (RegExp(
    r'^(specials?|spesial|special\b.*|specials?\s*&.*|ovas?\b.*|onas?\b.*)$',
    caseSensitive: false,
  ).hasMatch(f)) {
    return SeasonInfo(number: 0, label: f);
  }
  final m = RegExp(
    r'(?:season|seazon|ssason|series|\bS)\s*[-._]?\s*(\d{1,3})\b',
    caseSensitive: false,
  ).firstMatch(f);
  if (m == null) return null;
  String? lang;
  final l = _langRe.firstMatch(f.substring(m.end));
  if (l != null) {
    lang = RegExp(r'[A-Za-z]+').firstMatch(l[0]!)![0]!.toLowerCase();
  }
  return SeasonInfo(number: int.parse(m[1]!), language: lang, label: f);
}

class EpisodeInfo {
  const EpisodeInfo({this.season, this.episode, this.episodeEnd});
  final int? season;
  final int? episode;
  final int? episodeEnd;
}

const _nb = r'(?<![A-Za-z0-9])'; // underscore-safe "word boundary"

/// Episode file name -> season/episode (range-aware). Order of rules matters.
EpisodeInfo parseEpisode(String file) {
  final n = file.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '');
  // S01E01, S01 E01-E05, S01E01E02, S01.E01-E05, s01x06
  var m = RegExp(
    '${_nb}S(\\d{1,3})[\\s._-]*[Ex](\\d{1,4})(?:(?:\\s*(?:-|–|to)\\s*E?|\\s*E)(\\d{1,4}))?',
    caseSensitive: false,
  ).firstMatch(n);
  if (m != null) {
    final a = int.parse(m[2]!);
    final b = m[3] == null ? null : int.parse(m[3]!);
    return EpisodeInfo(
      season: int.parse(m[1]!),
      episode: a,
      episodeEnd: (b != null && b > a) ? b : null,
    );
  }
  // 3x21
  m = RegExp('$_nb(\\d{1,2})x(\\d{2,3})(?![A-Za-z0-9])').firstMatch(n);
  if (m != null) {
    return EpisodeInfo(season: int.parse(m[1]!), episode: int.parse(m[2]!));
  }
  // Episode 178 / Ep 12 / E012
  m = RegExp(
    '$_nb(?:Episode|Ep|E)[\\s._-]*(\\d{1,4})(?![A-Za-z0-9])',
    caseSensitive: false,
  ).firstMatch(n);
  if (m != null) return EpisodeInfo(episode: int.parse(m[1]!));
  final b = _bareNumber(n);
  return b == null ? const EpisodeInfo() : EpisodeInfo(episode: b);
}

/// Last-resort: "Show - 442", "Show 04", "05 Show", "Show_-_43_(10bit)".
/// Strips tags first so resolution/codec/year numbers are never picked.
int? _bareNumber(String name) {
  var t = name
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ')
      .replaceAll('_', ' ');
  t = t.replaceAll(
    RegExp(
      r'\b(\d{3,4}p|x26[45]|h\.?26[45]|hevc|\d+\s?bit|[257]\.[01]|aac|ac3|dts|ddp?\d?|web-?dl|web-?rip|bluray|brrip|dvdrip|hdtv|kor|hindi|eng|sub|dub)\b',
      caseSensitive: false,
    ),
    ' ',
  );
  t = t.replaceAll(RegExp(r'\b(?:19|20)\d{2}\b'), ' ');
  t = t.replaceAll(RegExp(r'[._]'), ' ');
  final nums = RegExp(r'(?<![A-Za-z0-9-])(\d{1,4})(?![A-Za-z0-9])')
      .allMatches(t)
      .toList();
  if (nums.isEmpty) return null;
  // Prefer a number set off by " - ".
  for (final x in nums) {
    final before = t.substring(0, x.start).trimRight();
    if (before.endsWith('-')) return int.parse(x[1]!);
  }
  return int.parse(nums.last[1]!);
}
