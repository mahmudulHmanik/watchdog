// Connects the Crawler to the Repository. Plain Dart; no UI.
import 'dart:async';

import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/crawler.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/index/index_meta.dart';

enum IndexPhase { idle, probing, crawling, writing, done, failed }

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
  });
  final IndexPhase phase;
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

  bool get running =>
      phase == IndexPhase.probing ||
      phase == IndexPhase.crawling ||
      phase == IndexPhase.writing;

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
  );
}

class IndexResult {
  const IndexResult({
    required this.outcome,
    required this.elapsed,
    this.message,
    this.summary,
    this.titlesWritten = 0,
    this.titlesUnchanged = 0,
    this.titlesRemoved = 0,
    this.batches = 0,
    this.categoriesComplete = 0,
    this.categoriesIncomplete = 0,
    this.foldersFetched = 0,
    this.full = false,
  });
  final IndexOutcome outcome;
  final Duration elapsed;
  final String? message;

  /// Crawler summary (null when nothing was crawled, e.g. off-BDIX).
  final CrawlSummary? summary;
  final int titlesWritten;
  final int titlesUnchanged;
  final int titlesRemoved;
  final int batches;
  final int categoriesComplete;
  final int categoriesIncomplete;
  final int foldersFetched;
  final bool full;

  bool get offBdix => outcome == IndexOutcome.offBdix;
  bool get ok => outcome == IndexOutcome.success;
}

class IndexService {
  IndexService({
    required this.repository,
    required this.client,
    required this.configOf,
    IndexMetaStore? meta,
    this.options = const CrawlOptions(),
    this.batchSize = 200,
    DateTime Function()? now,
  }) : meta = meta ?? MemoryIndexMeta(),
       _now = now ?? DateTime.now;

  final Repository repository;
  final ListingClient client;

  /// Read at the start of every reindex (so Settings edits apply).
  final CrawlConfig Function() configOf;
  final IndexMetaStore meta;
  final CrawlOptions options;
  final int batchSize;
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

  /// Cancels the current run, if any. Already committed batches stay.
  void cancel() => _token?.cancel();

  /// Crawls and updates the index. A concurrent call joins the running one.
  /// [full] ignores stored mtimes (re-crawls every title).
  Future<IndexResult> reindex({
    bool full = false,
    CrawlConfig? config,
    CancelToken? cancel,
  }) =>
      _running ??= _reindex(full, config ?? configOf(), cancel ?? CancelToken())
          .whenComplete(() {
            _running = null;
            _token = null;
          });

