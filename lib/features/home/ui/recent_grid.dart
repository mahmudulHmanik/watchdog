import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/ui/paged_title_list.dart';
import 'package:watchdog/features/browse/ui/title_tile.dart';

/// 3-column grid of 2:3 posters with a quality/Series badge.
class PosterCell extends StatelessWidget {
  const PosterCell(this.title, {super.key});
  final MediaTitle title;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final badge = title.kind == TitleKind.series
        ? 'Series'
        : title.quality == null
        ? null
        : title.quality! >= 2160
        ? '4K'
        : '${title.quality}p';
    return InkWell(
      onTap: () => openTitle(context, title),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (_, c) => Poster(
                    title.posterUrl,
                    width: c.maxWidth,
                    height: c.maxHeight,
                  ),
                ),
                if (badge != null)
                  Positioned(left: 6, bottom: 6, child: PosterBadge(badge)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          Text(
            [
              if (title.year != null) '${title.year}',
              ?title.language,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }
}

SliverPadding posterGridSliver(List<MediaTitle> items) => SliverPadding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  sliver: SliverGrid.builder(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2 / 3.7,
    ),
    itemCount: items.length,
    itemBuilder: (_, i) => PosterCell(items[i]),
  ),
);

/// "See all": every title, most recently added first, paged.
class AllTitlesScreen extends ConsumerWidget {
  const AllTitlesScreen({super.key, required this.loader});
  final Future<List<MediaTitle>> Function(int offset, int limit) loader;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Recently added')),
    body: PagedTitleList(loader: loader),
  );
}
