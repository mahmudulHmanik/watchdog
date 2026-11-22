import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/app_info.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/title/ui/file_actions_sheet.dart'
    show showToast;
import 'package:watchdog/platform/platform_api.dart';

import '../release.dart';
import '../update_providers.dart';
import '../update_service.dart';

/// Looks for a newer release and, if there is one, offers to install it.
///
/// [manual] (Settings button) always reports the outcome; the automatic
/// launch check ([manual] false) stays silent unless there is an update, and
/// honours the daily limit and the "check on launch" switch.
Future<void> checkForUpdate(
  BuildContext context,
  WidgetRef ref, {
  required bool manual,
}) async {
  final prefsN = ref.read(updatePrefsProvider.notifier);
  if (!manual) {
    final p = await ref.read(updatePrefsProvider.future);
    if (!p.due(DateTime.now())) return;
  }
  final ReleaseInfo? r;
  try {
    r = await ref.read(updateServiceProvider).check(currentVersion: appVersion);
  } on UpdateException catch (e) {
    if (manual && context.mounted) {
      showToast(context, e.message, error: true);
    }
    return;
  }
  await prefsN.markChecked(DateTime.now());
  if (!context.mounted) return;
  if (r == null) {
    if (manual) showToast(context, "You're up to date (v$appVersion)");
    return;
  }
  await _offer(context, ref, r);
}

Future<void> _offer(BuildContext context, WidgetRef ref, ReleaseInfo r) async {
  final installer = ref.read(apkInstallerProvider);
  final canInstallHere = installer.supported && r.apkUrl != null;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Update available: v${r.version}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have v$appVersion'
                '${r.apkSize == null ? '' : ' · download ${formatSizeKb((r.apkSize! / 1024).round())}'}',
              ),
              if (r.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(r.notes, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(canInstallHere ? 'Update' : 'Open release page'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  if (!canInstallHere) {
    await ref.read(platformApiProvider).openUrl(Uri.parse(r.pageUrl));
    return;
  }
  await _downloadAndInstall(context, ref, r);
}

Future<void> _downloadAndInstall(
  BuildContext context,
  WidgetRef ref,
  ReleaseInfo r,
) async {
  final service = ref.read(updateServiceProvider);
  final installer = ref.read(apkInstallerProvider);
  final dir = await ref.read(updateDirProvider)();
  if (!context.mounted) return;
  final cancel = CancelToken();
  final progress = ValueNotifier<(int, int)>((0, r.apkSize ?? -1));
  final started = Stopwatch()..start();

  // Progress dialog (not awaited: it is closed when the download ends).
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Downloading v${r.version}'),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, p, _) {
            final (got, total) = p;
            final mbps = started.elapsedMilliseconds > 500
                ? got / 1e6 / (started.elapsedMilliseconds / 1000)
                : 0.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: total > 0 ? got / total : null),
                const SizedBox(height: 8),
                Text(
                  total > 0
                      ? '${formatSizeKb((got / 1024).round())} / '
                            '${formatSizeKb((total / 1024).round())}'
                            '${mbps > 0 ? ' · ${mbps.toStringAsFixed(1)} MB/s' : ''}'
                      : formatSizeKb((got / 1024).round()),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: cancel.cancel, child: const Text('Cancel')),
        ],
      ),
    ),
  );

  File? apk;
  String? error;
  try {
    apk = await service.download(
      r,
      dir,
      cancel: cancel,
      onProgress: (g, t) => progress.value = (g, t),
    );
  } on UpdateException catch (e) {
    error = e.message;
  }
  progress.dispose();
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (!context.mounted) return;
  if (apk == null) {
    if (error != 'Cancelled') {
      showToast(context, error ?? 'Download failed', error: true);
    }
    return;
  }

  if (!await installer.canInstall()) {
    if (!context.mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow installing updates'),
        content: const Text(
          'Android needs your OK before watchdog can install its own update. '
          'Turn on "Allow from this source", come back, and tap '
          '"Check for updates" again. The download is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (open == true) await installer.openInstallSettings();
    return;
  }
  try {
    await installer.install(apk.path);
  } catch (e) {
    if (context.mounted) {
      showToast(context, 'Could not start the installer: $e', error: true);
    }
  }
}
