import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/index/ui/index_progress.dart';
import 'package:watchdog/features/player/domain/track_prefs.dart';
import 'package:watchdog/features/player/player_providers.dart';

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
        padding: const EdgeInsets.all(16),
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
          const Text('Repository: github.com/mahmudulHmanik/watchdog'),
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
