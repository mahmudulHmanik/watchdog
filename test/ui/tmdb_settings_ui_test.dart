import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/search/search_providers.dart'
    show tmdbHasDataProvider;
import 'package:watchdog/features/settings/tmdb_ui_providers.dart';
import 'package:watchdog/tmdb/tmdb_client.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_settings.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart';

import 'fakes.dart';
import 'settings_helpers.dart';
import 'tmdb_helpers.dart';

class _Api implements TmdbApi {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _SpySync extends TmdbSyncService {
  _SpySync(Repository repo) : super(repo: repo, api: _Api());
  int started = 0;
  @override
  void start() => started++;
}

class _FailingStore extends MemoryTmdbSettingsStore {
  @override
  Future<void> writeCredential(String c) => throw StateError('keystore down');
}

late FakeRepository repo;
late FakePlatform platform;
late MemoryTmdbSettingsStore store;

Future<ProviderContainer> boot(
  WidgetTester t, {
  String? key,
  TmdbSettings settings = const TmdbSettings(),
  http.Client? client,
  ShapeMode shape = ShapeMode.box,
  List<Override> extra = const [],
  String? page = 'tmdb',
  MemoryTmdbSettingsStore? useStore,
}) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  repo = FakeRepository();
  platform = FakePlatform();
  store = useStore ?? MemoryTmdbSettingsStore(value: settings, credential: key);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(repo, platform),
        initialThemeProvider.overrideWithValue(
          ThemeSettings(shape: shape, followSystem: false),
        ),
        tmdbSettingsStoreProvider.overrideWithValue(store),
        if (client != null) tmdbHttpClientProvider.overrideWithValue(client),
        ...extra,
      ],
      child: const WatchdogApp(),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Settings'),
    ),
  );
  await t.pumpAndSettle();
  if (page != null) await openGroup(t, page);
  return ProviderScope.containerOf(t.element(find.byType(WatchdogApp)));
}

Future<void> show(WidgetTester t, String key) async {
  await t.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
}

