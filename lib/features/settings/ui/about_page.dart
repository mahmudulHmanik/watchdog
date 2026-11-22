import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/app_info.dart';
import 'package:watchdog/features/settings/tmdb_ui_providers.dart';
import 'package:watchdog/platform/platform_api.dart';

import 'settings_widgets.dart';

/// Settings -> About: credits, license, repository, TMDB notice, licenses.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SettingsPageScaffold(
      title: 'About',
      children: [
        const SettingsBlock(
          title: 'WATCHDOG',
          children: [
            Padding(
              padding: settingsPad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('watchdog, unofficial DhakaFlix client'),
                  SizedBox(height: 4),
                  Text('Author: mhm'),
                  Text('License: Apache-2.0'),
                ],
              ),
            ),
          ],
        ),
        SettingsBlock(
          title: 'LINKS',
          children: [
            ListTile(
              key: const Key('repository'),
              title: const Text('Repository'),
              subtitle: const Text(repoLabel),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openRepo(context, ref),
            ),
            ListTile(
              key: const Key('licenses'),
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
        SettingsBlock(
          title: 'CREDITS',
          children: [
            Padding(
              padding: settingsPad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Approved TMDB logo (unmodified apart from inlining its CSS
                  // fill for flutter_svg). Kept small: TMDB requires it to be
                  // less prominent than the app's own branding.
                  Semantics(
                    label: 'The Movie Database (TMDB)',
                    image: true,
                    child: SvgPicture.asset(
                      tmdbLogoAsset,
                      key: const Key('tmdb-logo'),
                      height: 14,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(tmdbAttribution, key: Key('tmdb-attribution')),
                  const SizedBox(height: 10),
                  Text(
                    'Native libraries: playback uses libmpv and FFmpeg '
                    '(LGPL-3.0+); source: see docs/LICENSE-ANALYSIS.md / the '
                    'project repository.',
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
