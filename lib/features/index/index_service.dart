// Connects the crawlers to the Repository. Plain Dart; no UI.
//
// Per host (in parallel) and per category (priority order, a couple at a
// time): probe the h5ai JSON API -> SkeletonCrawler -> skeleton drafts ->
// batched fast inserts. A host or category without a usable API falls back to
// the HTML Crawler. Later runs compare folder times / group signatures and
// write only what changed. Everything is bounded (crawler queue -> mapper ->
// batch buffer), cancellable and idempotent, so a killed run simply restarts.
import 'dart:async';
import 'dart:collection';

import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/crawler.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/host_limiter.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/crawler/skeleton_crawler.dart';
import 'package:watchdog/crawler/skeleton_probe.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/index/index_meta.dart';
import 'package:watchdog/features/index/title_mapping.dart';

enum IndexPhase {
  idle,

  /// Reachability / API probes.
  probing,

  /// Crawling and committing batches (titles appear in Browse/Search).
  crawling,

  /// Final pruning of vanished titles and compaction.
  writing,
  done,
  failed,
}

enum IndexOutcome {
  /// Every category crawled completely.
  success,

  /// Some categories incomplete (errors); their old data was left intact.
  partial,
  cancelled,

  /// No host reachable; index untouched.
  offBdix,

  /// Internal/write error; completed batches are kept, nothing was deleted.
  failed,
}

enum CategoryStatus {
  pending,
  running,
  done,

  /// Finished in an earlier (killed) run of the first full index; not
  /// repeated.
  skipped,
  failed,

  /// Host did not answer.
  unreachable,
  cancelled,
}

/// Progress of one category (immutable snapshot).
class CategoryProgress {
  const CategoryProgress({
    required this.name,
    required this.host,
    required this.url,
    this.status = CategoryStatus.pending,
    this.titles = 0,
    this.estimatedTotal,
    this.errors = 0,
    this.lastError,
    this.htmlFallback = false,
  });
  final String name, host, url;
  final CategoryStatus status;

  /// Titles seen so far (committed + unchanged).
  final int titles;

  /// Rough total (probe answer, else the count of the last complete run).
  final int? estimatedTotal;
  final int errors;
  final String? lastError;

  /// Crawled with the HTML crawler (API missing or misbehaving).
  final bool htmlFallback;

  bool get finished =>
      status == CategoryStatus.done || status == CategoryStatus.skipped;

  /// 0..1, null when the total is unknown.
  double? get fraction {
    if (finished) return 1;
    final e = estimatedTotal;
    return e == null || e <= 0 ? null : (titles / e).clamp(0.0, 1.0);
  }
}

class IndexState {
  const IndexState({
    this.phase = IndexPhase.idle,
    this.foldersFetched = 0,
    this.titlesFound = 0,
    this.titlesUnchanged = 0,
    this.titlesWritten = 0,
    this.titlesRemoved = 0,
    this.errors = 0,
    this.lastError,
    this.offBdix = false,
    this.message,
    this.isFirstRun = false,
    this.hasUsableData = false,
    this.elapsed = Duration.zero,
    this.estimatedTotal,
    this.categories = const [],
    this.outcome,
  });
  final IndexPhase phase;

  /// Requests made so far (API calls + HTML listings).
  final int foldersFetched;

  /// New/changed titles crawled so far.
  final int titlesFound;
  final int titlesUnchanged;

  /// Titles committed to the repository so far.
  final int titlesWritten;
  final int titlesRemoved;
  final int errors;
  final String? lastError;
  final bool offBdix;

  /// Human-readable status or failure reason.
  final String? message;

  /// The first full index has not finished yet (never ran, or was cut short):
  /// show an "indexing" banner (not a blocking screen) until it ends. Still
  /// true after a partial run, so the next launch continues.
  final bool isFirstRun;

  /// At least one title is stored (already true on a restart that finds a
  /// partial index, else after the first committed batch): Browse and Search
  /// can be used.
  final bool hasUsableData;
  final Duration elapsed;

  /// Rough total number of titles to index (sum of the categories' estimates,
  /// null when none is known yet).
  final int? estimatedTotal;
  final List<CategoryProgress> categories;

  /// Set when the run ended.
  final IndexOutcome? outcome;

  bool get running =>
      phase == IndexPhase.probing ||
      phase == IndexPhase.crawling ||
      phase == IndexPhase.writing;

