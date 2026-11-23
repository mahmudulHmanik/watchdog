import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/player/domain/mpv_tuning.dart';
import 'package:watchdog/features/player/domain/player_settings.dart';
import 'package:watchdog/features/player/player_providers.dart';

void main() {
  test('defaults: no preferred audio, autoplay on', () {
    const s = PlayerSettings();
    expect(s.preferredAudio, isNull);
    expect(s.autoplayNext, isTrue);
  });

  test('hardware decoding: default Auto, round trip, auto-off flag', () async {
    const d = PlayerSettings();
    expect(d.hwdec, HwdecMode.auto);
    expect(d.hwdecAutoOff, isFalse);
    expect(hwdecValue(HwdecMode.auto, override: ''), 'auto-safe');
    // The diagnostic env override wins for "auto", never for "off".
    expect(hwdecValue(HwdecMode.auto, override: ' vaapi '), 'vaapi');
    expect(hwdecValue(HwdecMode.off, override: 'vaapi'), 'no');
    expect(hwdecValue(HwdecMode.off), 'no');
    final r = PlayerSettings.fromJson(
      const PlayerSettings(hwdec: HwdecMode.off, hwdecAutoOff: true).toJson(),
    );
    expect(r.hwdec, HwdecMode.off);
    expect(r.hwdecAutoOff, isTrue);
    // old file without the keys, unknown value, flag without Off
    expect(PlayerSettings.fromJson(const {}).hwdec, HwdecMode.auto);
    expect(PlayerSettings.fromJson(const {'hwdec': 'x'}).hwdec, HwdecMode.auto);
    expect(
      PlayerSettings.fromJson(const {'hwdec': 'auto', 'hwdecAutoOff': true})
          .hwdecAutoOff,
      isFalse,
    );
    final dir = await Directory.systemTemp.createTemp('ps');
    addTearDown(() => dir.delete(recursive: true));
    final st = FilePlayerSettingsStore(File('${dir.path}/p.json'));
    await st.save(
      const PlayerSettings(hwdec: HwdecMode.off, hwdecAutoOff: true),
    );
    final l = await st.load();
    expect((l.hwdec, l.hwdecAutoOff), (HwdecMode.off, true));
  });

  test('provider: auto-off, user choice and reset', () async {
    final store = MemoryPlayerSettingsStore();
    final c = ProviderContainer(
      overrides: [playerSettingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    await c.read(playerSettingsProvider.future);
    final n = c.read(playerSettingsProvider.notifier);
    await n.markHwdecAutoOff();
    expect(store.value.hwdec, HwdecMode.off);
    expect(store.value.hwdecAutoOff, isTrue);
    expect(c.read(hwdecProvider), (mode: HwdecMode.off, autoOff: true));
    await n.resetHwdec();
    expect(store.value.hwdec, HwdecMode.auto);
    expect(store.value.hwdecAutoOff, isFalse);
    // explicit Off is the user's: not flagged automatic, never overwritten
    await n.setHwdec(HwdecMode.off);
    await n.markHwdecAutoOff();
    expect(store.value.hwdecAutoOff, isFalse);
    // other prefs survive
    await n.setPreferredAudio('hin');
    await n.resetHwdec();
    expect(store.value.preferredAudio, 'hin');
  });

  test('copyWith can clear preferredAudio', () {
    final s = const PlayerSettings(preferredAudio: 'hin')
        .copyWith(preferredAudio: null);
    expect(s.preferredAudio, isNull);
    expect(
      const PlayerSettings(preferredAudio: 'hin')
          .copyWith(autoplayNext: false)
          .preferredAudio,
      'hin',
    );
  });

  test(
    'file store round-trips; corrupt/missing file reads as defaults',
    () async {
      final dir = await Directory.systemTemp.createTemp('ps');
      addTearDown(() => dir.delete(recursive: true));
      final st = FilePlayerSettingsStore(File('${dir.path}/sub/p.json'));
      expect((await st.load()).autoplayNext, isTrue);
      await st.save(
        const PlayerSettings(preferredAudio: 'eng', autoplayNext: false),
      );
      final r = await st.load();
      expect(r.preferredAudio, 'eng');
      expect(r.autoplayNext, isFalse);
      await File('${dir.path}/sub/p.json').writeAsString('{nope');
      expect((await st.load()).preferredAudio, isNull);
    },
  );

  test('provider loads, updates and persists', () async {
    final store = MemoryPlayerSettingsStore(
      const PlayerSettings(preferredAudio: 'hin'),
    );
    final c = ProviderContainer(
      overrides: [playerSettingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    expect((await c.read(playerSettingsProvider.future)).preferredAudio, 'hin');
    await c.read(playerSettingsProvider.notifier).setPreferredAudio('eng');
    expect(c.read(preferredAudioProvider), 'eng');
    expect(store.value.preferredAudio, 'eng');
    await c.read(playerSettingsProvider.notifier).setAutoplayNext(false);
    expect(store.value.autoplayNext, isFalse);
    await c.read(playerSettingsProvider.notifier).setPreferredAudio(null);
    expect(store.value.preferredAudio, isNull);
    expect(store.value.autoplayNext, isFalse);
  });
}
