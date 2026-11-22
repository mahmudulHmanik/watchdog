import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'domain/player_settings.dart';
import 'domain/subtitle_style.dart';

class _LazyFileStore implements PlayerSettingsStore {
  FilePlayerSettingsStore? _s;
  Future<FilePlayerSettingsStore>
  _get() async => _s ??= FilePlayerSettingsStore(
    File(
      '${(await getApplicationSupportDirectory()).path}/player_settings.json',
    ),
  );
  @override
  Future<PlayerSettings> load() async => (await _get()).load();
  @override
  Future<void> save(PlayerSettings s) async => (await _get()).save(s);
}

/// Persistence for [PlayerSettings]; override with a memory store in tests.
final playerSettingsStoreProvider = Provider<PlayerSettingsStore>(
  (ref) => _LazyFileStore(),
);

/// Player preferences (preferred audio language, autoplay next). Settings UI
/// (T3.2) uses `setPreferredAudio` / `setAutoplayNext` on the notifier.
final playerSettingsProvider =
    AsyncNotifierProvider<PlayerSettingsNotifier, PlayerSettings>(
      PlayerSettingsNotifier.new,
    );

class PlayerSettingsNotifier extends AsyncNotifier<PlayerSettings> {
  @override
  Future<PlayerSettings> build() =>
      ref.watch(playerSettingsStoreProvider).load();

  Future<void> _set(PlayerSettings s) async {
    state = AsyncData(s);
    await ref.read(playerSettingsStoreProvider).save(s);
  }

  /// ISO 639 code or language name; null clears the preference.
  Future<void> setPreferredAudio(String? lang) async => _set(
    (state.value ?? const PlayerSettings()).copyWith(preferredAudio: lang),
  );

  Future<void> setAutoplayNext(bool on) async =>
      _set((state.value ?? const PlayerSettings()).copyWith(autoplayNext: on));

  /// User's choice; clears the "switched off automatically" note.
  Future<void> setHwdec(HwdecMode m) async => _set(
    (state.value ?? const PlayerSettings()).copyWith(
      hwdec: m,
      hwdecAutoOff: false,
    ),
  );

  /// The player found hardware decoding broken on this device and switched it
  /// off (a software retry played). Never overrides an explicit Off.
  Future<void> markHwdecAutoOff() async {
    final cur = state.value ?? const PlayerSettings();
    if (cur.hwdec == HwdecMode.off) return;
    await _set(cur.copyWith(hwdec: HwdecMode.off, hwdecAutoOff: true));
  }

  /// "Try hardware again": back to Auto.
  Future<void> resetHwdec() => setHwdec(HwdecMode.auto);

  Future<void> setSubtitleStyle(SubtitleStyle st) async =>
      _set((state.value ?? const PlayerSettings()).copyWith(subtitleStyle: st));
}

/// Hardware decoding setting (Auto while loading).
final hwdecProvider = Provider<({HwdecMode mode, bool autoOff})>((ref) {
  final s = ref.watch(playerSettingsProvider).value;
  return (mode: s?.hwdec ?? HwdecMode.auto, autoOff: s?.hwdecAutoOff ?? false);
});

/// Preferred audio language, null when unset (or still loading).
final preferredAudioProvider = Provider<String?>(
  (ref) => ref.watch(playerSettingsProvider).value?.preferredAudio,
);