  /// Titles stored or verified so far (committed + unchanged).
  int get titlesIndexed => titlesWritten + titlesUnchanged;

  /// 0..1 overall, null when [estimatedTotal] is unknown.
  double? get progress {
    final e = estimatedTotal;
    if (e == null || e <= 0) return null;
    if (phase == IndexPhase.done) return 1;
    return (titlesIndexed / e).clamp(0.0, 0.99);
  }

  /// Errors per host (for categories that had any).
  Map<String, int> get errorsByHost {
    final m = <String, int>{};
    for (final c in categories) {
      if (c.errors > 0) m[c.host] = (m[c.host] ?? 0) + c.errors;
    }
    return m;
  }

  IndexState copyWith({
    IndexPhase? phase,
    int? foldersFetched,
    int? titlesFound,
    int? titlesUnchanged,
    int? titlesWritten,
    int? titlesRemoved,
    int? errors,
    String? lastError,
    bool? offBdix,
    String? message,
    bool? isFirstRun,
    bool? hasUsableData,
    Duration? elapsed,
    int? estimatedTotal,
    List<CategoryProgress>? categories,
    IndexOutcome? outcome,
  }) => IndexState(
    phase: phase ?? this.phase,
    foldersFetched: foldersFetched ?? this.foldersFetched,
    titlesFound: titlesFound ?? this.titlesFound,
    titlesUnchanged: titlesUnchanged ?? this.titlesUnchanged,
    titlesWritten: titlesWritten ?? this.titlesWritten,
    titlesRemoved: titlesRemoved ?? this.titlesRemoved,
    errors: errors ?? this.errors,
    lastError: lastError ?? this.lastError,
    offBdix: offBdix ?? this.offBdix,
    message: message ?? this.message,
    isFirstRun: isFirstRun ?? this.isFirstRun,
    hasUsableData: hasUsableData ?? this.hasUsableData,
    elapsed: elapsed ?? this.elapsed,
    estimatedTotal: estimatedTotal ?? this.estimatedTotal,
    categories: categories ?? this.categories,
    outcome: outcome ?? this.outcome,
  );
}

class IndexResult {
  const IndexResult({
    required this.outcome,
    required this.elapsed,
    this.message,
    this.titlesWritten = 0,
    this.titlesUnchanged = 0,
    this.titlesRemoved = 0,
    this.batches = 0,
    this.categoriesComplete = 0,
    this.categoriesIncomplete = 0,
    this.requests = 0,
    this.bytes = 0,
    this.full = false,
    this.firstBatchAfter,
    this.categories = const [],
  });
  final IndexOutcome outcome;
  final Duration elapsed;
  final String? message;
  final int titlesWritten;
  final int titlesUnchanged;
  final int titlesRemoved;
  final int batches;
  final int categoriesComplete;
  final int categoriesIncomplete;

  /// API calls + HTML listings of this run.
  final int requests;

  /// API response bytes (HTML listings are not counted).
  final int bytes;
  final bool full;

  /// Time until the first batch was committed (null: none was).
  final Duration? firstBatchAfter;
  final List<CategoryProgress> categories;

  int get foldersFetched => requests;
  bool get offBdix => outcome == IndexOutcome.offBdix;
  bool get ok => outcome == IndexOutcome.success;
}

enum _HostMode { api, html, down }

class _CatRun {
  _CatRun(this.server, this.cat, this.id)
    : draft = cat.toDraft(server.host),
      p = CategoryProgress(
        name: cat.name,
        host: server.host,
        url: cat.toDraft(server.host).url,
      );
  final ServerConfig server;
  final CategoryConfig cat;
  final CategoryDraft draft;
  final int id;
  CategoryProgress p;
  int seen = 0, unchanged = 0, written = 0, htmlFolders = 0;
  bool complete = false;
}

class _Run {
  _Run({required this.full, required this.token, required this.meta})
    : sw = Stopwatch()..start();
  final bool full;
  final CancelToken token;
  final IndexMetaData meta;
  final Stopwatch sw;
  final cats = <_CatRun>[];
  final modes = <String, _HostMode>{};
  bool firstRun = false, usable = false;
  int written = 0, unchanged = 0, found = 0, removed = 0, batches = 0;
  int errors = 0, apiStart = 0, apiBytesStart = 0;
  String? lastError;
  Duration? firstBatchAt;
  Object? writeError;
  IndexPhase phase = IndexPhase.probing;
  String? message;
  IndexOutcome? outcome;
  bool offBdix = false;
  Duration lastPublish = const Duration(days: -1);
  Timer? timer;
}

