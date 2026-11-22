// Crawl engine: bounded-concurrency walk of the configured categories,
// producing id-free drafts. No database access (that is the index writer).
import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/bounded_queue.dart';
import 'package:watchdog/crawler/classifier.dart';
import 'package:watchdog/crawler/fast_listing.dart';
import 'package:watchdog/crawler/host_limiter.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/crawler/parsing.dart';
import 'package:watchdog/data/models.dart';

class CrawlOptions {
  const CrawlOptions({
    this.concurrency = 8,
    this.requestTimeout = const Duration(seconds: 20),
    this.probeTimeout = const Duration(seconds: 5),
    this.retries = 3,
    this.backoffBase = const Duration(milliseconds: 500),
    this.maxMovieDepth = 8,
    this.maxShowDepth = 2,
    this.deadHostAfter = 5,
    this.progressInterval = const Duration(milliseconds: 200),
    this.parseOffloadBytes = 256 * 1024,
    this.itemBuffer = 256,
  });

  /// Max simultaneous requests (global, all hosts). Ignored when the
  /// [Crawler] has per-host [HostLimiters].
  final int concurrency;
  final Duration requestTimeout;

  /// Reachability probe: one attempt, short timeout.
  final Duration probeTimeout;

  /// Retries after the first attempt (so up to retries + 1 attempts).
  final int retries;

  /// Delay before retry n is backoffBase * 2^(n-1).
  final Duration backoffBase;
  final int maxMovieDepth;

  /// Listing levels fetched below a show folder (season, nested release).
  final int maxShowDepth;

  /// Consecutive unanswered folders after which a host is declared dead and
  /// its remaining requests fail immediately.
  final int deadHostAfter;
  final Duration progressInterval;

  /// Bodies larger than this are parsed in a short-lived isolate so a
  /// 1000-entry listing never blocks the UI isolate.
  final int parseOffloadBytes;

  /// Max items buffered between the crawl and the consumer of
  /// [CrawlRun.items]. When full, the crawl stops starting new folders until
  /// the consumer catches up, so memory stays flat. The consumer must read
  /// `items` (e.g. `await for`) or the crawl stalls once the buffer fills.
  final int itemBuffer;
}

class CancelToken {
  bool _cancelled = false;
  final _c = Completer<void>();
  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _c.future;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _c.complete();
  }
}

class CrawlCancelled implements Exception {
  const CrawlCancelled();
}

class CrawlIssue {
  const CrawlIssue({
    required this.message,
    this.url,
    this.host,
    this.unreachable = false,
  });
  final String message;
  final String? url;
  final String? host;

  /// The host never answered (off-BDIX / down), as opposed to a bad folder.
  final bool unreachable;
  @override
  String toString() => '${url ?? host ?? ''}: $message';
}

class CrawlProgress {
  const CrawlProgress({
    this.foldersFetched = 0,
    this.titlesFound = 0,
    this.titlesUnchanged = 0,
    this.errors = 0,
    this.retries = 0,
    this.lastError,
    this.finished = false,
  });
  final int foldersFetched;
  final int titlesFound;

  /// Skipped by the incremental check (still present on the server).
  final int titlesUnchanged;
  final int errors;
  final int retries;
  final String? lastError;
  final bool finished;
}

sealed class CrawlItem {
  const CrawlItem(this.category);
  final CategoryDraft category;
}

/// A (re)crawled title; upsert it.
class TitleItem extends CrawlItem {
  const TitleItem(super.category, this.draft);
  final TitleDraft draft;
}

/// Present on the server with an unchanged mtime; keep the stored row.
class UnchangedItem extends CrawlItem {
  const UnchangedItem(super.category, this.folderUrl);
  final String folderUrl;
}

class CategoryResult {
  const CategoryResult({
    required this.category,
    required this.complete,
    required this.titles,
    required this.unchanged,
  });
  final CategoryDraft category;

  /// True only if the whole category was walked without errors or cancel.
  /// Only then is it safe to delete titles that were not seen.
  final bool complete;
  final int titles;
  final int unchanged;
}

