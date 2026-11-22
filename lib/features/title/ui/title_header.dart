import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/browse/ui/title_tile.dart';
import 'package:watchdog/tmdb/tmdb_images.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';

import '../tmdb_title_providers.dart';
import 'tmdb_block.dart';

class TitleHeader extends ConsumerWidget {
  const TitleHeader(this.t, {super.key, this.subtitle});
  final MediaTitle t;

  /// e.g. `S02 · E05` for the current/resume episode.
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TMDB parts exist only with a key and matched data.
    final hasKey = ref.watch(tmdbConfigProvider).value?.auth != null;
    final info = hasKey ? ref.watch(tmdbInfoProvider(t.id)).value : null;
    final matched = info != null && info.status != TmdbStatus.unmatched;
    final backdrop = matched
        ? tmdbImageUrl(info.backdropPath, TmdbImageSize.backdrop)
        : null;
    final poster =
        t.posterUrl ??
        (matched
            ? tmdbImageUrl(info.posterPath, TmdbImageSize.posterLarge)
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (backdrop != null) TmdbBackdrop(backdrop),
        _row(poster),
        TmdbBlock(t),
      ],
    );
  }

  Widget _row(String? poster) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Poster(poster, width: 90, height: 135),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!),
              Text(titleSubtitle(t)),
              if (t.kind == TitleKind.series && t.fileCount > 0)
                Text('${t.fileCount} episodes'),
              if (t.tags.isNotEmpty) Text(t.tags.join(', ')),
            ],
          ),
        ),
      ],
    ),
  );
}