  void _set(IndexState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  Future<IndexResult> _reindex(
    bool full,
    CrawlConfig cfg,
    CancelToken token,
  ) async {
    final sw = Stopwatch()..start();
    _token = token;
    _set(const IndexState(phase: IndexPhase.probing));
    final crawler = Crawler(client, options: options);

    IndexResult finish(
      IndexOutcome o,
      IndexPhase phase, {
      String? message,
      CrawlSummary? summary,
      int written = 0,
      int unchanged = 0,
      int removed = 0,
      int batches = 0,
    }) {
      final cs = summary?.results ?? const <CategoryResult>[];
      _set(
        _state.copyWith(
          phase: phase,
          offBdix: o == IndexOutcome.offBdix,
          message: message ?? '',
          titlesWritten: written,
          titlesRemoved: removed,
        ),
      );
      return IndexResult(
        outcome: o,
        elapsed: sw.elapsed,
        message: message,
        summary: summary,
        titlesWritten: written,
        titlesUnchanged: unchanged,
        titlesRemoved: removed,
        batches: batches,
        categoriesComplete: cs.where((c) => c.complete).length,
        categoriesIncomplete: cs.where((c) => !c.complete).length,
        foldersFetched: summary?.foldersFetched ?? 0,
        full: full,
      );
    }

    try {
      final enabled = cfg.enabledCategories.toList();
      if (enabled.isEmpty) {
        return finish(
          IndexOutcome.success,
          IndexPhase.done,
          message: 'No categories enabled.',
        );
      }

      // 1. Fail fast off-BDIX, before touching the repository.
      final servers = <ServerConfig>[];
      for (final (s, _) in enabled) {
        if (!servers.contains(s)) servers.add(s);
      }
      final probes = await Future.wait(servers.map(crawler.probeHost));
      final down = [
        for (final p in probes)
          if (!p.reachable) p.host,
      ];
      if (down.length == probes.length) {
        return finish(
          IndexOutcome.offBdix,
          IndexPhase.failed,
          message: offBdixMessage(down),
        );
      }
      if (token.isCancelled) {
        return finish(
          IndexOutcome.cancelled,
          IndexPhase.failed,
          message: 'Cancelled.',
        );
      }

      // 2. Categories on reachable hosts -> ids.
      final drafts = [
        for (final (s, c) in enabled)
          if (!down.contains(s.host)) c.toDraft(s.host),
      ];
      final ids = await repository.upsertCategories(drafts);

      // 3. Known mtimes (incremental).
      final known = <String, DateTime>{};
      if (!full) {
        for (final id in ids.values) {
          (await repository.knownFolders(id)).forEach((u, m) {
            if (m != null) known[u] = m;
          });
        }
      }

      // 4. Crawl, writing in batches.
      _set(_state.copyWith(phase: IndexPhase.crawling));
      final run = crawler.start(
        cfg,
        known: known,
        cancel: token,
        categoryIdFor: (c) => ids[c.url] ?? -1,
      );
      final progressSub = run.progress.listen((p) {
        _set(
          _state.copyWith(
            foldersFetched: p.foldersFetched,
            titlesFound: p.titlesFound,
            titlesUnchanged: p.titlesUnchanged,
            errors: p.errors,
            lastError: p.lastError,
          ),
        );
      });

      final seen = <String, Set<String>>{}; // category url -> folderUrls
      final buffer = <TitleDraft>[];
      var written = 0, batches = 0, unchanged = 0;
      Object? writeError;

      Future<void> flush() async {
        if (buffer.isEmpty) return;
        final batch = List<TitleDraft>.of(buffer);
        buffer.clear();
        final prev = _state.phase;
        _set(_state.copyWith(phase: IndexPhase.writing));
        await repository.upsertTitles(batch);
        written += batch.length;
        batches++;
        _set(_state.copyWith(phase: prev, titlesWritten: written));
        // Let the UI breathe between batches.
        await Future<void>.delayed(Duration.zero);
      }

      try {
        await for (final item in run.items) {
          final s = seen.putIfAbsent(item.category.url, () => {});
          switch (item) {
            case TitleItem(:final draft):
              s.add(draft.folderUrl);
              buffer.add(draft);
              if (buffer.length >= batchSize) await flush();
            case UnchangedItem(:final folderUrl):
              s.add(folderUrl);
              unchanged++;
          }
        }
        await flush();
      } catch (e) {
        writeError = e;
        token.cancel();
      }
      final summary = await run.done;
      await progressSub.cancel();

      if (writeError != null) {
        return finish(
          IndexOutcome.failed,
          IndexPhase.failed,
          message: 'Index write failed: $writeError',
          summary: summary,
          written: written,
          unchanged: unchanged,
          batches: batches,
        );
      }

      // 5. Delete vanished titles, only for fully crawled categories.
      var removed = 0;
      if (!summary.cancelled && !summary.offBdix) {
        for (final r in summary.results) {
          if (!r.complete) continue;
          final id = ids[r.category.url];
          if (id == null) continue;
          final keep = seen[r.category.url] ?? const <String>{};
          if (keep.isEmpty && (await repository.knownFolders(id)).isNotEmpty) {
            // A "complete" crawl that saw nothing is not trustworthy.
            continue;
          }
          removed += await repository.removeMissing(id, keep);
        }
      }

      final anyComplete = summary.results.any((r) => r.complete);
      if (anyComplete && !summary.cancelled) {
        await meta.setLastIndexedAt(_now());
      }

      final IndexOutcome outcome;
      final String? message;
      if (summary.cancelled) {
        outcome = IndexOutcome.cancelled;
        message = 'Cancelled.';
      } else if (summary.offBdix) {
        outcome = IndexOutcome.offBdix;
        message = summary.failureMessage;
      } else if (summary.complete) {
        outcome = IndexOutcome.success;
        message = null;
      } else {
        outcome = IndexOutcome.partial;
        message = summary.failureMessage;
      }
      return finish(
        outcome,
        outcome == IndexOutcome.success || outcome == IndexOutcome.partial
            ? IndexPhase.done
            : IndexPhase.failed,
        message: message,
        summary: summary,
        written: written,
        unchanged: unchanged,
        removed: removed,
        batches: batches,
      );
    } catch (e) {
      return finish(
        IndexOutcome.failed,
        IndexPhase.failed,
        message: 'Index failed: $e',
      );
    }
  }

  void dispose() {
    _token?.cancel();
    _states.close();
  }
}
