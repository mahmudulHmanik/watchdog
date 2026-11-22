import 'package:material_ui/material_ui.dart';

import 'settings_widgets.dart';
import 'theme_section.dart';

/// Settings -> Appearance: palette rows (incl. follow system / Omarchy) and shape.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPageScaffold(
    title: 'Appearance',
    children: [
      SettingsBlock(
        title: 'THEME',
        bordered: false,
        children: [ThemeSection()],
      ),
      SettingsBlock(
        title: 'SHAPE',
        bordered: false,
        children: [ShapeSection()],
      ),
    ],
  );
}
