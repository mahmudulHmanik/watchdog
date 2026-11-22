// Adaptive per-host request limiter shared by the HTML and API clients.
import 'dart:async';
import 'dart:collection';

import 'package:watchdog/crawler/listing_client.dart';

/// True for failures that mean "the server is struggling": timeouts, 5xx,
/// 429. Connect failures (host down) and 4xx are not overload.
bool isOverloadError(Object e) =>
    e is FetchException &&
    (e.kind == FetchFailure.timeout ||
        (e.kind == FetchFailure.http &&
            e.status != null &&
            (e.status! >= 500 || e.status == 429)));

/// Concurrency gate for one host. Starts at [start], grows by one (up to
/// [max]) every [step] successful requests while the p90 latency of the last
/// [window] requests is under [fast] and none failed from overload, halves
/// (floor [min]) on an overload error. Tasks that were already running when
/// a halving happened do not halve it again.
class AdaptiveLimiter {
  AdaptiveLimiter({
    this.start = 6,
    this.min = 2,
    this.max = 12,
    this.fast = const Duration(milliseconds: 150),
    this.window = 20,
    this.step = 10,
  }) : _limit = start.clamp(min, max);

  final int start, min, max, window, step;
  final Duration fast;

  int _limit;
  int _active = 0;
  int _epoch = 0;
  int _sinceChange = 0;
  final _lat = <int>[]; // microseconds, ring of the last [window]
  final _waiting = Queue<Completer<void>>();

  int get limit => _limit;
  int get active => _active;
  int get waiting => _waiting.length;

  /// p90 of the recent latencies (null until a sample exists).
  Duration? get p90 {
    if (_lat.isEmpty) return null;
    final s = [..._lat]..sort();
    return Duration(microseconds: s[((s.length - 1) * 0.9).round()]);
  }

  /// Runs [task] when a permit is free. Latency of [task] feeds the limit;
  /// an [isOverloadError] failure shrinks it. Errors are rethrown.
  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= _limit) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future; // permit handed over (_active already counted)
    } else {
      _active++;
    }
    final epoch = _epoch;
    final sw = Stopwatch()..start();
    try {
      final r = await task();
      recordSuccess(sw.elapsed);
      return r;
    } catch (e) {
      if (isOverloadError(e)) recordOverload(epoch);
      rethrow;
    } finally {
      _active--;
      _pump();
    }
  }

  void _pump() {
    while (_waiting.isNotEmpty && _active < _limit) {
      _active++;
      _waiting.removeFirst().complete();
    }
  }

  /// Feeds one completed request; may raise the limit.
  void recordSuccess(Duration latency) {
    _lat.add(latency.inMicroseconds);
    if (_lat.length > window) _lat.removeAt(0);
    _sinceChange++;
    if (_limit < max &&
        _sinceChange >= step &&
        _lat.length >= step &&
        p90! < fast) {
      _limit++;
      _sinceChange = 0;
      _pump();
    }
  }

  /// Halves the limit (floor [min]) unless this failure belongs to a request
  /// that started before the last halving ([epoch] from that request).
  void recordOverload([int? epoch]) {
    if (epoch != null && epoch != _epoch) return;
    _epoch++;
    _limit = (_limit ~/ 2).clamp(min, max);
    _lat.clear();
    _sinceChange = 0;
  }

  int get epoch => _epoch;
}

/// One [AdaptiveLimiter] per host, created on demand.
class HostLimiters {
  HostLimiters({
    this.start = 6,
    this.min = 2,
    this.max = 12,
    this.fast = const Duration(milliseconds: 150),
  });
  final int start, min, max;
  final Duration fast;
  final _by = <String, AdaptiveLimiter>{};

  AdaptiveLimiter forHost(String host) => _by.putIfAbsent(
    host,
    () => AdaptiveLimiter(start: start, min: min, max: max, fast: fast),
  );

  Map<String, int> get limits => {
    for (final e in _by.entries) e.key: e.value.limit,
  };
}
