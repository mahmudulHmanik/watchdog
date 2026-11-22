import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io' show Platform;

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

  void setPalette(AppPalette p) => _update(state.copyWith(palette: p));
  void setShape(ShapeMode m) => _update(state.copyWith(shape: m));
  void setAskExternal(bool v) => _update(state.copyWith(askExternalPlayer: v));
  void setFollowOmarchy(bool v) => _update(state.copyWith(followOmarchy: v));
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

/// Active palette: Omarchy when following and available, else the saved one.
final paletteProvider = Provider<AppPalette>((ref) {
  final s = ref.watch(themeSettingsProvider);
  if (s.followOmarchy) {
    final o = ref.watch(omarchyProvider);
    if (o != null) return o.palette;
  }
  return s.palette;
});
final shapeModeProvider = Provider<ShapeMode>(
  (ref) => ref.watch(themeSettingsProvider.select((s) => s.shape)),
);
