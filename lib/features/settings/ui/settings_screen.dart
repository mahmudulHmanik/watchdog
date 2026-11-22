import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/app_info.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/platform/platform_api.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/index/ui/index_progress.dart';
import 'package:watchdog/features/player/domain/track_prefs.dart';
import 'package:watchdog/features/player/player_providers.dart';
import 'package:watchdog/features/update/ui/update_flow.dart';
import 'package:watchdog/features/update/update_providers.dart';

import 'theme_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear index?'),
        content: const Text(
          'Removes all indexed titles. Watch history is kept. '
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

  Future<void> _openRepo(BuildContext context, WidgetRef ref) async {
    final api = ref.read(platformApiProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.openUrl(Uri.parse(repoUrl));
    } catch (_) {
      await api.copyUrl(repoUrl);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open browser. Link copied.')),
      );
    }
  }

  Future<void> _pickAudio(BuildContext context, WidgetRef ref) async {
    final cur = ref.read(preferredAudioProvider);
    final pick = await showModalBottomSheet<(String?,)>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Preferred audio',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              title: const Text('No preference'),
              selected: cur == null,
              onTap: () => Navigator.pop(ctx, (null,)),
            ),
            for (final (code, label) in preferredLanguageChoices)
              ListTile(
                title: Text(label),
                selected: cur == code,
                onTap: () => Navigator.pop(ctx, (code,)),
              ),
          ],
        ),
      ),
    );
    if (pick != null) {
      await ref
          .read(playerSettingsProvider.notifier)
          .setPreferredAudio(pick.$1);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(indexStateProvider).value?.running ?? false;
    final last = ref.watch(lastIndexedAtProvider).value;
    final counts = ref.watch(countsProvider).value;
    final ask = ref.watch(themeSettingsProvider).askExternalPlayer;
    final audio = ref.watch(preferredAudioProvider);
    final audioLabel = audio == null
        ? 'No preference'
        : preferredLanguageChoices
                  .where((c) => c.$1 == audio)
                  .firstOrNull
                  ?.$2 ??
              audio;
    final h = Theme.of(context).textTheme.titleSmall;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          Text('Theme', style: h),
          const SizedBox(height: 8),
          const ThemeSection(),
          const SizedBox(height: 24),
          Text('Playback', style: h),
          ListTile(
            key: const Key('external-player'),
            contentPadding: EdgeInsets.zero,
            title: const Text('External player'),
            trailing: Text(ask ? 'Ask every time' : 'Last used'),
            onTap: () =>
                ref.read(themeSettingsProvider.notifier).setAskExternal(!ask),
          ),
          ListTile(
            key: const Key('preferred-audio'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Preferred audio'),
            trailing: Text(audioLabel),
            onTap: () => _pickAudio(context, ref),
          ),
          ListTile(
            key: const Key('reindex'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Re-index'),
            trailing: const Text('Run now'),
            onTap: running
                ? null
                : () => ref.read(indexServiceProvider).reindex(),
          ),
          const SizedBox(height: 16),
          Text('Index', style: h),
          const SizedBox(height: 8),
          Text('Last indexed: ${last == null ? 'never' : formatTime(last)}'),
          if (counts != null)
            Text('${counts.titles} titles, ${counts.files} files'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: running
                    ? null
                    : () => ref.read(indexServiceProvider).reindex(),
                child: const Text('Re-index (incremental)'),
              ),
              OutlinedButton(
                onPressed: running
                    ? null
                    : () => ref.read(indexServiceProvider).reindex(full: true),
                child: const Text('Full re-index'),
              ),
              OutlinedButton(
                onPressed: running ? null : () => _clear(context, ref),
                child: const Text('Clear index'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const IndexProgress(),
          const SizedBox(height: 24),
          Text('About', style: h),
          const SizedBox(height: 8),
          const Text('watchdog, unofficial DhakaFlix client'),
          const Text('Author: mhm'),
          const Text('License: Apache-2.0'),
          const Text('Version: $appVersion'),
          ListTile(
            key: const Key('check-updates'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Check for updates'),
            subtitle: const Text('Looks at the GitHub releases'),
            trailing: const Icon(Icons.system_update_alt),
            onTap: () => checkForUpdate(context, ref, manual: true),
          ),
          SwitchListTile(
            key: const Key('auto-update'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Check on launch'),
            subtitle: const Text('At most once a day'),
            value: ref.watch(updatePrefsProvider).value?.autoCheck ?? true,
            onChanged: (v) =>
                ref.read(updatePrefsProvider.notifier).setAutoCheck(v),
          ),
          ListTile(
            key: const Key('repository'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Repository'),
            subtitle: const Text(repoLabel),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openRepo(context, ref),
          ),
          const SizedBox(height: 12),
          const Text(
            'Native libraries: playback uses libmpv and FFmpeg (LGPL-3.0+); '
            'source: see docs/LICENSE-ANALYSIS.md / the project repository.',
          ),
          ListTile(
            key: const Key('licenses'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Open source licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'watchdog',
              applicationLegalese: 'Apache-2.0 · by mhm',
            ),
          ),
        ],
      ),
    );
  }
}
