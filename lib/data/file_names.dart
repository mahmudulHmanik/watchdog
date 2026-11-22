/// Derivations from stored relative paths (schema v3 stores no name/ext/
/// playable and no absolute urls). Pure; no IO.
library;

/// Extensions the player can open. Keep in sync with `videoExts` in
/// lib/crawler/parsing.dart (test/data/file_names_test.dart checks it).
const playableExts = {
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

/// Decoded last path segment of [rel] (trailing slash ignored). Falls back to
/// the raw segment when it is not valid percent-encoding.
String nameOfRel(String rel) {
  var end = rel.length;
  while (end > 0 && rel.codeUnitAt(end - 1) == 0x2f) {
    end--;
  }
  if (end == 0) return '';
  final raw = rel.substring(rel.lastIndexOf('/', end - 1) + 1, end);
  try {
    return Uri.decodeComponent(raw);
  } on ArgumentError {
    return raw;
  }
}

/// Lower-case extension of a file name without the dot, '' when none.
String extOfName(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

bool isPlayableExt(String ext) => playableExts.contains(ext);

/// [url] relative to [base]; a url that is not under [base] is kept absolute
/// (never happens with real listings; keeps sloppy callers working).
String relativeTo(String base, String url) =>
    url.startsWith(base) ? url.substring(base.length) : url;

bool _isAbsolute(String s) =>
    s.startsWith('http://') || s.startsWith('https://');

/// Inverse of [relativeTo]; an absolute [rel] is returned as is.
String composeUrl(String base, String rel) =>
    _isAbsolute(rel) ? rel : '$base$rel';
