/// Pure-Dart track helpers: language matching for the preferred-audio setting
/// and display labels. Operates on plain strings so tests need no media_kit.
library;

/// Canonical language -> aliases (ISO 639-1, 639-2/B, 639-2/T, English and
/// native names). First entry is the canonical ISO 639-2 code.
const _languages = <List<String>>[
  ['eng', 'en', 'english'],
  ['hin', 'hi', 'hindi'],
  ['ben', 'bn', 'bengali', 'bangla'],
  ['tam', 'ta', 'tamil'],
  ['tel', 'te', 'telugu'],
  ['mal', 'ml', 'malayalam'],
  ['kan', 'kn', 'kannada'],
  ['mar', 'mr', 'marathi'],
  ['pan', 'pa', 'punjabi'],
  ['urd', 'ur', 'urdu'],
  ['jpn', 'ja', 'jp', 'japanese'],
  ['kor', 'ko', 'korean'],
  ['zho', 'zh', 'chi', 'cmn', 'chinese', 'mandarin'],
  ['spa', 'es', 'spanish'],
  ['fra', 'fr', 'fre', 'french'],
  ['deu', 'de', 'ger', 'german'],
  ['ita', 'it', 'italian'],
  ['por', 'pt', 'portuguese'],
  ['rus', 'ru', 'russian'],
  ['ara', 'ar', 'arabic'],
  ['tha', 'th', 'thai'],
  ['tur', 'tr', 'turkish'],
  ['ind', 'id', 'indonesian'],
];

final _alias = <String, String>{
  for (final l in _languages)
    for (final a in l) a: l.first,
};

/// Canonical ISO 639-2 code for a code/name, or the lower-cased input when
/// unknown. Null for null/empty/`und`.
String? canonicalLanguage(String? s) {
  final k = s?.trim().toLowerCase();
  if (k == null || k.isEmpty || k == 'und' || k == 'unknown') return null;
  return _alias[k] ?? k;
}

/// Languages of the common choices, for a settings picker: (code, label).
const preferredLanguageChoices = <(String, String)>[
  ('eng', 'English'),
  ('hin', 'Hindi'),
  ('ben', 'Bengali'),
  ('tam', 'Tamil'),
  ('tel', 'Telugu'),
  ('jpn', 'Japanese'),
  ('kor', 'Korean'),
];

/// Does a track with [language] tag / [title] match the [preferred] language
/// (any code or name)? The language tag wins; the title is matched as whole
/// words ("Hindi 2.0", "English 5.1") so dual-audio labels work when the tag
/// is missing or `und`.
bool trackMatchesLanguage(String? language, String? title, String preferred) {
  final want = canonicalLanguage(preferred);
  if (want == null) return false;
  final tag = canonicalLanguage(language);
  if (tag != null) return tag == want;
  if (title == null) return false;
  final words = title.toLowerCase().split(RegExp(r'[^a-z]+'));
  return words.any((w) => w.isNotEmpty && _alias[w] == want);
}

/// Index of the first entry matching [preferred], else null. [candidates] are
/// (language, title) pairs for real tracks only (no auto/no pseudo tracks).
int? pickPreferredIndex(
  List<(String? language, String? title)> candidates,
  String? preferred,
) {
  if (preferred == null) return null;
  for (var i = 0; i < candidates.length; i++) {
    if (trackMatchesLanguage(candidates[i].$1, candidates[i].$2, preferred)) {
      return i;
    }
  }
  return null;
}

/// Human language name for a code, e.g. `hi` -> `Hindi`; falls back to the
/// upper-cased code, null when unknown/und.
String? languageName(String? code) {
  final c = canonicalLanguage(code);
  if (c == null) return null;
  for (final l in _languages) {
    if (l.first == c) return l.last[0].toUpperCase() + l.last.substring(1);
  }
  return c.toUpperCase();
}

/// mpv channel layout (`stereo`, `5.1(side)`, `unknown6`) -> `2.0`/`5.1`/...
String? channelLabel(String? layout, int? count) {
  final l = layout?.toLowerCase();
  if (l != null) {
    if (l == 'mono') return '1.0';
    if (l == 'stereo') return '2.0';
    final m = RegExp(r'^(\d)\.(\d)').firstMatch(l);
    if (m != null) return '${m[1]}.${m[2]}';
    final u = RegExp(r'^unknown(\d+)$').firstMatch(l);
    if (u != null) return _byCount(int.parse(u[1]!));
  }
  return count == null ? null : _byCount(count);
}

String? _byCount(int n) => switch (n) {
  1 => '1.0',
  2 => '2.0',
  6 => '5.1',
  8 => '7.1',
  _ => n > 0 ? '${n}ch' : null,
};

/// Title text worth showing: drops empty values and release-group noise is
/// left to the caller (shown as secondary text).
String? cleanTitle(String? t) {
  final s = t?.trim();
  return s == null || s.isEmpty ? null : s;
}

/// Short codec label for the right-aligned meta column ("AC3", "SRT").
String? codecLabel(String? codec) {
  final c = codec?.toLowerCase();
  if (c == null || c.isEmpty) return null;
  return switch (c) {
    'subrip' => 'SRT',
    'webvtt' => 'VTT',
    'mov_text' => 'TX3G',
    'hdmv_pgs_subtitle' => 'PGS',
    'dvd_subtitle' => 'VOBSUB',
    'eac3' => 'E-AC3',
    'h264' => 'H.264',
    _ => c.toUpperCase(),
  };
}

/// Meta text from codec + channels + resolution, e.g. `AC3 5.1`, `H.264 1280x720`.
String trackMeta({
  String? codec,
  String? channels,
  int? channelCount,
  int? w,
  int? h,
}) => [
  ?codecLabel(codec),
  ?channelLabel(channels, channelCount),
  if (w != null && h != null && w > 0 && h > 0) '${w}x$h',
].join(' ');

/// Display names for one group: language name (or `Track n`); the track title
/// is appended only when titles differ inside the group (a title shared by
/// all tracks, like a release-group tag, is noise).
List<String> trackNames(List<(String? language, String? title)> tracks) {
  final titles = {for (final t in tracks) cleanTitle(t.$2)};
  final useTitle = titles.length > 1;
  return [
    for (var i = 0; i < tracks.length; i++)
      [
        languageName(tracks[i].$1) ?? 'Track ${i + 1}',
        if (useTitle && cleanTitle(tracks[i].$2) != null)
          '(${cleanTitle(tracks[i].$2)})',
      ].join(' '),
  ];
}

/// mpv reports `auto` in media_kit's `state.track` even after it picked a
/// concrete track (verified against libmpv 0.41: state.track.audio.id=auto
/// while mpv aid=1). Resolve the id to show as selected: an explicit id is
/// kept; `no` stays off; `auto` resolves to the default-flagged track, else
/// the first one for audio/video ([autoPicksFirst]) or Off (null) for subs.
String? effectiveTrackId(
  List<(String id, bool? isDefault)> real,
  String selectedId, {
  required bool autoPicksFirst,
}) {
  if (selectedId == 'no') return null;
  if (selectedId != 'auto') return selectedId;
  for (final t in real) {
    if (t.$2 == true) return t.$1;
  }
  return autoPicksFirst && real.isNotEmpty ? real.first.$1 : null;
}
