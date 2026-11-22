import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/core/app_info.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/omarchy_source.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';
import 'package:watchdog/core/theme/palettes.dart';

import 'fakes.dart';
import 'settings_helpers.dart';

Future<ProviderContainer> boot(
  WidgetTester t, {
  ThemeSettings settings = const ThemeSettings(),
  FakePlatform? platform,
  OmarchyLocator? omarchy,
}) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
  t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(FakeRepository(), platform ?? FakePlatform()),
        initialThemeProvider.overrideWithValue(settings),
        omarchyLocatorProvider.overrideWithValue(omarchy),
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
  return ProviderScope.containerOf(t.element(find.byType(WatchdogApp)));
}

void main() {
  for (final shape in ShapeMode.values) {
    testWidgets('first label fully below app bar (${shape.name})', (t) async {
      await boot(t, settings: ThemeSettings(shape: shape));
      await openGroup(t, 'appearance');
      final bar = t.getRect(find.byType(AppBar));
      final label = t.getRect(find.text('THEME').first);
      expect(label.top, greaterThanOrEqualTo(bar.bottom));
      expect(
        label.bottom,
        lessThanOrEqualTo(t.getRect(find.byType(ListView).first).bottom),
      );
    });
  }

  testWidgets('follow system by default: dark -> everforest, live switch', (
    t,
  ) async {
    final c = await boot(t);
    await openGroup(t, 'appearance');
    expect(c.read(paletteProvider).id, 'everforest');
    expect(find.text('Following system: dark'), findsOneWidget);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.pumpAndSettle();
    expect(c.read(paletteProvider).id, 'latte');
    expect(find.text('Following system: light'), findsOneWidget);
    expect(
      Theme.of(t.element(find.byType(Scaffold).first)).scaffoldBackgroundColor,
      catppuccinLatte.bg,
    );
  });

  testWidgets('explicit pick turns following off; follow entry restores', (
    t,
  ) async {
    final c = await boot(t);
    await openGroup(t, 'appearance');
    await t.scrollUntilVisible(
      find.byKey(const Key('palette-nord')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('palette-nord')));
    await t.pumpAndSettle();
    expect(c.read(themeSettingsProvider).followSystem, isFalse);
    expect(c.read(paletteProvider).id, 'nord');
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.pumpAndSettle();
    expect(c.read(paletteProvider).id, 'nord');
    await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('palette-follow')));
    await t.pumpAndSettle();
    expect(c.read(paletteProvider).id, 'latte');
  });

  testWidgets('Omarchy present: live-follow with name', (t) async {
    final root = Directory.systemTemp.createTempSync('om-set');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/current/theme').createSync(recursive: true);
    File('${root.path}/current/theme/colors.toml').writeAsStringSync(
      File('test/fixtures/omarchy_dark.toml').readAsStringSync(),
    );
    File('${root.path}/current/theme.name').writeAsStringSync('serenity\n');
    final c = await boot(t, omarchy: OmarchyLocator(root));
    // Live summary on the home tile, then the row on the page.
    expect(find.text('Following Omarchy: serenity · Box'), findsOneWidget);
    await openGroup(t, 'appearance');
    expect(find.text('Following Omarchy: serenity'), findsOneWidget);
    expect(c.read(paletteProvider).bg, const Color(0xFF232E37));
  });

  testWidgets('repository row opens URL; failure copies link', (t) async {
    final p = FakePlatform();
    await boot(t, platform: p);
    await openGroup(t, 'about');
    expect(find.text(repoLabel), findsOneWidget);
    await t.tap(find.byKey(const Key('repository')));
    await t.pumpAndSettle();
    expect(p.openedUrls.single.toString(), repoUrl);
    p.openUrlError = StateError('no browser');
    await t.tap(find.byKey(const Key('repository')));
    await t.pumpAndSettle();
    expect(p.copied, [repoUrl]);
    expect(find.textContaining('Link copied'), findsOneWidget);
  });

  testWidgets('updates page shows version and last check', (t) async {
    await boot(t);
    await openGroup(t, 'updates');
    expect(find.text('Version'), findsOneWidget);
    expect(find.text(appVersion), findsOneWidget);
    expect(find.text('Last checked'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Check on launch'), findsOneWidget);
  });
}
