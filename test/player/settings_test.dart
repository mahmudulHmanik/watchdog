import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/player/domain/player_settings.dart';
import 'package:watchdog/features/player/player_providers.dart';

void main() {
  test('defaults: no preferred audio, autoplay on', () {
    const s = PlayerSettings();
    expect(s.preferredAudio, isNull);
    expect(s.autoplayNext, isTrue);
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
