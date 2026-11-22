import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart'
    show tmdbRevisionProvider;
import 'package:watchdog/tmdb/tmdb_models.dart';

class SearchFilterNotifier extends Notifier<BrowseFilter> {
  @override
  BrowseFilter build() => const BrowseFilter();
  void set(BrowseFilter f) => state = f;
}

final searchFilterProvider =
    NotifierProvider<SearchFilterNotifier, BrowseFilter>(
      SearchFilterNotifier.new,
    );

/// Actors whose name matches the search text (empty for blank input). The UI
/// debounces the text before passing it in.
final peopleMatchesProvider = FutureProvider.autoDispose
    .family<List<PersonHit>, String>((ref, query) async {
      final q = query.trim();
      if (q.isEmpty) return const [];
      return ref.watch(repositoryProvider).searchPeople(q);
    });

/// One actor by TMDB person id (for the "actor" filter chip).
final personProvider = FutureProvider.autoDispose.family<PersonHit?, int>(
  (ref, id) => ref.watch(repositoryProvider).person(id),
);

/// Genre facet, scoped by the other active filters (its own selection is
/// ignored by the repository).
final genreFacetsProvider = FutureProvider.autoDispose
    .family<List<FacetValue<TmdbGenre>>, BrowseFilter>((ref, within) {
      ref.watch(tmdbRevisionProvider);
      return ref.watch(repositoryProvider).genres(within);
    });

/// TMDB original-language facet (ISO codes such as `en`, `hi`).
final tmdbLanguageFacetsProvider = FutureProvider.autoDispose
    .family<List<FacetValue<String>>, BrowseFilter>((ref, within) {
      ref.watch(tmdbRevisionProvider);
      return ref.watch(repositoryProvider).tmdbLanguages(within);
    });

/// True once at least one title has TMDB data; the TMDB filters are only
/// shown then. Refreshes on the throttled [tmdbRevisionProvider].
final tmdbHasDataProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(tmdbRevisionProvider);
  final p = await ref.watch(repositoryProvider).tmdbProgress();
  return p.matched > 0;
});
