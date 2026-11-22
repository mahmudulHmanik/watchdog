import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:watchdog/platform/platform_api.dart' show kImageCacheDirName;

/// Hard cap on cached images.
const kImageCacheMaxObjects = 1500;

/// Images unused for this long are dropped.
const kImageCacheStalePeriod = Duration(days: 60);

/// Tiny LRU file cache for poster/backdrop/profile images: one file per URL
/// (sha1 name) in [dir]; recency = file mtime. At most [maxObjects] files
/// (checked after every write, evicts oldest-used first) and none older than
/// [stalePeriod]. Never throws: a failure just means "not cached".
///
/// In-house instead of flutter_cache_manager 3.5.0 (verified on pub.dev: only
/// maxNrOfCacheObjects + stalePeriod, no byte cap, adds sqflite on mobile): one
/// small class, no native plugin, strict cap, and the dir is trivially
/// measurable/clearable by the Storage settings.
class ImageStore {
  ImageStore({
    required Future<Directory?> Function() dir,
    http.Client? client,
    this.maxObjects = kImageCacheMaxObjects,
    this.stalePeriod = kImageCacheStalePeriod,
    this.maxBytesPerImage = 8 << 20,
    this.timeout = const Duration(seconds: 15),
    this.parallel = 6,
    DateTime Function()? now,
  }) : _dirFn = dir,
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final Future<Directory?> Function() _dirFn;
  final http.Client _client;
  final int maxObjects, maxBytesPerImage, parallel;
  final Duration stalePeriod, timeout;
  final DateTime Function() _now;

  Directory? _dir;
  int? _count;
  bool _trimming = false;
  final _inflight = <String, Future<File?>>{};
  final _failedAt = <String, DateTime>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;

  /// Resolved cache dir once known (sync lookups before that miss).
  Directory? get dirIfKnown => _dir;

  Future<Directory?> _ensureDir() async {
    if (_dir != null) return _dir;
    try {
      final d = await _dirFn();
      if (d == null) return null;
      _dir = d;
    } catch (_) {}
    return _dir;
  }

  /// Warms the dir lookup so [peek] works synchronously afterwards.
  Future<void> init() async {
    await _ensureDir();
  }

  String _name(String url) => sha1.convert(url.codeUnits).toString();

  /// Where [url] is (or would be) stored; null until the dir is known.
  File? fileFor(String url) {
    final d = _dir;
    return d == null ? null : File('${d.path}/${_name(url)}');
  }

  /// Cached file for [url] if present and fresh, else null. Sync (one stat);
  /// marks it as just used.
  File? peek(String url) {
    final f = fileFor(url);
    if (f == null) return null;
    try {
      final st = f.statSync();
      if (st.type != FileSystemEntityType.file || st.size == 0) return null;
      final age = _now().difference(st.modified);
      if (age > stalePeriod) {
        try {
          f.deleteSync();
        } catch (_) {}
        return null;
      }
      // Refresh recency at most hourly (keeps scrolling cheap).
      if (age > const Duration(hours: 1)) {
        try {
          f.setLastModifiedSync(_now());
        } catch (_) {}
      }
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Cached file, downloading it first when missing. Null when offline,
  /// failing, or too large. Failures are remembered for 60 s (no retry storms
  /// while offline). Concurrent calls for one URL share a single download.
  Future<File?> fetch(
    String url,
  ) => _inflight[url] ??= _fetch(url).whenComplete(() {
    // Block body: returning the removed future would make it wait on itself.
    _inflight.remove(url);
  });

  Future<File?> _fetch(String url) async {
    await _ensureDir();
    final hit = peek(url);
    if (hit != null) return hit;
    final failed = _failedAt[url];
    if (failed != null &&
        _now().difference(failed) < const Duration(seconds: 60)) {
      return null;
    }
    return _download(url);
  }

  Future<void> _slot() async {
    if (_active < parallel) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }

  Future<File?> _download(String url) async {
    await _slot();
    try {
      final dir = await _ensureDir();
      if (dir == null) return null;
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) return null;
      final res = await _client.get(uri).timeout(timeout);
      final ct = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 ||
          res.bodyBytes.isEmpty ||
          res.bodyBytes.length > maxBytesPerImage ||
          (ct.isNotEmpty && !ct.startsWith('image/'))) {
        _failedAt[url] = _now();
        return null;
      }
      await dir.create(recursive: true);
      final f = File('${dir.path}/${_name(url)}');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(res.bodyBytes, flush: false);
      await tmp.rename(f.path);
      _failedAt.remove(url);
      unawaited(_afterWrite(f));
      return f;
    } catch (e) {
      _failedAt[url] = _now();
      if (_failedAt.length > 2000) _failedAt.clear();
      return null;
    } finally {
      _release();
    }
  }

  Future<void> _afterWrite(File written) async {
    try {
      final c = _count;
      if (c == null || c + 1 > maxObjects) {
        await trim(keep: written.path);
      } else {
        _count = c + 1;
      }
    } catch (e) {
      debugPrint('image cache trim failed: $e');
    }
  }

  /// Drops stale files, then the least recently used until at most
  /// [maxObjects] remain (down to 95 % so it does not rescan on every write).
  /// [keep] is never evicted.
  Future<int> trim({String? keep}) async {
    final dir = _dir;
    if (dir == null || _trimming) return _count ?? 0;
    _trimming = true;
    try {
      if (!dir.existsSync()) return _count = 0;
      final live = <(File, DateTime)>[];
      final cutoff = _now().subtract(stalePeriod);
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! File) continue;
        final m = e.statSync().modified;
        if (e.path.endsWith('.tmp')) {
          // Leftover of an interrupted write; spare one that may be in flight.
          if (_now().difference(m) > const Duration(minutes: 10)) {
            try {
              e.deleteSync();
            } catch (_) {}
          }
        } else if (m.isAfter(cutoff)) {
          live.add((e, m));
        } else if (e.path != keep) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
      if (live.length > maxObjects) {
        live.sort((a, b) {
          final c = a.$2.compareTo(b.$2);
          return c != 0 ? c : a.$1.path.compareTo(b.$1.path);
        });
        final target = maxObjects - maxObjects ~/ 20;
        var n = live.length;
        for (final (f, _) in live) {
          if (n <= target) break;
          if (f.path == keep) continue;
          try {
            f.deleteSync();
            n--;
          } catch (_) {}
        }
        return _count = n;
      }
      return _count = live.length;
    } finally {
      _trimming = false;
    }
  }

  /// Number of cached files on disk (rescans).
  Future<int> count() async {
    await _ensureDir();
    final d = _dir;
    if (d == null || !d.existsSync()) return 0;
    return d.listSync().whereType<File>().length;
  }

  /// Deletes every cached file.
  Future<void> clear() async {
    final d = await _ensureDir();
    _count = 0;
    _failedAt.clear();
    if (d == null || !d.existsSync()) return;
    for (final e in d.listSync()) {
      try {
        e.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  void dispose() => _client.close();
}

/// `<cache dir>/image_cache`; null when the platform has no cache dir.
Future<Directory?> defaultImageCacheDir() async {
  try {
    return Directory(
      '${(await getTemporaryDirectory()).path}/$kImageCacheDirName',
    );
  } catch (_) {
    return null;
  }
}

final imageStoreProvider = Provider<ImageStore>((ref) {
  final s = ImageStore(dir: defaultImageCacheDir);
  unawaited(s.init());
  ref.onDispose(s.dispose);
  return s;
});
