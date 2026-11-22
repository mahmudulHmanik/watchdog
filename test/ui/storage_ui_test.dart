import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/platform/platform_api.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_settings.dart';

import 'fakes.dart';
import 'settings_helpers.dart';

late FakePlatform platform;

Future<void> boot(
  WidgetTester t, {
  Size size = const Size(360, 740),
  ShapeMode shape = ShapeMode.box,
  AppPalette? palette,
  Object? usageError,
  Completer<void>? gate,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  platform = FakePlatform()
    ..usageError = usageError
    ..usageGate = gate;
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(
          FakeRepository(titles: [mkTitle(1, 'A'), mkTitle(2, 'B')]),
          platform,
        ),
        initialThemeProvider.overrideWithValue(
          ThemeSettings(
            shape: shape,
            followSystem: false,
            palette: palette ?? everforest,
          ),
        ),
        tmdbSettingsStoreProvider.overrideWithValue(MemoryTmdbSettingsStore()),
      ],
      child: const WatchdogApp(),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Settings'),
    ),
  );
  await t.pumpAndSettle();
}

Finder row(String key, String size) => find.descendant(
  of: find.byKey(Key('storage-$key')),
  matching: find.text(size),
);

void main() {
  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(900), '900 B');
    expect(formatBytes(412 * 1024), '412 KB');
    expect(formatBytes(23 * 1024 * 1024), '23 MB');
    expect(formatBytes((2.5 * 1024 * 1024).round()), '2.5 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  testWidgets('home tile adds the total to the Library summary', (t) async {
    await boot(t);
    final total = platform.usage.totalBytes;
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-library')),
        matching: find.text('2 titles · ${formatBytes(total)}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Storage block shows sizes, total and free space', (t) async {
    await boot(t);
    platform.usage = const StorageUsage(
      indexBytes: 23 << 20,
      imageCacheBytes: 41 << 20,
      playerCacheBytes: 2 << 20,
      downloadsBytes: 1 << 30,
      freeBytes: 5 << 30,
    );
    await openGroup(t, 'library');
    expect(find.text('STORAGE'), findsOneWidget);
    expect(find.text('Index database'), findsOneWidget);
    expect(row('index', '23 MB'), findsOneWidget);
    expect(row('images', '41 MB'), findsOneWidget);
    expect(row('player', '2.0 MB'), findsOneWidget);
    expect(row('downloads', '1.0 GB'), findsOneWidget);
    expect(row('total', '1.1 GB'), findsOneWidget);
    expect(find.text('5.0 GB free on device'), findsOneWidget);
    expect(find.text('Delete index'), findsNothing);
    // Storage comes before the index block.
    final storageY = t.getTopLeft(find.text('STORAGE')).dy;
    await t.scrollUntilVisible(find.byKey(const Key('clear-index')), 300);
    expect(find.text('INDEX'), findsOneWidget);
    expect(find.byKey(const Key('clear-index')), findsOneWidget);
    expect(storageY, lessThan(t.getTopLeft(find.text('INDEX')).dy + 5000));
  });

  testWidgets('clear image / player cache call the platform and refresh', (
    t,
  ) async {
    await boot(t);
    await openGroup(t, 'library');
    expect(row('images', '41 MB'), findsOneWidget);
    await t.tap(find.byKey(const Key('clear-image-cache')));
    await t.pumpAndSettle();
    expect(platform.calls, contains('clearImageCache'));
    expect(row('images', '0 B'), findsOneWidget);
    expect(row('player', '2.0 MB'), findsOneWidget);
    await t.tap(find.byKey(const Key('clear-player-cache')));
    await t.pumpAndSettle();
    expect(platform.calls, contains('clearPlayerCache'));
    expect(row('player', '0 B'), findsOneWidget);
  });

  testWidgets('delete all downloads asks first, naming the size', (t) async {
    await boot(t);
    await openGroup(t, 'library');
    await t.ensureVisible(find.byKey(const Key('delete-downloads')));
    await t.tap(find.byKey(const Key('delete-downloads')));
    await t.pumpAndSettle();
    expect(find.text('Delete all downloads?'), findsOneWidget);
    expect(find.textContaining('About 3.0 GB'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(platform.calls, isNot(contains('deleteAllDownloads')));

    await t.tap(find.byKey(const Key('delete-downloads')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm-delete-downloads')));
    await t.pumpAndSettle();
    expect(platform.calls, contains('deleteAllDownloads'));
    expect(row('downloads', '0 B'), findsOneWidget);
  });

  testWidgets('failed read shows n/a and a working Retry', (t) async {
    await boot(t, usageError: Exception('nope'));
    await openGroup(t, 'library');
    expect(row('index', 'n/a'), findsOneWidget);
    expect(find.text('Could not read sizes.'), findsOneWidget);
    // The Library tile on the home just omits the total.
    platform.usageError = null;
    await t.ensureVisible(find.byKey(const Key('storage-retry')));
    await t.tap(find.byKey(const Key('storage-retry')));
    await t.pumpAndSettle();
    expect(row('index', '23 MB'), findsOneWidget);
    expect(find.text('Could not read sizes.'), findsNothing);
  });

  testWidgets('loading state shows a placeholder, then the sizes', (t) async {
    final gate = Completer<void>();
    await boot(t, gate: gate);
    await t.tap(find.byKey(const Key('settings-library')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(row('index', '…'), findsOneWidget);
    expect(row('total', '…'), findsOneWidget);
    gate.complete();
    await t.pumpAndSettle();
    expect(row('index', '23 MB'), findsOneWidget);
  });

  for (final shape in ShapeMode.values) {
    for (final p in [tokyoNight, everforest, catppuccinLatte]) {
      testWidgets('360 px, ${shape.name}, ${p.id}: no overflow', (t) async {
        await boot(t, shape: shape, palette: p);
        await openGroup(t, 'library');
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(
          find.byKey(const Key('delete-downloads')),
          200,
        );
        expect(t.takeException(), isNull);
      });
    }
  }
}
