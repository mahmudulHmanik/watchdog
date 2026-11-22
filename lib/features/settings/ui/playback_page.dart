import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/features/player/domain/player_settings.dart';
import 'package:watchdog/features/player/domain/track_prefs.dart';
import 'package:watchdog/features/player/player_providers.dart';

import 'settings_widgets.dart';

/// Label for the preferred-audio setting (also used by the home summary).
String preferredAudioLabel(String? code) => code == null
    ? 'No preference'
    : preferredLanguageChoices.where((c) => c.$1 == code).firstOrNull?.$2 ??
          code;

/// Settings -> Playback: external player behaviour, preferred audio.
class PlaybackPage extends ConsumerWidget {
  const PlaybackPage({super.key});

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
    final ask = ref.watch(themeSettingsProvider).askExternalPlayer;
    final audio = ref.watch(preferredAudioProvider);
    final hw = ref.watch(hwdecProvider);
    final hwOff = hw.mode == HwdecMode.off;
    return SettingsPageScaffold(
      title: 'Playback',
      children: [
        SettingsBlock(
          title: 'EXTERNAL PLAYER',
          children: [
            ListTile(
              key: const Key('external-player'),
              title: const Text('External player'),
              trailing: Text(ask ? 'Ask every time' : 'Last used'),
              onTap: () =>
                  ref.read(themeSettingsProvider.notifier).setAskExternal(!ask),
            ),
          ],
        ),
        SettingsBlock(
          title: 'AUDIO',
          children: [
            ListTile(
              key: const Key('preferred-audio'),
              title: const Text('Preferred audio'),
              trailing: Text(preferredAudioLabel(audio)),
              onTap: () => _pickAudio(context, ref),
            ),
          ],
        ),
        SettingsBlock(
          title: 'VIDEO',
          children: [
            ListTile(
              key: const Key('hwdec'),
              title: const Text('Hardware decoding'),
              subtitle: hw.autoOff
                  ? const Text(
                      'Switched off automatically on this phone after a '
                      'decoder error',
                    )
                  : null,
              trailing: Text(hwOff ? 'Off (software)' : 'Auto'),
              onTap: () => ref
                  .read(playerSettingsProvider.notifier)
                  .setHwdec(hwOff ? HwdecMode.auto : HwdecMode.off),
            ),
            if (hw.autoOff)
              ListTile(
                key: const Key('hwdec-retry'),
                leading: const Icon(Icons.refresh),
                title: const Text('Try hardware again'),
                onTap: () =>
                    ref.read(playerSettingsProvider.notifier).resetHwdec(),
              ),
          ],
        ),
      ],
    );
  }
}
