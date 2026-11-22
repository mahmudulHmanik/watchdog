import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/theme/font_licenses.dart';
import 'core/theme/theme_providers.dart';
import 'core/theme/theme_store.dart';
import 'data/database.dart';
import 'data/drift_repository.dart';
import 'data/repository.dart';
import 'features/demo/ui/demo_mode.dart';
import 'features/update/update_providers.dart';
import 'platform/platform_impl.dart';
import 'tmdb/tmdb_providers.dart';
import 'tmdb/tmdb_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads libmpv; Player() throws until this has run.
  MediaKit.ensureInitialized();
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
        autoUpdateCheckProvider.overrideWithValue(true),
        repositoryProvider.overrideWithValue(repo),
        themeStoreProvider.overrideWithValue(themeStore),
        initialThemeProvider.overrideWithValue(theme),
        tmdbSettingsStoreProvider.overrideWithValue(
          FileTmdbSettingsStore.platform(dir),
        ),
      ],
      child: const WatchdogApp(),
    ),
  );
}
