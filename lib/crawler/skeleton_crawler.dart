// Drives the API client + skeleton classifier over one category. Pure
// crawler: no repository types. Phase B maps [SkeletonTitle]s to the index.
import 'dart:async';

import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/bounded_queue.dart';
import 'package:watchdog/crawler/crawler.dart' show CancelToken;
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/host_limiter.dart';
import 'package:watchdog/crawler/skeleton.dart';

class SkeletonIssue {
  const SkeletonIssue(this.url, this.message, {this.reason});
  final String url;
  final String message;
  final ApiFailure? reason;
  @override
  String toString() => '$url: $message';
}

class SkeletonSummary {
  const SkeletonSummary({
    required this.complete,
    required this.titles,
    required this.requests,
    required this.issues,
    required this.needsHtmlFallback,
    required this.warnings,
  });

  /// Every folder was listed and no error occurred: only then is it safe to
  /// delete titles that were not seen.
  final bool complete;
  final int titles;
  final int requests;
  final List<SkeletonIssue> issues;

  /// The API misbehaved (unsupported / bad answer): redo with the HTML
  /// crawler.
  final bool needsHtmlFallback;
  final List<String> warnings;
}

class SkeletonRun {
  SkeletonRun._(this.titles, this.done, this._cancel);

  /// Bounded (backpressure) single-subscription stream; read it with
  /// `await for`. Cancelling the subscription cancels the crawl.
  final Stream<SkeletonTitle> titles;

  /// Completes (never throws) when the category is done, failed or cancelled.
  final Future<SkeletonSummary> done;
  final CancelToken _cancel;
  void cancel() => _cancel.cancel();
}

class SkeletonCrawler {
  SkeletonCrawler(
    this.api, {
    this.buffer = 256,
    this.parallel = 6,
    this.descendWarnAt = 64,
    this.seasonContainersAsSeries = true,
  });

  final H5aiApiClient api;

  /// Max titles buffered between the crawl and the consumer.
  final int buffer;

  /// Folders being fetched/classified/emitted at once (the host limiter on
  /// the client further caps requests per host).
  final int parallel;

  /// A single parent with more unlisted children than this is suspicious
  /// (each `what=2` repeats the ancestors' siblings): reported as a warning.
  final int descendWarnAt;

  /// See [SkeletonClassifier.seasonContainersAsSeries].
  final bool seasonContainersAsSeries;

  /// Starts crawling [cat] (on [host], e.g. `172.16.50.7`).
  ///
  /// [only] restricts the first level below the category root to the child
  /// folders it accepts (by href, as served): the incremental run re-reads
  /// just the year buckets / groups whose [probeCategory] signature changed.
  /// [onRoot] gets the root answer as soon as it arrives (cheap totals for
  /// progress estimates, no extra request).
  SkeletonRun crawlCategory(
    String host,
    CategoryConfig cat, {
    CancelToken? cancel,
    bool Function(String href)? only,
    void Function(ApiItem root)? onRoot,
  }) {
    final token = cancel ?? CancelToken();
    final q = BoundedQueue<SkeletonTitle>(buffer);
    final done = Completer<SkeletonSummary>();
    final issues = <SkeletonIssue>[];
    final warnings = <String>[];
    var titles = 0;
    final startRequests = api.requests;
    final classifier = SkeletonClassifier(
      origin: 'http://$host',
      seasonContainersAsSeries: seasonContainersAsSeries,
    );
    // Gate around fetch + classify + emit, so waiting walkers hold only a
    // folder href, never a pile of finished titles.
    final gate = AdaptiveLimiter(start: parallel, min: parallel, max: parallel);

    token.whenCancelled.then((_) => q.abort());
    q.onConsumerCancel = token.cancel;

    final root = Uri.parse(cat.url.endsWith('/') ? cat.url : '${cat.url}/');

    Future<void> walk(Uri url, int what) async {
      if (token.isCancelled) return;
      List<Uri> next = const [];
      try {
        next = await gate.run(() async {
          if (token.isCancelled) return const <Uri>[];
          var folder = await api.getFolder(url, what: what);
          if (identical(url, root)) {
            onRoot?.call(folder);
            if (only != null) {
              folder = ApiItem(
                name: folder.name,
                href: folder.href,
                isFolder: true,
                time: folder.time,
                children: [
                  for (final c in folder.children ?? const <ApiItem>[])
                    if (only(c.href)) c,
                ],
              );
            }
          }
          final lvl = classifier.classify(
            folder,
            layout: cat.layout,
            kind: cat.kind,
          );
          for (final t in lvl.titles) {
            if (token.isCancelled) break;
            titles++;
            await q.add(t);
          }
          if (lvl.descend.length > descendWarnAt) {
            warnings.add(
              '${lvl.descend.length} unlisted folders under ${folder.href}',
            );
          }
          return [
            for (final c in lvl.descend) Uri.parse('http://$host${c.href}'),
          ];
        });
      } on ApiException catch (e) {
        issues.add(SkeletonIssue('$url', e.message, reason: e.reason));
        return;
      }
      // Descend outside the gate: a container must not hold a slot while its
      // children wait for one.
      await Future.wait([for (final u in next) walk(u, 2)]);
    }

    Future<void> run() async {
      // Year/language bucket roots only need their child list; series and
      // flat roots hold titles (or shows with seasons) one level down.
      final what = cat.layout == LayoutKind.yearBuckets ? 1 : 2;
      try {
        await walk(root, what);
      } catch (e) {
        issues.add(SkeletonIssue('$root', 'internal error: $e'));
      } finally {
        q.close();
        done.complete(
          SkeletonSummary(
            complete: issues.isEmpty && !token.isCancelled,
            titles: titles,
            requests: api.requests - startRequests,
            issues: List.unmodifiable(issues),
            needsHtmlFallback: issues.any(
              (i) =>
                  i.reason == ApiFailure.unsupported ||
                  i.reason == ApiFailure.badResponse,
            ),
            warnings: List.unmodifiable(warnings),
          ),
        );
      }
    }

    unawaited(run());
    return SkeletonRun._(q.stream, done.future, token);
  }
}
