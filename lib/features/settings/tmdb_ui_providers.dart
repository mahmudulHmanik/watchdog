import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/data/models.dart' show TmdbProgress;
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart'
    show tmdbRevisionProvider;
import 'package:watchdog/tmdb/tmdb_client.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart' show TmdbSyncState;

/// Languages offered for TMDB text. TMDB takes `ll-CC` tags (format and
/// `en-US` / `pt-BR` confirmed on developer.themoviedb.org/docs/languages);
/// texts it has no translation for fall back to the default language.
const tmdbLanguageChoices = <(String, String)>[
  ('en-US', 'English (US)'),
  ('en-GB', 'English (UK)'),
  ('hi-IN', 'Hindi'),
  ('bn-BD', 'Bengali'),
  ('ta-IN', 'Tamil'),
  ('te-IN', 'Telugu'),
  ('ko-KR', 'Korean'),
  ('ja-JP', 'Japanese'),
  ('es-ES', 'Spanish'),
  ('fr-FR', 'French'),
  ('de-DE', 'German'),
  ('ar-SA', 'Arabic'),
  ('pt-BR', 'Portuguese (Brazil)'),
];

String tmdbLanguageLabel(String tag) =>
    tmdbLanguageChoices.where((c) => c.$1 == tag).firstOrNull?.$2 ?? tag;

/// TMDB's required notice (About screen, README, NOTICE).
/// Approved TMDB logo (short, gradient). See assets/tmdb/.
const tmdbLogoAsset = 'assets/tmdb/tmdb_logo_short.svg';

const tmdbAttribution =
    'This product uses the TMDB API but is not endorsed or certified by TMDB.';

/// Link shown and copied in the key help text.
const tmdbApiSettingsUrl = 'https://www.themoviedb.org/settings/api';

/// Text safe to show: never contains a key (defensive scrub of any URL).
String tmdbErrorText(Object e) {
  final raw = e is TmdbException
      ? switch (e.kind) {
          TmdbErrorKind.unauthorized =>
            'TMDB rejected the key. Check it in Settings.',
          TmdbErrorKind.network => 'Cannot reach TMDB. Check your internet.',
          _ => e.message,
        }
      : 'Something went wrong.';
  return raw.replaceAll(RegExp(r'api_key=[^&\s]+'), 'api_key=***');
}

/// Library-wide TMDB counts. Reloads on the throttled [tmdbRevisionProvider]
/// (at most every ~10 s while a sync writes); the TMDB page also refreshes it
/// when opened.
final tmdbLibraryProgressProvider = FutureProvider.autoDispose<TmdbProgress>((
  ref,
) {
  ref.watch(tmdbRevisionProvider);
  return ref.watch(repositoryProvider).tmdbProgress();
});

/// App-shell hook (watched by the app). Always on: keeps the throttled TMDB
/// revision alive, listens to sync progress without letting events buffer
/// while the Settings tab is hidden, and delivers the final refresh when a
/// sync goes idle. Then, with a key and "background fetch" on, starts the
/// fill after a short delay (never blocks startup).
final tmdbAutoStartProvider = Provider<void>((ref) {
  // listen, not watch: a bump must not rebuild this and re-arm the start timer.
  ref.listen(tmdbRevisionProvider, (_, _) {});
  ref.listen(tmdbProgressProvider.select((v) => v.value?.state), (prev, next) {
    if (prev == TmdbSyncState.running && next != TmdbSyncState.running) {
      ref.read(tmdbRevisionProvider.notifier).flush();
    }
  });
  final on = ref.watch(
    tmdbConfigProvider.select((v) {
      final c = v.value;
      return c != null && c.auth != null && c.settings.backgroundFetch;
    }),
  );
  if (!on) return;
  final sync = ref.watch(tmdbSyncProvider);
  if (sync == null) return;
  final timer = Timer(const Duration(seconds: 3), sync.start);
  ref.onDispose(timer.cancel);
});
