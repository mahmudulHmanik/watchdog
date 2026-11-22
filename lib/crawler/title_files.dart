// Single-title file listing (lazy files): lists one title's folder (and its
// season folders) over the HTML listing client, classifies with the same
// code as the full crawler, and writes the result with
// `Repository.upsertTitleFiles`. No UI, no Riverpod.
import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:watchdog/crawler/classifier.dart';
import 'package:watchdog/crawler/fast_listing.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/crawler/parsing.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';

class TitleLoadOptions {
  const TitleLoadOptions({
    this.requestTimeout = const Duration(seconds: 10),
    this.retries = 2,
    this.backoffBase = const Duration(milliseconds: 300),
    this.concurrency = 6,
    this.parseOffloadBytes = 256 * 1024,
    this.maxCacheRows = 20000,
  });

  final Duration requestTimeout;

  /// Retries after the first attempt (network trouble, 5xx/408/429 only).
  final int retries;

  /// Delay before retry n is backoffBase * 2^(n-1).
  final Duration backoffBase;

  /// Simultaneous requests across all loads of one loader.
  final int concurrency;

  /// Bodies larger than this are parsed in a short-lived isolate.
  final int parseOffloadBytes;

  /// Cap handed to `Repository.trimFileCache` after each load.
  final int maxCacheRows;
}

/// Caller-side cancel (e.g. the screen was closed).
class LoadCancel {
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

class TitleLoadCancelled implements Exception {
  const TitleLoadCancelled();
  @override
  String toString() => 'TitleLoadCancelled';
}

/// The title id is not in the index.
class TitleNotFound implements Exception {
  const TitleNotFound(this.titleId);
  final int titleId;
  @override
  String toString() => 'TitleNotFound($titleId)';
}

class TitleFilesResult {
  const TitleFilesResult({
    required this.fromNetwork,
    this.files = 0,
    this.seasons = 0,
  });

