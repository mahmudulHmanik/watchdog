import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Serializes "open this file" jobs; the latest request wins.
///
/// [run] bumps the generation synchronously, so rapid next/prev presses each
/// register at once. Jobs run one at a time; a job whose request was
/// superseded before it started is skipped, and a running job can poll
/// `current()` after each await and bail out. Errors are logged, never
/// unhandled.
class LatestWinsRunner {
  int _gen = 0;
  Future<void> _tail = Future<void>.value();

  int get generation => _gen;

  Future<void> run(Future<void> Function(bool Function() current) job) {
    final g = ++_gen;
    bool current() => g == _gen;
    final f = _tail.then((_) async {
      if (!current()) return;
      try {
        await job(current);
      } catch (e, st) {
        debugPrint('LatestWinsRunner job failed: $e\n$st');
      }
    });
    _tail = f;
    return f;
  }
}

/// Drops position/duration/completed events that arrive between a new open
/// request and the moment the open call has returned (late events of the
/// previous file). Each [begin] starts a new epoch.
class EventGate {
  int _epoch = 0;
  bool _live = false;

  int get epoch => _epoch;
  bool get live => _live;

  /// New file requested: events are ignored until [ready] for this epoch.
  int begin() {
    _live = false;
    return ++_epoch;
  }

  /// The open for [epoch] finished; later events belong to the new file.
  /// Ignored when a newer epoch has begun.
  void ready(int epoch) {
    if (epoch == _epoch) _live = true;
  }

  void close() {
    _live = false;
    _epoch++;
  }
}

/// True when [path] is a file strictly inside [dir] (never [dir] itself, never
/// a sibling with the same prefix). Used to delete only our own cache copies.
bool isInsideDir(String path, String dir) =>
    p.isAbsolute(path) &&
    p.isAbsolute(dir) &&
    p.isWithin(p.normalize(dir), p.normalize(path));

/// Counts failed files for the auto-skip cap. One broken file is one failure
/// no matter how many error signals (mpv error event, throwing open) it
/// produces; a successful start of playback resets the streak.
class FailureStreak {
  FailureStreak({this.maxSkips = 2});
  final int maxSkips;
  final _files = <int>{};
  int _epoch = -1;

  /// Record a failure of [fileId] for open request [epoch]. Returns false for
  /// a duplicate signal of the same request (caller should ignore it).
  bool record(int epoch, int fileId) {
    if (epoch == _epoch) return false;
    _epoch = epoch;
    _files.add(fileId);
    return true;
  }

  /// Distinct failed files in the current streak.
  int get count => _files.length;

  /// May we still auto-skip to the next file?
  bool get canSkip => _files.length <= maxSkips;

  void reset() => _files.clear();
}
