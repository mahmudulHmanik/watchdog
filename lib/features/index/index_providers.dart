import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:watchdog/core/config/crawl_config.dart';
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

final listingClientProvider = Provider<ListingClient>((ref) {
  final c = HttpListingClient();
  ref.onDispose(c.close);
  return c;
});

final indexServiceProvider = Provider<IndexService>((ref) {
  final s = IndexService(
    repository: ref.watch(repositoryProvider),
    client: ref.watch(listingClientProvider),
    configOf: () => ref.read(crawlConfigProvider),
    meta: ref.watch(indexMetaProvider),
  );
  ref.onDispose(s.dispose);
  return s;
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

class _LazyFileMeta implements IndexMetaStore {
  FileIndexMeta? _m;
  Future<FileIndexMeta> _get() async => _m ??= FileIndexMeta(
    File('${(await getApplicationSupportDirectory()).path}/index_meta.json'),
  );

  @override
  Future<DateTime?> lastIndexedAt() async => (await _get()).lastIndexedAt();
  @override
  Future<void> setLastIndexedAt(DateTime t) async =>
      (await _get()).setLastIndexedAt(t);
}
