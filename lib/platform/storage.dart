import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import 'platform_api.dart';

/// Native helper channel (Android only), see MainActivity.kt.
const storageChannel = MethodChannel('dev.watchdog/storage');

/// Sub-folders of the app cache dir that make up the "player cache": copies of
/// subtitle files made by the Android file picker, external-player playlists,
/// and `player` (reserved). mpv's own demuxer cache lives in RAM
/// (`cache-on-disk` is never enabled).
const playerCacheDirNames = ['file_picker', 'm3u', 'player'];

/// Total size of the regular files under [d] (0 if it does not exist).
int dirBytes(Directory d) {
  var n = 0;
  try {
    if (!d.existsSync()) return 0;
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          n += e.lengthSync();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return n;
}

/// Deletes the files (and sub-folders left empty) under [d], skipping the
/// absolute paths in [keep]. Returns the number of files removed.
int emptyDir(Directory d, {Set<String> keep = const {}}) {
  var n = 0;
  try {
    if (!d.existsSync()) return 0;
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File && !keep.contains(e.path)) {
        try {
          e.deleteSync();
          n++;
        } catch (_) {}
      }
    }
    // Remove folders that are now empty (deepest first).
    final dirs =
        d
            .listSync(recursive: true, followLinks: false)
            .whereType<Directory>()
            .toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final s in dirs) {
      try {
        if (s.listSync().isEmpty) s.deleteSync();
      } catch (_) {}
    }
  } catch (_) {}
  return n;
}

/// Measures and clears the app's storage. Directories are injected so tests
/// can use temp folders.
class StorageOps {
  StorageOps({
    required this.supportDir,
    required this.cacheDir,
    required this.downloadDirs,
    this.freeBytes,
    bool? android,
    MethodChannel? channel,
  }) : _android = android ?? Platform.isAndroid,
       _channel = channel ?? storageChannel;

  /// App support dir (holds `watchdog.db`).
  final Future<Directory> Function() supportDir;

  /// App cache dir (holds the image cache and player temp files).
  final Future<Directory> Function() cacheDir;

  /// Folders downloads live in: the default download folder, plus on Android
  /// the shared `Movies/watchdog` (used only when MediaStore cannot be queried).
  final Future<List<Directory>> Function() downloadDirs;

  /// Free device space, when known (Android: StatFs via the channel).
  final Future<int?> Function()? freeBytes;
  final bool _android;
  final MethodChannel _channel;

  Future<int> _indexBytes() async {
    final dir = (await supportDir()).path;
    var n = 0;
    for (final suffix in const ['', '-wal', '-shm']) {
      try {
        final f = File('$dir/watchdog.db$suffix');
        if (f.existsSync()) n += f.lengthSync();
      } catch (_) {}
    }
    return n;
  }

  Future<int> _playerBytes() async {
    final c = (await cacheDir()).path;
    return [for (final n in playerCacheDirNames) dirBytes(Directory('$c/$n'))]
        .fold<int>(0, (a, b) => a + b);
  }

  /// Bytes MediaStore holds for this app's own files in `Movies/watchdog`
  /// (no permission needed: an app can always query what it owns). Null when
  /// unavailable (Android < 10, Linux, channel error).
  Future<int?> _mediaStoreBytes() async {
    if (!_android) return null;
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>(
        'downloadsUsage',
      );
      final b = m?['bytes'];
      return b is num ? b.toInt() : null;
    } catch (e) {
      debugPrint('MediaStore usage failed: $e');
      return null;
    }
  }

  Future<StorageUsage> usage() async {
    final dirs = await downloadDirs();
    final ms = await _mediaStoreBytes();
    // With MediaStore the shared folder is counted there; the rest (private
    // folder: partial / not yet moved downloads) by walking it.
    final walk = ms == null ? dirs : dirs.take(1);
    final downloads = (ms ?? 0) + walk.fold<int>(0, (a, d) => a + dirBytes(d));
    int? free;
    try {
      free = await freeBytes?.call();
    } catch (_) {}
    return StorageUsage(
      indexBytes: await _indexBytes(),
      imageCacheBytes: dirBytes(
        Directory('${(await cacheDir()).path}/$kImageCacheDirName'),
      ),
      playerCacheBytes: await _playerBytes(),
      downloadsBytes: downloads,
      freeBytes: free,
    );
  }

  Future<void> clearImageCache() async =>
      emptyDir(Directory('${(await cacheDir()).path}/$kImageCacheDirName'));

  Future<void> clearPlayerCache() async {
    final c = (await cacheDir()).path;
    for (final n in playerCacheDirNames) {
      emptyDir(Directory('$c/$n'));
    }
  }

  /// Removes leftover download files the records did not cover: on Android
  /// every MediaStore entry this app owns in `Movies/watchdog` (other apps'
  /// files are never touched: the query is filtered by owner and a delete of
  /// a foreign row is refused by the system), then files in the private
  /// download folder except [keep] (active downloads). Linux: the download
  /// folder except [keep]. Returns the number of files removed.
  Future<int> sweepDownloads({Set<String> keep = const {}}) async {
    var n = 0;
    final dirs = await downloadDirs();
    var viaMediaStore = false;
    if (_android) {
      try {
        final r = await _channel.invokeMethod<int>('deleteDownloads');
        if (r != null) {
          viaMediaStore = true;
          n += r;
        }
      } catch (e) {
        debugPrint('MediaStore delete failed: $e');
      }
    }
    // With MediaStore only the private folder (first) is walked; the shared
    // folder was handled above.
    for (final d in viaMediaStore ? dirs.take(1) : dirs) {
      n += emptyDir(d, keep: keep);
    }
    return n;
  }

  /// Free space via StatFs on Android; unknown elsewhere.
  static Future<int?> androidFreeBytes() async {
    if (!Platform.isAndroid) return null;
    try {
      return (await storageChannel.invokeMethod<num>('freeBytes'))?.toInt();
    } catch (_) {
      return null;
    }
  }
}

/// Removes the in-app player's temp files under [cacheDir] (called when the
/// player closes; the external-player playlist `m3u` is left for the manual
/// clear since another app may still be reading it). Never throws.
void clearPlayerTemp(String cacheDir) {
  for (final n in const ['file_picker', 'player']) {
    emptyDir(Directory('$cacheDir/$n'));
  }
}
