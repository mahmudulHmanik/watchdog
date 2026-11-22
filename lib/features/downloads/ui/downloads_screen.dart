import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/title/ui/file_actions_sheet.dart'
    show describeError, showToast;
import 'package:watchdog/platform/platform_api.dart';

import '../downloads_providers.dart';

String stateLabel(DownloadProgress d) => switch (d.state) {
  DownloadState.queued => 'Queued',
  DownloadState.running => 'Downloading',
  DownloadState.paused => 'Paused',
  DownloadState.complete => 'Complete',
  DownloadState.failed => 'Failed',
  DownloadState.canceled => 'Canceled',
};

String bytesLabel(DownloadProgress d) {
  final r = d.bytesReceived, t = d.bytesTotal;
  if (r == null && t == null) return '';
  String f(int b) => formatSizeKb((b / 1024).round());
  return t == null ? f(r!) : '${f(r ?? 0)} / ${f(t)}';
}

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(downloadsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(describeError(e))),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No downloads yet.'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => DownloadTile(items[i]),
              ),
      ),
    );
  }
}

class DownloadTile extends ConsumerWidget {
  const DownloadTile(this.d, {super.key});
  final DownloadProgress d;

  Future<void> _do(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(PlatformApi) f,
  ) async {
    try {
      await f(ref.read(platformApiProvider));
      ref.invalidate(downloadsProvider);
    } catch (e) {
      if (context.mounted) showToast(context, describeError(e), error: true);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    var deleteFile = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Remove download?'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: deleteFile,
            onChanged: (v) => set(() => deleteFile = v ?? false),
            title: const Text('Also delete file'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await _do(
        context,
        ref,
        (p) => p.removeDownload(d.id, deleteFile: deleteFile),
      );
    }
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final path = d.filePath;
    if (path == null) return;
    try {
      await ref.read(platformApiProvider).openLocalFile(path);
    } catch (e) {
      if (context.mounted) showToast(context, describeError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final active =
        d.state == DownloadState.running ||
        d.state == DownloadState.paused ||
        d.state == DownloadState.queued;
    final color = switch (d.state) {
      DownloadState.complete => t.palette.ok,
      DownloadState.failed => t.palette.error,
      _ => cs.onSurfaceVariant,
    };
    final bytes = bytesLabel(d);
    final pct = d.progress >= 0 ? ' · ${(d.progress * 100).round()}%' : '';
    return InkWell(
      onTap: d.state == DownloadState.complete
          ? () => _open(context, ref)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (active)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: LinearProgressIndicator(
                        value: d.progress >= 0 ? d.progress : null,
                        minHeight: 4,
                        backgroundColor: t.border,
                      ),
                    ),
                  Text(
                    [
                      stateLabel(d) + (active ? pct : ''),
                      if (bytes.isNotEmpty) bytes,
                      if (d.state == DownloadState.failed && d.error != null)
                        d.error!,
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ],
              ),
            ),
            if (d.state == DownloadState.running ||
                d.state == DownloadState.queued)
              IconButton(
                tooltip: 'Pause',
                icon: const Icon(Icons.pause),
                onPressed: () =>
                    _do(context, ref, (p) => p.pauseDownload(d.id)),
              ),
            if (d.state == DownloadState.paused)
              IconButton(
                tooltip: 'Resume',
                icon: const Icon(Icons.play_arrow),
                onPressed: () =>
                    _do(context, ref, (p) => p.resumeDownload(d.id)),
              ),
            if (active)
              IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: () =>
                    _do(context, ref, (p) => p.cancelDownload(d.id)),
              )
            else ...[
              if (d.state == DownloadState.complete)
                IconButton(
                  tooltip: 'Open',
                  icon: Icon(Icons.play_circle_outline, color: t.accent),
                  onPressed: () => _open(context, ref),
                ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(context, ref),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
