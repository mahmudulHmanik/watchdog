import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/index/index_service.dart';

import 'index_format.dart';
import 'index_sheet.dart';

void _retry(WidgetRef ref) =>
    unawaited(ref.read(indexServiceProvider).ensureIndexed(force: true));

/// Calm card: servers not reachable (never blocks; indexed data still works).
class OfflineCard extends ConsumerWidget {
  const OfflineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Card(
    key: const Key('index-offline'),
    icon: Icons.wifi_off,
    title: "Can't reach the DhakaFlix servers.",
    body:
        'Connect to a BDIX-peered network. Indexed titles still work for '
        'browsing; playback needs BDIX.',
    action: FilledButton(
      key: const Key('index-retry'),
      onPressed: () => _retry(ref),
      child: const Text('Retry'),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final th = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: t.plain(r: 14, color: th.cardColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: t.palette.muted),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: th.textTheme.titleSmall)),
                ],
              ),
              if (body != null) ...[
                const SizedBox(height: 8),
                Text(
                  body!,
                  style: TextStyle(color: th.colorScheme.onSurfaceVariant),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet line after a run that did not finish: "some categories could not be
/// indexed" + Retry. Nothing while running, after success, or off BDIX (the
/// [OfflineCard] covers that).
class IndexNotice extends ConsumerWidget {
  const IndexNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(indexStateProvider).value;
    if (s == null || s.running) return const SizedBox.shrink();
    if (s.offBdix) return const OfflineCard();
    final text = switch (s.outcome) {
      IndexOutcome.partial => 'Some categories could not be indexed.',
      IndexOutcome.failed =>
        'Indexing hit an error. Some titles may be missing.',
      IndexOutcome.cancelled when s.isFirstRun =>
        'Indexing was cancelled. Some titles may be missing.',
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        key: const Key('index-partial'),
        children: [
          Icon(Icons.info_outline, size: 16, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: muted)),
          ),
          TextButton(
            key: const Key('index-retry'),
            onPressed: () => _retry(ref),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Search results header while the first index is still filling.
class StillIndexingNote extends ConsumerWidget {
  const StillIndexingNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(indexStateProvider).value;
    if (s == null || !(s.running && s.isFirstRun)) {
      return const SizedBox.shrink();
    }
    return Padding(
      key: const Key('still-indexing'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Still indexing: more titles will appear.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Home body while nothing is stored yet: a friendly setup state (never a
/// wall: the tab bar and the other tabs stay usable), or a calm offline /
/// error card. First results replace it automatically.
class LibrarySetupView extends ConsumerWidget {
  const LibrarySetupView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(indexStateProvider).value ?? const IndexState();
    final boot = ref.watch(indexBootstrapProvider);
    Widget scroll(Widget w) => LayoutBuilder(
      builder: (_, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: w),
        ),
      ),
    );
    if (s.offBdix) return scroll(const OfflineCard());
    if (!s.running) {
      final bad = switch (s.outcome) {
        IndexOutcome.partial ||
        IndexOutcome.failed ||
        IndexOutcome.cancelled => true,
        _ => false,
      };
      if (bad) {
        final msg = s.message;
        return scroll(
          _Card(
            key: const Key('index-error'),
            icon: Icons.error_outline,
            title: s.outcome == IndexOutcome.cancelled
                ? 'Indexing was cancelled.'
                : "The library couldn't be set up.",
            body: msg == null || msg.isEmpty ? null : msg,
            action: FilledButton(
              key: const Key('index-retry'),
              onPressed: () => _retry(ref),
              child: const Text('Try again'),
            ),
          ),
        );
      }
      if (s.outcome == IndexOutcome.success || boot.hasError) {
        return scroll(
          _Card(
            key: const Key('index-empty'),
            icon: Icons.video_library_outlined,
            title: 'Your library is empty.',
            body: 'Index the DhakaFlix servers to browse and search.',
            action: FilledButton(
              key: const Key('index-now'),
              onPressed: () => _retry(ref),
              child: const Text('Index now'),
            ),
          ),
        );
      }
    }
    return scroll(_Setup(s: s));
  }
}

class _Setup extends StatelessWidget {
  const _Setup({required this.s});
  final IndexState s;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final th = Theme.of(context);
    final muted = th.colorScheme.onSurfaceVariant;
    final n = s.titlesIndexed;
    final sub = s.phase == IndexPhase.probing
        ? 'Searching the servers'
        : n > 0
        ? '${fmtCount(n)} titles found so far'
        : 'Reading the catalogue. The first titles appear in a moment.';
    return Padding(
      key: const Key('library-setup'),
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined, size: 40, color: t.accent),
            const SizedBox(height: 16),
            Text(
              'Setting up your library…',
              textAlign: TextAlign.center,
              style: th.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              key: const Key('setup-progress'),
              // Not started yet: a still bar (no endless animation).
              value: s.running ? indexBarValue(s) : 0,
              minHeight: 3,
              backgroundColor: t.border,
            ),
            const SizedBox(height: 16),
            Text(
              'You can already use Search, Downloads and Settings. '
              'Playback needs a BDIX connection.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: muted),
            ),
            if (s.categories.isNotEmpty)
              TextButton(
                key: const Key('setup-details'),
                onPressed: () => showIndexSheet(context),
                child: const Text('Details'),
              ),
          ],
        ),
      ),
    );
  }
}

/// App-level: one-time "Library ready" message when the first full index
/// completes. Wrap the shell body.
class IndexEvents extends ConsumerWidget {
  const IndexEvents({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<IndexState>>(indexStateProvider, (prev, next) {
      final p = prev?.value, n = next.value;
      if (p == null || n == null) return;
      if (!(p.running && p.isFirstRun) ||
          n.running ||
          n.outcome != IndexOutcome.success) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      unawaited(() async {
        var titles = n.titlesIndexed;
        try {
          titles = (await ref.read(repositoryProvider).counts()).titles;
        } catch (_) {}
        messenger.showSnackBar(
          SnackBar(content: Text('Library ready · ${fmtCount(titles)} titles')),
        );
      }());
    });
    return child;
  }
}
