/// Pure-Dart playback policies: resume position, progress throttling,
/// watched threshold. No media_kit, no Flutter.
library;

import 'package:watchdog/data/models.dart';

/// Minimum saved position (ms) worth resuming.
const kResumeMinMs = 10000;

/// Fraction at which a file counts as watched (matches Repository.setProgress).
const kWatchedFraction = 0.9;

/// Where to start a file: saved position when > 10 s and not watched and not
/// already in the watched zone; otherwise 0.
Duration resumePosition(WatchState? s) {
  if (s == null || s.watched || s.positionMs <= kResumeMinMs) {
    return Duration.zero;
  }
  if (s.durationMs > 0 && s.positionMs / s.durationMs >= kWatchedFraction) {
    return Duration.zero;
  }
  return Duration(milliseconds: s.positionMs);
}

bool isWatchedPosition(Duration position, Duration duration) =>
    duration > Duration.zero &&
    position.inMilliseconds / duration.inMilliseconds >= kWatchedFraction;

typedef ProgressSink = Future<void> Function(
  int fileId, {
  required int positionMs,
  required int durationMs,
});

/// Throttles progress writes: at most one per [interval] while playing, plus
/// explicit [flush] on pause/close/dispose/background.
///
/// Nothing is written until [begin] has been called and the first real
/// position is [arm]ed, so the initial 0 position of a file that is about to
/// be resumed can never overwrite the stored one. Positions under 1 s and an
/// unchanged position are not written.
class ProgressTracker {
  ProgressTracker(
    this._sink, {
    this.interval = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ProgressSink _sink;
  final Duration interval;
  final DateTime Function() _now;

  int? _fileId;
  bool _armed = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  int? _lastWrittenMs;
  DateTime? _lastWriteAt;

  /// Number of sink writes (for tests/diagnostics).
  int writes = 0;

  /// Start tracking [fileId]; flushes nothing (call [flush] first if needed).
  void begin(int fileId) {
    _fileId = fileId;
    _armed = false;
    _pos = Duration.zero;
    _dur = Duration.zero;
    _lastWrittenMs = null;
    _lastWriteAt = null;
  }

  /// Allow writes (call once the resume seek has completed).
  void arm() => _armed = true;

  void updateDuration(Duration d) => _dur = d;

  /// Feed a position tick. Writes when the interval has elapsed.
  Future<void> update(Duration position) async {
    _pos = position;
    if (!_armed || _fileId == null) return;
    final last = _lastWriteAt;
    if (last != null && _now().difference(last) < interval) return;
    await _write();
  }

  /// Write the latest position now (pause/close/dispose/background/seek end).
  Future<void> flush() async {
    if (!_armed || _fileId == null) return;
    await _write();
  }

  /// Stop tracking (after a final [flush]).
  void end() {
    _fileId = null;
    _armed = false;
  }

  Future<void> _write() async {
    final id = _fileId;
    if (id == null) return;
    final ms = _pos.inMilliseconds;
    if (ms < 1000 || ms == _lastWrittenMs) return;
    _lastWrittenMs = ms;
    _lastWriteAt = _now();
    writes++;
    await _sink(id, positionMs: ms, durationMs: _dur.inMilliseconds);
  }
}
