import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';

import '../title_providers.dart';

/// Loading state of the file/episode area: a spinner line, then placeholder
/// rows as tall as a [FileTile] (72) so the list does not jump when the real
/// rows arrive.
class FilesLoadingRows extends StatelessWidget {
  const FilesLoadingRows({
    super.key,
    this.label = 'Loading episodes…',
    this.rows = 3,
  });
  final String label;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: t.hi, borderRadius: t.radius(4)),
    );
    return Column(
      key: const Key('files-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < rows; i++)
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const SizedBox(width: 22),
                Container(
                  width: 112,
                  height: 63,
                  decoration: BoxDecoration(
                    color: t.hi,
                    borderRadius: t.radius(10),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(140, 12),
                      const SizedBox(height: 8),
                      bar(80, 9),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Failed load: message ("Can't reach the server. Playback needs BDIX.") and
/// Retry.
class FilesErrorRow extends StatelessWidget {
  const FilesErrorRow({super.key, required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final d = error == null
        ? (message: "Couldn't load the file list.", offline: false)
        : describeLoadError(error!);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      key: const Key('files-error'),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(
            d.offline ? Icons.cloud_off : Icons.error_outline,
            size: 32,
            color: muted,
          ),
          const SizedBox(height: 8),
          Text(d.message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('files-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Loaded, but the folder holds nothing playable.
class FilesEmptyRow extends StatelessWidget {
  const FilesEmptyRow({super.key, this.onReload});
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      key: const Key('files-empty'),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(Icons.movie_outlined, size: 32, color: muted),
          const SizedBox(height: 8),
          const Text('No playable files', textAlign: TextAlign.center),
          if (onReload != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload'),
            ),
          ],
        ],
      ),
    );
  }
}
