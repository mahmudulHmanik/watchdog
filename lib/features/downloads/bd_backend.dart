import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';

import '../../platform/platform_api.dart';
import 'download_backend.dart';

DownloadState mapStatus(TaskStatus s) => switch (s) {
  TaskStatus.enqueued || TaskStatus.waitingToRetry => DownloadState.queued,
  TaskStatus.running => DownloadState.running,
  TaskStatus.paused => DownloadState.paused,
  TaskStatus.complete => DownloadState.complete,
  TaskStatus.canceled => DownloadState.canceled,
  TaskStatus.failed || TaskStatus.notFound => DownloadState.failed,
};

String encodeMeta(int? fileId, String url) =>
    jsonEncode({'fileId': ?fileId, 'url': url});

int? fileIdFromMeta(String meta) {
  if (meta.isEmpty) return null;
  try {
    final v = (jsonDecode(meta) as Map)['fileId'];
    return v is int ? v : null;
  } catch (_) {
    return null;
  }
}

/// Last known progress per task, pruned when a task reaches a terminal state
/// or is removed/cancelled.
class LastProgress {
  final _m = <String, double>{};
  int get length => _m.length;
  double? operator [](String id) => _m[id];
  void note(String id, double p) => _m[id] = p;
  void forget(String id) => _m.remove(id);

  /// Reads the value for [id] and prunes it if [state] is terminal.
  double? onStatus(String id, DownloadState state) {
    final v = _m[id];
    if (state == DownloadState.complete ||
        state == DownloadState.failed ||
        state == DownloadState.canceled) {
      _m.remove(id);
    }
    return v;
  }
}

/// [DownloadBackend] over background_downloader 9.x (Android + Linux).
/// On Android it uses HttpURLConnection, so cleartext HTTP is subject to
/// network_security_config.xml (only the listed BDIX IPs are allowed).
class BackgroundDownloaderBackend implements DownloadBackend {
  final _out = StreamController<DownloadProgress>.broadcast();
  final _lastProgress = LastProgress();
  bool _askedNotifications = false;
  StreamSubscription<TaskUpdate>? _sub;

  @override
  Stream<DownloadProgress> get updates => _out.stream;

  @override
  Future<void> start() async {
    final d = FileDownloader();
    d.configureNotification(
      running: const TaskNotification('Downloading', '{filename}'),
      complete: const TaskNotification('Download complete', '{filename}'),
      error: const TaskNotification('Download failed', '{filename}'),
      paused: const TaskNotification('Download paused', '{filename}'),
      progressBar: true,
    );
    // Foreground mode: no 9 minute WorkManager limit for multi-GB files
    // (needs the running notification configured above; Android only).
    await d.configure(globalConfig: (Config.runInForeground, Config.always));
    // Listener must exist before start() so replayed updates are not lost.
    await _sub?.cancel();
    _sub = d.updates.listen(_onUpdate);
    await d.start();
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _out.close();
  }

  void _onUpdate(TaskUpdate u) {
    switch (u) {
      case TaskStatusUpdate():
        final st = mapStatus(u.status);
        final last = _lastProgress.onStatus(u.task.taskId, st);
        _out.add(
          DownloadProgress(
            id: u.task.taskId,
            filename: u.task.filename,
            state: st,
            progress: st == DownloadState.complete ? 1 : (last ?? 0),
            error: u.exception?.description,
            fileId: fileIdFromMeta(u.task.metaData),
            url: u.task.url,
            filePath: _pathSync(u.task),
          ),
        );
      case TaskProgressUpdate():
        if (u.progress < 0) return;
        _lastProgress.note(u.task.taskId, u.progress);
        final total = u.hasExpectedFileSize ? u.expectedFileSize : null;
        _out.add(
          DownloadProgress(
            id: u.task.taskId,
            filename: u.task.filename,
            state: DownloadState.running,
            progress: u.progress,
            fileId: fileIdFromMeta(u.task.metaData),
            url: u.task.url,
            filePath: _pathSync(u.task),
            bytesTotal: total,
            bytesReceived: total == null ? null : (u.progress * total).round(),
          ),
        );
    }
  }

  // Tasks are always BaseDirectory.root, so the path is plain concatenation.
  String _pathSync(Task t) => '${t.directory}/${t.filename}';

  DownloadProgress _fromRecord(TaskRecord r) {
    final st = mapStatus(r.status);
    final total = r.expectedFileSize >= 0 ? r.expectedFileSize : null;
    final p = st == DownloadState.complete
        ? 1.0
        : (r.progress >= 0 ? r.progress : -1.0);
    return DownloadProgress(
      id: r.taskId,
      filename: r.task.filename,
      state: st,
      progress: p,
      error: st == DownloadState.failed
          ? (r.exception?.description ??
                (r.status == TaskStatus.notFound ? 'Not found (404)' : null))
          : null,
      fileId: fileIdFromMeta(r.task.metaData),
      url: r.task.url,
      filePath: _pathSync(r.task),
      bytesTotal: total,
      bytesReceived: (total != null && p >= 0) ? (p * total).round() : null,
    );
  }

  @override
  Future<List<DownloadProgress>> records() async => [
    for (final r in await FileDownloader().database.allRecords())
      if (r.task is DownloadTask) _fromRecord(r),
  ];

  @override
  Future<String?> enqueue(DownloadSpec spec) async {
    final d = FileDownloader();
    if (!_askedNotifications) {
      _askedNotifications = true;
      // POST_NOTIFICATIONS on API 33+; a denial only hides notifications.
      if (await d.permissions.status(PermissionType.notifications) !=
          PermissionStatus.granted) {
        await d.permissions.request(PermissionType.notifications);
      }
    }
    final task = DownloadTask(
      url: spec.url,
      filename: spec.filename,
      directory: spec.directory,
      baseDirectory: BaseDirectory.root,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
      requiresWiFi: false,
      metaData: encodeMeta(spec.fileId, spec.url),
      displayName: spec.filename,
    );
    return await d.enqueue(task) ? task.taskId : null;
  }

  Future<DownloadTask?> _task(String id) async {
    final t = (await FileDownloader().database.recordForId(id))?.task;
    return t is DownloadTask ? t : null;
  }

  @override
  Future<bool> pause(String id) async {
    final t = await _task(id);
    return t != null && await FileDownloader().pause(t);
  }

  @override
  Future<bool> resume(String id) async {
    final t = await _task(id);
    return t != null && await FileDownloader().resume(t);
  }

  @override
  Future<bool> cancel(String id) {
    _lastProgress.forget(id);
    return FileDownloader().cancelTaskWithId(id);
  }

  @override
  Future<void> deleteRecord(String id) async {
    _lastProgress.forget(id);
    await FileDownloader().database.deleteRecordWithId(id);
  }
}
