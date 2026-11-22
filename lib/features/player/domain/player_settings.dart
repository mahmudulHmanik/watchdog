import 'dart:convert';
import 'dart:io';

import 'subtitle_style.dart';

/// Video decoder choice. [auto] = mpv `auto-safe` (hardware where it is known
/// to work, software otherwise); [off] = software decoding only.
enum HwdecMode { auto, off }

/// Player preferences. [preferredAudio] is an ISO 639 code or language name
/// (`hin`, `en`, `Hindi`); null = no preference (use the file default).
class PlayerSettings {
  const PlayerSettings({
    this.preferredAudio,
    this.autoplayNext = true,
    this.subtitleStyle = const SubtitleStyle(),
    this.hwdec = HwdecMode.auto,
    this.hwdecAutoOff = false,
  });
  final String? preferredAudio;
  final bool autoplayNext;
  final SubtitleStyle subtitleStyle;
  final HwdecMode hwdec;

  /// True when [hwdec] is [HwdecMode.off] because the player switched it off
  /// itself after a decoder error (not the user's choice). Only meaningful
  /// with [HwdecMode.off].
  final bool hwdecAutoOff;

  PlayerSettings copyWith({
    Object? preferredAudio = _keep,
    bool? autoplayNext,
    SubtitleStyle? subtitleStyle,
    HwdecMode? hwdec,
    bool? hwdecAutoOff,
  }) => PlayerSettings(
    preferredAudio: identical(preferredAudio, _keep)
        ? this.preferredAudio
        : preferredAudio as String?,
    autoplayNext: autoplayNext ?? this.autoplayNext,
    subtitleStyle: subtitleStyle ?? this.subtitleStyle,
    hwdec: hwdec ?? this.hwdec,
    hwdecAutoOff: hwdecAutoOff ?? this.hwdecAutoOff,
  );

  static const _keep = Object();

  Map<String, Object?> toJson() => {
    'preferredAudio': preferredAudio,
    'autoplayNext': autoplayNext,
    'subtitleStyle': subtitleStyle.toJson(),
    'hwdec': hwdec.name,
    'hwdecAutoOff': hwdecAutoOff,
  };

  factory PlayerSettings.fromJson(Map<String, Object?> j) {
    final hw = j['hwdec'] == 'off' ? HwdecMode.off : HwdecMode.auto;
    return PlayerSettings(
      preferredAudio:
          j['preferredAudio'] is String &&
              (j['preferredAudio'] as String).isNotEmpty
          ? j['preferredAudio'] as String
          : null,
      autoplayNext: j['autoplayNext'] is bool
          ? j['autoplayNext'] as bool
          : true,
      subtitleStyle: SubtitleStyle.fromJson(j['subtitleStyle']),
      hwdec: hw,
      hwdecAutoOff: hw == HwdecMode.off && j['hwdecAutoOff'] == true,
    );
  }
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
