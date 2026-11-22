import '../../platform/platform_api.dart';

/// What the manager asks a backend to download.
class DownloadSpec {
  const DownloadSpec({
    required this.url,
    required this.filename,
    required this.directory,
    this.fileId,
  });
  final String url;
  final String filename;

  /// Absolute directory path.
  final String directory;
  final int? fileId;
}

/// Seam over the transfer engine so [DownloadManager] is testable without
/// platform channels. Backends report state as [DownloadProgress].
abstract class DownloadBackend {
  /// Starts listening/rehydrating; call once before anything else.
  Future<void> start();

  /// Cancels listeners and closes [updates].
  Future<void> dispose();

  Stream<DownloadProgress> get updates;

  /// All persisted downloads (survives restarts).
  Future<List<DownloadProgress>> records();

  /// Returns the new download id, or null if the engine refused the task.
  Future<String?> enqueue(DownloadSpec spec);
  Future<bool> pause(String id);
  Future<bool> resume(String id);
  Future<bool> cancel(String id);

  /// Removes the persisted record (not the file).
  Future<void> deleteRecord(String id);
}