/// Collects drafts into batches: commits at [size] drafts or [maxDelay] after
/// the first pending one, whichever comes first (a crawl answer arrives as a
/// burst, so slow trickles still show up quickly). At most one write runs at a
/// time per batcher; [add] waits for it when a batch is full (backpressure).
class _Batcher {
  _Batcher(this._write, {required this.size, required this.maxDelay});
  final Future<void> Function(List<TitleDraft> batch) _write;
  final int size;
  final Duration maxDelay;
  final _buf = <TitleDraft>[];
  Timer? _timer;
  Future<void> _tail = Future.value();
  Object? _error;

  Future<void> add(TitleDraft d) {
    if (_error != null) return Future.error(_error!);
    _buf.add(d);
    if (_buf.length >= size) return flush();
    _timer ??= Timer(maxDelay, () {
      flush().catchError((Object e) => _error ??= e);
    });
    return Future.value();
  }

  /// Drops pending drafts and the timer (failure path).
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _buf.clear();
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_buf.isNotEmpty) {
      final batch = List<TitleDraft>.of(_buf);
      _buf.clear();
      _tail = _tail.then((_) => _write(batch));
    }
    return _tail.then((_) {
      if (_error != null) throw _error!;
    });
  }
}

class IndexService {
  IndexService({
    required this.repository,
    required this.client,
    this.api,
    required this.configOf,
    IndexMetaStore? meta,
    this.options = const CrawlOptions(),
    this.limiters,
    this.batchSize = 400,
    this.maxBatchDelay = const Duration(milliseconds: 250),
    this.categoryParallel = 2,
    this.crawlParallel = 6,
    this.progressInterval = const Duration(milliseconds: 200),
    this.changeThrottle = const Duration(seconds: 1),
    this.staleAfter = const Duration(hours: 12),
    DateTime Function()? now,
  }) : meta = meta ?? MemoryIndexMeta(),
       _now = now ?? DateTime.now;

  final Repository repository;

  /// HTML listing client (fallback crawler, and the only crawler when [api]
  /// is null).
  final ListingClient client;

  /// h5ai JSON API client; null = HTML crawler only.
  final H5aiApiClient? api;

  /// Read at the start of every reindex (so Settings edits apply).
  final CrawlConfig Function() configOf;
  final IndexMetaStore meta;
  final CrawlOptions options;

  /// Shared per-host request limits for the HTML fallback (the API client has
  /// its own, pass the same instance to both to cap them together).
  final HostLimiters? limiters;

  /// Commit after this many titles ...
  final int batchSize;

  /// ... or this long after the first uncommitted one.
  final Duration maxBatchDelay;

  /// Categories crawled at once per host.
  final int categoryParallel;

  /// Folders read at once inside one category (the per-host request limit
  /// caps the total).
  final int crawlParallel;

  /// State updates are coalesced to at most one per interval.
  final Duration progressInterval;

  /// While running, `Repository.changes` fires at most this often.
  final Duration changeThrottle;

  /// [ensureIndexed] re-runs when the last complete run is older than this.
  final Duration staleAfter;
  final DateTime Function() _now;

  final _states = StreamController<IndexState>.broadcast();
  IndexState _state = const IndexState();
  Future<IndexResult>? _running;
  CancelToken? _token;

  IndexState get state => _state;

  /// Broadcast; does not replay. Read [state] for the current value.
  Stream<IndexState> get states => _states.stream;
  bool get isRunning => _running != null;

  Future<DateTime?> lastIndexedAt() => meta.lastIndexedAt();

  /// Loads the stored status into [state] (isFirstRun) without crawling, so
  /// the UI can show the banner from the first frame. Safe to call any time.
  Future<IndexState> loadStatus() async {
    if (isRunning) return _state;
    final m = await meta.read();
    final titles = (await repository.counts()).titles;
    final first = m.lastIndexedAt == null || titles == 0;
    _set(_state.copyWith(isFirstRun: first, hasUsableData: titles > 0));
    return _state;
  }