class CrawlSummary {
  const CrawlSummary({
    required this.cancelled,
    required this.elapsed,
    required this.results,
    required this.issues,
    required this.unreachableHosts,
    required this.probedHosts,
    required this.foldersFetched,
  });
  final bool cancelled;
  final Duration elapsed;
  final List<CategoryResult> results;
  final List<CrawlIssue> issues;
  final List<String> unreachableHosts;
  final List<String> probedHosts;
  final int foldersFetched;

  /// Every probed host was unreachable: almost certainly not on BDIX.
  bool get offBdix =>
      probedHosts.isNotEmpty && unreachableHosts.length == probedHosts.length;

  bool get complete =>
      !cancelled && results.every((r) => r.complete) && issues.isEmpty;

  /// Human-readable reason when nothing (or not everything) was crawled.
  String? get failureMessage {
    if (offBdix) {
      return offBdixMessage(unreachableHosts);
    }
    if (unreachableHosts.isNotEmpty) {
      return 'Skipped unreachable hosts: ${unreachableHosts.join(', ')}.';
    }
    if (cancelled) return 'Crawl cancelled.';
    if (issues.isNotEmpty) return '${issues.length} folder(s) failed.';
    return null;
  }
}

String offBdixMessage(List<String> hosts) =>
    'Cannot reach ${hosts.join(', ')}. DhakaFlix is only reachable from a '
    'BDIX-connected network; connect and retry.';

class HostProbe {
  const HostProbe(this.host, this.reachable, [this.message]);
  final String host;
  final bool reachable;
  final String? message;
}

class _Pool {
  _Pool(this.max);
  final int max;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() f) async {
    if (_active >= max) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future; // permit handed over, _active unchanged
    } else {
      _active++;
    }
    try {
      return await f();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}

class Crawler {
  Crawler(this.client, {this.options = const CrawlOptions(), this.limiters});

  final ListingClient client;
  final CrawlOptions options;

  /// Adaptive per-host concurrency (6 -> 12 while fast). Null: one global
  /// pool of [CrawlOptions.concurrency].
  final HostLimiters? limiters;

  /// One quick GET of the server root; any HTTP answer counts as reachable.
  Future<HostProbe> probeHost(ServerConfig s) async {
    try {
      await client.fetch(s.rootUri, timeout: options.probeTimeout);
      return HostProbe(s.host, true);
    } on FetchException catch (e) {
      if (e.noAnswer) {
        return HostProbe(s.host, false, 'no answer: ${e.message}');
      }
      return HostProbe(s.host, true, e.message);
    } catch (e) {
      return HostProbe(s.host, false, '$e');
    }
  }

  /// Starts a crawl of the enabled categories in [config].
  ///
  /// [known] maps title folderUrl -> stored folderMtime for incremental mode:
  /// unchanged movie/event folders are skipped without any request, unchanged
  /// shows after one listing request. [categoryIdFor] supplies the id written
  /// into each TitleDraft (default: index in config order).
  CrawlRun start(
    CrawlConfig config, {
    Map<String, DateTime> known = const {},
    CancelToken? cancel,
    int Function(CategoryDraft category)? categoryIdFor,
  }) {
    final run = CrawlRun._(
      this,
      config,
      known,
      cancel ?? CancelToken(),
      categoryIdFor,
    );
    run._start();
    return run;
  }
}

class _CatCtx {
  _CatCtx(this.draft, this.config, this.id);
  final CategoryDraft draft;
  final CategoryConfig config;
  final int id;
  bool complete = true;
  int titles = 0;
  int unchanged = 0;
}

class CrawlRun {
  CrawlRun._(
    this._crawler,
    this._config,
    this._known,
    this._cancel,
    this._categoryIdFor,
  ) : _pool = _Pool(_crawler.options.concurrency) {
    // Cancelled (by token or cancel()): stop applying backpressure so waiting
    // walkers wake up and see the cancellation. A consumer that stops
    // listening cancels the crawl; nobody is left to read the items.
    _cancel.whenCancelled.then((_) => _items.abort());
    _items.onConsumerCancel = _cancel.cancel;
  }

  final Crawler _crawler;
  final CrawlConfig _config;
  final Map<String, DateTime> _known;
  final CancelToken _cancel;
  final int Function(CategoryDraft)? _categoryIdFor;
  final _Pool _pool;

