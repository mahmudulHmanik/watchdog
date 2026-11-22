import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/title/ui/title_screen.dart';

void openTitle(BuildContext context, MediaTitle t) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => TitleScreen(titleId: t.id)));

/// Poster with a neutral fallback when missing or failing to load.
class Poster extends StatelessWidget {
  const Poster(
    this.url, {
    super.key,
    this.width = 48,
    this.height = 72,
    this.icon = true,
  });
  final String? url;
  final bool icon;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: width,
      height: height,
      color: cs.surfaceContainerHigh,
      child: icon
          ? Icon(Icons.movie_outlined, color: cs.onSurfaceVariant)
          : null,
    );
    final img = url == null
        ? fallback
        : Image.network(
            url!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            cacheWidth: (width * 2).round(),
            errorBuilder: (_, _, _) => fallback,
          );
    return ClipRRect(borderRadius: context.tokens.radius(10), child: img);
  }
}

/// Small label on posters (`1080p`, `Series`).
class PosterBadge extends StatelessWidget {
  const PosterBadge(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: t.badge, borderRadius: t.radius(4)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: t.palette.text,
        ),
      ),
    );
  }
}

/// Text with the first case-insensitive [query] match in accent colour.
Widget highlighted(
  BuildContext context,
  String text,
  String query, {
  TextStyle? style,
}) {
  final accent = context.tokens.accent;
  final i = query.isEmpty
      ? -1
      : text.toLowerCase().indexOf(query.toLowerCase());
  if (i < 0) {
    return Text(
      text,
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
  return Text.rich(
    TextSpan(
      style: style,
      children: [
        TextSpan(text: text.substring(0, i)),
        TextSpan(
          text: text.substring(i, i + query.length),
          style: TextStyle(color: accent, fontWeight: FontWeight.w700),
        ),
        TextSpan(text: text.substring(i + query.length)),
      ],
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

/// Search/list result row: 64x96 poster, title (match highlighted), meta.
class TitleTile extends StatelessWidget {
  const TitleTile(this.title, {super.key, this.query = ''});
  final MediaTitle title;
  final String query;

  @override
  Widget build(BuildContext context) {
    final t = title;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final l1 = [
      switch (t.kind) {
        TitleKind.series => 'TV Series',
        TitleKind.movie => 'Movie',
        TitleKind.event => 'Event',
      },
      if (t.year != null) '${t.year}',
      ?t.language,
    ].join(' · ');
    final l2 = t.kind == TitleKind.series
        ? [
            if (t.seasonCount > 0)
              '${t.seasonCount} season${t.seasonCount == 1 ? '' : 's'}',
            if (t.fileCount > 0) '${t.fileCount} episodes',
          ].join(' · ')
        : [if (t.quality != null) '${t.quality}p'].join(' · ');
    return InkWell(
      onTap: () => openTitle(context, t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Poster(t.posterUrl, width: 64, height: 96),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  highlighted(
                    context,
                    t.name,
                    query,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(l1, style: TextStyle(fontSize: 12, color: muted)),
                  if (l2.isNotEmpty)
                    Text(l2, style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
