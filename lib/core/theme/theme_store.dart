import 'dart:convert';
import 'dart:io';

import 'app_theme.dart';
import 'palettes.dart';

class ThemeSettings {
  const ThemeSettings({
    this.palette = everforest,
    this.shape = ShapeMode.box,
    this.followOmarchy = false,
    this.askExternalPlayer = true,
  });
  final AppPalette palette;
  final ShapeMode shape;

  /// Stub toggle (Linux); the colors.toml reader is T3.3.
  final bool followOmarchy;

  /// UI preference: ask which external player each time (else last used).
  final bool askExternalPlayer;

  ThemeSettings copyWith({
    AppPalette? palette,
    ShapeMode? shape,
    bool? followOmarchy,
    bool? askExternalPlayer,
  }) => ThemeSettings(
    palette: palette ?? this.palette,
    shape: shape ?? this.shape,
    followOmarchy: followOmarchy ?? this.followOmarchy,
    askExternalPlayer: askExternalPlayer ?? this.askExternalPlayer,
  );

  Map<String, Object?> toJson() => {
    'palette': palette.id,
    'shape': shape.name,
    'followOmarchy': followOmarchy,
    'askExternalPlayer': askExternalPlayer,
  };

  /// Unknown/missing values fall back to defaults.
  factory ThemeSettings.fromJson(Map<String, Object?> j) => ThemeSettings(
    palette:
        allPalettes.where((p) => p.id == j['palette']).firstOrNull ??
        everforest,
    shape:
        ShapeMode.values.where((s) => s.name == j['shape']).firstOrNull ??
        ShapeMode.box,
    followOmarchy: j['followOmarchy'] == true,
    askExternalPlayer: j['askExternalPlayer'] != false,
  );
}

abstract interface class ThemeStore {
  Future<ThemeSettings> load();
  Future<void> save(ThemeSettings s);
}

class MemoryThemeStore implements ThemeStore {
  MemoryThemeStore([this.value = const ThemeSettings()]);
  ThemeSettings value;
  @override
  Future<ThemeSettings> load() async => value;
  @override
  Future<void> save(ThemeSettings s) async => value = s;
}

/// JSON file store; missing/corrupt file loads defaults.
class FileThemeStore implements ThemeStore {
  FileThemeStore(this.file);
  final File file;

  @override
  Future<ThemeSettings> load() async {
    try {
      return ThemeSettings.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return const ThemeSettings();
    }
  }

  @override
  Future<void> save(ThemeSettings s) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(s.toJson()));
  }
}
