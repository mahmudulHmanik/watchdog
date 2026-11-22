import 'dart:async';
import 'dart:io';

import '../../platform/platform_api.dart';
import 'download_backend.dart';

/// Filesystem limit is 255 bytes; reserve room for the ' (999)' collision
/// suffix added by [uniqueFilename].
const _maxNameBytes = 255 - 6;

final _extender = RegExp(
  r'^[\p{M}\u200D\uFE0F\u{1F3FB}-\u{1F3FF}]$',
  unicode: true,
);
bool _isExtender(int rune) => _extender.hasMatch(String.fromCharCode(rune));

int _utf8Len(int r) => r < 0x80
    ? 1
    : r < 0x800
    ? 2
    : r < 0x10000
    ? 3
    : 4;

/// Truncates [s] to [_maxNameBytes] UTF-8 bytes on rune boundaries without
/// splitting a combining sequence / ZWJ cluster, keeping a short extension.
String _fitBytes(String s) {
  int bytes(List<int> r) => r.fold(0, (a, c) => a + _utf8Len(c));
  final all = s.runes.toList();
  if (bytes(all) <= _maxNameBytes) return s;
  final dot = s.lastIndexOf('.');
  final ext = dot > 0 && s.length - dot <= 10 ? s.substring(dot) : '';
  final extBytes = bytes(ext.runes.toList());
  final base = (ext.isEmpty ? s : s.substring(0, dot)).runes.toList();
  var budget = _maxNameBytes - extBytes, used = 0, n = 0;
  while (n < base.length && used + _utf8Len(base[n]) <= budget) {
    used += _utf8Len(base[n++]);
  }
  if (n < base.length && _isExtender(base[n])) {
    // Cut falls inside a cluster: drop the whole partial cluster.
    while (n > 0 && _isExtender(base[n - 1])) {
      n--;
    }
    if (n > 0) n--;
  }
  while (n > 0 && base[n - 1] == 0x200D) {
    n--;
  }
  if (n == 0) return 'download$ext';
  return String.fromCharCodes(base.sublist(0, n)) + ext;
}

/// Strips path separators/control characters, keeps unicode, avoids empty,
/// dot-only and over-long names (255 bytes budget, extension preserved).
String sanitizeFilename(String name) {
  var s = name
      .replaceAll(RegExp(r'[\\/\x00-\x1f\x7f]'), '_')
      .replaceAll(RegExp(r'[<>:"|?*]'), '_')
      .trim();
  s = s.replaceAll(RegExp(r'^\.+'), '_');
  s = s.replaceAll(RegExp(r'[. ]+$'), '');
  if (s.isEmpty) s = 'download';
  s = _fitBytes(s);
  return s;
}

/// `name.ext` -> `name (1).ext`, `name (2).ext`, ... until not in [taken]
/// (compared case-sensitively; callers pass what they know exists).
String uniqueFilename(String name, bool Function(String) isTaken) {
  if (!isTaken(name)) return name;
  final dot = name.lastIndexOf('.');
  final hasExt = dot > 0;
  final base = hasExt ? name.substring(0, dot) : name;
  final ext = hasExt ? name.substring(dot) : '';
  for (var i = 1; ; i++) {
    final c = '$base ($i)$ext';
    if (!isTaken(c)) return c;
  }
}

/// Download queue logic over a [DownloadBackend].
class DownloadManager {
  DownloadManager({
    required this.backend,
    required Future<String> Function() defaultDirectory,
    bool Function(String path)? fileExists,
    Future<void> Function(String path)? deleteFile,
  }) : _defaultDir = defaultDirectory,
       _exists = fileExists ?? ((p) => File(p).existsSync()),
       _delete =
           deleteFile ??
           ((p) async {
             final f = File(p);
             if (f.existsSync()) await f.delete();
           });

  final DownloadBackend backend;
  final Future<String> Function() _defaultDir;
  final bool Function(String) _exists;
  final Future<void> Function(String) _delete;

  Future<void>? _started;
  Future<void> _ensureStarted() => _started ??= backend.start();

  /// Stops listening to the engine; the manager is unusable afterwards.
  Future<void> dispose() => backend.dispose();

  Future<String> defaultDirectory() => _defaultDir();

  Stream<DownloadProgress> get updates async* {
    await _ensureStarted();
    yield* backend.updates;
  }

  Future<List<DownloadProgress>> downloads() async {
    await _ensureStarted();
    return backend.records();
  }

  Future<String> enqueue(
    String url,
    String filename, {
    int? fileId,
    String? directory,
  }) async {
    await _ensureStarted();
    final dir = directory ?? await _defaultDir();
    // Names already claimed by unfinished or finished downloads in this dir.
    final claimed = <String>{
      for (final r in await backend.records())
        if (r.filePath != null &&
            r.state != DownloadState.canceled &&
            r.state != DownloadState.failed &&
            File(r.filePath!).parent.path == dir)
          r.filename,
    };
    final name = uniqueFilename(
      sanitizeFilename(filename),
      (n) => claimed.contains(n) || _exists('$dir/$n'),
    );
    final id = await backend.enqueue(
      DownloadSpec(url: url, filename: name, directory: dir, fileId: fileId),
    );
    if (id == null) {
      throw StateError('Download engine refused to enqueue $name');
    }
    return id;
  }

  Future<void> pause(String id) async {
    await _ensureStarted();
    if (!await backend.pause(id)) {
      throw StateError('Cannot pause $id (finished, or server lacks Range)');
    }
  }

  Future<void> resume(String id) async {
    await _ensureStarted();
    if (!await backend.resume(id)) {
      throw StateError('Cannot resume $id');
    }
  }

  Future<void> cancel(String id) async {
    await _ensureStarted();
    await backend.cancel(id);
  }

  Future<void> remove(String id, {bool deleteFile = false}) async {
    await _ensureStarted();
    final rec = (await backend.records()).where((r) => r.id == id).firstOrNull;
    if (rec != null &&
        (rec.state == DownloadState.running ||
            rec.state == DownloadState.queued ||
            rec.state == DownloadState.paused)) {
      await backend.cancel(id);
    }
    await backend.deleteRecord(id);
    if (deleteFile && rec?.filePath != null) await _delete(rec!.filePath!);
  }
}
