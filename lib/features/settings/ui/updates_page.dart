import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/app_info.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/update/ui/update_flow.dart';
import 'package:watchdog/features/update/update_providers.dart';

import 'settings_widgets.dart';

/// Settings -> Updates: version, check now, check on launch, last check.
class UpdatesPage extends ConsumerWidget {
  const UpdatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(updatePrefsProvider).value;
    final ms = prefs?.lastCheckMs ?? 0;
    return SettingsPageScaffold(
      title: 'Updates',
      children: [
        SettingsBlock(
          title: 'VERSION',
          children: [
            const ListTile(
              key: Key('app-version'),
              title: Text('Version'),
              trailing: Text(appVersion),
            ),
            ListTile(
              key: const Key('last-check'),
              title: const Text('Last checked'),
              trailing: Text(
                ms == 0
                    ? 'never'
                    : formatTime(DateTime.fromMillisecondsSinceEpoch(ms)),
              ),
            ),
          ],
        ),
        SettingsBlock(
          title: 'CHECK',
          children: [
            ListTile(
              key: const Key('check-updates'),
              title: const Text('Check for updates'),
              subtitle: const Text('Looks at the GitHub releases'),
              trailing: const Icon(Icons.system_update_alt),
              onTap: () => checkForUpdate(context, ref, manual: true),
            ),
            SwitchListTile(
              key: const Key('auto-update'),
              title: const Text('Check on launch'),
              subtitle: const Text('At most once a day'),
              value: prefs?.autoCheck ?? true,
              onChanged: (v) =>
                  ref.read(updatePrefsProvider.notifier).setAutoCheck(v),
            ),
          ],
        ),
      ],
    );
  }
}
