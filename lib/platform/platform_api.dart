import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A playable item handed to an external player.
class ExternalMedia {
  const ExternalMedia({required this.url, required this.title});

  /// Absolute, percent-encoded http(s) URL.
  final String url;

  /// Human-readable title (used for playlist entries / chooser).
  final String title;
}

/// Lifecycle state of a download.
enum DownloadState {
  queued,
  running,

  /// Transfer done; the file is being copied to its final (shared) folder.
  finishing,
  paused,
  complete,
  failed,
  canceled,
}

/// Snapshot of a download's progress, emitted by [PlatformApi.downloadUpdates]
/// and returned by [PlatformApi.downloads].
class DownloadProgress {
  const DownloadProgress({
    required this.id,
    required this.filename,
    required this.state,
    this.progress = 0,
    this.error,
    this.fileId,
    this.url,
    this.filePath,
    this.bytesReceived,
    this.bytesTotal,
    this.speedMBps,
    this.eta,
  });

  /// Opaque id returned by [PlatformApi.enqueueDownload].
  final String id;
  final String filename;
  final DownloadState state;

  /// 0.0..1.0; negative if unknown.
  final double progress;

  /// Set when [state] is [DownloadState.failed].
  final String? error;

  /// `MediaFile.id` this download was started for (survives app restarts).
  final int? fileId;

  /// Source URL.
  final String? url;

  /// Absolute path of the saved file once known (set when complete).
  final String? filePath;

  /// Byte counters; null when unknown.
  final int? bytesReceived;
  final int? bytesTotal;

  /// Current transfer rate in MB/s (1 MB = 10^6 bytes); null when unknown.
  final double? speedMBps;

  /// Estimated time left; null when unknown.
  final Duration? eta;
}

/// Sub-folder of the app cache dir holding the poster/backdrop disk cache.
const kImageCacheDirName = 'image_cache';

/// What the app stores, in bytes. Null fields could not be measured.
class StorageUsage {
  const StorageUsage({
    this.indexBytes = 0,
    this.imageCacheBytes = 0,
    this.playerCacheBytes = 0,
    this.downloadsBytes = 0,
    this.freeBytes,
  });

  /// `watchdog.db` + `-wal` + `-shm` in the app support dir.
  final int indexBytes;

  /// The poster/backdrop disk cache ([kImageCacheDirName]).
  final int imageCacheBytes;

  /// Temporary files of the player: copies of subtitle files picked with the
  /// file picker and external-player playlists (mpv itself caches in RAM only).
  final int playerCacheBytes;

  /// Finished and partial downloads (`Movies/watchdog` + the private folder).
  final int downloadsBytes;

  /// Free space on the device, when cheap to get.
  final int? freeBytes;

  int get totalBytes =>
      indexBytes + imageCacheBytes + playerCacheBytes + downloadsBytes;
}

/// Platform contract (C3): external players, clipboard, downloads.
/// Implementations: Android (android_intent_plus, background_downloader)
/// and Linux (mpv process).
abstract class PlatformApi {
  /// Opens [items] in an external player. One item plays directly; several
  /// are passed as a playlist (m3u on Android, multiple args to mpv on Linux).
  /// Throws if no player is available.
  Future<void> openExternal(List<ExternalMedia> items);

  /// Opens a finished download (local file) in an external player.
  /// [path] must be absolute, inside the default download directory and free
  /// of `..`; otherwise throws `ExternalPlayerException(invalidPath)`.
  /// [mimeType] overrides the type inferred from the extension (`video/*`
  /// fallback). Throws `ExternalPlayerException(noPlayer)` if nothing can
  /// play it. See `external_player.dart`.
  Future<void> openLocalFile(String path, {String? mimeType});

  /// Opens [url] (http/https) in the default browser. Throws if it cannot.
  Future<void> openUrl(Uri url);

  /// Copies [url] to the system clipboard.
  Future<void> copyUrl(String url);

  /// Queues [url] for download as [filename]; returns the download id.
  /// [fileId] links the download to a `MediaFile` (stored with the task so it
  /// survives restarts). [directory] overrides the default download folder
  /// (absolute path); null uses the default from [defaultDownloadDirectory].
  Future<String> enqueueDownload(
    String url,
    String filename, {
    int? fileId,
    String? directory,
  });

  /// Progress/state updates for all downloads.
  Stream<DownloadProgress> get downloadUpdates;

  /// Current snapshot of every known download (queued, running, finished),
  /// including those started before the last app restart.
  Future<List<DownloadProgress>> downloads();

  /// Default folder new downloads are saved into.
  Future<String> defaultDownloadDirectory();

  /// Pauses the download [id].
  Future<void> pauseDownload(String id);

  /// Resumes the paused download [id].
  Future<void> resumeDownload(String id);

  /// Cancels the download [id].
  Future<void> cancelDownload(String id);

  /// Forgets the download [id]; with [deleteFile] also removes the saved file.
  Future<void> removeDownload(String id, {bool deleteFile = false});

  /// Sizes of everything the app keeps on disk.
  Future<StorageUsage> storageUsage();

  /// Deletes the poster/backdrop disk cache.
  Future<void> clearImageCache();

  /// Deletes the player's temporary files (see [StorageUsage.playerCacheBytes]).
  Future<void> clearPlayerCache();

  /// Deletes every finished download (files + records, like removing each one
  /// with "also delete file"); running/queued/paused ones are left alone. On
  /// Android only entries owned by this app in `Movies/watchdog` are touched.
  /// Returns the number of files removed.
  Future<int> deleteAllDownloads();
}

/// Overridden at app start with the platform implementation.
final platformApiProvider = Provider<PlatformApi>(
  (ref) => throw UnimplementedError('platformApiProvider not overridden'),
);
