import 'dart:io';

import 'package:path/path.dart' as p;

import 'platform_api.dart';

enum ExternalPlayerError {
  /// No installed app/binary can play the media.
  noPlayer,

  /// Local path rejected (outside the downloads dir, `..`, missing file).
  invalidPath,

  /// The file exists in an allowed folder but cannot be shared with another
  /// app (e.g. outside the Android FileProvider paths).
  unsupportedLocation,

  /// The launch itself failed (see [ExternalPlayerException.message]).
  launchFailed,
}

/// Typed failure from [PlatformApi.openExternal]; the UI can switch on [error].
class ExternalPlayerException implements Exception {
  const ExternalPlayerException(this.error, [this.message]);
  final ExternalPlayerError error;
  final String? message;

  /// Short text suitable for a snackbar.
  String get userMessage => switch (error) {
    ExternalPlayerError.noPlayer => 'No player installed',
    ExternalPlayerError.unsupportedLocation =>
      'This download location cannot be opened by other apps',
    ExternalPlayerError.invalidPath => 'File not found or not allowed',
    ExternalPlayerError.launchFailed => 'Could not open player',
  };

  @override
  String toString() => 'ExternalPlayerException($error, $message)';
}

/// Builds an extended m3u playlist. Newlines in titles are collapsed so a
/// title can never inject a playlist entry.
String buildM3u(List<ExternalMedia> items) {
  final b = StringBuffer('#EXTM3U\n');
  for (final m in items) {
    final title = m.title.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    b
      ..write('#EXTINF:-1,')
      ..write(title)
      ..write('\n')
      ..write(m.url)
      ..write('\n');
  }
  return b.toString();
}

/// Returns the normalized absolute [path] if it is a file path strictly inside
/// [root] and contains no `..` segment; otherwise throws
/// [ExternalPlayerError.invalidPath]. Does not touch the filesystem.
String validateLocalPath(String path, String root) {
  const bad = ExternalPlayerError.invalidPath;
  if (path.isEmpty || path.contains('\u0000')) {
    throw const ExternalPlayerException(bad, 'empty path');
  }
  if (!p.isAbsolute(path)) {
    throw ExternalPlayerException(bad, 'not absolute: $path');
  }
  if (p.split(path).contains('..')) {
    throw ExternalPlayerException(bad, 'contains ..: $path');
  }
  final norm = p.normalize(path);
  if (!p.isWithin(p.normalize(root), norm)) {
    throw ExternalPlayerException(bad, 'outside downloads dir: $path');
  }
  return norm;
}

const _videoMimes = {
  '.mkv': 'video/x-matroska',
  '.mp4': 'video/mp4',
  '.m4v': 'video/x-m4v',
  '.webm': 'video/webm',
  '.avi': 'video/x-msvideo',
  '.mov': 'video/quicktime',
  '.wmv': 'video/x-ms-wmv',
  '.flv': 'video/x-flv',
  '.ts': 'video/mp2t',
  '.mpg': 'video/mpeg',
  '.mpeg': 'video/mpeg',
  '.3gp': 'video/3gpp',
};

/// MIME type from the file extension; falls back to `video/*`.
String inferVideoMime(String path) =>
    _videoMimes[p.extension(path).toLowerCase()] ?? 'video/*';

/// Symlink-safe check: [path] must exist and its real (resolved) location must
/// lie strictly inside the real location of one of [roots] (roots that do not
/// exist are ignored). Lexical rules of [validateLocalPath] apply first.
/// Returns the real path and the real root that contains it.
Future<({String path, String root})> resolveLocalPath(
  String path,
  List<String> roots,
) async {
  const bad = ExternalPlayerError.invalidPath;
  final lexical = <String>[];
  for (final r in roots) {
    try {
      validateLocalPath(path, r);
      lexical.add(r);
    } on ExternalPlayerException {
      // try next root
    }
  }
  if (lexical.isEmpty) {
    // Re-run against the first root for a precise message.
    if (roots.isEmpty) {
      throw const ExternalPlayerException(bad, 'no download folders known');
    }
    validateLocalPath(path, roots.first);
    throw ExternalPlayerException(bad, 'outside download folders: $path');
  }
  final String real;
  try {
    real = await File(path).resolveSymbolicLinks();
  } on FileSystemException {
    throw ExternalPlayerException(bad, 'missing: $path');
  }
  if (FileSystemEntity.typeSync(real) != FileSystemEntityType.file) {
    throw ExternalPlayerException(bad, 'not a file: $path');
  }
  for (final r in roots) {
    final String realRoot;
    try {
      realRoot = await Directory(r).resolveSymbolicLinks();
    } on FileSystemException {
      continue;
    }
    if (p.isWithin(realRoot, real)) return (path: real, root: realRoot);
  }
  throw ExternalPlayerException(
    bad,
    'resolves outside download folders: $path',
  );
}
