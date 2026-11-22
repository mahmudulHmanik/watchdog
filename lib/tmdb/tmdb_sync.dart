/// Background TMDB fill: match each library title, fetch details, save.
///
/// One worker, one request pacer shared by the background loop and on-demand
/// calls (on-demand jumps the queue). Failures never throw out of the loop;
/// they land in [TmdbSyncService.progress].
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../data/models.dart';
import '../data/repository.dart';
import 'tmdb_client.dart';
import 'tmdb_matcher.dart';
import 'tmdb_models.dart';

enum TmdbSyncState { idle, running, paused, error }

class TmdbSyncProgress {
  const TmdbSyncProgress({
    this.state = TmdbSyncState.idle,
    this.processed = 0,
    this.matched = 0,
    this.unmatched = 0,
    this.failed = 0,
    this.current,
    this.message,
    this.error,
  });

  final TmdbSyncState state;

  /// Titles finished in this run (matched + unmatched + failed).
  final int processed;
  final int matched;
  final int unmatched;

  /// Skipped after retries ran out; tried again on the next run.
  final int failed;

  /// Title being looked up right now.
  final String? current;

  /// Human text: the error, or a notice such as "Rate limited, waiting 5s".
  final String? message;

  /// Set with [TmdbSyncState.error]; `unauthorized` means "fix the key".
  final TmdbErrorKind? error;

  TmdbSyncProgress _with({
    TmdbSyncState? state,
    int? processed,
    int? matched,
    int? unmatched,
    int? failed,
    String? current,
    bool clearCurrent = false,
    String? message,
    bool clearMessage = true,
    TmdbErrorKind? error,
  }) => TmdbSyncProgress(
    state: state ?? this.state,
    processed: processed ?? this.processed,
    matched: matched ?? this.matched,
    unmatched: unmatched ?? this.unmatched,
    failed: failed ?? this.failed,
    current: clearCurrent ? null : (current ?? this.current),
    message: message ?? (clearMessage ? null : this.message),
    error: error,
  );
}

enum TmdbFetchStatus {
  /// Details saved.
  matched,

  /// Nothing trustworthy found on TMDB.
  unmatched,

  /// Stored data is fresh enough; no request made.
  cached,

  /// Request failed; see [TmdbFetchResult.error].
  failed,
}

class TmdbFetchResult {
  const TmdbFetchResult(this.status, {this.details, this.error});
  final TmdbFetchStatus status;
  final TmdbDetails? details;
  final TmdbException? error;
}

typedef DelayFn = Future<void> Function(Duration d);

class TmdbSyncService {
  TmdbSyncService({
    required this.repo,
    required TmdbApi api,
    TmdbMatcher? matcher,
    this.requestsPerSecond = 5,
    this.batchSize = 50,
    this.maxRetries = 3,
    this.maxConsecutiveFailures = 3,
    this.retryUnmatchedAfter = const Duration(days: 30),
    this.onDemandRetryUnmatchedAfter = const Duration(days: 1),
    DelayFn? delay,
    DateTime Function()? clock,
  }) : assert(requestsPerSecond > 0),
       _delay = delay ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now {
    _pacer = _Pacer(
      Duration(microseconds: (1e6 / requestsPerSecond).round()),
      _clock,
      _delay,
    );
    _api = _PacedApi(this, api);
    _matcher = TmdbMatcher(
      _api,
      threshold: matcher?.threshold ?? TmdbMatcher.defaultThreshold,
    );
  }

  final Repository repo;

  /// Request starts per second (TMDB's soft limit is about 40).
  final double requestsPerSecond;
  final int batchSize;

  /// Extra attempts after a transient failure (429 gets more patience).
  final int maxRetries;

  /// Titles in a row that fail on network/server errors before the run stops.
  final int maxConsecutiveFailures;
  final Duration retryUnmatchedAfter;
  final Duration onDemandRetryUnmatchedAfter;
  final DelayFn _delay;
  final DateTime Function() _clock;

  late final _Pacer _pacer;
  late final _PacedApi _api;
  late final TmdbMatcher _matcher;

  final _ctrl = StreamController<TmdbSyncProgress>.broadcast();
  TmdbSyncProgress _p = const TmdbSyncProgress();
  bool _disposed = false;