  /// Start-up hook: runs [reindex] unless a run is going on, or the index is
  /// complete and younger than [staleAfter] (then it only loads the status).
  /// Joins a running run; [force] ignores the age.
  Future<IndexResult> ensureIndexed({bool force = false}) async {
    final running = _running;
    if (running != null) return running;
    final last = await meta.lastIndexedAt();
    final fresh =
        !force &&
        last != null &&
        _now().difference(last) < staleAfter &&
        (await repository.counts()).titles > 0;
    if (fresh) {
      await loadStatus();
      return IndexResult(
        outcome: IndexOutcome.success,
        elapsed: Duration.zero,
        message: 'Index is up to date.',
      );
    }
    return reindex();
  }

  /// Cancels the current run, if any. Already committed batches stay.
  void cancel() => _token?.cancel();

  /// Crawls and updates the index. A concurrent call joins the running one.
  /// [full] ignores stored mtimes and signatures (re-crawls every title).
  Future<IndexResult> reindex({
    bool full = false,
    CrawlConfig? config,
    CancelToken? cancel,
  }) => _running ??= _guard(full, config ?? configOf(), cancel ?? CancelToken())
      .whenComplete(() {
        _running = null;
        _token = null;
      });

  Future<IndexResult> _guard(
    bool full,
    CrawlConfig cfg,
    CancelToken token,
  ) async {
    final thr = repository is ChangeThrottling
        ? repository as ChangeThrottling
        : null;
    thr?.throttleChanges(changeThrottle);
    try {
      return await _reindex(full, cfg, token);
    } finally {
      thr?.throttleChanges(null);
    }
  }

