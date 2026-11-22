import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/index/index_providers.dart';

import 'index_progress.dart';

/// Shown on Home while the index is empty.
class FirstRunView extends ConsumerWidget {
  const FirstRunView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(indexStateProvider).value?.running ?? false;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Build the index',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'DhakaFlix servers are only reachable from a BDIX-peered ISP. '
              'Indexing reads the server listings once and stores them on this '
              'device, so browsing and search then work offline. Playback and '
              'downloads still need BDIX.',
            ),
            const SizedBox(height: 20),
            if (!running)
              FilledButton(
                onPressed: () => ref.read(indexServiceProvider).reindex(),
                child: const Text('Index now'),
              ),
            const IndexProgress(),
            const SizedBox(height: 12),
            if (!running)
              TextButton(
                onPressed: () => ref.read(skipIndexProvider.notifier).skip(),
                child: const Text('Skip for now'),
              ),
          ],
        ),
      ),
    );
  }
}
