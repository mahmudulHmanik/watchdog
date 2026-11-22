import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:path_provider/path_provider.dart';

import '../features/downloads/bd_backend.dart';
import '../features/downloads/download_manager.dart';
import 'external_player_android.dart';
import 'external_player_linux.dart';
import 'open_url.dart';
import 'platform_api.dart';
import 'storage.dart';

/// Real [PlatformApi]; downloads delegate to [DownloadManager] (lazy).
// ignore_for_file: prefer_initializing_formals
class PlatformApiImpl implements PlatformApi {
  PlatformApiImpl({
    Future<void> Function(List<ExternalMedia>)? openExternalImpl,
    Future<void> Function(String)? setClipboard,
    DownloadManager? downloads,
    Future<void> Function(String, {String? mimeType})? openLocalImpl,
    Future<void> Function(Uri)? openUrlImpl,
    StorageOps? storage,
  }) : _openUrl = openUrlImpl ?? openUrlDefault,
       _open = openExternalImpl ?? _defaultOpen(),
       _clip =
           setClipboard ?? ((t) => Clipboard.setData(ClipboardData(text: t))),
       _downloads = downloads,
       _storage = storage ?? _defaultStorage() {
    _openLocal = openLocalImpl ?? _defaultOpenLocal();
  }

  final Future<void> Function(List<ExternalMedia>) _open;
  final Future<void> Function(String) _clip;
  final Future<void> Function(Uri) _openUrl;
  late final Future<void> Function(String, {String? mimeType}) _openLocal;
  DownloadManager? _downloads;
  final StorageOps _storage;
  DownloadManager get _dl => _downloads ??= DownloadManager(
    backend: BackgroundDownloaderBackend(),
    defaultDirectory: defaultDownloadDir,
  );

  static Future<void> Function(List<ExternalMedia>) _defaultOpen() {
    if (Platform.isAndroid) return AndroidExternalPlayer().open;
    if (Platform.isLinux) return const LinuxExternalPlayer().open;
    return (_) => throw UnsupportedError('No external player on this OS');
  }

  Future<void> Function(String, {String? mimeType}) _defaultOpenLocal() {
    if (Platform.isAndroid) {
      return AndroidExternalPlayer(
        downloadRoots: knownDownloadRoots,
        providerRoot: androidProviderRoot,
        sharedRoot: androidSharedMoviesRoot,
      ).openLocal;
    }
    if (Platform.isLinux) {
      return LinuxExternalPlayer(downloadRoots: knownDownloadRoots).openLocal;
    }
    return (_, {mimeType}) =>
        throw UnsupportedError('No external player on this OS');
  }

  static StorageOps _defaultStorage() => StorageOps(
    supportDir: getApplicationSupportDirectory,
    cacheDir: getTemporaryDirectory,
    downloadDirs: () async => [
      Directory(await defaultDownloadDir()),
      if (Platform.isAndroid)
        if (await androidSharedMoviesRoot() case final r?) Directory(r),
    ],
    freeBytes: StorageOps.androidFreeBytes,
  );

  /// Default download dir plus the folders of every known download record.
  Future<List<String>> knownDownloadRoots() async {
    final roots = <String>{await defaultDownloadDir()};
    for (final d in await _dl.downloads()) {
      final fp = d.filePath;
      if (fp != null && d.state == DownloadState.complete) {
        roots.add(File(fp).parent.path);
      }
    }
    return roots.toList();
  }

  /// Releases the download engine listeners. Called by the provider.
  Future<void> dispose() async => _downloads?.dispose();

  @override
  Future<void> openLocalFile(String path, {String? mimeType}) =>
      _openLocal(path, mimeType: mimeType);

  @override
  Future<void> openExternal(List<ExternalMedia> items) => _open(items);

  @override
  Future<void> openUrl(Uri url) => _openUrl(url);

  @override
  Future<void> copyUrl(String url) => _clip(url);

  @override
  Future<String> enqueueDownload(
    String url,
    String filename, {
    int? fileId,
    String? directory,
  }) => _dl.enqueue(url, filename, fileId: fileId, directory: directory);

  @override
  Future<List<DownloadProgress>> downloads() => _dl.downloads();

  @override
  Future<String> defaultDownloadDirectory() => _dl.defaultDirectory();

  @override
  Future<void> removeDownload(String id, {bool deleteFile = false}) =>
      _dl.remove(id, deleteFile: deleteFile);

  @override
  Future<StorageUsage> storageUsage() => _storage.usage();

  @override
  Future<void> clearImageCache() => _storage.clearImageCache();

  @override
  Future<void> clearPlayerCache() => _storage.clearPlayerCache();

  @override
  Future<int> deleteAllDownloads() async {
    final all = await _dl.downloads();
    var n = 0;
    final keep = <String>{};
    for (final d in all) {
      if (d.state == DownloadState.complete) {
        // Same path as the Downloads screen's "also delete file": record
        // (moved_downloads.json included) + file.
        final fp = d.filePath;
        final existed = fp != null && File(fp).existsSync();
        try {
          await _dl.remove(d.id, deleteFile: true);
          if (existed && !File(fp).existsSync()) n++;
        } catch (_) {}
      } else if (d.filePath != null) {
        keep.add(d.filePath!);
      }
    }
    return n + await _storage.sweepDownloads(keep: keep);
  }

  @override
  Stream<DownloadProgress> get downloadUpdates => _dl.updates;

  @override
  Future<void> pauseDownload(String id) => _dl.pause(id);

  @override
  Future<void> resumeDownload(String id) => _dl.resume(id);

  @override
  Future<void> cancelDownload(String id) => _dl.cancel(id);
}

/// Android: app-specific external dir (no permission needed, visible to file
/// managers/ADB). Linux: XDG download dir. Always a `watchdog` subfolder.
Future<String> defaultDownloadDir() async {
  final base = Platform.isAndroid
      ? (await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory())
      : (await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory());
  return '${base.path}/watchdog';
}

/// `<external files dir>/watchdog` (the only folder file_paths.xml exposes),
/// or null if Android external storage is unavailable.
Future<String?> androidProviderRoot() async {
  final d = await getExternalStorageDirectory();
  return d == null ? null : '${d.path}/watchdog';
}

/// `<primary storage>/Movies/watchdog`, where finished downloads are moved
/// (see `BackgroundDownloaderBackend`); null if it cannot be derived.
Future<String?> androidSharedMoviesRoot() async {
  final d = await getExternalStorageDirectory();
  if (d == null) return null;
  final i = d.path.indexOf('/Android/');
  return i < 0 ? null : '${d.path.substring(0, i)}/Movies/watchdog';
}

/// Overrides for `ProviderScope(overrides: platformOverrides())` in main.
/// Tests pass their own fake instead: `platformApiProvider.overrideWithValue(fake)`.
List<Override> platformOverrides({PlatformApiImpl Function()? create}) => [
  platformApiProvider.overrideWith((ref) {
    final api = (create ?? PlatformApiImpl.new)();
    ref.onDispose(api.dispose);
    return api;
  }),
];
