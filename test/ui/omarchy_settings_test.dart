import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/core/theme/omarchy_source.dart';
import 'package:watchdog/core/theme/theme_providers.dart';

import 'fakes.dart';

Future<ProviderContainer> boot(WidgetTester t, Directory root) async {
  useTallView(t);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(FakeRepository(), FakePlatform()),
        omarchyLocatorProvider.overrideWithValue(OmarchyLocator(root)),
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
  testWidgets('switch disabled when theme missing', (t) async {
    final root = Directory.systemTemp.createTempSync('om-none');
    addTearDown(() => root.deleteSync(recursive: true));
    await boot(t, root);
    expect(find.text('Omarchy theme not found'), findsOneWidget);
    expect(
      t
          .widget<SwitchListTile>(find.byKey(const Key('follow-omarchy')))
          .onChanged,
      isNull,
    );
  });

  testWidgets('on: shows theme name, dims built-in palettes, applies colors', (
    t,
  ) async {
    final root = Directory.systemTemp.createTempSync('om-on');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/current/theme').createSync(recursive: true);
    File('${root.path}/current/theme/colors.toml').writeAsStringSync(
      File('test/fixtures/omarchy_dark.toml').readAsStringSync(),
    );
    File('${root.path}/current/theme.name').writeAsStringSync('serenity\n');
    final c = await boot(t, root);
    expect(find.text('Linux only · reads your active theme'), findsOneWidget);
    await t.tap(find.byKey(const Key('follow-omarchy')));
    await t.pumpAndSettle();
    expect(c.read(themeSettingsProvider).followOmarchy, isTrue);
    expect(find.text('serenity'), findsOneWidget);
    final op = t.widget<Opacity>(
      find.ancestor(
        of: find.byKey(const Key('palette-latte')),
        matching: find.byType(Opacity),
      ),
    );
    expect(op.opacity, lessThan(1));
    expect(
      Theme.of(t.element(find.byType(Scaffold).first)).scaffoldBackgroundColor,
      const Color(0xFF232E37),
    );
  });
}