  late final _items = BoundedQueue<CrawlItem>(
    _o.itemBuffer > 0 ? _o.itemBuffer : 1 << 30,
  );
  final _progress = StreamController<CrawlProgress>.broadcast();
  final _done = Completer<CrawlSummary>();

  final _issues = <CrawlIssue>[];
  final _deadHosts = <String>{};
  final _failStreak = <String, int>{};
  final _clock = Stopwatch();
  Duration _lastTick = Duration.zero;
  int _folders = 0, _titles = 0, _unchanged = 0, _errors = 0, _retries = 0;
  String? _lastError;
  CrawlProgress _latest = const CrawlProgress();

  CrawlOptions get _o => _crawler.options;

  /// Titles and unchanged markers. Single-subscription, bounded by
  /// [CrawlOptions.itemBuffer] (backpressure). Cancelling the subscription
  /// cancels the crawl.
  Stream<CrawlItem> get items => _items.stream;

  /// Counters; broadcast. Throttled, last event has `finished == true`.
  Stream<CrawlProgress> get progress => _progress.stream;
  CrawlProgress get latestProgress => _latest;

  /// Completes (never throws) when the crawl ends, fails or is cancelled.
  Future<CrawlSummary> get done => _done.future;

  void cancel() => _cancel.cancel();

  // ---- internals ----

  void _tick({bool force = false}) {
    if (!force && _clock.elapsed - _lastTick < _o.progressInterval) return;
    _lastTick = _clock.elapsed;
    _latest = CrawlProgress(
      foldersFetched: _folders,
      titlesFound: _titles,
      titlesUnchanged: _unchanged,
      errors: _errors,
      retries: _retries,
      lastError: _lastError,
      finished: _finishing,
    );
    if (!_progress.isClosed) _progress.add(_latest);
  }

  bool _finishing = false;

  void _issue(CrawlIssue i) {
    _issues.add(i);
    _errors++;
    _lastError = i.toString();
    _tick();
  }

  void _check() {
    if (_cancel.isCancelled) throw const CrawlCancelled();
  }

  Future<String> _get(Uri url) async {
    var attempt = 0;
    while (true) {
      _check();
      if (_deadHosts.contains(url.host)) {
        throw FetchException(url, FetchFailure.connect, 'host unreachable');
      }
      try {
        Future<String> go() {
          _check();
          return _crawler.client.fetch(url, timeout: _o.requestTimeout);
        }

        final lim = _crawler.limiters;
        final body = await (lim == null
            ? _pool.run(go)
            : lim.forHost(url.host).run(go));
        _failStreak[url.host] = 0;
        return body;
      } on FetchException catch (e) {
        if (!e.retryable || attempt >= _o.retries) {
          if (e.noAnswer) {
            final n = (_failStreak[url.host] ?? 0) + 1;
            _failStreak[url.host] = n;
            if (n >= _o.deadHostAfter && _deadHosts.add(url.host)) {
              _issue(
                CrawlIssue(
                  host: url.host,
                  unreachable: true,
                  message:
                      'host stopped answering; aborting its remaining requests',
                ),
              );
            }
          }
          rethrow;
        }
        attempt++;
        _retries++;
        final delay = _o.backoffBase * (1 << (attempt - 1));
        await Future.any([Future<void>.delayed(delay), _cancel.whenCancelled]);
      }
    }
  }

  Future<FolderNode> _list(String url, {String? name, DateTime? mtime}) async {
    final body = await _get(Uri.parse(url));
    _folders++;
    _tick();
    final entries = body.length > _o.parseOffloadBytes
        ? await Isolate.run(() => parseListingFast(body))
        : parseListingFast(body);
    return FolderNode.fromListing(url, entries, name: name, mtime: mtime);
  }

  static bool _same(DateTime? a, DateTime? b) =>
      a != null && b != null && a.isAtSameMomentAs(b);

  Future<void> _start() async {
    _clock.start();
    try {
      final summary = await _run();
      _finish(summary);
    } catch (e) {
      // Unexpected: never leave callers hanging.
      _issue(CrawlIssue(message: 'internal error: $e'));
      _finish(_summary(const [], const [], const []));
    }
  }

