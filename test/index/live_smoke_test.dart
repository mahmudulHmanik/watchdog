// ignore_for_file: avoid_print
// Live incremental-index check on ONE default category into an in-memory repo,
// plus event-loop lag measurement. Needs BDIX.
// Opt-in: WATCHDOG_LIVE="3D Movies" flutter test test/index/live_smoke_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/features/index/index_service.dart';

class CountingClient implements ListingClient {
  CountingClient(this.inner);
  final ListingClient inner;
  int requests = 0;
  @override
  Future<String> fetch(Uri url, {required Duration timeout}) {
    requests++;
    return inner.fetch(url, timeout: timeout);
  }

  @override
  void close() => inner.close();
}

Future<void> run(String name) async {
  final servers = [
    for (final s in CrawlConfig.defaults().servers)
      s.copyWith(
        categories: [
          for (final c in s.categories)
            if (c.name == name) c,
        ],
      ),
  ].where((s) => s.categories.isNotEmpty).toList();
  expect(servers, isNotEmpty);
  final cfg = CrawlConfig(servers: servers);
  final client = CountingClient(HttpListingClient());
  final repo = DriftRepository.memory();
  final svc = IndexService(
    repository: repo,
    client: client,
    configOf: () => cfg,
  );

  var maxLag = Duration.zero;
  final sw = Stopwatch()..start();
  var last = sw.elapsed;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
    final now = sw.elapsed;
    final lag = now - last - const Duration(milliseconds: 5);
    if (lag > maxLag) maxLag = lag;
    last = now;
  });

  for (final full in [true, false]) {
    client.requests = 0;
    final r = await svc.reindex(full: full);
    print(
      '${full ? 'full' : 'incremental'}: ${r.outcome.name} requests=${client.requests} '
      'written=${r.titlesWritten} unchanged=${r.titlesUnchanged} '
      'removed=${r.titlesRemoved} batches=${r.batches} ${r.elapsed.inMilliseconds} ms',
    );
  }
  timer.cancel();
  print('titles in repo: ${(await repo.counts()).titles}');
  print('max event-loop lag: ${maxLag.inMilliseconds} ms');
  client.close();
}

void main() {
  final live = Platform.environment['WATCHDOG_LIVE'];
  test(
    'live incremental index of one category',
    () => run(live!),
    timeout: const Timeout(Duration(minutes: 3)),
    skip: live == null
        ? 'set WATCHDOG_LIVE=<category name> (needs BDIX)'
        : false,
  );
}
