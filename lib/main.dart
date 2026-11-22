import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/theme/font_licenses.dart';
import 'core/theme/theme_providers.dart';
import 'core/theme/theme_store.dart';
import 'data/database.dart';
import 'data/drift_repository.dart';
import 'data/repository.dart';
import 'features/demo/ui/demo_mode.dart';
import 'platform/platform_impl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final demo = demoScreen;
  if (demo != null) {
    final d = await buildDemo(demo);
    runApp(
      ProviderScope(
        overrides: d.overrides,
        child: WatchdogApp(onReady: d.onReady),
      ),
    );
    return;
  }
  final repo = DriftRepository(await openDatabase());
  final dir = await getApplicationSupportDirectory();
  final themeStore = FileThemeStore(File('${dir.path}/theme.json'));
  final theme = await themeStore.load();
  runApp(
    ProviderScope(
      overrides: [
        ...platformOverrides(),
        repositoryProvider.overrideWithValue(repo),
        themeStoreProvider.overrideWithValue(themeStore),
        initialThemeProvider.overrideWithValue(theme),
      ],
      child: const WatchdogApp(),
    ),
  );
}
