import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/index/index_service.dart';

/// Live indexing status: progress while running, last failure/outcome after.
class IndexProgress extends ConsumerWidget {
  const IndexProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(indexStateProvider).value ?? const IndexState();
    final cs = Theme.of(context).colorScheme;
    if (s.running) {
      final phase = switch (s.phase) {
        IndexPhase.probing => 'Checking servers',
        IndexPhase.writing => 'Saving',
        _ => 'Crawling',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            '$phase...  ${s.foldersFetched} folders, '
            '${s.titlesFound + s.titlesUnchanged} titles',
          ),
          if (s.errors > 0)
            Text('${s.errors} errors', style: TextStyle(color: cs.error)),
          const SizedBox(height: 8),
          Align(
            child: OutlinedButton(
              onPressed: () => ref.read(indexServiceProvider).cancel(),
              child: const Text('Cancel'),
            ),
          ),
        ],
      );
    }
    final msg = s.message;
    if (s.offBdix) {
      return Text(
        msg == null || msg.isEmpty
            ? 'No DhakaFlix server reachable. Connect to a BDIX-peered ISP and try again.'
            : msg,
        style: TextStyle(color: cs.error),
      );
    }
    if (s.phase == IndexPhase.failed || s.phase == IndexPhase.done) {
      if (msg != null && msg.isNotEmpty) {
        return Text(
          msg,
          style: TextStyle(
            color: s.phase == IndexPhase.failed
                ? cs.error
                : cs.onSurfaceVariant,
          ),
        );
      }
      if (s.phase == IndexPhase.done) {
        return Text('Done: ${s.titlesWritten} titles updated.');
      }
    }
    return const SizedBox.shrink();
  }
}