  // run state
  Future<void>? _run;
  bool _cancel = false;
  Completer<void>? _pauseGate;
  bool _authFailed = false;
  final _skipIds = <int>{};
  final _inflight = <int, Future<TmdbFetchResult>>{};

  /// Last progress value.
  TmdbSyncProgress get current => _p;

  /// Current value first, then every change.
  Stream<TmdbSyncProgress> get progress => Stream.multi((c) {
    c.add(_p);
    final sub = _ctrl.stream.listen(c.add, onDone: c.close);
    c.onCancel = sub.cancel;
  });

  bool get isRunning => _run != null;

  void _emit(TmdbSyncProgress p) {
    _p = p;
    if (!_disposed) _ctrl.add(p);
  }

  // ---- run control ----

  /// Start (or restart after an error/finish) the background fill. No-op when
  /// already running; resumes when paused.
  void start() {
    if (_disposed) return;
    if (_run != null) {
      resume();
      return;
    }
    _cancel = false;
    _authFailed = false;
    _skipIds.clear();
    _emit(const TmdbSyncProgress(state: TmdbSyncState.running));
    _run = _loop().whenComplete(() => _run = null);
  }

  /// Stop after the title in progress; [resume] continues.
  void pause() {
    if (_run == null || _pauseGate != null) return;
    _pauseGate = Completer<void>();
    _emit(_p._with(state: TmdbSyncState.paused, clearMessage: false));
  }

  void resume() {
    final g = _pauseGate;
    if (g == null) {
      if (_run == null) start();
      return;
    }
    _pauseGate = null;
    _emit(_p._with(state: TmdbSyncState.running, clearMessage: false));
    g.complete();
  }

  /// End the run after the title in progress; state goes to idle.
  Future<void> cancel() async {
    final run = _run;
    if (run == null) return;
    _cancel = true;
    _pauseGate?.complete();
    _pauseGate = null;
    await run;
  }

  Future<void> dispose() async {
    await cancel();
    _disposed = true;
    await _ctrl.close();
  }

  Future<void> _loop() async {
    try {
      while (true) {
        if (await _gate()) break;
        final batch = (await repo.titlesNeedingTmdb(
          limit: batchSize,
          retryUnmatchedAfter: retryUnmatchedAfter,
        )).where((t) => !_skipIds.contains(t.id)).toList();
        if (batch.isEmpty) break;
        var consecutive = 0;
        for (final t in batch) {
          if (await _gate()) return _finish();
          _emit(_p._with(current: t.name, clearMessage: true));
          final r = await _process(t);
          _skipIds.add(t.id); // never revisit within a run
          switch (r.status) {
            case TmdbFetchStatus.matched:
              consecutive = 0;
              _emit(
                _p._with(
                  processed: _p.processed + 1,
                  matched: _p.matched + 1,
                  clearCurrent: true,
                ),
              );
            case TmdbFetchStatus.unmatched:
            case TmdbFetchStatus.cached:
              consecutive = 0;
              _emit(
                _p._with(
                  processed: _p.processed + 1,
                  unmatched: _p.unmatched + 1,
                  clearCurrent: true,
                ),
              );
            case TmdbFetchStatus.failed:
              final e = r.error;
              if (e?.kind == TmdbErrorKind.unauthorized) {
                return _fail(e!);
              }
              consecutive++;
              _emit(
                _p._with(
                  processed: _p.processed + 1,
                  failed: _p.failed + 1,
                  clearCurrent: true,
                ),
              );
              if (e != null &&
                  e.transient &&
                  consecutive >= maxConsecutiveFailures) {
                return _fail(e);
              }
          }
        }
      }
      _finish();
    } catch (e) {
      // Repository trouble or a bug: report, never throw.
      _emit(
        _p._with(
          state: TmdbSyncState.error,
          clearCurrent: true,
          message: 'Metadata sync stopped: $e',
        ),
      );
    }
  }

  /// Waits while paused; true when the run was cancelled.
  Future<bool> _gate() async {
    while (_pauseGate != null && !_cancel) {
      await _pauseGate!.future;
    }
    return _cancel;
  }

  void _finish() {
    _emit(_p._with(state: TmdbSyncState.idle, clearCurrent: true));
  }

