import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/host_limiter.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/index/index_meta.dart';
import 'package:watchdog/features/index/index_service.dart';

/// Active crawl config. Defaults only; Settings can override later.
final crawlConfigProvider = Provider<CrawlConfig>(
  (ref) => CrawlConfig.defaults(),
);

/// Where index metadata lives; override in tests.
final indexMetaProvider = Provider<IndexMetaStore>((ref) => _LazyFileMeta());

/// Per-host request limits shared by the API client and the HTML fallback:
/// polite, at most 8 in flight per host (adaptive 6..8).
final hostLimitersProvider = Provider<HostLimiters>(
  (ref) => HostLimiters(max: 8),
);

final listingClientProvider = Provider<ListingClient>((ref) {
  final c = HttpListingClient();
  ref.onDispose(c.close);
  return c;
});

/// h5ai JSON API client (fast skeleton crawl).
final h5aiApiProvider = Provider<H5aiApiClient>((ref) {
  final c = H5aiApiClient(limiters: ref.watch(hostLimitersProvider));
  ref.onDispose(c.close);
  return c;
});

final indexServiceProvider = Provider<IndexService>((ref) {
  final s = IndexService(
    repository: ref.watch(repositoryProvider),
    client: ref.watch(listingClientProvider),
    api: ref.watch(h5aiApiProvider),
    limiters: ref.watch(hostLimitersProvider),
    configOf: () => ref.read(crawlConfigProvider),
    meta: ref.watch(indexMetaProvider),
  );
  ref.onDispose(s.dispose);
  return s;
});

/// Start-up hook: watch it once (e.g. from the app shell). Loads the stored
/// status at once (so `isFirstRun` is right on the first frame) and starts
/// the index run in the background when the index is unfinished or stale. The
/// future completes with the run's result; the UI must not wait for it.
final indexBootstrapProvider = FutureProvider<void>((ref) async {
  final s = ref.read(indexServiceProvider);
  await s.loadStatus();
  // Fire and forget: progress is in [indexStateProvider].
  unawaited(s.ensureIndexed());
});

/// Current state, then live updates.
final indexStateProvider = StreamProvider<IndexState>((ref) async* {
  final s = ref.watch(indexServiceProvider);
  yield s.state;
  yield* s.states;
});

final lastIndexedAtProvider = FutureProvider<DateTime?>((ref) {
  ref.watch(indexStateProvider); // refresh when a run changes state
  return ref.watch(indexServiceProvider).lastIndexedAt();
});

class _LazyFileMeta extends IndexMetaStore {
  FileIndexMeta? _m;
  Future<FileIndexMeta> _get() async => _m ??= FileIndexMeta(
    File('${(await getApplicationSupportDirectory()).path}/index_meta.json'),
  );

  @override
  Future<IndexMetaData> read() async => (await _get()).read();

  @override
  Future<void> update(void Function(IndexMetaData m) change) async =>
      (await _get()).update(change);
}
