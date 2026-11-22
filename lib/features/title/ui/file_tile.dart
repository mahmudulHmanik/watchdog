import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/browse/ui/title_tile.dart';

import '../episode_title.dart';
import '../resume.dart';
import 'file_actions_sheet.dart';

/// 112x63 thumbnail: play glyph, duration badge, 3px progress bar.
class FileThumb extends StatelessWidget {
  const FileThumb({super.key, this.state, this.width = 112, this.height = 63});
  final WatchState? state;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final st = state;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: t.radius(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: t.palette.card,
                border: Border.all(color: t.border),
                borderRadius: t.radius(10),
              ),
            ),
            Icon(Icons.play_arrow, color: t.palette.muted),
            if (st != null && st.durationMs > 0)
              Positioned(
                right: 4,
                bottom: 6,
                child: PosterBadge(clock(st.durationMs)),
              ),
            if (st != null && !st.watched && st.fraction > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: st.fraction,
                  minHeight: 3,
                  backgroundColor: t.border,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One file/episode row: number (or '>' when [current]), thumb, name, meta,
/// three-dot menu. Tap plays in-app (episodes: from here).
class FileTile extends ConsumerWidget {
  const FileTile({
    super.key,
    required this.title,
    required this.file,
    this.state,
    this.current = false,
    this.siblings = const [],
    this.special = false,
  });
  final MediaTitle title;
  final MediaFile file;
  final WatchState? state;
  final bool current;

  /// Episodes of the same season, for the "from here" sublabel.
  final List<MediaFile> siblings;

  /// Season 0 (specials): fallback title is `Special N`.
  final bool special;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final watched = state?.watched ?? false;
    final q = qualityOfName(file.name) ?? title.quality;
    final isEp = file.seasonId != null;
    final started = (state?.positionMs ?? 0) > 0;
    final size = file.sizeKb != null ? formatSizeKb(file.sizeKb) : null;
    final meta = !file.playable
        ? [
            if (q != null) '${q}p',
            file.ext.toUpperCase(),
            ?size,
            'not playable',
          ].join(' · ')
        : watched
        ? 'Watched'
        : [
            if (isEp && current) started ? 'Now playing' : 'Up next',
            if (q != null) '${q}p',
            if (!isEp) file.ext.toUpperCase(),
            ?size,
          ].join(' · ');
    void sheet() => showFileActions(
      context,
      ref,
      title: title,
      file: file,
      watched: watched,
      state: state,
      siblings: siblings,
    );
    final accent = t.accent;
    final label = episodeLabel(file);
    final displayName = isEp
        ? [
            if (label.isNotEmpty) label,
            cleanEpisodeTitle(
              file.name,
              title.name,
              episode: file.episode,
              special: special,
            ),
          ].join(' · ')
        : file.name;
    final row = InkWell(
      onTap: file.playable
          ? () => playInApp(context, ref, title: title, file: file)
          : sheet,
      onLongPress: sheet,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        decoration: BoxDecoration(
          color: current ? t.hi : null,
          border: Border(
            left: BorderSide(
              color: current ? accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (isEp)
              SizedBox(
                width: 22,
                child: Text(
                  current ? '>' : '${file.episode ?? ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: current ? accent : cs.onSurfaceVariant,
                  ),
                ),
              ),
            file.playable
                ? FileThumb(state: state)
                : Icon(
                    Icons.archive_outlined,
                    size: 40,
                    color: cs.onSurfaceVariant,
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: current ? accent : null,
                    ),
                  ),
                  Row(
                    children: [
                      if (watched)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.check_circle,
                            size: 12,
                            color: cs.tertiary,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          meta,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Actions',
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const Icon(Icons.more_vert),
              onPressed: sheet,
            ),
          ],
        ),
      ),
    );
    return row;
  }
}
