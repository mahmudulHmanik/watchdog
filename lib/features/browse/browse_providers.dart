import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';

/// Bumps whenever the index changes; watch it to refresh data providers.
class RevisionNotifier extends Notifier<int> {
  @override
  int build() {
    final sub = ref.watch(repositoryProvider).changes.listen((_) => state++);
    ref.onDispose(sub.cancel);
    return 0;
  }

  void bump() => state++;
}

final revisionProvider = NotifierProvider<RevisionNotifier, int>(
  RevisionNotifier.new,
);

/// Minimum gap between TMDB-driven refreshes.
final tmdbRefreshIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

/// Throttled `tmdbChanges`: bumps on the first write, then at most once per
/// [tmdbRefreshIntervalProvider] (trailing edge, only if more writes came).
/// [flush] delivers a pending bump now (call when the sync goes idle).
/// Watch it only from what needs TMDB freshness (facets, "has data", sync
/// counts); never from the Search list key or crawl-driven lists, a
/// background sync would reset them every few seconds.
class TmdbRevisionNotifier extends Notifier<int> {
  Timer? _cooldown;
  bool _pending = false;

  @override
  int build() {
    final gap = ref.watch(tmdbRefreshIntervalProvider);
    final sub = ref
        .watch(repositoryProvider)
        .tmdbChanges
        .listen((_) => _event(gap));
    ref.onDispose(() {
      sub.cancel();
      _cooldown?.cancel();
      _cooldown = null;
      _pending = false;
    });
    return 0;
  }

  void _event(Duration gap) {
    if (_cooldown != null) {
      _pending = true;
      return;
    }
    _fire(gap);
  }

  void _fire(Duration gap) {
    _pending = false;
    state++;
    _cooldown?.cancel();
    _cooldown = Timer(gap, () {
      _cooldown = null;
      if (_pending) _fire(gap);
    });
  }

  /// Deliver a pending bump now.
  void flush() {
    if (_pending) _fire(ref.read(tmdbRefreshIntervalProvider));
  }
}

final tmdbRevisionProvider = NotifierProvider<TmdbRevisionNotifier, int>(
  TmdbRevisionNotifier.new,
);

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(revisionProvider);
  return ref.watch(repositoryProvider).categories();
});

final countsProvider = FutureProvider<IndexCounts>((ref) {
  ref.watch(revisionProvider);
  return ref.watch(repositoryProvider).counts();
});

final continueWatchingProvider = FutureProvider<List<ResumeItem>>((ref) {
  ref.watch(revisionProvider);
  return ref.watch(repositoryProvider).continueWatching();
});

/// Category chip selected on Home (null = all).
class SelectedCategory extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final selectedCategoryProvider = NotifierProvider<SelectedCategory, int?>(
  SelectedCategory.new,
);

/// User chose to browse without indexing first.
class SkipIndex extends Notifier<bool> {
  @override
  bool build() => false;
  void skip() => state = true;
}

final skipIndexProvider = NotifierProvider<SkipIndex, bool>(SkipIndex.new);

/// Bottom-nav tab: 0 Home, 1 Search, 2 Downloads, 3 Settings.
class NavIndex extends Notifier<int> {
  @override
  int build() => ref.watch(initialTabProvider);
  void go(int i) => state = i;
}

final initialTabProvider = Provider<int>((ref) => 0);
final navIndexProvider = NotifierProvider<NavIndex, int>(NavIndex.new);

const tabHome = 0, tabSearch = 1, tabDownloads = 2, tabSettings = 3;
