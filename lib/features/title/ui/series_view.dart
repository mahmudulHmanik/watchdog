import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/crawler/title_files.dart' show TitleFilesResult;
import 'package:watchdog/data/models.dart' show Season;
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/player/player_providers.dart';

import '../player_actions.dart';
import '../resume.dart';
import '../title_providers.dart';
import '../episode_title.dart';
import 'compact_switch.dart';
import 'file_actions_sheet.dart' show describeError, showToast;
import 'file_tile.dart';
import 'files_state.dart';
import 'title_header.dart';

/// YouTube-style playlist: header, Play/Resume, season chips, autoplay row,
/// episode rows. Metadata and season chips (with stored episode counts) show
/// at once; the episode area shows loading / error / empty states until the
/// title's files are loaded ([load], see `titleFilesProvider`).
class SeriesView extends ConsumerStatefulWidget {
  const SeriesView(this.d, {super.key, required this.load});
  final TitleDetail d;
  final AsyncValue<TitleFilesResult> load;

  @override
  ConsumerState<SeriesView> createState() => _SeriesViewState();
}

class _SeriesViewState extends ConsumerState<SeriesView> {
  int _selected = 0; // index into displayOrder

  void _refresh() {
    ref.invalidate(titleDetailProvider(widget.d.title.id));
    ref.invalidate(continueWatchingProvider);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final t = d.title;
    final seasons = displayOrder(d.seasons);
    final phase = filesPhase(d, widget.load);
    final ready = phase == FilesPhase.ready;
    void reload() => reloadTitleFiles(ref, t.id);
    Widget stateRow(int expected) => switch (phase) {
      FilesPhase.loading => FilesLoadingRows(
        rows: expected <= 0 ? 3 : expected.clamp(1, 6),
      ),
      FilesPhase.error => FilesErrorRow(
        error: widget.load.error,
        onRetry: reload,
      ),
      FilesPhase.ready => FilesEmptyRow(onReload: reload),
    };
    Future<void> guarded(Future<Object?> Function() f) async {
      try {
        await f();
      } catch (e) {
        if (context.mounted) showToast(context, describeError(e), error: true);
      }
      _refresh();
    }

    if (seasons.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => reload(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [TitleHeader(t), stateRow(0)],
        ),
      );
    }
    final tk = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final sel = seasons[_selected.clamp(0, seasons.length - 1)];
    final resume = ready ? pickResume(d.seasons, d.states) : null;
    final resuming =
        resume != null && (d.states[resume.id]?.positionMs ?? 0) > 0;
    final repo = ref.read(repositoryProvider);
    final actions = ref.read(playerActionsProvider);
    final autoplay =
        ref.watch(playerSettingsProvider).value?.autoplayNext ?? true;
    final playable = sel.files.where((f) => f.playable).toList();
    final allWatched =
        playable.isNotEmpty &&
        playable.every((f) => d.states[f.id]?.watched ?? false);
    final curIdx = resume == null
        ? -1
        : sel.files.indexWhere((f) => f.id == resume.id);
    final resumeSeason = resume == null
        ? null
        : seasons
              .where((s) => s.files.any((f) => f.id == resume.id))
              .firstOrNull;
    String two(int v) => v.toString().padLeft(2, '0');
    final subtitle = resume == null || resumeSeason == null
        ? null
        : () {
            final head = [
              if (resumeSeason.season.number > 0)
                'S${two(resumeSeason.season.number)}',
              if (episodeLabel(resume).isNotEmpty) episodeLabel(resume),
            ].join(' · ');
            final title = cleanEpisodeTitle(
              resume.name,
              t.name,
              episode: resume.episode,
              special: resumeSeason.season.number == 0,
            );
            final generic = RegExp(r'^(?:Episode|Special)(?: \d+)?$');
            return generic.hasMatch(title) ? head : '$head — $title';
          }();

    final shown = ready && sel.files.isNotEmpty ? sel.files.length : 1;
    return RefreshIndicator(
      onRefresh: () async {
        reload();
        try {
          await ref.read(titleFilesProvider(t.id).future);
        } catch (_) {}
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: shown + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TitleHeader(t, subtitle: subtitle),
                if (ready && resume != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: Text(resuming ? 'Resume' : 'Play'),
                      onPressed: () => guarded(
                        () => actions.playEpisode(context, repo, t, resume),
                      ),
                    ),
                  ),
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(8).copyWith(left: 16),
                    itemCount: seasons.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, k) => ChoiceChip(
                      label: Text(_chipLabel(seasons[k].season, ready)),
                      selected: k == _selected,
                      onSelected: (_) => setState(() => _selected = k),
                    ),
                  ),
                ),
                if (ready)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            curIdx >= 0
                                ? '${curIdx + 1} / ${sel.files.length} · Autoplay next'
                                : '${sel.files.length} episodes · Autoplay next',
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        ),
                        CompactSwitch(
                          key: const Key('autoplay-switch'),
                          value: autoplay,
                          onChanged: (v) => ref
                              .read(playerSettingsProvider.notifier)
                              .setAutoplayNext(v),
                        ),
                      ],
                    ),
                  ),
                if (ready)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.playlist_play),
                          label: const Text('Play season'),
                          onPressed: () => guarded(
                            () => actions.playSeason(
                              context,
                              repo,
                              t,
                              sel.season.id,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          icon: Icon(
                            allWatched ? Icons.visibility_off : Icons.check,
                          ),
                          label: Text(
                            allWatched
                                ? 'Mark season unwatched'
                                : 'Mark season watched',
                          ),
                          onPressed: () => guarded(
                            () => repo.markTitleWatched(
                              t.id,
                              seasonId: sel.season.id,
                              watched: !allWatched,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Divider(color: tk.border),
              ],
            );
          }
          if (!ready || sel.files.isEmpty) {
            return stateRow(sel.season.episodeCount);
          }
          final f = sel.files[i - 1];
          return FileTile(
            key: ValueKey('file-${f.id}'),
            title: t,
            file: f,
            state: d.states[f.id],
            current: resume?.id == f.id,
            special: sel.season.number == 0,
            siblings: sel.files.skipWhile((x) => x.id != f.id).toList(),
          );
        },
      ),
    );
  }

  static String _chipLabel(Season s, bool ready) => !ready && s.episodeCount > 0
      ? '${seasonLabel(s)} (${s.episodeCount})'
      : seasonLabel(s);
}