  void _fail(TmdbException e) {
    _emit(
      _p._with(
        state: TmdbSyncState.error,
        clearCurrent: true,
        message: e.message,
        error: e.kind,
      ),
    );
  }

  // ---- one title ----

  Future<TmdbFetchResult> _process(
    MediaTitle t, {
    bool priority = false,
  }) async {
    try {
      final hit = await _prio(priority, () => _matcher.match(t));
      if (hit == null) {
        await repo.saveTmdbUnmatched(t.id);
        return const TmdbFetchResult(TmdbFetchStatus.unmatched);
      }
      final d = await _prio(
        priority,
        () => _api.details(hit.id, hit.mediaType),
      );
      await repo.saveTmdbMatch(t.id, d);
      return TmdbFetchResult(TmdbFetchStatus.matched, details: d);
    } on TmdbException catch (e) {
      if (e.kind == TmdbErrorKind.notFound) {
        await _safe(() => repo.saveTmdbUnmatched(t.id));
        return const TmdbFetchResult(TmdbFetchStatus.unmatched);
      }
      return TmdbFetchResult(TmdbFetchStatus.failed, error: e);
    } catch (e) {
      return TmdbFetchResult(
        TmdbFetchStatus.failed,
        error: TmdbException(TmdbErrorKind.badResponse, 'Could not save: $e'),
      );
    }
  }

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  /// Runs [f] with every request inside it at on-demand priority.
  Future<T> _prio<T>(bool priority, Future<T> Function() f) {
    if (!priority) return f();
    return runZoned(f, zoneValues: {_prioKey: true});
  }

  static final _prioKey = Object();
  bool get _inPriority => Zone.current[_prioKey] == true;

  // ---- on demand ----

  /// Look up [t] now (title screen opened). Jumps ahead of the background
  /// loop, shares its throttle. Skips the network when fresh data exists.
  Future<TmdbFetchResult> fetchNow(MediaTitle t, {bool force = false}) {
    if (t.kind == TitleKind.event) {
      return Future.value(const TmdbFetchResult(TmdbFetchStatus.unmatched));
    }
    return _inflight[t.id] ??= _fetchNow(t, force).whenComplete(() {
      // block body: returning the removed future would deadlock itself
      _inflight.remove(t.id);
    });
  }

  Future<TmdbFetchResult> fetchNowById(
    int titleId, {
    bool force = false,
  }) async {
    final t = await repo.title(titleId);
    if (t == null) {
      return const TmdbFetchResult(
        TmdbFetchStatus.failed,
        error: TmdbException(TmdbErrorKind.notFound, 'Title not in library'),
      );
    }
    return fetchNow(t, force: force);
  }

  Future<TmdbFetchResult> _fetchNow(MediaTitle t, bool force) async {
    if (_authFailed) {
      return const TmdbFetchResult(
        TmdbFetchStatus.failed,
        error: TmdbException(
          TmdbErrorKind.unauthorized,
          'TMDB rejected the key. Check it in Settings.',
        ),
      );
    }
    if (!force) {
      try {
        final info = await repo.tmdbInfo(t.id);
        if (info != null) {
          final fresh =
              info.status != TmdbStatus.unmatched ||
              _clock().difference(info.fetchedAt) < onDemandRetryUnmatchedAfter;
          if (fresh) return const TmdbFetchResult(TmdbFetchStatus.cached);
        }
      } catch (_) {
        // unreadable row: just fetch
      }
    }
    return _process(t, priority: true);
  }

  /// Manual "fix match": store TMDB entry [tmdbId] for [titleId], marked
  /// manual so the background worker never replaces it.
  Future<TmdbFetchResult> rematch(
    int titleId,
    int tmdbId,
    TmdbMediaType type,
  ) async {
    try {
      final d = await _prio(true, () => _api.details(tmdbId, type));
      await repo.saveTmdbMatch(titleId, d, manual: true);
      return TmdbFetchResult(TmdbFetchStatus.matched, details: d);
    } on TmdbException catch (e) {
      return TmdbFetchResult(TmdbFetchStatus.failed, error: e);
    } catch (e) {
      return TmdbFetchResult(
        TmdbFetchStatus.failed,
        error: TmdbException(TmdbErrorKind.badResponse, 'Could not save: $e'),
      );
    }
  }

