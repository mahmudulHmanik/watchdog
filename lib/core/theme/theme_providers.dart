import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'omarchy_source.dart';
import 'palettes.dart';
import 'theme_store.dart';

/// Where theme choices are persisted; main overrides with a file store.
final themeStoreProvider = Provider<ThemeStore>((ref) => MemoryThemeStore());

/// Settings loaded before runApp (no flash of the default theme).
final initialThemeProvider = Provider<ThemeSettings>(
  (ref) => const ThemeSettings(),
);

class ThemeSettingsNotifier extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() => ref.watch(initialThemeProvider);

  void _update(ThemeSettings s) {
    state = s;
    ref.read(themeStoreProvider).save(s).catchError((_) {});
  }

  /// Picking an explicit palette turns following off.
  void setPalette(AppPalette p) =>
      _update(state.copyWith(palette: p, followSystem: false));
  void setFollowSystem() => _update(state.copyWith(followSystem: true));
  void setShape(ShapeMode m) => _update(state.copyWith(shape: m));
  void setAskExternal(bool v) => _update(state.copyWith(askExternalPlayer: v));
}

final themeSettingsProvider =
    NotifierProvider<ThemeSettingsNotifier, ThemeSettings>(
      ThemeSettingsNotifier.new,
    );

/// Where Omarchy state lives; null off Linux. Override in tests.
final omarchyLocatorProvider = Provider<OmarchyLocator?>(
  (ref) => Platform.isLinux ? OmarchyLocator.fromEnv() : null,
);

/// Theme loaded before runApp (avoids a flash); optional.
final initialOmarchyProvider = Provider<OmarchyState?>(
  (ref) => ref.read(omarchyLocatorProvider)?.load(),
);

/// Current Omarchy theme (null when absent/corrupt); live-updated by a
/// debounced directory watcher. Never throws.
class OmarchyNotifier extends Notifier<OmarchyState?> {
  @override
  OmarchyState? build() {
    final loc = ref.watch(omarchyLocatorProvider);
    if (loc == null) return null;
    final w = OmarchyWatcher(loc, () {
      try {
        state = loc.load();
      } catch (_) {}
    });
    ref.onDispose(w.dispose);
    return ref.read(initialOmarchyProvider);
  }
}

final omarchyProvider = NotifierProvider<OmarchyNotifier, OmarchyState?>(
  OmarchyNotifier.new,
);

/// System light/dark, live (updates on OS mode change, no restart).
class PlatformBrightnessNotifier extends Notifier<Brightness>
    with WidgetsBindingObserver {
  @override
  Brightness build() {
    final b = WidgetsBinding.instance;
    b.addObserver(this);
    ref.onDispose(() => b.removeObserver(this));
    return b.platformDispatcher.platformBrightness;
  }

  @override
  void didChangePlatformBrightness() =>
      state = WidgetsBinding.instance.platformDispatcher.platformBrightness;
}

final platformBrightnessProvider =
    NotifierProvider<PlatformBrightnessNotifier, Brightness>(
      PlatformBrightnessNotifier.new,
    );

/// What auto mode is doing right now: Omarchy (name) or system (mode).
class AutoTheme {
  const AutoTheme(this.palette, this.label);
  final AppPalette palette;

  /// e.g. `Following Omarchy: serenity`, `Following system: dark`.
  final String label;
}

final autoThemeProvider = Provider<AutoTheme>((ref) {
  final o = ref.watch(omarchyProvider);
  if (o != null) {
    return AutoTheme(o.palette, 'Following Omarchy: ${o.name ?? 'custom'}');
  }
  final dark = ref.watch(platformBrightnessProvider) == Brightness.dark;
  return AutoTheme(
    dark ? everforest : catppuccinLatte,
    'Following system: ${dark ? 'dark' : 'light'}',
  );
});

/// Active palette: auto (Omarchy, else system) when following, else the
/// saved explicit one.
final paletteProvider = Provider<AppPalette>((ref) {
  final s = ref.watch(themeSettingsProvider);
  return s.followSystem ? ref.watch(autoThemeProvider).palette : s.palette;
});
final shapeModeProvider = Provider<ShapeMode>(
  (ref) => ref.watch(themeSettingsProvider.select((s) => s.shape)),
);
