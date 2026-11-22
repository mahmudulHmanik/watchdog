import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/crawler/title_files.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/downloads/download_ids.dart';
import 'package:watchdog/features/index/index_providers.dart';

class TitleDetail {
  const TitleDetail({
    required this.title,
    required this.seasons,
    required this.files,
    required this.states,
  });
  final MediaTitle title;
  final List<SeasonEpisodes> seasons;
  final List<MediaFile> files;
  final Map<int, WatchState> states;
}

final titleDetailProvider = FutureProvider.family<TitleDetail?, int>((
  ref,
  id,
) async {
  final repo = ref.watch(repositoryProvider);
  final t = await repo.title(id);
  if (t == null) return null;
  final seasons = t.kind == TitleKind.series
      ? await repo.seasons(id)
      : const <SeasonEpisodes>[];
  final files = t.kind == TitleKind.series
      ? const <MediaFile>[]
      : await repo.titleFiles(id);
  final ids = [
    for (final s in seasons) ...s.files.map((f) => f.id),
    ...files.map((f) => f.id),
  ];
  return TitleDetail(
    title: t,
    seasons: seasons,
    files: files,
    states: await repo.watchStates(ids),
  );
});

/// Lazy file loader (one per app). Trims the file cache after each load,
/// never evicting titles that have downloads.
final titleFilesLoaderProvider = Provider<TitleFilesLoader>((ref) {
  return TitleFilesLoader(
    repo: ref.watch(repositoryProvider),
    client: ref.watch(listingClientProvider),
    protectedTitleIds: () => ref.read(downloadedTitleIdsProvider)(),
  );
});

/// One-shot "reload even if fresh" flag per title, consumed by
/// [titleFilesProvider] (pull-to-refresh, Retry after a failure).
class _ForceFlag {
  bool value = false;
  bool take() {
    final v = value;
    value = false;
    return v;
  }
}

final _forceFlagProvider = Provider.autoDispose.family<_ForceFlag, int>(
  (ref, id) => _ForceFlag(),
);

/// Load state of a title's files; opening the screen watches it, which
/// triggers the load once (served from the DB when loaded and fresh).
/// Loading -> spinner rows; error -> [describeLoadError]; data -> files are in
/// the DB and [titleDetailProvider] was refreshed. Closing the screen cancels.
final titleFilesProvider = FutureProvider.autoDispose
    .family<TitleFilesResult, int>((ref, id) async {
      final cancel = LoadCancel();
      ref.onDispose(cancel.cancel);
      final force = ref.watch(_forceFlagProvider(id)).take();
      final r = await ref
          .read(titleFilesLoaderProvider)
          .load(id, force: force, cancel: cancel);
      if (r.fromNetwork && ref.mounted) ref.invalidate(titleDetailProvider(id));
      return r;
    });

/// Force a reload (pull-to-refresh / Retry).
void reloadTitleFiles(WidgetRef ref, int id) {
  ref.read(_forceFlagProvider(id)).value = true;
  ref.invalidate(titleFilesProvider(id));
}

/// User-facing text for a failed load; [offline] -> show the BDIX hint.
({String message, bool offline}) describeLoadError(Object e) {
  if (e is FetchException) {
    if (e.noAnswer) {
      return (
        message: "Can't reach the server. Playback needs BDIX.",
        offline: true,
      );
    }
    if (e.kind == FetchFailure.http) {
      return (
        message: 'The server answered ${e.message}. Try again later.',
        offline: false,
      );
    }
    return (message: "Couldn't read the file list.", offline: false);
  }
  if (e is TitleNotFound) {
    return (message: 'This title is no longer indexed.', offline: false);
  }
  return (
    message: "Can't reach the server. Playback needs BDIX.",
    offline: true,
  );
}

/// What the file area of a title shows.
enum FilesPhase { ready, loading, error }

/// [FilesPhase.ready]: the stored files are loaded and fresh (a background
/// force-reload keeps showing them). Otherwise loading / error from [load].
FilesPhase filesPhase(TitleDetail d, AsyncValue<TitleFilesResult> load) {
  if (d.title.filesLoaded) return FilesPhase.ready;
  if (load.isLoading) return FilesPhase.loading;
  return FilesPhase.error;
}
