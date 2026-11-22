/// Readable names for common TMDB original-language ISO 639-1 codes.
const _languageNames = {
  'en': 'English',
  'hi': 'Hindi',
  'bn': 'Bengali',
  'ko': 'Korean',
  'ja': 'Japanese',
  'ta': 'Tamil',
  'te': 'Telugu',
  'fr': 'French',
  'es': 'Spanish',
  'zh': 'Chinese',
  'ml': 'Malayalam',
  'kn': 'Kannada',
  'mr': 'Marathi',
  'pa': 'Punjabi',
  'ur': 'Urdu',
  'de': 'German',
  'it': 'Italian',
  'ru': 'Russian',
  'pt': 'Portuguese',
  'th': 'Thai',
  'tr': 'Turkish',
  'ar': 'Arabic',
  'cn': 'Cantonese',
};

/// `hi` -> `Hindi`; unknown codes are returned as given.
String tmdbLanguageName(String code) => _languageNames[code] ?? code;

/// Minimum-rating presets for the Rating sheet (0 = any).
const ratingPresets = <double>[0, 6, 7, 8];

String ratingLabel(double v) => v <= 0 ? 'Any' : '${v.toStringAsFixed(0)}+';

String titleCountLabel(int n) => n == 1 ? '1 title' : '$n titles';

/// Up to two initials of [name] (`Tom Hanks` -> `TH`).
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final list = parts.toList();
  if (list.isEmpty) return '?';
  final a = String.fromCharCode(list.first.runes.first).toUpperCase();
  if (list.length == 1) return a;
  return a + String.fromCharCode(list.last.runes.first).toUpperCase();
}
