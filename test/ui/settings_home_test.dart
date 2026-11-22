import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/core/app_info.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/settings/settings_target.dart';
import 'package:watchdog/features/settings/tmdb_ui_providers.dart';
import 'package:watchdog/tmdb/tmdb_client.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_settings.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart';

import 'fakes.dart';
import 'settings_helpers.dart';
import 'tmdb_helpers.dart';

const _groups = {
  'appearance': 'Appearance',
  'playback': 'Playback',
  'library': 'Library',
  'tmdb': 'TMDB',
  'updates': 'Updates',
  'about': 'About',
};

late FakeRepository repo;

Future<ProviderContainer> boot(
  WidgetTester t, {
  Size size = const Size(360, 740),
  ShapeMode shape = ShapeMode.box,
  String? key,
  List<Override> extra = const [],
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  repo = FakeRepository(titles: [mkTitle(1, 'A'), mkTitle(2, 'B')]);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(repo, FakePlatform()),
        initialThemeProvider.overrideWithValue(
          ThemeSettings(shape: shape, followSystem: false, palette: everforest),
        ),
        tmdbSettingsStoreProvider.overrideWithValue(
          MemoryTmdbSettingsStore(credential: key),
        ),
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
  return ProviderScope.containerOf(t.element(find.byType(WatchdogApp)));
}

Finder summary(String group, String text) => find.descendant(
  of: find.byKey(Key('settings-$group')),
  matching: find.text(text),
);

void main() {
  testWidgets('home lists all six groups with live summaries', (t) async {
    await boot(t);
    for (final g in _groups.keys) {
      expect(find.byKey(Key('settings-$g')), findsOneWidget, reason: g);
    }
    expect(summary('appearance', 'Everforest · Box'), findsOneWidget);
    expect(summary('playback', 'Ask every time · any audio'), findsOneWidget);
    expect(summary('library', '2 titles · 3.1 GB'), findsOneWidget);
    expect(summary('tmdb', 'No key'), findsOneWidget);
    expect(
      summary('updates', 'v$appVersion · check on launch on'),
      findsOneWidget,
    );
    expect(summary('about', 'mhm · Apache-2.0'), findsOneWidget);
    // Long content lives on the pages, not on the home.
    expect(find.byKey(const Key('tmdb-key-field')), findsNothing);
    expect(find.text('Clear index'), findsNothing);
  });

  testWidgets('summaries follow the settings', (t) async {
    final c = await boot(t);
    await openGroup(t, 'appearance');
    await t.scrollUntilVisible(
      find.byKey(const Key('shape-rounded')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('shape-rounded')));
    await t.pumpAndSettle();
    await goBack(t);
    expect(summary('appearance', 'Everforest · Rounded'), findsOneWidget);
    await openGroup(t, 'playback');
    await t.tap(find.byKey(const Key('external-player')));
    await t.pumpAndSettle();
    await goBack(t);
    expect(summary('playback', 'Last used player · any audio'), findsOneWidget);
    expect(c.read(tmdbConfigProvider).value?.auth, isNull);
  });

  testWidgets('tmdb tile: matched count, syncing, bad key', (t) async {
    final c = await boot(
      t,
      key: fakeKey,
      extra: [
        tmdbProgressProvider.overrideWith(
          (ref) => Stream.value(const TmdbSyncProgress()),
        ),
      ],
    );
    expect(summary('tmdb', 'Key saved'), findsOneWidget);
    repo.tmdbProgressValue = const TmdbProgress(
      eligible: 10,
      matched: 6,
      unmatched: 2,
    );
    c.invalidate(tmdbLibraryProgressProvider);
    await t.pumpAndSettle();
    expect(summary('tmdb', '6 of 10 matched'), findsOneWidget);
  });

  testWidgets('tmdb tile: Syncing...', (t) async {
    await boot(
      t,
      key: fakeKey,
      extra: [
        tmdbProgressProvider.overrideWith(
          (ref) => Stream.value(
            const TmdbSyncProgress(state: TmdbSyncState.running),
          ),
        ),
      ],
    );
    expect(summary('tmdb', 'Syncing…'), findsOneWidget);
  });

  testWidgets('tmdb tile: Check your key on a rejected key', (t) async {
    await boot(
      t,
      key: fakeKey,
      extra: [
        tmdbProgressProvider.overrideWith(
          (ref) => Stream.value(
            const TmdbSyncProgress(
              state: TmdbSyncState.error,
              error: TmdbErrorKind.unauthorized,
              message: 'x',
            ),
          ),
        ),
      ],
    );
    expect(summary('tmdb', 'Check your key'), findsOneWidget);
  });

  for (final shape in ShapeMode.values) {
    for (final (name, size) in [
      ('phone 360', const Size(360, 740)),
      ('wide', const Size(1400, 900)),
    ]) {
      testWidgets('every page opens, goes back, no overflow '
          '(${shape.name}, $name)', (t) async {
        await boot(t, size: size, shape: shape, key: fakeKey);
        expect(t.takeException(), isNull);
        for (final MapEntry(key: g, value: title) in _groups.entries) {
          await openGroup(t, g);
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(title),
            ),
            findsOneWidget,
            reason: g,
          );
          // Walk the whole (lazy) page so every block gets laid out.
          await t.drag(find.byType(Scrollable).first, const Offset(0, -3000));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'page $g');
          await goBack(t);
          expect(find.byKey(const Key('settings-appearance')), findsOneWidget);
        }
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('wide window: content column is capped', (t) async {
    await boot(t, size: const Size(1400, 900));
    final w = t.getSize(find.byKey(const Key('settings-library'))).width;
    expect(w, lessThanOrEqualTo(680));
  });

  testWidgets('library page: destructive Clear index confirms first', (
    t,
  ) async {
    await boot(t);
    await openGroup(t, 'library');
    await t.scrollUntilVisible(
      find.text('Re-index (incremental)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Re-index (incremental)'), findsOneWidget);
    expect(find.text('Full re-index'), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('clear-index')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('clear-index')));
    await t.pumpAndSettle();
    expect(find.text('Clear index?'), findsOneWidget);
    expect(find.textContaining('TMDB details'), findsOneWidget);
    expect(find.textContaining('manual match fixes'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(repo.indexCleared, isFalse);
    await t.tap(find.byKey(const Key('clear-index')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Clear'));
    await t.pumpAndSettle();
    expect(repo.indexCleared, isTrue);
  });

  testWidgets('playback page has no duplicate re-index row', (t) async {
    await boot(t);
    await openGroup(t, 'playback');
    expect(find.text('Re-index'), findsNothing);
    expect(find.byKey(const Key('external-player')), findsOneWidget);
    expect(find.byKey(const Key('preferred-audio')), findsOneWidget);
  });

  testWidgets('deep link: TMDB page opens straight from the title hint', (
    t,
  ) async {
    final c = await boot(t);
    await t.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Home'),
      ),
    );
    await t.pumpAndSettle();
    // What the title screen's hint does: set the target, switch tab.
    c.read(settingsTargetProvider.notifier).open(SettingsPage.tmdb);
    c.read(navIndexProvider.notifier).go(tabSettings);
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('TMDB')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tmdb-key-field')), findsOneWidget);
    expect(c.read(settingsTargetProvider), isNull, reason: 'consumed once');
    await goBack(t);
    expect(find.byKey(const Key('settings-tmdb')), findsOneWidget);
    // Plain Settings visits do not reopen it.
    expect(find.byKey(const Key('tmdb-key-field')), findsNothing);
  });

  testWidgets('deep link end to end: title hint -> TMDB page', (t) async {
    final c = await boot(t);
    await t.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Home'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('A').first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tmdb-hint')));
    await t.pumpAndSettle();
    expect(c.read(navIndexProvider), tabSettings);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('TMDB')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tmdb-key-field')), findsOneWidget);
    await goBack(t);
    expect(find.byKey(const Key('settings-tmdb')), findsOneWidget);
    // The title screen is gone: back lands on the Settings home.
    expect(find.byKey(const Key('tmdb-hint')), findsNothing);
  });
}
