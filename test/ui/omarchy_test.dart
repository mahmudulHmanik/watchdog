import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/core/theme/omarchy_colors.dart';
import 'package:watchdog/core/theme/omarchy_source.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';

String fx(String n) => File('test/fixtures/$n').readAsStringSync();

Directory mkTheme(String colors, {String name = 'serenity'}) {
  final root = Directory.systemTemp.createTempSync('omarchy');
  Directory('${root.path}/current/theme').createSync(recursive: true);
  File('${root.path}/current/theme/colors.toml').writeAsStringSync(colors);
  File('${root.path}/current/theme.name').writeAsStringSync('$name\n');
  File('${root.path}/current/theme.generation').writeAsStringSync('1\n');
  addTearDown(() => root.deleteSync(recursive: true));
  return root;
}

void main() {
  group('parse + mapping', () {
    test('real dark sample', () {
      final c = OmarchyColors.parse(fx('omarchy_dark.toml'));
      expect(c.dark, isTrue);
      expect(c['background'], const Color(0xFF232E37));
      final p = c.toPalette()!;
      expect(p.bg, const Color(0xFF232E37));
      expect(p.bar, const Color(0xFF1B242B));
      expect(p.text, const Color(0xFFF0EAD6));
      expect(p.accent, const Color(0xFFA69F96));
      expect(p.ok, const Color(0xFF7E8B56));
      expect(p.dark, isTrue);
      // selection == lighter_background: hi must still differ from card.
      expect(p.highlight, isNot(p.card));
      // muted (#6b706f) is too faint on bg -> derived, passes 4.5.
      expect(contrast(p.muted, p.bg), greaterThanOrEqualTo(4.5));
      // onAccent is the higher-contrast of bar / foreground.
      expect(
        contrast(p.onAccent, p.accent),
        greaterThanOrEqualTo(contrast(p.text, p.accent) - 1e-9),
      );
    });

    test('light sample', () {
      final p = OmarchyColors.parse(fx('omarchy_light.toml')).toPalette()!;
      expect(p.dark, isFalse);
      expect(p.bg, const Color(0xFFFAFAFA));
      expect(contrast(p.muted, p.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(p.accent, p.bg), greaterThanOrEqualTo(3));
    });

    test('contrast helper', () {
      expect(
        contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
      expect(
        contrast(const Color(0xFF777777), const Color(0xFF777777)),
        closeTo(1, 0.001),
      );
      expect(
        contrast(const Color(0xFF767676), const Color(0xFFFFFFFF)),
        closeTo(4.54, 0.05),
      );
    });

    test('muted kept when contrast is enough', () {
      final p = OmarchyColors.parse(
        'background = "#000000"\nforeground = "#ffffff"\nmuted = "#aaaaaa"',
      ).toPalette()!;
      expect(p.muted, const Color(0xFFAAAAAA));
    });

    test('poor accent falls back to bright_blue', () {
      final p = OmarchyColors.parse('''
background = "#222222"
foreground = "#eeeeee"
accent = "#242424"
bright_blue = "#88aaff"
''').toPalette()!;
      expect(p.accent, const Color(0xFF88AAFF));
    });

    test('card equal to bg is shifted; tolerant parsing', () {
      final c = OmarchyColors.parse('''
# comment
garbage line
mode = "light"
background = "#fff"
foreground = '#000'
lighter_background = "#ffffff"   # trailing
bogus = "nothex"
unknown = "#123456"
''');
      final p = c.toPalette()!;
      expect(p.bg, const Color(0xFFFFFFFF));
      expect(p.text, const Color(0xFF000000));
      expect(p.card, isNot(p.bg));
      expect(p.dark, isFalse);
    });

    test('missing background -> null', () {
      expect(OmarchyColors.parse('foreground = "#fff"').toPalette(), isNull);
      expect(OmarchyColors.parse('').toPalette(), isNull);
    });
  });

  group('locator + provider', () {
    test('load reads name; missing/corrupt -> null', () {
      final root = mkTheme(fx('omarchy_dark.toml'));
      final loc = OmarchyLocator(Directory(root.path));
      expect(loc.load()!.name, 'serenity');
      File(loc.colors.path).writeAsStringSync('\u0000 not toml');
      expect(loc.load(), isNull);
      File(loc.colors.path).deleteSync();
      expect(loc.load(), isNull);
      expect(
        OmarchyLocator.fromEnv({'XDG_STATE_HOME': '/x'})!.root.path,
        '/x/omarchy',
      );
      expect(
        OmarchyLocator.fromEnv({'HOME': '/h'})!.root.path,
        '/h/.local/state/omarchy',
      );
    });

    ProviderContainer container(Directory root, {bool follow = true}) {
      final c = ProviderContainer(
        overrides: [
          omarchyLocatorProvider.overrideWithValue(OmarchyLocator(root)),
          themeStoreProvider.overrideWithValue(MemoryThemeStore()),
          initialThemeProvider.overrideWithValue(
            ThemeSettings(followOmarchy: follow, palette: tokyoNight),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('follow on -> omarchy palette; off -> saved', () {
      final root = mkTheme(fx('omarchy_dark.toml'));
      final c = container(root);
      expect(c.read(paletteProvider).id, 'omarchy');
      c.read(themeSettingsProvider.notifier).setFollowOmarchy(false);
      expect(c.read(paletteProvider).id, 'tokyo');
    });

    test('file missing or corrupt -> falls back to saved palette', () {
      final root = mkTheme('garbage');
      expect(container(root).read(paletteProvider).id, 'tokyo');
      final none = Directory.systemTemp.createTempSync('omarchy-none');
      addTearDown(() => none.deleteSync(recursive: true));
      expect(container(none).read(paletteProvider).id, 'tokyo');
    });

    test('live update through the notifier', () async {
      final root = mkTheme(fx('omarchy_dark.toml'));
      final c = container(root);
      final sub = c.listen(omarchyProvider, (_, _) {});
      expect(sub.read()!.palette.bg, const Color(0xFF232E37));
      File('${root.path}/current/theme/colors.toml')
          .writeAsStringSync(fx('omarchy_light.toml'));
      File('${root.path}/current/theme.generation').writeAsStringSync('2\n');
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(c.read(paletteProvider).bg, const Color(0xFFFAFAFA));
    });
  });

  group('watcher', () {
    test('rewrite + generation change fires within a second', () async {
      final root = mkTheme(fx('omarchy_dark.toml'));
      final fired = Completer<void>();
      final w = OmarchyWatcher(
        OmarchyLocator(root),
        () => fired.isCompleted ? null : fired.complete(),
      );
      addTearDown(w.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      File('${root.path}/current/theme.generation').writeAsStringSync('2\n');
      await fired.future.timeout(const Duration(seconds: 1));
    });

    test('symlink swap of theme dir is noticed (re-subscribes)', () async {
      final root = mkTheme(fx('omarchy_dark.toml'));
      var n = 0;
      final w = OmarchyWatcher(OmarchyLocator(root), () => n++);
      addTearDown(w.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final next = Directory('${root.path}/current/theme-next')..createSync();
      File('${next.path}/colors.toml')
          .writeAsStringSync(fx('omarchy_light.toml'));
      Directory('${root.path}/current/theme').deleteSync(recursive: true);
      Link('${root.path}/current/theme').createSync(next.path);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(n, greaterThan(0));
      final before = n;
      File('${next.path}/colors.toml').writeAsStringSync('x');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(n, greaterThan(before)); // new dir is watched
    });

    test('missing dir retries with backoff and recovers', () async {
      final root = Directory.systemTemp.createTempSync('omarchy-late');
      addTearDown(() => root.deleteSync(recursive: true));
      var n = 0;
      final w = OmarchyWatcher(
        OmarchyLocator(root),
        () => n++,
        maxBackoff: const Duration(milliseconds: 200),
      );
      addTearDown(w.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      Directory('${root.path}/current/theme').createSync(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(n, greaterThan(0));
    });
  });
}
