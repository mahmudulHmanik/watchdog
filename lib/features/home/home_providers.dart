import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/crawler/crawler.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/index/index_providers.dart';

/// Reachability of the DhakaFlix hosts: one probe per host, cached until
/// invalidated (pill tap or an index run finishing). true = any host answered.
final bdixOnlineProvider = FutureProvider<bool>((ref) async {
  ref.keepAlive();
  final cfg = ref.read(crawlConfigProvider);
  final crawler = Crawler(ref.read(listingClientProvider));
  final servers = {for (final (s, _) in cfg.enabledCategories) s.host: s}.values
      .toList();
  if (servers.isEmpty) return false;
  final probes = await Future.wait(servers.map(crawler.probeHost));
  final online = probes.any((p) => p.reachable);
  if (!online) {
    // A failed probe (phone just woke up, Wi-Fi switching) must not stick
    // until the user taps the pill: look again shortly while offline.
    final retry = Timer(const Duration(seconds: 15), ref.invalidateSelf);
    ref.onDispose(retry.cancel);
  }
  return online;
});

/// Recently added titles for the Home grid, optionally within a category.
final recentTitlesProvider = FutureProvider.family<List<MediaTitle>, int?>((
  ref,
  categoryId,
) {
  ref.watch(revisionProvider);
  return ref
      .watch(repositoryProvider)
      .browse(
        BrowseFilter(categoryId: categoryId, sort: BrowseSort.recentlyAdded),
        limit: 12,
      );
});