void main() {
  for (final shape in ShapeMode.values) {
    testWidgets('section renders with a key, no overflow (${shape.name})', (
      t,
    ) async {
      await boot(t, key: fakeKey, shape: shape);
      expect(find.text('Key saved'), findsOneWidget);
      await show(t, 'tmdb-sync-toggle');
      await show(t, 'tmdb-clear-data');
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('no key: only key setup, no key-dependent controls', (t) async {
    await boot(t);
    await show(t, 'tmdb-save');
    expect(find.text('No key saved'), findsOneWidget);
    expect(
      t.widget<OutlinedButton>(find.byKey(const Key('tmdb-test'))).onPressed,
      isNull,
    );
    expect(find.byKey(const Key('tmdb-bg')), findsNothing);
    expect(find.byKey(const Key('tmdb-language')), findsNothing);
    expect(find.byKey(const Key('tmdb-clear-key')), findsNothing);
  });

  testWidgets('key field is obscured', (t) async {
    await boot(t);
    await show(t, 'tmdb-key-field');
    final f = t.widget<TextField>(find.byKey(const Key('tmdb-key-field')));
    expect(f.obscureText, isTrue);
  });

  testWidgets('invalid key is rejected and not stored', (t) async {
    await boot(t);
    await show(t, 'tmdb-save');
    await t.enterText(find.byKey(const Key('tmdb-key-field')), 'not-a-key');
    await t.tap(find.byKey(const Key('tmdb-save')));
    await t.pumpAndSettle();
    expect(find.textContaining('Not a TMDB key'), findsOneWidget);
    expect(await store.readCredential(), isNull);
    expect(find.text('No key saved'), findsOneWidget);
  });

  testWidgets('valid key is stored, field cleared, controls appear', (t) async {
    await boot(t);
    await show(t, 'tmdb-save');
    await t.enterText(find.byKey(const Key('tmdb-key-field')), ' $fakeKey ');
    await t.tap(find.byKey(const Key('tmdb-save')));
    await t.pumpAndSettle();
    expect(await store.readCredential(), fakeKey);
    expect(find.text('Key saved'), findsOneWidget);
    // The saved key is never shown again.
    expect(find.textContaining(fakeKey), findsNothing);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('tmdb-key-field')))
          .controller!
          .text,
      isEmpty,
    );
    await show(t, 'tmdb-bg');
    expect(find.byKey(const Key('tmdb-language')), findsOneWidget);
  });

  testWidgets('a failed key write says so and stores nothing', (t) async {
    await boot(t, useStore: _FailingStore());
    await show(t, 'tmdb-save');
    await t.enterText(find.byKey(const Key('tmdb-key-field')), fakeKey);
    await t.tap(find.byKey(const Key('tmdb-save')));
    await t.pumpAndSettle();
    expect(find.text('Could not store the key on this device'), findsOneWidget);
    expect(find.text('No key saved'), findsOneWidget);
    expect(find.textContaining('Not a TMDB key'), findsNothing);
  });

  testWidgets('language row says it only applies to future fetches', (t) async {
    await boot(t, key: fakeKey);
    await show(t, 'tmdb-language');
    expect(
      find.text(
        'Applies to titles fetched from now on. Clear TMDB data to refetch '
        'in the new language.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Test key: success', (t) async {
    final seen = <Uri>[];
    await boot(t, key: fakeKey, client: matrixClient(seen));
    await show(t, 'tmdb-test');
    await t.tap(find.byKey(const Key('tmdb-test')));
    await t.pumpAndSettle();
    expect(find.text('Key works.'), findsOneWidget);
    expect(seen.single.path, '/3/configuration');
    expect(find.textContaining(fakeKey), findsNothing);
  });

  testWidgets('Test key: 401 shows a clear error', (t) async {
    await boot(
      t,
      key: fakeKey,
      client: MockClient((_) async => jsonResp({}, 401)),
    );
    await show(t, 'tmdb-test');
    await t.tap(find.byKey(const Key('tmdb-test')));
    await t.pumpAndSettle();
    expect(find.textContaining('TMDB rejected the key'), findsOneWidget);
    expect(find.textContaining(fakeKey), findsNothing);
  });

  testWidgets('Test key: offline shows a network message', (t) async {
    await boot(
      t,
      key: fakeKey,
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    await show(t, 'tmdb-test');
    await t.tap(find.byKey(const Key('tmdb-test')));
    await t.pumpAndSettle();
    expect(find.textContaining('Cannot reach TMDB'), findsOneWidget);
  });

  testWidgets('background switch is stored', (t) async {
    await boot(t, key: fakeKey);
    await show(t, 'tmdb-bg');
    expect(store.value.backgroundFetch, isTrue);
    await t.tap(find.byKey(const Key('tmdb-bg')));
    await t.pumpAndSettle();
    expect(store.value.backgroundFetch, isFalse);
  });

  testWidgets('language picker stores the tag', (t) async {
    await boot(t, key: fakeKey);
    await show(t, 'tmdb-language');
    expect(find.text('English (US)'), findsOneWidget);
    await t.tap(find.byKey(const Key('tmdb-language')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tmdb-lang-hi-IN')));
    await t.pumpAndSettle();
    expect(store.value.language, 'hi-IN');
    expect(find.text('Hindi'), findsOneWidget);
  });

  testWidgets('clear key removes it and hides key controls', (t) async {
    await boot(t, key: fakeKey);
    await show(t, 'tmdb-clear-key');
    await t.tap(find.byKey(const Key('tmdb-clear-key')));
    await t.pumpAndSettle();
    expect(await store.readCredential(), isNull);
    expect(find.text('No key saved'), findsOneWidget);
    expect(find.byKey(const Key('tmdb-bg')), findsNothing);
  });

  testWidgets('sync counts and live status', (t) async {
    final c = await boot(t, key: fakeKey);
    repo.tmdbProgressValue = const TmdbProgress(
      eligible: 10,
      matched: 6,
      unmatched: 2,
    );
    // Counts are read on demand; refresh as the live sync would.
    c.invalidate(tmdbLibraryProgressProvider);
    await t.pumpAndSettle();
    await show(t, 'tmdb-counts');
    expect(find.text('Matched 6 · Unmatched 2 · Pending 2'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('unauthorized error tells the user to check the key', (t) async {
    await boot(
      t,
      key: fakeKey,
      extra: [
        tmdbProgressProvider.overrideWith(
          (ref) => Stream.value(
            const TmdbSyncProgress(
              state: TmdbSyncState.error,
              error: TmdbErrorKind.unauthorized,
              message: 'TMDB rejected the key. Check it in Settings.',
            ),
          ),
        ),
      ],
    );
    await show(t, 'tmdb-sync-error');
    expect(find.textContaining('Check your key'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('running shows Pause and the current title', (t) async {
    await boot(
      t,
      key: fakeKey,
      extra: [
        tmdbProgressProvider.overrideWith(
          (ref) => Stream.value(
            const TmdbSyncProgress(
              state: TmdbSyncState.running,
              current: 'The Matrix',
            ),
          ),
        ),
      ],
    );
    await show(t, 'tmdb-sync-toggle');
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Looking up: The Matrix'), findsOneWidget);
  });

  testWidgets('Start runs without error', (t) async {
    final c = await boot(t, key: fakeKey);
    final sync = c.read(tmdbSyncProvider)!;
    await show(t, 'tmdb-sync-toggle');
    expect(find.text('Start'), findsOneWidget);
    // Nothing queued in the fake repo: start finishes at once; no crash.
    await t.tap(find.byKey(const Key('tmdb-sync-toggle')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(sync.current.state, isNot(TmdbSyncState.paused));
  });

  testWidgets('clear TMDB data asks first, then clears', (t) async {
    await boot(t, key: fakeKey);
    await show(t, 'tmdb-clear-data');
    await t.tap(find.byKey(const Key('tmdb-clear-data')));
    await t.pumpAndSettle();
    expect(find.text('Clear TMDB data?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(repo.tmdbCleared, isFalse);
    await t.tap(find.byKey(const Key('tmdb-clear-data')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tmdb-clear-confirm')));
    await t.pumpAndSettle();
    expect(repo.tmdbCleared, isTrue);
  });

  testWidgets('copy link button copies the TMDB API settings URL', (t) async {
    await boot(t);
    await show(t, 'tmdb-copy-url');
    await t.tap(find.byKey(const Key('tmdb-copy-url')));
    await t.pumpAndSettle();
    expect(platform.copied, ['https://www.themoviedb.org/settings/api']);
  });

  testWidgets('About carries the exact TMDB attribution', (t) async {
    await boot(t, page: 'about');
    await show(t, 'tmdb-attribution');
    expect(
      find.text(
        'This product uses the TMDB API but is not endorsed or certified '
        'by TMDB.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('About shows the approved TMDB logo above the notice', (t) async {
    final semantics = t.ensureSemantics();
    await boot(t, page: 'about');
    await show(t, 'tmdb-attribution');
    final logo = find.byKey(const Key('tmdb-logo'));
    expect(logo, findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('The Movie Database \\(TMDB\\)')),
      findsOneWidget,
    );
    // Small, and above the attribution sentence.
    expect(t.getSize(logo).height, lessThanOrEqualTo(16));
    expect(
      t.getTopLeft(logo).dy,
      lessThan(t.getTopLeft(find.byKey(const Key('tmdb-attribution'))).dy),
    );
    expect(t.takeException(), isNull);
    semantics.dispose();
  });

  test('the bundled TMDB logo is a clean SVG with its gradient fill', () {
    final svg = File(tmdbLogoAsset).readAsStringSync();
    expect(svg, contains('viewBox="0 0 273.42 35.52"'));
    expect(svg, contains('fill="url(#linear-gradient)"'));
    // flutter_svg ignores <style>/class fills, so none may remain.
    expect(svg, isNot(contains('<style')));
    expect(svg, isNot(contains('class="cls-')));
    // Nothing active or external in a bundled asset.
    expect(
      RegExp(
        '<script|onload|javascript:|href="http',
        caseSensitive: false,
      ).hasMatch(svg),
      isFalse,
    );
  });

  group('tmdb freshness (throttled tmdbChanges)', () {
    testWidgets('background off: a manual sync still makes the TMDB '
        'filters appear', (t) async {
      final c = await boot(
        t,
        key: fakeKey,
        settings: const TmdbSettings(backgroundFetch: false),
        page: null,
      );
      final seen = <bool?>[];
      final sub = c.listen(
        tmdbHasDataProvider,
        (_, n) => seen.add(n.value),
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await t.pump();
      expect(c.read(tmdbHasDataProvider).value, isFalse);
      repo.tmdbProgressValue = const TmdbProgress(
        eligible: 5,
        matched: 1,
        unmatched: 0,
      );
      repo.fireTmdbChange();
      await t.pump();
      await t.pump();
      expect(c.read(tmdbHasDataProvider).value, isTrue);
    });

    testWidgets('TMDB writes never bump the crawl revision', (t) async {
      final c = await boot(t, key: fakeKey, page: null);
      final rev = c.read(revisionProvider);
      for (var i = 0; i < 5; i++) {
        repo.fireTmdbChange();
      }
      await t.pump();
      expect(c.read(revisionProvider), rev);
      expect(c.read(tmdbRevisionProvider), greaterThan(0));
    });

    testWidgets('library counts refresh at most once per interval, and when '
        'the TMDB page opens', (t) async {
      final c = await boot(
        t,
        key: fakeKey,
        settings: const TmdbSettings(backgroundFetch: false),
        page: null,
      );
      final sub = c.listen(tmdbLibraryProgressProvider, (_, _) {});
      addTearDown(sub.close);
      await t.pump();
      final base = c.read(tmdbRevisionProvider);
      for (var i = 0; i < 20; i++) {
        repo.fireTmdbChange();
        await t.pump(const Duration(milliseconds: 100));
      }
      // 2 s of writes: leading bump only, rest is pending.
      expect(c.read(tmdbRevisionProvider), base + 1);
      await t.pump(const Duration(seconds: 10));
      expect(c.read(tmdbRevisionProvider), base + 2, reason: 'trailing');
      await t.pump(const Duration(seconds: 11));
      expect(c.read(tmdbRevisionProvider), base + 2, reason: 'nothing new');
      // Opening the page reads fresh counts.
      repo.tmdbProgressValue = const TmdbProgress(eligible: 9, matched: 4);
      await openGroup(t, 'tmdb');
      await t.pumpAndSettle();
      expect(c.read(tmdbLibraryProgressProvider).value?.matched, 4);
    });

    testWidgets('sync going idle flushes the pending refresh at once', (
      t,
    ) async {
      final prog = StreamController<TmdbSyncProgress>.broadcast();
      addTearDown(prog.close);
      final c = await boot(
        t,
        key: fakeKey,
        page: null,
        extra: [tmdbProgressProvider.overrideWith((ref) => prog.stream)],
      );
      prog.add(const TmdbSyncProgress(state: TmdbSyncState.running));
      await t.pump();
      final base = c.read(tmdbRevisionProvider);
      repo.fireTmdbChange(); // leading
      repo.fireTmdbChange(); // pending
      await t.pump(const Duration(seconds: 1));
      expect(c.read(tmdbRevisionProvider), base + 1);
      prog.add(const TmdbSyncProgress(state: TmdbSyncState.idle));
      await t.pump();
      expect(c.read(tmdbRevisionProvider), base + 2);
    });
  });

  group('background start', () {
    testWidgets('key + switch on: starts after a short delay', (t) async {
      late _SpySync spy;
      await boot(
        t,
        key: fakeKey,
        extra: [tmdbSyncProvider.overrideWith((ref) => spy = _SpySync(repo))],
      );
      expect(spy.started, 0, reason: 'never at the first frame');
      await t.pump(const Duration(seconds: 4));
      expect(spy.started, 1);
    });

    testWidgets('switch off: does not start', (t) async {
      _SpySync? spy;
      await boot(
        t,
        key: fakeKey,
        settings: const TmdbSettings(backgroundFetch: false),
        extra: [tmdbSyncProvider.overrideWith((ref) => spy = _SpySync(repo))],
      );
      await t.pump(const Duration(seconds: 4));
      expect(spy?.started ?? 0, 0);
    });

    testWidgets('no key: nothing starts and no request is made', (t) async {
      final seen = <Uri>[];
      await boot(t, client: matrixClient(seen));
      await t.pump(const Duration(seconds: 4));
      expect(seen, isEmpty);
    });
  });
}