  void _set(IndexState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  // ------------------------------------------------------------ publishing

  IndexState _build(_Run r) {
    var est = 0, any = false, requests = 0;
    for (final c in r.cats) {
      final e = c.p.estimatedTotal;
      if (e != null) {
        est += c.p.finished ? c.p.titles : e;
        any = true;
      } else if (c.p.finished) {
        est += c.p.titles;
      }
      requests += c.htmlFolders;
    }
    final a = api;
    if (a != null) requests += a.requests - r.apiStart;
    return IndexState(
      phase: r.phase,
      foldersFetched: requests,
      titlesFound: r.found,
      titlesUnchanged: r.unchanged,
      titlesWritten: r.written,
      titlesRemoved: r.removed,
      errors: r.errors,
      lastError: r.lastError,
      offBdix: r.offBdix,
      message: r.message ?? '',
      isFirstRun: r.firstRun,
      hasUsableData: r.usable,
      elapsed: r.sw.elapsed,
      estimatedTotal: any ? est : null,
      categories: [for (final c in r.cats) c.p],
      outcome: r.outcome,
    );
  }

  /// At most one state per [progressInterval]; [force] for phase changes.
  void _publish(_Run r, {bool force = false}) {
    void now() {
      r.timer?.cancel();
      r.timer = null;
      r.lastPublish = r.sw.elapsed;
      _set(_build(r));
    }

    if (force || r.sw.elapsed - r.lastPublish >= progressInterval) {
      now();
    } else {
      r.timer ??= Timer(progressInterval, now);
    }
  }

  void _problem(_Run r, _CatRun c, String message) {
    r.errors++;
    r.lastError = message;
    c.p = CategoryProgress(
      name: c.p.name,
      host: c.p.host,
      url: c.p.url,
      status: c.p.status,
      titles: c.p.titles,
      estimatedTotal: c.p.estimatedTotal,
      errors: c.p.errors + 1,
      lastError: message,
      htmlFallback: c.p.htmlFallback,
    );
    _publish(r);
  }

  void _cat(
    _Run r,
    _CatRun c, {
    CategoryStatus? status,
    int? titles,
    int? estimate,
    bool? html,
    bool force = false,
  }) {
    c.p = CategoryProgress(
      name: c.p.name,
      host: c.p.host,
      url: c.p.url,
      status: status ?? c.p.status,
      titles: titles ?? c.p.titles,
      estimatedTotal: estimate ?? c.p.estimatedTotal,
      errors: c.p.errors,
      lastError: c.p.lastError,
      htmlFallback: html ?? c.p.htmlFallback,
    );
    _publish(r, force: force);
  }

  // ------------------------------------------------------------------ run

  IndexResult _finish(
    _Run r,
    IndexOutcome o,
    IndexPhase phase, {
    String? message,
  }) {
    r.timer?.cancel();
    r.outcome = o;
    r.phase = phase;
    r.offBdix = o == IndexOutcome.offBdix;
    r.message = message ?? '';
    r.lastPublish = r.sw.elapsed;
    _set(_build(r));
    final a = api;
    return IndexResult(
      outcome: o,
      elapsed: r.sw.elapsed,
      message: message,
      titlesWritten: r.written,
      titlesUnchanged: r.unchanged,
      titlesRemoved: r.removed,
      batches: r.batches,
      categoriesComplete: r.cats.where((c) => c.complete).length,
      categoriesIncomplete: r.cats.where((c) => !c.complete).length,
      requests: _state.foldersFetched,
      bytes: a == null ? 0 : a.bytes - r.apiBytesStart,
      full: r.full,
      firstBatchAfter: r.firstBatchAt,
      categories: _state.categories,
    );
  }

  Future<IndexResult> _reindex(
    bool full,
    CrawlConfig cfg,
    CancelToken token,
  ) async {
    _token = token;
    final data = await meta.read();
    var titlesInDb = 0;
    try {
      titlesInDb = (await repository.counts()).titles;
    } catch (_) {}
    final r = _Run(full: full, token: token, meta: data)
      ..firstRun = data.lastIndexedAt == null || titlesInDb == 0
      ..usable = titlesInDb > 0
      ..apiStart = api?.requests ?? 0
      ..apiBytesStart = api?.bytes ?? 0;
    _publish(r, force: true);
    final crawler = Crawler(client, options: options, limiters: limiters);
    api?.forgetProbe(); // probes are cached per client: look again every run

    try {
      final enabled = cfg.enabledCategories.toList();
      if (enabled.isEmpty) {
        return _finish(
          r,
          IndexOutcome.success,
          IndexPhase.done,
          message: 'No categories enabled.',
        );
      }

      // 1. Probe every host once: API, HTML only, or down (fail fast).
      final servers = <ServerConfig>[];
      for (final (s, _) in enabled) {
        if (!servers.any((x) => x.host == s.host)) servers.add(s);
      }
      await Future.wait([for (final s in servers) _probeHost(r, crawler, s)]);
      final down = [
        for (final e in r.modes.entries)
          if (e.value == _HostMode.down) e.key,
      ];
      if (down.length == servers.length) {
        return _finish(
          r,
          IndexOutcome.offBdix,
          IndexPhase.failed,
          message: offBdixMessage(down),
        );
      }
      if (token.isCancelled) {
        return _finish(
          r,
          IndexOutcome.cancelled,
          IndexPhase.failed,
          message: 'Cancelled.',
        );
      }

      // 2. Categories on reachable hosts -> ids.
      final live = [
        for (final (s, c) in enabled)
          if (r.modes[s.host] != _HostMode.down) (s, c),
      ];
      final ids = await repository.upsertCategories([
        for (final (s, c) in live) c.toDraft(s.host),
      ]);
      if (titlesInDb == 0 &&
          (data.lastIndexedAt != null || data.categories.isNotEmpty)) {
        // The index was wiped (Settings / migration): forget the run state.
        await meta.update((m) {
          m.lastIndexedAt = null;
          m.categories.clear();
        });
        data.lastIndexedAt = null;
        data.categories.clear();
      }

      // Down-host categories show up as unreachable (never crawled).
      for (final (s, c) in enabled) {
        final run = _CatRun(s, c, ids[c.toDraft(s.host).url] ?? -1);
        if (r.modes[s.host] == _HostMode.down) {
          run.p = CategoryProgress(
            name: c.name,
            host: s.host,
            url: run.draft.url,
            status: CategoryStatus.unreachable,
          );
        } else {
          final cm = data.categories[run.draft.url];
          final est = cm != null && cm.titles > 0 ? cm.titles : null;
          if (est != null) {
            run.p = CategoryProgress(
              name: c.name,
              host: s.host,
              url: run.draft.url,
              estimatedTotal: est,
            );
          }
        }
        r.cats.add(run);
      }
      // Resume: the first full index skips categories an earlier run finished.
      if (r.firstRun && !full) {
        for (final c in r.cats) {
          final cm = data.categories[c.draft.url];
          if (c.p.status == CategoryStatus.pending &&
              cm?.completedAt != null &&
              c.id >= 0) {
            c.complete = true;
            c.seen = cm!.titles;
            c.p = CategoryProgress(
              name: c.p.name,
              host: c.p.host,
              url: c.p.url,
              status: CategoryStatus.skipped,
              titles: cm.titles,
              estimatedTotal: cm.titles,
            );
          }
        }
      }
      r.phase = IndexPhase.crawling;
      _publish(r, force: true);

      // 3. Hosts in parallel; within a host, categories by priority.
      await Future.wait([
        for (final s in servers)
          if (r.modes[s.host] != _HostMode.down) _runHost(r, crawler, s),
      ]);

      // 4. Finish: compact, set the marker only if EVERYTHING completed.
      r.phase = IndexPhase.writing;
      _publish(r, force: true);
      if (r.writeError == null) {
        try {
          await repository.compact();
        } catch (_) {}
      }
      final allDone = r.cats.every((c) => c.complete);
      if (r.writeError != null) {
        return _finish(
          r,
          IndexOutcome.failed,
          IndexPhase.failed,
          message: 'Index write failed: ${r.writeError}',
        );
      }
      if (token.isCancelled) {
        return _finish(
          r,
          IndexOutcome.cancelled,
          IndexPhase.failed,
          message: 'Cancelled.',
        );
      }
      if (allDone) {
        await meta.update((m) {
          m.lastIndexedAt = _now();
        });
        r.firstRun = false;
        return _finish(r, IndexOutcome.success, IndexPhase.done);
      }
      final bad = r.cats.where((c) => !c.complete).toList();
      return _finish(
        r,
        IndexOutcome.partial,
        IndexPhase.done,
        message: down.isNotEmpty
            ? 'Skipped unreachable hosts: ${down.join(', ')}.'
            : '${bad.length} categor${bad.length == 1 ? 'y' : 'ies'} incomplete'
                  '${r.lastError == null ? '.' : ': ${r.lastError}'}',
      );
    } catch (e) {
      return _finish(
        r,
        IndexOutcome.failed,
        IndexPhase.failed,
        message: 'Index failed: $e',
      );
    } finally {
      r.timer?.cancel();
    }
  }

  Future<void> _probeHost(_Run r, Crawler crawler, ServerConfig s) async {
    final a = api;
    if (a != null) {
      final p = await a.probe(s.host);
      if (p.supported) {
        r.modes[s.host] = _HostMode.api;
        return;
      }
      // Timeout / connect failure: the host is not there at all.
      if (p.reason == ApiFailure.timeout || p.reason == ApiFailure.connect) {
        r.modes[s.host] = _HostMode.down;
        return;
      }
      r.modes[s.host] = _HostMode.html;
      return;
    }
    final p = await crawler.probeHost(s);
    r.modes[s.host] = p.reachable ? _HostMode.html : _HostMode.down;
  }

  static int _rank(CategoryConfig c) => switch (c.layout) {
    LayoutKind.yearBuckets => 0,
    LayoutKind.series => 1,
    LayoutKind.flat => 2,
    LayoutKind.events => 3,
  };

  Future<void> _runHost(_Run r, Crawler crawler, ServerConfig s) async {
    final mine = [
      for (final c in r.cats)
        if (c.server.host == s.host &&
            c.p.status == CategoryStatus.pending &&
            c.id >= 0)
          c,
    ];
    final order = {for (var i = 0; i < mine.length; i++) mine[i]: i};
    mine.sort((a, b) {
      final k = _rank(a.cat).compareTo(_rank(b.cat));
      return k != 0 ? k : order[a]!.compareTo(order[b]!);
    });
    final queue = Queue<_CatRun>.of(mine);
    Future<void> lane() async {
      while (queue.isNotEmpty && !r.token.isCancelled && r.writeError == null) {
        await _runCategory(r, crawler, queue.removeFirst());
      }
    }

    await Future.wait([
      for (var i = 0; i < categoryParallel.clamp(1, 8); i++) lane(),
    ]);
  }

  Future<void> _runCategory(_Run r, Crawler crawler, _CatRun c) async {
    _cat(r, c, status: CategoryStatus.running, force: true);
    try {
      if (r.modes[c.server.host] == _HostMode.api && api != null) {
        final needsHtml = await _crawlApi(r, c);
        if (needsHtml && !r.token.isCancelled && r.writeError == null) {
          await _crawlHtml(r, crawler, c);
        }
      } else {
        await _crawlHtml(r, crawler, c);
      }
    } catch (e) {
      // Only repository failures reach here (crawl errors are values).
      r.writeError ??= e;
      r.token.cancel();
      c.complete = false;
    }
    final st = c.complete
        ? CategoryStatus.done
        : r.token.isCancelled
        ? CategoryStatus.cancelled
        : CategoryStatus.failed;
    _cat(r, c, status: st, force: true);
  }

  // ------------------------------------------------------------ API path

  static bool _sameTime(DateTime? a, DateTime? b) =>
      a != null && b != null && a.isAtSameMomentAs(b);

  _Batcher _batcher(_Run r, _CatRun c) => _Batcher(
    (batch) async {
      await repository.upsertTitles(batch);
      r.written += batch.length;
      c.written += batch.length;
      r.batches++;
      if (!r.usable) {
        r.usable = true;
        r.firstBatchAt ??= r.sw.elapsed;
        _publish(r, force: true);
      } else {
        r.firstBatchAt ??= r.sw.elapsed;
        _publish(r);
      }
    },
    size: batchSize,
    maxDelay: maxBatchDelay,
  );

  /// Returns true when the category must be redone with the HTML crawler.
  Future<bool> _crawlApi(_Run r, _CatRun c) async {
    final a = api!;
    final cat = c.cat;
    final host = c.server.host;
    final url = c.draft.url;
    final stored = r.meta.categories[url];
    final known = await repository.knownFolders(c.id);
    final hadKnown = known.isNotEmpty;
    final useStored = !r.full;

    // Cheap change detection for bucketed layouts.
    Set<String>? changed; // null = crawl everything
    CategoryProbe? probe;
    Future<CategoryProbe?>? lateProbe;
    Future<CategoryProbe?> doProbe() async {
      try {
        return await probeCategory(a, cat);
      } catch (_) {
        return null;
      }
    }

    if (usesGroupSignatures(cat)) {
      if (useStored && hadKnown && stored != null && stored.sigs.isNotEmpty) {
        probe = await doProbe();
        if (r.token.isCancelled) return false;
        if (probe != null) {
          changed = {
            for (final e in probe.signatures.entries)
              if (stored.sigs[e.key] != e.value) e.key,
          };
          _cat(r, c, estimate: probe.estimatedTitles);
        }
      } else {
        lateProbe = doProbe().then((p) {
          if (p != null) _cat(r, c, estimate: p.estimatedTitles);
          return p;
        });
      }
    }

    // Known titles in groups that did not change count as seen.
    final keep = <String>{};
    var keptUnchanged = 0;
    if (changed != null) {
      final unchangedGroups = {
        for (final h in probe!.signatures.keys)
          if (!changed.contains(h)) h,
      };
      final rootPath = Uri.parse(url).path;
      final rootPrefix = 'http://$host$rootPath';
      for (final u in known.keys) {
        if (!u.startsWith(rootPrefix)) continue;
        final rest = u.substring(rootPrefix.length);
        final i = rest.indexOf('/');
        final group = '$rootPath${i < 0 ? rest : rest.substring(0, i + 1)}';
        if (unchangedGroups.contains(group)) {
          keep.add(u);
          keptUnchanged++;
        }
      }
      r.unchanged += keptUnchanged;
      c.unchanged += keptUnchanged;
      c.seen += keptUnchanged;
    }

    var complete = true;
    var needsHtml = false;
    if (changed == null || changed.isNotEmpty) {
      final sk = SkeletonCrawler(
        a,
        buffer: options.itemBuffer,
        parallel: crawlParallel,
      );
      final run = sk.crawlCategory(
        host,
        cat,
        cancel: r.token,
        only: changed?.contains,
        onRoot: (root) {
          if (cat.layout == LayoutKind.series ||
              cat.layout == LayoutKind.flat) {
            _cat(r, c, estimate: estimateTitles(root, cat));
          }
        },
      );
      final batcher = _batcher(r, c);
      try {
        await for (final t in run.titles) {
          if (hadKnown) keep.add(t.folderUrl);
          c.seen++;
          final d = draftFromSkeleton(t, c.id);
          if (useStored && _sameTime(known[t.folderUrl], d.folderMtime)) {
            r.unchanged++;
            c.unchanged++;
          } else {
            r.found++;
            await batcher.add(d);
          }
          _cat(r, c, titles: c.seen);
          // Microtask chains starve the event loop (UI frames): take a real
          // turn now and then.
          if (c.seen % 256 == 0) await Future<void>.delayed(Duration.zero);
        }
        await batcher.flush();
      } catch (_) {
        run.cancel();
        batcher.dispose(); // a failed write: the run is over
        rethrow;
      }
      final sum = await run.done;
      for (final i in sum.issues) {
        _problem(r, c, '$i');
      }
      complete = sum.complete;
      needsHtml = sum.needsHtmlFallback;
    }
    if (needsHtml) {
      // The API misbehaved: this category is redone from scratch (HTML).
      return true;
    }
    if (r.token.isCancelled) complete = false;
    if (complete) {
      final sigs = changed != null
          ? probe!.signatures
          : (await lateProbe)?.signatures ?? const <String, int>{};
      await _finishCategory(r, c, known, keep, sigs: sigs);
    }
    return false;
  }

  /// Prune vanished titles (only after a complete crawl) and remember the
  /// category as complete.
  Future<void> _finishCategory(
    _Run r,
    _CatRun c,
    Map<String, DateTime?> known,
    Set<String> keep, {
    Map<String, int> sigs = const {},
  }) async {
    var prune = known.isNotEmpty;
    if (prune && keep.isEmpty) {
      // A "complete" crawl that saw nothing is not trustworthy.
      prune = false;
      _problem(r, c, 'listing is empty; kept the stored titles');
    } else if (prune && known.length >= 20 && keep.length * 2 < known.length) {
      prune = false;
      _problem(
        r,
        c,
        'listing shrank by more than half; kept the stored titles',
      );
    }
    if (prune) {
      final n = await repository.removeMissing(c.id, keep);
      r.removed += n;
    }
    c.complete = true;
    final seen = c.seen;
    await meta.update((m) {
      final cm = m.category(c.draft.url);
      cm.completedAt = _now();
      cm.titles = seen;
      cm.sigs = Map.of(sigs);
    });
  }

  // ----------------------------------------------------------- HTML path

  Future<void> _crawlHtml(_Run r, Crawler crawler, _CatRun c) async {
    _cat(r, c, html: true);
    // Restart this category's counters (a failed API attempt may have run).
    final known = await repository.knownFolders(c.id);
    final compare = !r.full;
    final seenUrls = <String>{};
    final cfg = CrawlConfig(
      servers: [
        c.server.copyWith(categories: [c.cat]),
      ],
    );
    final run = crawler.start(
      cfg,
      known: compare
          ? {
              for (final e in known.entries)
                if (e.value != null) e.key: e.value!,
            }
          : const {},
      cancel: r.token,
      categoryIdFor: (_) => c.id,
    );
    final sub = run.progress.listen((p) {
      c.htmlFolders = p.foldersFetched;
      if (p.errors > c.p.errors && p.lastError != null) {
        r.errors += p.errors - c.p.errors;
        r.lastError = p.lastError;
        c.p = CategoryProgress(
          name: c.p.name,
          host: c.p.host,
          url: c.p.url,
          status: c.p.status,
          titles: c.p.titles,
          estimatedTotal: c.p.estimatedTotal,
          errors: p.errors,
          lastError: p.lastError,
          htmlFallback: true,
        );
      }
      _publish(r);
    });
    final batcher = _batcher(r, c);
    var seen = 0;
    try {
      await for (final item in run.items) {
        seen++;
        switch (item) {
          case TitleItem(:final draft):
            seenUrls.add(draft.folderUrl);
            r.found++;
            await batcher.add(skeletonOfFull(draft));
          case UnchangedItem(:final folderUrl):
            seenUrls.add(folderUrl);
            r.unchanged++;
            c.unchanged++;
        }
        c.seen = seen;
        _cat(r, c, titles: seen);
        if (seen % 256 == 0) await Future<void>.delayed(Duration.zero);
      }
      await batcher.flush();
    } catch (_) {
      run.cancel();
      batcher.dispose();
      rethrow;
    } finally {
      await sub.cancel();
    }
    final sum = await run.done;
    c.htmlFolders = sum.foldersFetched;
    if (sum.offBdix) {
      _problem(r, c, sum.failureMessage ?? 'unreachable');
    }
    final ok =
        !r.token.isCancelled &&
        !sum.cancelled &&
        sum.results.isNotEmpty &&
        sum.results.every((x) => x.complete) &&
        sum.issues.isEmpty;
    if (ok) await _finishCategory(r, c, known, seenUrls);
  }

  void dispose() {
    _token?.cancel();
    _states.close();
  }
}
