import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:path_provider/path_provider.dart';

import '../features/downloads/bd_backend.dart';
import '../features/downloads/download_manager.dart';
import 'external_player_android.dart';
import 'external_player_linux.dart';
import 'platform_api.dart';

/// Real [PlatformApi]; downloads delegate to [DownloadManager] (lazy).
// ignore_for_file: prefer_initializing_formals
class PlatformApiImpl implements PlatformApi {
  PlatformApiImpl({
    Future<void> Function(List<ExternalMedia>)? openExternalImpl,
    Future<void> Function(String)? setClipboard,
    DownloadManager? downloads,
    Future<void> Function(String, {String? mimeType})? openLocalImpl,
  }) : _open = openExternalImpl ?? _defaultOpen(),
       _clip =
           setClipboard ?? ((t) => Clipboard.setData(ClipboardData(text: t))),
       _downloads = downloads {
    _openLocal = openLocalImpl ?? _defaultOpenLocal();
  }

  final Future<void> Function(List<ExternalMedia>) _open;
  final Future<void> Function(String) _clip;
  late final Future<void> Function(String, {String? mimeType}) _openLocal;
  DownloadManager? _downloads;
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
      ).openLocal;
    }
    if (Platform.isLinux) {
      return LinuxExternalPlayer(downloadRoots: knownDownloadRoots).openLocal;
    }
    return (_, {mimeType}) =>
        throw UnsupportedError('No external player on this OS');
  }

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

/// Overrides for `ProviderScope(overrides: platformOverrides())` in main.
/// Tests pass their own fake instead: `platformApiProvider.overrideWithValue(fake)`.
List<Override> platformOverrides({PlatformApiImpl Function()? create}) => [
  platformApiProvider.overrideWith((ref) {
    final api = (create ?? PlatformApiImpl.new)();
    ref.onDispose(api.dispose);
    return api;
  }),
];
