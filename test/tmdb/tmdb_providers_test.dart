import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_settings.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart';

import 'fakes.dart';

const _key = '0123456789abcdef0123456789abcdef';

void main() {
  late MemoryTmdbSettingsStore store;
  late List<Uri> requests;

  ProviderContainer make({FakeRepo? repo}) {
    requests = [];
    final c = ProviderContainer(
      overrides: [
        tmdbSettingsStoreProvider.overrideWithValue(store),
        tmdbHttpClientProvider.overrideWithValue(
          MockClient((r) async {
            requests.add(r.url);
            return http.Response(
              jsonEncode({'results': <Object>[]}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
        repositoryProvider.overrideWithValue(repo ?? FakeRepo([])),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => store = MemoryTmdbSettingsStore());

  test('no key: everything is null/false and nothing is requested', () async {
    final c = make();
    await c.read(tmdbConfigProvider.future);
    expect(c.read(hasTmdbKey), isFalse);
    expect(c.read(hasTmdbKeyProvider), isFalse);
    expect(c.read(tmdbClientProvider), isNull);
    expect(c.read(tmdbSyncProvider), isNull);
    // Riverpod 3 pauses unlistened providers: listen, then read.
    final sub = c.listen(tmdbProgressProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value?.state, TmdbSyncState.idle);
    sub.close();
    expect(requests, isEmpty);
  });

  test('defaults while nothing is stored', () async {
    final c = make();
    final cfg = await c.read(tmdbConfigProvider.future);
    expect(cfg.settings.language, 'en-US');
    expect(cfg.settings.backgroundFetch, isTrue);
    expect(cfg.auth, isNull);
  });

  test('stored key is picked up at load', () async {
    store = MemoryTmdbSettingsStore(credential: _key);
    final c = make();
    await c.read(tmdbConfigProvider.future);
    expect(c.read(hasTmdbKey), isTrue);
    expect(c.read(tmdbClientProvider), isNotNull);
  });

  test('a stored but malformed key counts as no key', () async {
    store = MemoryTmdbSettingsStore(credential: 'garbage');
    final c = make();
    await c.read(tmdbConfigProvider.future);
    expect(c.read(hasTmdbKey), isFalse);
  });

  test(
    'setCredential validates the shape, stores, builds the client',
    () async {
      final c = make();
      await c.read(tmdbConfigProvider.future);
      final n = c.read(tmdbConfigProvider.notifier);
      expect(await n.setCredential('not a key'), isFalse);
      expect(await store.readCredential(), isNull);
      expect(c.read(hasTmdbKey), isFalse);

      expect(await n.setCredential('  $_key '), isTrue);
      expect(await store.readCredential(), _key);
      expect(c.read(hasTmdbKey), isTrue);
      expect(c.read(tmdbClientProvider), isNotNull);
      expect(c.read(tmdbSyncProvider), isNotNull);
    },
  );

  test('clearCredential removes the key and the client', () async {
    store = MemoryTmdbSettingsStore(credential: _key);
    final c = make();
    await c.read(tmdbConfigProvider.future);
    expect(c.read(tmdbClientProvider), isNotNull);
    await c.read(tmdbConfigProvider.notifier).clearCredential();
    expect(await store.readCredential(), isNull);
    expect(c.read(tmdbClientProvider), isNull);
    expect(c.read(hasTmdbKey), isFalse);
  });

  test('settings persist and keep the key', () async {
    store = MemoryTmdbSettingsStore(credential: _key);
    final c = make();
    await c.read(tmdbConfigProvider.future);
    final n = c.read(tmdbConfigProvider.notifier);
    await n.setBackgroundFetch(false);
    await n.setLanguage('hi-IN');
    await n.setLanguage('nonsense'); // ignored
    expect(store.value.backgroundFetch, isFalse);
    expect(store.value.language, 'hi-IN');
    final cfg = c.read(tmdbConfigProvider).value!;
    expect(cfg.auth, isNotNull);
    expect(cfg.settings.language, 'hi-IN');
  });

  test('toggling background fetch keeps the same client and service', () async {
    store = MemoryTmdbSettingsStore(credential: _key);
    final c = make(repo: FakeRepo([]));
    await c.read(tmdbConfigProvider.future);
    final client = c.read(tmdbClientProvider);
    final sync = c.read(tmdbSyncProvider);
    await c.read(tmdbConfigProvider.notifier).setBackgroundFetch(false);
    expect(c.read(tmdbClientProvider), same(client));
    expect(c.read(tmdbSyncProvider), same(sync));
  });

  test('changing the language rebuilds the client with it', () async {
    store = MemoryTmdbSettingsStore(credential: _key);
    final c = make();
    await c.read(tmdbConfigProvider.future);
    final a = c.read(tmdbClientProvider)!;
    expect(a.language, 'en-US');
    await c.read(tmdbConfigProvider.notifier).setLanguage('fr-FR');
    final b = c.read(tmdbClientProvider)!;
    expect(b, isNot(same(a)));
    expect(b.language, 'fr-FR');
  });

  test(
    'sync service runs through the provider (fake HTTP, no network)',
    () async {
      store = MemoryTmdbSettingsStore(credential: _key);
      final repo = FakeRepo([title(1, 'Some Film', year: 2001)]);
      final c = make(repo: repo);
      await c.read(tmdbConfigProvider.future);
      final s = c.read(tmdbSyncProvider)!;
      s.start();
      final p = await s.progress.firstWhere(
        (p) => p.state == TmdbSyncState.idle || p.state == TmdbSyncState.error,
      );
      expect(p.state, TmdbSyncState.idle);
      expect(p.unmatched, 1); // fake TMDB answered "no results"
      expect(repo.unmatched, [1]);
      expect(requests.every((u) => u.host == 'api.themoviedb.org'), isTrue);
    },
  );

  test('progress provider follows the service', () async {
    store = MemoryTmdbSettingsStore(credential: _key);
    final c = make(repo: FakeRepo([title(1, 'Some Film', year: 2001)]));
    await c.read(tmdbConfigProvider.future);
    final sub = c.listen(tmdbProgressProvider, (_, _) {});
    addTearDown(sub.close);
    c.read(tmdbSyncProvider)!.start();
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (sub.read().value?.state == TmdbSyncState.idle &&
          (sub.read().value?.processed ?? 0) == 1) {
        break;
      }
    }
    expect(sub.read().value?.processed, 1);
  });

  group('storage failures', () {
    test('saveCredential reports saved / invalid / storageFailed', () async {
      final bad = _FailingStore();
      store = bad;
      final c = make();
      await c.read(tmdbConfigProvider.future);
      final n = c.read(tmdbConfigProvider.notifier);
      expect(await n.saveCredential('nope'), TmdbSaveResult.invalid);

      bad.failWrite = true;
      expect(await n.saveCredential(_key), TmdbSaveResult.storageFailed);
      expect(c.read(hasTmdbKey), isFalse, reason: 'nothing half-saved');
      expect(await n.setCredential(_key), isFalse, reason: 'old API: false');

      bad.failWrite = false;
      expect(await n.saveCredential(_key), TmdbSaveResult.saved);
      expect(c.read(hasTmdbKey), isTrue);
      expect(await bad.readCredential(), _key);
      expect(await n.setCredential(_key), isTrue);
    });

    test('clearCredential survives a failing delete', () async {
      final bad = _FailingStore(credential: _key);
      store = bad;
      final c = make();
      await c.read(tmdbConfigProvider.future);
      final n = c.read(tmdbConfigProvider.notifier);
      bad.failDelete = true;
      expect(await n.clearCredential(), isFalse);
      expect(c.read(hasTmdbKey), isTrue, reason: 'key is still stored');
      bad.failDelete = false;
      expect(await n.clearCredential(), isTrue);
      expect(c.read(hasTmdbKey), isFalse);
    });

    test('a SecretStore whose write throws never escapes', () async {
      final fileStore = FileTmdbSettingsStore(
        File('${Directory.systemTemp.path}/unused-tmdb.json'),
        _ThrowingSecrets(),
      );
      store = _Wrapped(fileStore);
      final c = make();
      await c.read(tmdbConfigProvider.future);
      final n = c.read(tmdbConfigProvider.notifier);
      expect(await n.saveCredential(_key), TmdbSaveResult.storageFailed);
    });
  });
}

class _FailingStore extends MemoryTmdbSettingsStore {
  _FailingStore({super.credential});
  bool failWrite = false;
  bool failDelete = false;
  @override
  Future<void> writeCredential(String c) => failWrite
      ? Future.error(StateError('keystore down'))
      : super.writeCredential(c);
  @override
  Future<void> clearCredential() => failDelete
      ? Future.error(StateError('keystore down'))
      : super.clearCredential();
}

class _ThrowingSecrets implements SecretStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) => Future.error(StateError('keystore down'));
  @override
  Future<void> delete() => Future.error(StateError('keystore down'));
}

/// Delegates to a [FileTmdbSettingsStore] whose plain settings are never
/// touched (load falls back to defaults).
class _Wrapped extends MemoryTmdbSettingsStore {
  _Wrapped(this.inner);
  final FileTmdbSettingsStore inner;
  @override
  Future<String?> readCredential() => inner.readCredential();
  @override
  Future<void> writeCredential(String c) => inner.writeCredential(c);
  @override
  Future<void> clearCredential() => inner.clearCredential();
}
