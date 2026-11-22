import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/features/browse/image_store.dart'
    show kImageCacheMaxObjects;
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/downloads/downloads_providers.dart';
import 'package:watchdog/features/settings/storage_providers.dart';
import 'package:watchdog/features/title/ui/file_actions_sheet.dart'
    show showToast;
import 'package:watchdog/platform/platform_api.dart';

import 'settings_widgets.dart';

/// Settings -> Library -> STORAGE: sizes of what the app keeps (index, image
/// cache, player cache, downloads) with clear / delete actions.
class StorageBlock extends ConsumerStatefulWidget {
  const StorageBlock({super.key});

  @override
  ConsumerState<StorageBlock> createState() => _StorageBlockState();
}

class _StorageBlockState extends ConsumerState<StorageBlock> {
  String? _busy;

  @override
  void initState() {
    super.initState();
    // Fresh numbers on every open (the Settings home keeps the provider alive).
    Future.microtask(() {
      if (mounted) ref.invalidate(storageUsageProvider);
    });
  }

  Future<void> _run(
    String key,
    String done,
    Future<void> Function(PlatformApi) f,
  ) async {
    setState(() => _busy = key);
    try {
      await f(ref.read(platformApiProvider));
      ref.invalidate(storageUsageProvider);
      if (mounted) showToast(context, done);
    } catch (e) {
      if (mounted) showToast(context, 'Failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _deleteDownloads(int? size) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all downloads?'),
        content: Text(
          '${size == null ? 'All' : 'About ${formatBytes(size)} of'} '
          'downloaded files will be deleted from Movies/watchdog and removed '
          'from the Downloads list. Downloads in progress are kept. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-downloads'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run('downloads', 'Downloads deleted', (p) async {
      await p.deleteAllDownloads();
      ref.invalidate(downloadsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(storageUsageProvider);
    final u = usage.value;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final err = context.tokens.palette.error;
    final busy = _busy != null;

    Widget row(String key, String title, int? bytes, {String? sub}) => ListTile(
      key: Key('storage-$key'),
      title: Text(title),
      subtitle: sub == null ? null : Text(sub),
      trailing: Text(
        bytes != null
            ? formatBytes(bytes)
            : usage.hasError
            ? 'n/a'
            : '…',
        style: TextStyle(color: muted),
      ),
    );

    return SettingsBlock(
      title: 'STORAGE',
      children: [
        row('index', 'Index database', u?.indexBytes),
        row(
          'images',
          'Image cache',
          u?.imageCacheBytes,
          sub: 'Posters and photos, up to $kImageCacheMaxObjects images',
        ),
        row('player', 'Player cache', u?.playerCacheBytes),
        row('downloads', 'Downloads', u?.downloadsBytes),
        ListTile(
          key: const Key('storage-total'),
          title: const Text(
            'Total',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: u?.freeBytes == null
              ? null
              : Text('${formatBytes(u!.freeBytes!)} free on device'),
          trailing: Text(
            u == null
                ? (usage.hasError ? 'n/a' : '…')
                : formatBytes(u.totalBytes),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: settingsPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (usage.hasError) ...[
                Text(
                  'Could not read sizes.',
                  style: TextStyle(fontSize: 13, color: err),
                ),
                TextButton(
                  key: const Key('storage-retry'),
                  onPressed: () => ref.invalidate(storageUsageProvider),
                  child: const Text('Retry'),
                ),
                const SizedBox(height: 6),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('clear-image-cache'),
                    onPressed: busy
                        ? null
                        : () =>
                              _run('images', 'Image cache cleared', (p) async {
                                await p.clearImageCache();
                                PaintingBinding.instance.imageCache
                                  ..clear()
                                  ..clearLiveImages();
                              }),
                    child: const Text('Clear image cache'),
                  ),
                  OutlinedButton(
                    key: const Key('clear-player-cache'),
                    onPressed: busy
                        ? null
                        : () => _run(
                            'player',
                            'Player cache cleared',
                            (p) => p.clearPlayerCache(),
                          ),
                    child: const Text('Clear player cache'),
                  ),
                  OutlinedButton(
                    key: const Key('delete-downloads'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: err,
                      side: BorderSide(color: err),
                    ),
                    onPressed: busy
                        ? null
                        : () => _deleteDownloads(u?.downloadsBytes),
                    child: const Text('Delete all downloads'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
