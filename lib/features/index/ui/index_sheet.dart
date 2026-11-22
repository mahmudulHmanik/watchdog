import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/index/index_service.dart';

import 'index_format.dart';

/// Per-category indexing progress with Cancel (opened from the banner).
Future<void> showIndexSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => const IndexSheet(),
);

class IndexSheet extends ConsumerWidget {
  const IndexSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(indexStateProvider).value ?? const IndexState();
    final th = Theme.of(context);
    final muted = th.colorScheme.onSurfaceVariant;
    final shown = [
      for (final c in s.categories)
        if (c.status != CategoryStatus.pending || s.running) c,
    ];
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  s.running
                      ? indexLabel(s)
                      : (s.categories.isEmpty
                            ? 'Indexing'
                            : '${fmtCount(s.titlesIndexed)} titles indexed'),
                  key: const Key('index-sheet-title'),
                  style: th.textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '${s.elapsed.inSeconds}s · '
                  '${fmtCount(s.foldersFetched)} requests'
                  '${s.errors > 0 ? ' · ${s.errors} errors' : ''}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
              if (s.running)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(
                    value: indexBarValue(s),
                    minHeight: 3,
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _CategoryRow(c: shown[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    if (s.running)
                      OutlinedButton(
                        key: const Key('index-cancel'),
                        onPressed: () =>
                            ref.read(indexServiceProvider).cancel(),
                        child: const Text('Cancel'),
                      )
                    else
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Close'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.c});
  final CategoryProgress c;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final (icon, color, label) = switch (c.status) {
      CategoryStatus.pending => (Icons.schedule, t.palette.muted, 'waiting'),
      CategoryStatus.running => (Icons.sync, t.accent, 'indexing'),
      CategoryStatus.done => (Icons.check_circle_outline, t.palette.ok, 'done'),
      CategoryStatus.skipped => (
        Icons.check_circle_outline,
        t.palette.ok,
        'done earlier',
      ),
      CategoryStatus.failed => (Icons.error_outline, t.palette.error, 'failed'),
      CategoryStatus.unreachable => (
        Icons.cloud_off,
        t.palette.error,
        'unreachable',
      ),
      CategoryStatus.cancelled => (
        Icons.cancel_outlined,
        t.palette.muted,
        'cancelled',
      ),
    };
    final est = c.estimatedTotal;
    final count = c.finished || est == null || est <= 0
        ? fmtCount(c.titles)
        : '${fmtCount(c.titles)} / ~${fmtCount(est)}';
    final notes = [
      c.host,
      label,
      if (c.htmlFallback) 'HTML fallback',
      if (c.errors > 0)
        '${c.errors} error${c.errors == 1 ? '' : 's'}'
            '${c.lastError == null ? '' : ': ${c.lastError}'}',
    ];
    final frac = c.status == CategoryStatus.running ? c.fraction : null;
    return ListTile(
      key: Key('cat-row-${c.host}/${c.name}'),
      dense: true,
      leading: Icon(icon, color: color, size: 20, semanticLabel: label),
      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notes.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: muted),
          ),
          if (frac != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: frac, minHeight: 2),
            ),
        ],
      ),
      trailing: Text(count, style: const TextStyle(fontSize: 12)),
    );
  }
}
