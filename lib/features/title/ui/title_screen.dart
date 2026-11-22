import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/crawler/title_files.dart' show TitleFilesResult;
import 'package:watchdog/data/models.dart';

import '../tmdb_title_providers.dart';
import '../title_providers.dart';
import 'file_actions_sheet.dart' show showToast;
import 'file_tile.dart';
import 'files_state.dart';
import 'series_view.dart';
import 'title_header.dart';

class TitleScreen extends ConsumerWidget {
  const TitleScreen({super.key, required this.titleId});
  final int titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(titleDetailProvider(titleId));
    // Opening the title triggers the (lazy) file load once.
    final load = ref.watch(titleFilesProvider(titleId));
    ref.listen(titleFilesProvider(titleId), (prev, next) {
      // A failed refresh over files that are already shown: say so.
      if (next.hasError &&
          !next.isLoading &&
          (d.value?.title.filesLoaded ?? false)) {
        showToast(context, describeLoadError(next.error!).message, error: true);
      }
    });
    // Keeps the on-open TMDB lookup alive while the screen is open.
    ref.watch(tmdbFetchProvider(titleId));
    // Keep showing the previous data while a refresh is in flight.
    final data = d.value;
    return Scaffold(
      appBar: AppBar(title: Text(data?.title.name ?? '')),
      body: data != null
          ? _Body(data, load)
          : d.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => const Center(child: Text('Title not found.')),
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.d, this.load);
  final TitleDetail d;
  final AsyncValue<TitleFilesResult> load;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = d.title.id;
    void reload() => reloadTitleFiles(ref, id);
    final phase = filesPhase(d, load);
    if (d.title.kind == TitleKind.series) {
      return SeriesView(d, load: load);
    }
    final n = phase == FilesPhase.ready
        ? (d.files.isEmpty ? 1 : d.files.length)
        : 1;
    return RefreshIndicator(
      onRefresh: () async {
        reload();
        try {
          await ref.read(titleFilesProvider(id).future);
        } catch (_) {}
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: n + 1,
        itemBuilder: (context, i) {
          if (i == 0) return TitleHeader(d.title);
          switch (phase) {
            case FilesPhase.loading:
              return FilesLoadingRows(
                label: 'Loading files…',
                rows: d.title.fileCount.clamp(1, 4),
              );
            case FilesPhase.error:
              return FilesErrorRow(error: load.error, onRetry: reload);
            case FilesPhase.ready:
              if (d.files.isEmpty) return FilesEmptyRow(onReload: reload);
          }
          final f = d.files[i - 1];
          return FileTile(
            key: ValueKey('file-${f.id}'),
            title: d.title,
            file: f,
            state: d.states[f.id],
          );
        },
      ),
    );
  }
}
