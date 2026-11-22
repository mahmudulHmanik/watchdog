import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/platform/platform_api.dart';

/// Live updates are subscribed first and buffered while the snapshot loads,
/// then merged over it (latest event per id wins), so nothing emitted during
/// the snapshot await is dropped.
final downloadsProvider = StreamProvider<List<DownloadProgress>>((ref) async* {
  final api = ref.watch(platformApiProvider);
  final map = <String, DownloadProgress>{};
  final pending = <DownloadProgress>[];
  final tick = StreamController<void>();
  var ready = false;
  final sub = api.downloadUpdates.listen((u) {
    if (!ready) {
      pending.add(u);
    } else {
      map[u.id] = u;
      tick.add(null);
    }
  });
  ref.onDispose(() {
    sub.cancel();
    tick.close();
  });
  for (final d in await api.downloads()) {
    map[d.id] = d;
  }
  for (final u in pending) {
    map[u.id] = u;
  }
  pending.clear();
  ready = true;
  yield map.values.toList();
  await for (final _ in tick.stream) {
    yield map.values.toList();
  }
});
