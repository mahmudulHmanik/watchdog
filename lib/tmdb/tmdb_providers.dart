/// Riverpod wiring for TMDB. Nothing here starts on its own: with no key the
/// client and sync providers are null and the app behaves as before. The UI
/// lane calls `ref.read(tmdbSyncProvider)?.start()` when it wants the fill.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/repository.dart';
import 'tmdb_client.dart';
import 'tmdb_settings.dart';
import 'tmdb_sync.dart';

/// Where TMDB settings live; main overrides it with
/// `FileTmdbSettingsStore.platform(supportDir)`.
final tmdbSettingsStoreProvider = Provider<TmdbSettingsStore>(
  (ref) => MemoryTmdbSettingsStore(),
);

/// Credential (parsed) and preferences. [auth] is null when no valid key is
/// stored. Never print this object's [auth].
class TmdbConfig {
  const TmdbConfig({this.settings = const TmdbSettings(), this.auth});
  final TmdbSettings settings;
  final TmdbAuth? auth;
}

/// Outcome of [TmdbConfigNotifier.saveCredential].
enum TmdbSaveResult { saved, invalid, storageFailed }

class TmdbConfigNotifier extends AsyncNotifier<TmdbConfig> {
  @override
  Future<TmdbConfig> build() async {
    final store = ref.watch(tmdbSettingsStoreProvider);
    final settings = await store.load();
    final raw = await store.readCredential();
    return TmdbConfig(
      settings: settings,
      auth: raw == null ? null : TmdbAuth.parse(raw),
    );
  }

  TmdbConfig get _cur => state.value ?? const TmdbConfig();

  /// Stores [input] when it looks like a TMDB v3 key or v4 token. The result
  /// tells the UI what happened; nothing is stored unless it is `saved`. The
  /// network check is `client.validate()`.
  Future<TmdbSaveResult> saveCredential(String input) async {
    final auth = TmdbAuth.parse(input);
    if (auth == null) return TmdbSaveResult.invalid;
    try {
      await ref.read(tmdbSettingsStoreProvider).writeCredential(auth.value);
    } catch (_) {
      // Keystore/file failure; the error text is dropped on purpose.
      return TmdbSaveResult.storageFailed;
    }
    state = AsyncData(TmdbConfig(settings: _cur.settings, auth: auth));
    return TmdbSaveResult.saved;
  }

  /// Compatibility wrapper: true = saved, false = invalid or storage failed.
  Future<bool> setCredential(String input) async =>
      await saveCredential(input) == TmdbSaveResult.saved;

  /// Removes the stored key. False (key still stored, state unchanged) when
  /// the storage refused.
  Future<bool> clearCredential() async {
    try {
      await ref.read(tmdbSettingsStoreProvider).clearCredential();
    } catch (_) {
      return false;
    }
    state = AsyncData(TmdbConfig(settings: _cur.settings));
    return true;
  }

  Future<void> setBackgroundFetch(bool v) =>
      _save(_cur.settings.copyWith(backgroundFetch: v));

  /// Ignored when [tag] is not like `en-US`.
  Future<void> setLanguage(String tag) => TmdbSettings.isValidLanguage(tag)
      ? _save(_cur.settings.copyWith(language: tag))
      : Future.value();

  Future<void> _save(TmdbSettings s) async {
    state = AsyncData(TmdbConfig(settings: s, auth: _cur.auth));
    await ref.read(tmdbSettingsStoreProvider).save(s);
  }
}

final tmdbConfigProvider =
    AsyncNotifierProvider<TmdbConfigNotifier, TmdbConfig>(
      TmdbConfigNotifier.new,
    );

/// True when a credential is stored (false while still loading).
final hasTmdbKeyProvider = Provider<bool>(
  (ref) => ref.watch(tmdbConfigProvider).value?.auth != null,
);

/// Alias matching the short name used in the plan.
final hasTmdbKey = hasTmdbKeyProvider;

/// HTTP client for TMDB; tests override with a MockClient.
final tmdbHttpClientProvider = Provider<http.Client?>((ref) => null);

/// Null when there is no key. Rebuilt (old one closed) when the key or the
/// language changes.
final tmdbClientProvider = Provider<TmdbClient?>((ref) {
  final auth = ref.watch(tmdbConfigProvider.select((v) => v.value?.auth));
  final language = ref.watch(
    tmdbConfigProvider.select((v) => v.value?.settings.language ?? 'en-US'),
  );
  if (auth == null) return null;
  final c = TmdbClient(
    auth: auth,
    language: language,
    client: ref.watch(tmdbHttpClientProvider),
  );
  ref.onDispose(c.close);
  return c;
});

/// Null when there is no key. Not started automatically.
final tmdbSyncProvider = Provider<TmdbSyncService?>((ref) {
  final client = ref.watch(tmdbClientProvider);
  if (client == null) return null;
  final s = TmdbSyncService(repo: ref.watch(repositoryProvider), api: client);
  ref.onDispose(s.dispose);
  return s;
});

/// Sync progress; idle default when there is no key.
final tmdbProgressProvider = StreamProvider<TmdbSyncProgress>((ref) {
  final s = ref.watch(tmdbSyncProvider);
  return s == null ? Stream.value(const TmdbSyncProgress()) : s.progress;
});