  void _finish(CrawlSummary s) {
    _finishing = true;
    _tick(force: true);
    _items.close();
    _progress.close();
    if (!_done.isCompleted) _done.complete(s);
  }

  CrawlSummary _summary(
    List<CategoryResult> results,
    List<String> unreachable,
    List<String> probed,
  ) => CrawlSummary(
    cancelled: _cancel.isCancelled,
    elapsed: _clock.elapsed,
    results: results,
    issues: List.unmodifiable(_issues),
    unreachableHosts: unreachable,
    probedHosts: probed,
    foldersFetched: _folders,
  );

  Future<CrawlSummary> _run() async {
    final cats = _config.enabledCategories.toList();
    final servers = <ServerConfig>[];
    for (final (s, _) in cats) {
      if (!servers.contains(s)) servers.add(s);
    }

    // 1. Fail fast: probe every host once, in parallel.
    final probes = await Future.wait(servers.map(_crawler.probeHost));
    final down = {for (final p in probes.where((p) => !p.reachable)) p.host: p};
    for (final p in down.values) {
      _issue(
        CrawlIssue(
          host: p.host,
          unreachable: true,
          message: 'unreachable (${p.message ?? 'no answer'})',
        ),
      );
    }

    // 2. Walk the categories on reachable hosts.
    final ctxs = <_CatCtx>[];
    final skipped = <CategoryResult>[];
    var idx = 0;
    for (final (s, c) in cats) {
      final draft = c.toDraft(s.host);
      final id = _categoryIdFor?.call(draft) ?? idx;
      idx++;
      if (down.containsKey(s.host)) {
        skipped.add(
          CategoryResult(
            category: draft,
            complete: false,
            titles: 0,
            unchanged: 0,
          ),
        );
      } else {
        ctxs.add(_CatCtx(draft, c, id));
      }
    }
    await Future.wait(ctxs.map(_crawlCategory));

    return _summary(
      [
        for (final c in ctxs)
          CategoryResult(
            category: c.draft,
            complete: c.complete && !_cancel.isCancelled,
            titles: c.titles,
            unchanged: c.unchanged,
          ),
        ...skipped,
      ],
      [for (final p in down.values) p.host],
      [for (final p in probes) p.host],
    );
  }

  Future<void> _crawlCategory(_CatCtx ctx) async {
    final c = ctx.config;
    try {
      final root = await _list(ctx.draft.url, name: c.name);
      if (root.folders.isEmpty && root.files.isEmpty) {
        ctx.complete = false;
        _issue(
          CrawlIssue(
            url: ctx.draft.url,
            message: 'empty or not an h5ai listing',
          ),
        );
        return;
      }
      if (c.layout == LayoutKind.series) {
        await Future.wait([for (final k in root.folders) _walkSeries(ctx, k)]);
      } else {
        await Future.wait([
          for (final k in root.folders) _walkMovies(ctx, k, 1),
        ]);
      }
    } on CrawlCancelled {
      ctx.complete = false;
    } on FetchException catch (e) {
      ctx.complete = false;
      _issue(CrawlIssue(url: e.url.toString(), message: e.message));
    }
  }

  // Both emitters consume a slot claimed with `_items.reserve()` (or add one
  // implicitly when none is held), so the walkers reserve before fetching.
  void _emitTitle(_CatCtx ctx, TitleDraft d) {
    ctx.titles++;
    _titles++;
    _items.put(TitleItem(ctx.draft, d));
    _tick();
  }

  void _emitUnchanged(_CatCtx ctx, String url) {
    ctx.unchanged++;
    _unchanged++;
    _items.put(UnchangedItem(ctx.draft, url));
    _tick();
  }

  /// Lists [stub]; an empty listing is retried once (servers sometimes
  /// return a blank page under load) before being accepted.
  Future<FolderNode> _listRetryEmpty(FolderNode stub) async {
    var node = await _list(stub.url, name: stub.name, mtime: stub.mtime);
    if (node.files.isEmpty && node.folders.isEmpty) {
      node = await _list(stub.url, name: stub.name, mtime: stub.mtime);
    }
    return node;
  }