  /// Hits for the manual picker. Throws [TmdbException] on failure.
  Future<List<TmdbHit>> searchCandidates(
    String query,
    TmdbMediaType type, {
    int? year,
  }) {
    final q = query.trim();
    if (q.isEmpty) return Future.value(const []);
    return _prio(
      true,
      () => type == TmdbMediaType.movie
          ? _api.searchMovies(q, year: year)
          : _api.searchTv(q, year: year),
    );
  }

  // ---- paced, retried requests ----

  Future<T> _request<T>(Future<T> Function() call) async {
    final priority = _inPriority;
    var attempt = 0;
    var rateHits = 0;
    while (true) {
      if (_authFailed) {
        throw const TmdbException(
          TmdbErrorKind.unauthorized,
          'TMDB rejected the key. Check it in Settings.',
        );
      }
      await _pacer.acquire(priority: priority);
      try {
        final r = await call();
        _pacer.ok();
        return r;
      } on TmdbException catch (e) {
        if (e.kind == TmdbErrorKind.unauthorized) {
          _authFailed = true;
          rethrow;
        }
        if (!e.transient) rethrow;
        final Duration wait;
        if (e.kind == TmdbErrorKind.rateLimited) {
          // 429: honour Retry-After, then run slower.
          if (++rateHits > maxRetries + 2) rethrow;
          wait = e.retryAfter ?? const Duration(seconds: 5);
          _pacer.slowDown();
          if (!_disposed && !priority) {
            _emit(
              _p._with(
                message: 'Rate limited, waiting ${wait.inSeconds}s',
                clearMessage: false,
              ),
            );
          }
        } else {
          if (++attempt > maxRetries) rethrow;
          wait = Duration(seconds: 1 << (attempt - 1));
        }
        _pacer.penalize(wait);
      }
    }
  }
}

class _PacedApi implements TmdbApi {
  _PacedApi(this._s, this._api);
  final TmdbSyncService _s;
  final TmdbApi _api;

  @override
  Future<List<TmdbHit>> searchMovies(String query, {int? year}) =>
      _s._request(() => _api.searchMovies(query, year: year));
  @override
  Future<List<TmdbHit>> searchTv(String query, {int? year}) =>
      _s._request(() => _api.searchTv(query, year: year));
  @override
  Future<TmdbDetails> details(int id, TmdbMediaType type) =>
      _s._request(() => _api.details(id, type));
}

/// Hands out request slots at most one per [base] (longer after a 429), on-
/// demand callers first. Uses the injected clock and delay only.
class _Pacer {
  _Pacer(this.base, this._clock, this._delay) : _interval = base;
  final Duration base;
  final DateTime Function() _clock;
  final DelayFn _delay;
  Duration _interval;
  DateTime? _next;
  int _good = 0;
  bool _pumping = false;
  final _hi = Queue<Completer<void>>();
  final _lo = Queue<Completer<void>>();

  static const _maxInterval = Duration(seconds: 2);

  Future<void> acquire({bool priority = false}) {
    final c = Completer<void>();
    (priority ? _hi : _lo).add(c);
    if (!_pumping) _pump();
    return c.future;
  }

  Future<void> _pump() async {
    _pumping = true;
    try {
      while (_hi.isNotEmpty || _lo.isNotEmpty) {
        final next = _next;
        if (next != null) {
          final wait = next.difference(_clock());
          if (wait > Duration.zero) await _delay(wait);
        }
        // Choose only after waiting, so a late on-demand caller still wins.
        final c = _hi.isNotEmpty ? _hi.removeFirst() : _lo.removeFirst();
        _next = _clock().add(_interval);
        c.complete();
        // Let the granted caller start its request before the next slot.
        await Future<void>.value();
      }
    } finally {
      _pumping = false;
    }
  }

  /// No request before [d] from now (Retry-After, backoff).
  void penalize(Duration d) {
    final t = _clock().add(d);
    if (_next == null || t.isAfter(_next!)) _next = t;
  }

  void slowDown() {
    _good = 0;
    _interval = Duration(
      microseconds: math.min(
        _interval.inMicroseconds * 2,
        _maxInterval.inMicroseconds,
      ),
    );
  }

  /// After 20 clean requests the pace recovers to the base.
  void ok() {
    if (_interval == base) return;
    if (++_good >= 20) {
      _good = 0;
      _interval = base;
    }
  }
}
