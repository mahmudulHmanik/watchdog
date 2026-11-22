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