  /// False: served from the DB, no request was made.
  final bool fromNetwork;
  final int files;
  final int seasons;
}

/// Files/seasons drafts of one title, ready for `upsertTitleFiles`.
class TitleFilesDraft {
  const TitleFilesDraft({this.files = const [], this.seasons = const []});
  final List<FileDraft> files;
  final List<SeasonDraft> seasons;
}

class _Gate {
  _Gate(this.max);
  final int max;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() f) async {
    if (_active >= max) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future; // permit handed over
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

bool _sameUrl(String? a, String? b) {
  if (a == null || b == null) return false;
  if (a == b) return true;
  try {
    return Uri.decodeFull(a) == Uri.decodeFull(b);
  } catch (_) {
    return false;
  }
}

/// Lists one title and builds its drafts. Pure IO + classification; the
/// repository is only used by [TitleFilesLoader].
class TitleFilesFetcher {
  TitleFilesFetcher(this.client, {this.options = const TitleLoadOptions()})
    : _gate = _Gate(options.concurrency);

  final ListingClient client;
  final TitleLoadOptions options;
  final _Gate _gate;

  Future<String> _get(Uri url, LoadCancel? cancel) async {
    var attempt = 0;
    while (true) {
      _check(cancel);
      try {
        final body = await _gate.run(() {
          _check(cancel);
          return client.fetch(url, timeout: options.requestTimeout);
        });
        _check(cancel);
        return body;
      } on TitleLoadCancelled {
        rethrow;
      } on FetchException catch (e) {
        if (!e.retryable || attempt >= options.retries) rethrow;
      } catch (e) {
        // Not a FetchException: a client that cannot even try. Treat as
        // "no answer" so the UI says offline.
        if (attempt >= options.retries) {
          throw FetchException(url, FetchFailure.connect, '$e');
        }
      }
      attempt++;
      final delay = options.backoffBase * (1 << (attempt - 1));
      if (cancel == null) {
        await Future<void>.delayed(delay);
      } else {
        await Future.any([Future<void>.delayed(delay), cancel.whenCancelled]);
      }
    }
  }

  static void _check(LoadCancel? c) {
    if (c != null && c.isCancelled) throw const TitleLoadCancelled();
  }

  /// A blank page under load is retried once. [allowEmpty] false: an empty
  /// listing is an error (cannot tell "no files" from a failed read).
  Future<FolderNode> _list(
    String url,
    LoadCancel? cancel, {
    String? name,
    DateTime? mtime,
    bool allowEmpty = true,
  }) async {
    final uri = Uri.parse(url);
    Future<FolderNode> once() async {
      final body = await _get(uri, cancel);
      final entries = body.length > options.parseOffloadBytes
          ? await Isolate.run(() => parseListingFast(body))
          : parseListingFast(body);
      _check(cancel);
      // Uri.pathSegments are already decoded (FolderNode would decode twice,
      // which throws on a literal '%').
      final folderName =
          name ??
          uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
      return FolderNode.fromListing(
        url,
        entries,
        name: folderName,
        mtime: mtime,
      );
    }

    var node = await once();
    if (node.files.isEmpty && node.folders.isEmpty) node = await once();
    if (!allowEmpty && node.files.isEmpty && node.folders.isEmpty) {
      throw FetchException(uri, FetchFailure.other, 'empty listing');
    }
    return node;
  }

  /// Drafts for [t]. [stored] = the title's stored seasons (series only); the
  /// returned season drafts reuse their identity (folder url, number, label,
  /// language) so season ids survive.
  Future<TitleFilesDraft> fetch(
    MediaTitle t, {
    List<Season> stored = const [],
    LoadCancel? cancel,
  }) => t.kind == TitleKind.series
      ? _series(t, stored, cancel)
      : _movie(t, cancel);

  /// Movie/event: direct media of the title folder plus the media directly in
  /// its non-extras subfolders (nested release folders, flattened).
  Future<TitleFilesDraft> _movie(MediaTitle t, LoadCancel? cancel) async {
    final node = await _list(t.folderUrl, cancel, allowEmpty: false);
    final kids = await Future.wait([
      for (final k in node.folders)
        if (!isExtrasFolder(k.name))
          _list(k.url, cancel, name: k.name, mtime: k.mtime),
    ]);
    final merged = FolderNode(
      name: node.name,
      url: node.url,
      mtime: node.mtime,
      files: [
        ...node.files,
        for (final k in kids)
          for (final f in k.files)
            if (isVideo(f.name) || isArchive(f.name)) f,
      ],
    );
    final d = classifyMovieFolder(
      merged,
      categoryId: t.categoryId,
      kind: t.kind,
    );
    return TitleFilesDraft(files: d.files);
  }

  /// Show: season folders listed in parallel (nested release folders one
  /// level deeper when a season holds no media directly), as the crawler does.
  Future<TitleFilesDraft> _series(
    MediaTitle t,
    List<Season> stored,
    LoadCancel? cancel,
  ) async {
    final node = await _list(t.folderUrl, cancel, allowEmpty: false);
    final seasonNodes = await Future.wait([
      for (final k in node.folders)
        if (!isExtrasFolder(k.name)) _season(k, cancel),
    ]);
    final full = FolderNode(
      name: node.name,
      url: node.url,
      mtime: node.mtime,
      files: node.files,
      folders: seasonNodes,
    );
    final d = classifyShow(full, categoryId: t.categoryId);
    return TitleFilesDraft(
      seasons: alignSeasons(d?.seasons ?? const [], stored, t.folderUrl),
    );
  }

  Future<FolderNode> _season(FolderNode k, LoadCancel? cancel) async {
    final s = await _list(k.url, cancel, name: k.name, mtime: k.mtime);
    if (hasMedia(s)) return s;
    final nested = await Future.wait([
      for (final n in s.folders)
        if (!isExtrasFolder(n.name))
          _list(n.url, cancel, name: n.name, mtime: n.mtime),
    ]);
    return FolderNode(
      name: s.name,
      url: s.url,
      mtime: s.mtime,
      files: s.files,
      folders: nested,
    );
  }
}

/// Gives each derived season the identity of the stored season it matches
/// (same folder, ignoring percent-encoding differences), so ids survive a
/// reload. Loose seasons (episodes directly in the show folder) have no
/// folder of their own in the classifier; they map to the stored season that
/// lives in the title folder, or get the title folder url.
List<SeasonDraft> alignSeasons(
  List<SeasonDraft> derived,
  List<Season> stored,
  String titleUrl,
) {
  final used = <int>{};
  Season? take(bool Function(Season s) test) {
    for (final s in stored) {
      if (!used.contains(s.id) && test(s)) {
        used.add(s.id);
        return s;
      }
    }
    return null;
  }

  bool sameIdentity(Season s, SeasonDraft d) =>
      s.number == d.number && s.label == d.label && s.language == d.language;

  final out = <SeasonDraft>[];
  for (final d in derived) {
    Season? m;
    if (d.folderUrl != null) {
      m = take((s) => _sameUrl(s.folderUrl, d.folderUrl));
    } else {
      m =
          take((s) => _sameUrl(s.folderUrl, titleUrl) && sameIdentity(s, d)) ??
          take((s) => _sameUrl(s.folderUrl, titleUrl));
    }
    // Legacy rows without a folder match on (number, label, language).
    m ??= take((s) => s.folderUrl == null && sameIdentity(s, d));
    out.add(
      SeasonDraft(
        number: m?.number ?? d.number,
        label: m?.label ?? d.label,
        language: m == null ? d.language : m.language,
        folderUrl: m != null ? m.folderUrl : (d.folderUrl ?? titleUrl),
        files: d.files,
      ),
    );
  }
  return out;
}

class _Run {
  _Run(this.token);
  final LoadCancel token;
  late final Future<TitleFilesResult> future;
  int waiters = 0;
}

/// Loads a title's files on demand and stores them (see
/// `Repository.upsertTitleFiles`). One load per title in flight; loaded and
/// fresh titles are served from the DB without any request.
class TitleFilesLoader {
  TitleFilesLoader({
    required this.repo,
    required this.client,
    this.protectedTitleIds,
    this.options = const TitleLoadOptions(),
  }) : _fetcher = TitleFilesFetcher(client, options: options);

  final Repository repo;
  final ListingClient client;
  final TitleLoadOptions options;

  /// Titles that must survive cache trimming (downloads). Throwing skips the
  /// trim rather than trimming unprotected.
  final Future<Set<int>> Function()? protectedTitleIds;

  final TitleFilesFetcher _fetcher;
  final _runs = <int, _Run>{};
  Future<void> _trimmed = Future.value();

  /// Completes when the trims started so far are done (tests, shutdown).
  Future<void> get trimIdle => _trimmed;

  bool isLoading(int titleId) => _runs.containsKey(titleId);

  /// Loads [titleId] unless its stored files are loaded and fresh. [force]
  /// reloads anyway. Concurrent calls share one run; [cancel] only detaches
  /// this caller (the run stops when no caller is left). Throws
  /// [FetchException] (network/HTTP/empty listing), [TitleNotFound],
  /// [TitleLoadCancelled].
  Future<TitleFilesResult> load(
    int titleId, {
    bool force = false,
    LoadCancel? cancel,
  }) {
    if (cancel != null && cancel.isCancelled) {
      return Future.error(const TitleLoadCancelled());
    }
    var run = _runs[titleId];
    // A run abandoned by all its callers is winding down: start a fresh one.
    if (run == null || run.token.isCancelled) {
      final r = run = _Run(LoadCancel());
      r.future = _execute(titleId, force, r.token).whenComplete(() {
        if (identical(_runs[titleId], r)) _runs.remove(titleId);
      });
      _runs[titleId] = r;
    }
    final shared = run;
    shared.waiters++;
    final out = Completer<TitleFilesResult>();
    shared.future.then(
      (v) {
        if (!out.isCompleted) out.complete(v);
      },
      onError: (Object e, StackTrace s) {
        if (!out.isCompleted) out.completeError(e, s);
      },
    );
    cancel?.whenCancelled.then((_) {
      if (out.isCompleted) return;
      out.completeError(const TitleLoadCancelled());
      if (--shared.waiters == 0) shared.token.cancel();
    });
    return out.future;
  }

  /// [load] for callers that only need the files to be there (playback).
  Future<void> ensureLoaded(int titleId) async {
    await load(titleId);
  }

  Future<TitleFilesResult> _execute(
    int id,
    bool force,
    LoadCancel token,
  ) async {
    final t = await repo.title(id);
    if (t == null) throw TitleNotFound(id);
    if (!force && t.filesLoaded) {
      return TitleFilesResult(
        fromNetwork: false,
        files: t.fileCount,
        seasons: t.seasonCount,
      );
    }
    final stored = t.kind == TitleKind.series
        ? [for (final s in await repo.seasons(id)) s.season]
        : const <Season>[];
    final d = await _fetcher.fetch(t, stored: stored, cancel: token);
    if (token.isCancelled) throw const TitleLoadCancelled();
    await repo.upsertTitleFiles(id, files: d.files, seasons: d.seasons);
    _trimmed = _trimmed.then((_) => _trim(id));
    return TitleFilesResult(
      fromNetwork: true,
      files: d.files.length + d.seasons.fold(0, (n, s) => n + s.files.length),
      seasons: d.seasons.length,
    );
  }

  Future<void> _trim(int justLoaded) async {
    try {
      final prot = await protectedTitleIds?.call() ?? const <int>{};
      await repo.trimFileCache(
        maxRows: options.maxCacheRows,
        protectedTitleIds: {...prot, justLoaded},
      );
    } catch (_) {
      // Best effort; the cache is only a cache.
    }
  }
}
