import 'dart:convert';
import 'dart:io';

import 'subtitle_style.dart';

/// Player preferences. [preferredAudio] is an ISO 639 code or language name
/// (`hin`, `en`, `Hindi`); null = no preference (use the file default).
class PlayerSettings {
  const PlayerSettings({
    this.preferredAudio,
    this.autoplayNext = true,
    this.subtitleStyle = const SubtitleStyle(),
  });
  final String? preferredAudio;
  final bool autoplayNext;
  final SubtitleStyle subtitleStyle;

  PlayerSettings copyWith({
    Object? preferredAudio = _keep,
    bool? autoplayNext,
    SubtitleStyle? subtitleStyle,
  }) => PlayerSettings(
    preferredAudio: identical(preferredAudio, _keep)
        ? this.preferredAudio
        : preferredAudio as String?,
    autoplayNext: autoplayNext ?? this.autoplayNext,
    subtitleStyle: subtitleStyle ?? this.subtitleStyle,
  );

  static const _keep = Object();

  Map<String, Object?> toJson() => {
    'preferredAudio': preferredAudio,
    'autoplayNext': autoplayNext,
    'subtitleStyle': subtitleStyle.toJson(),
  };

  factory PlayerSettings.fromJson(Map<String, Object?> j) => PlayerSettings(
    preferredAudio:
        j['preferredAudio'] is String &&
            (j['preferredAudio'] as String).isNotEmpty
        ? j['preferredAudio'] as String
        : null,
    autoplayNext: j['autoplayNext'] is bool ? j['autoplayNext'] as bool : true,
    subtitleStyle: SubtitleStyle.fromJson(j['subtitleStyle']),
  );
}

abstract interface class PlayerSettingsStore {
  Future<PlayerSettings> load();
  Future<void> save(PlayerSettings s);
}

class MemoryPlayerSettingsStore implements PlayerSettingsStore {
  MemoryPlayerSettingsStore([this.value = const PlayerSettings()]);
  PlayerSettings value;
  @override
  Future<PlayerSettings> load() async => value;
  @override
  Future<void> save(PlayerSettings s) async => value = s;
}

/// JSON file store (same pattern as FileIndexMeta). Corrupt/missing file
/// reads as defaults.
class FilePlayerSettingsStore implements PlayerSettingsStore {
  FilePlayerSettingsStore(this.file);
  final File file;

  @override
  Future<PlayerSettings> load() async {
    try {
      return PlayerSettings.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return const PlayerSettings();
    }
  }

  @override
  Future<void> save(PlayerSettings s) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(s.toJson()));
  }
}
