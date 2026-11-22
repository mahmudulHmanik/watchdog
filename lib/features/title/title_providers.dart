import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';

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
