import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/tmdb/tmdb_settings.dart';

const _key = '0123456789abcdef0123456789abcdef';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('tmdb_settings'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('TmdbSettings', () {
    test('defaults: background on, en-US', () {
      const s = TmdbSettings();
      expect(s.backgroundFetch, isTrue);
      expect(s.language, 'en-US');
    });

    test('json round trip', () {
      const s = TmdbSettings(backgroundFetch: false, language: 'hi-IN');
      final r = TmdbSettings.fromJson(s.toJson());
      expect((r.backgroundFetch, r.language), (false, 'hi-IN'));
    });

    test('bad values fall back to defaults', () {
      final r = TmdbSettings.fromJson({
        'language': 'English!',
        'backgroundFetch': 3,
      });
      expect((r.backgroundFetch, r.language), (true, 'en-US'));
      expect(TmdbSettings.isValidLanguage('fr'), isTrue);
      expect(TmdbSettings.isValidLanguage('en-us'), isFalse);
    });
  });

  group('FileTmdbSettingsStore', () {
    FileTmdbSettingsStore store([SecretStore? s]) => FileTmdbSettingsStore(
      File('${dir.path}/tmdb.json'),
      s ?? FileSecretStore(File('${dir.path}/secrets/tmdb.key')),
    );

    test('missing file loads defaults', () async {
      expect((await store().load()).language, 'en-US');
    });

    test('corrupt file loads defaults', () async {
      File('${dir.path}/tmdb.json').writeAsStringSync('{nope');
      expect((await store().load()).backgroundFetch, isTrue);
    });

    test('settings persist', () async {
      await store().save(
        const TmdbSettings(backgroundFetch: false, language: 'de-DE'),
      );
      final s = await store().load();
      expect((s.backgroundFetch, s.language), (false, 'de-DE'));
    });

    test('credential round trip, trimmed, and cleared', () async {
      final st = store();
      expect(await st.readCredential(), isNull);
      await st.writeCredential('  $_key\n');
      expect(await store().readCredential(), _key);
      await st.clearCredential();
      expect(await st.readCredential(), isNull);
      await st.clearCredential(); // already gone: fine
    });

    test('credential never lands in the settings json', () async {
      final st = store();
      await st.writeCredential(_key);
      await st.save(const TmdbSettings());
      expect(
        File('${dir.path}/tmdb.json').readAsStringSync(),
        isNot(contains(_key)),
      );
    });

    test('secret file is 0600 in a 0700 directory', () async {
      await store().writeCredential(_key);
      final f = File('${dir.path}/secrets/tmdb.key');
      expect(f.statSync().mode & 0x1ff, 0x180); // 0600
      expect(f.parent.statSync().mode & 0x1ff, 0x1c0); // 0700
      expect(File('${f.path}.tmp').existsSync(), isFalse);
    }, skip: !Platform.isLinux && !Platform.isMacOS);

    test('overwriting keeps the permissions', () async {
      final st = store();
      await st.writeCredential(_key);
      await st.writeCredential('a' * 32);
      final f = File('${dir.path}/secrets/tmdb.key');
      expect(f.readAsStringSync(), 'a' * 32);
      expect(f.statSync().mode & 0x1ff, 0x180);
    }, skip: !Platform.isLinux && !Platform.isMacOS);

    test('unreadable secret file reads as no key', () async {
      File('${dir.path}/secrets').createSync();
      expect(await store().readCredential(), isNull);
    });
  });

  group('MemoryTmdbSettingsStore', () {
    test('behaves like the real one', () async {
      final m = MemoryTmdbSettingsStore();
      expect(await m.readCredential(), isNull);
      await m.writeCredential(_key);
      await m.save(const TmdbSettings(language: 'fr-FR'));
      expect(await m.readCredential(), _key);
      expect((await m.load()).language, 'fr-FR');
      await m.clearCredential();
      expect(await m.readCredential(), isNull);
    });
  });
}
