import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sub-pages of the Settings tab.
enum SettingsPage { appearance, playback, library, tmdb, updates, about }

/// Deep link into Settings: set it, switch to the Settings tab, and the
/// Settings screen opens that page once and clears it.
class SettingsTarget extends Notifier<SettingsPage?> {
  @override
  SettingsPage? build() => null;
  void open(SettingsPage p) => state = p;
  void clear() => state = null;
}

final settingsTargetProvider = NotifierProvider<SettingsTarget, SettingsPage?>(
  SettingsTarget.new,
);
