import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/index/ui/index_progress.dart';

import 'settings_widgets.dart';
import 'storage_block.dart';

/// Settings -> Library: storage, index status, re-index, clear index.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear index?'),
        content: const Text(
          'Removes all indexed titles, including their TMDB details and any '
          'manual match fixes. Watch history is kept. '
          'You can re-index on BDIX.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repositoryProvider).clearIndex();
    ref.read(revisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexState = ref.watch(indexStateProvider).value;
    final running = indexState?.running ?? false;
    final indexShown = indexState != null && indexProgressVisible(indexState);
    final last = ref.watch(lastIndexedAtProvider).value;
    final counts = ref.watch(countsProvider).value;
    final err = context.tokens.palette.error;
    return SettingsPageScaffold(
      title: 'Library',
      children: [
        const StorageBlock(),
        SettingsBlock(
          title: 'INDEX',
          children: [
            ListTile(
              title: const Text('Last indexed'),
              trailing: Text(last == null ? 'never' : formatTime(last)),
            ),
            if (counts != null)
              ListTile(
                title: const Text('Library'),
                trailing: Text('${counts.titles} titles'),
              ),
            if (indexShown)
              const Padding(padding: settingsPad, child: IndexProgress()),
          ],
        ),
        SettingsBlock(
          title: 'RE-INDEX',
          children: [
            Padding(
              padding: settingsPad,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('reindex'),
                    onPressed: running
                        ? null
                        : () => ref.read(indexServiceProvider).reindex(),
                    child: const Text('Re-index (incremental)'),
                  ),
                  OutlinedButton(
                    key: const Key('reindex-full'),
                    onPressed: running
                        ? null
                        : () => ref
                              .read(indexServiceProvider)
                              .reindex(full: true),
                    child: const Text('Full re-index'),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsBlock(
          title: 'DANGER ZONE',
          children: [
            Padding(
              padding: settingsPad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Removes all indexed titles. Watch history is kept.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const Key('clear-index'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: err,
                      side: BorderSide(color: err),
                    ),
                    onPressed: running ? null : () => _clear(context, ref),
                    child: const Text('Clear index'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