  /// A folder already in the index that now lists nothing usable cannot be
  /// verified: keep it (so it is not deleted), flag the category incomplete
  /// and record an issue. Unknown empty folders just yield nothing.
  bool _unverified(
    _CatCtx ctx,
    FolderNode stub,
    FolderNode node, {
    bool folderless = false,
  }) {
    if (!_known.containsKey(stub.url)) return false;
    final empty = node.files.isEmpty && node.folders.isEmpty;
    final noMedia =
        folderless && !isMovieTitleFolder(node) && node.folders.isEmpty;
    if (!empty && !noMedia) return false;
    ctx.complete = false;
    _issue(
      CrawlIssue(
        url: stub.url,
        message: 'known title now lists no media; kept unverified',
      ),
    );
    _emitUnchanged(ctx, stub.url);
    return true;
  }

  // Walkers claim an output slot before doing any work and give it back
  // before recursing into children, so a slow consumer stops the crawl from
  // starting new folders while finished titles never pile up in memory.
  Future<void> _walkMovies(_CatCtx ctx, FolderNode stub, int depth) async {
    if (isExtrasFolder(stub.name) || depth > _o.maxMovieDepth) return;
    var held = false;
    try {
      await _items.reserve();
      held = true;
      _check();
      if (_same(_known[stub.url], stub.mtime)) {
        held = false;
        _emitUnchanged(ctx, stub.url);
        return;
      }
      final node = await _listRetryEmpty(stub);
      if (_unverified(ctx, stub, node, folderless: true)) {
        held = false;
        return;
      }
      if (isMovieTitleFolder(node)) {
        held = false;
        _emitTitle(
          ctx,
          classifyMovieFolder(node, categoryId: ctx.id, kind: ctx.config.kind),
        );
      } else {
        held = false;
        _items.release();
        await Future.wait([
          for (final k in node.folders) _walkMovies(ctx, k, depth + 1),
        ]);
      }
    } on CrawlCancelled {
      ctx.complete = false;
    } on FetchException catch (e) {
      ctx.complete = false;
      _issue(CrawlIssue(url: e.url.toString(), message: e.message));
    } finally {
      if (held) _items.release();
    }
  }

  Future<void> _walkSeries(_CatCtx ctx, FolderNode stub) async {
    if (isExtrasFolder(stub.name)) return;
    var held = false;
    try {
      await _items.reserve();
      held = true;
      _check();
      final node = await _listRetryEmpty(stub);
      if (_unverified(ctx, stub, node)) {
        held = false;
        return;
      }
      if (looksLikeShow(node)) {
        if (_same(_known[node.url], showFingerprint(node))) {
          held = false;
          _emitUnchanged(ctx, node.url);
          return;
        }
        final full = await _expand(node, _o.maxShowDepth, isShow: true);
        final t = classifyShow(full, categoryId: ctx.id);
        if (t != null) {
          held = false;
          _emitTitle(ctx, t);
        }
      } else {
        held = false;
        _items.release();
        await Future.wait([for (final k in node.folders) _walkSeries(ctx, k)]);
      }
    } on CrawlCancelled {
      ctx.complete = false;
    } on FetchException catch (e) {
      ctx.complete = false;
      _issue(CrawlIssue(url: e.url.toString(), message: e.message));
    } finally {
      if (held) _items.release();
    }
  }

  /// Lists the children of a show (seasons) and, for season folders without
  /// direct media, their children (nested release folders).
  Future<FolderNode> _expand(
    FolderNode n,
    int depthLeft, {
    bool isShow = false,
  }) async {
    if (depthLeft <= 0 || (!isShow && hasMedia(n))) return n;
    final kids = await Future.wait([
      for (final k in n.folders)
        if (!isExtrasFolder(k.name))
          _list(
            k.url,
            name: k.name,
            mtime: k.mtime,
          ).then((l) => _expand(l, depthLeft - 1)),
    ]);
    return FolderNode(
      name: n.name,
      url: n.url,
      mtime: n.mtime,
      files: n.files,
      folders: kids,
    );
  }
}
