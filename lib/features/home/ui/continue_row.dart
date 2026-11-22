import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/browse/ui/title_tile.dart';
import 'package:watchdog/features/title/ui/file_actions_sheet.dart';

/// 220x124 resume card: thumb with play glyph and 4px progress bar.
class ResumeCard extends ConsumerWidget {
  const ResumeCard(this.item, {super.key});
  final ResumeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => playInApp(context, ref, title: item.title, file: item.file),
      child: SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 124,
              child: ClipRRect(
                borderRadius: t.radius(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Poster(
                      item.title.bestPosterUrl,
                      width: 220,
                      height: 124,
                      icon: false,
                    ),
                    const Center(
                      child: Icon(Icons.play_circle_outline, size: 36),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: item.state.fraction,
                        minHeight: 4,
                        backgroundColor: t.border,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Text(
              resumeMeta(item),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Section title ........ See all" row.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('See all')),
      ],
    ),
  );
}

class ContinueAllScreen extends ConsumerWidget {
  const ContinueAllScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Continue watching')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (_, i) => ResumeCard(items[i]),
      ),
    );
  }
}

/// Horizontal "Continue watching" row; hidden when empty.
class ContinueRow extends ConsumerWidget {
  const ContinueRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Continue watching',
          onSeeAll: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ContinueAllScreen()),
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => ResumeCard(items[i]),
          ),
        ),
      ],
    );
  }
}
