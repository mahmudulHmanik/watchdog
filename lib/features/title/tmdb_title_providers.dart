import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/search/search_providers.dart'
    show tmdbHasDataProvider;
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart';

/// Stored TMDB data of one title (what the title screen shows at once).
final tmdbInfoProvider = FutureProvider.autoDispose.family<TmdbInfo?, int>(
  (ref, id) => ref.watch(repositoryProvider).tmdbInfo(id),
);

/// On-open lookup. Null result = no key. Refreshes [tmdbInfoProvider] when
/// new data was saved. The title screen watches it so it lives as long as
/// the screen does.
final tmdbFetchProvider = FutureProvider.autoDispose
    .family<TmdbFetchResult?, int>((ref, id) async {
      final sync = ref.watch(tmdbSyncProvider);
      if (sync == null) return null;
      final r = await sync.fetchNowById(id);
      if (ref.mounted &&
          (r.status == TmdbFetchStatus.matched ||
              r.status == TmdbFetchStatus.unmatched)) {
        ref.invalidate(tmdbInfoProvider(id));
        ref.invalidate(tmdbHasDataProvider);
      }
      return r;
    });
