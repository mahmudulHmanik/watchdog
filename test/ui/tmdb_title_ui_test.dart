import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/search/search_providers.dart';
import 'package:watchdog/features/title/ui/title_screen.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_settings.dart';

import 'fakes.dart';
import 'tmdb_helpers.dart';

final movie = mkTitle(1, 'The Matrix', year: 1999);
final show = mkTitle(5, 'Some Show', kind: TitleKind.series);

late FakeRepository repo;

Future<ProviderContainer> open(
  WidgetTester t, {
  String? key = fakeKey,
  http.Client? client,
  MediaTitle? title,
  ShapeMode shape = ShapeMode.box,
  void Function(FakeRepository)? setup,
  bool settle = true,
}) async {
  t.view.physicalSize = const Size(400, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final ttl = title ?? movie;
  repo = FakeRepository(
    titles: [ttl],
    files: [mkFile(11, ttl.id, 'm.mkv')],
    seasonList: ttl.kind == TitleKind.series
        ? [
            SeasonEpisodes(
              season: Season(id: 1, titleId: ttl.id, number: 1, label: 'S1'),
              files: [mkFile(51, ttl.id, 'e1.mkv', seasonId: 1)],
            ),
          ]
        : const [],
  );
  setup?.call(repo);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(repo, FakePlatform()),
        tmdbSettingsStoreProvider.overrideWithValue(
          MemoryTmdbSettingsStore(credential: key),
        ),
        if (client != null) tmdbHttpClientProvider.overrideWithValue(client),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: buildTheme(everforest, shape),
          home: TitleScreen(titleId: ttl.id),
        ),
      ),
    ),
  );
  if (settle) {
    await t.pumpAndSettle();
  } else {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }
  return ProviderScope.containerOf(t.element(find.byType(TitleScreen)));
}

void main() {
  for (final shape in ShapeMode.values) {
    testWidgets('cached TMDB data is shown with no request (${shape.name})', (
      t,
    ) async {
      final seen = <Uri>[];
      await open(
        t,
        client: matrixClient(seen),
        shape: shape,
        setup: (r) => r.tmdbData[1] = sampleInfo(1),
      );
      expect(find.byKey(const Key('tmdb-backdrop')), findsOneWidget);
      expect(find.text('7.8/10'), findsOneWidget);
      expect(find.text('1h 52m'), findsOneWidget);
      expect(find.text('Original: Hindi'), findsOneWidget);
      expect(find.text('Welcome to the real world.'), findsOneWidget);
      expect(find.textContaining('A computer hacker'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Keanu Reeves'), findsOneWidget);
      expect(find.text('Neo'), findsOneWidget);
      expect(find.text('Fix match'), findsOneWidget);
      expect(find.byKey(const Key('tmdb-hint')), findsNothing);
      expect(seen, isEmpty, reason: 'fresh data: no network');
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('rating hidden when null', (t) async {
    await open(t, setup: (r) => r.tmdbData[1] = sampleInfo(1, rating: null));
    expect(find.byKey(const Key('tmdb-rating')), findsNothing);
    expect(find.text('Fix match'), findsOneWidget);
  });

  testWidgets('series show TMDB details too', (t) async {
    await open(t, title: show, setup: (r) => r.tmdbData[5] = sampleInfo(5));
    expect(find.text('7.8/10'), findsOneWidget);
    expect(find.text('Keanu Reeves'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsOneWidget);
  });

  testWidgets('genre chip opens search filtered by that genre', (t) async {
    final c = await open(t, setup: (r) => r.tmdbData[1] = sampleInfo(1));
    await t.tap(find.byKey(const Key('genre-28')));
    await t.pumpAndSettle();
    expect(c.read(searchFilterProvider).genreIds, {28});
    expect(c.read(navIndexProvider), tabSearch);
  });

  testWidgets('cast tile opens search filtered by that person', (t) async {
    final c = await open(t, setup: (r) => r.tmdbData[1] = sampleInfo(1));
    await t.tap(find.byKey(const Key('cast-6384')));
    await t.pumpAndSettle();
    expect(c.read(searchFilterProvider).personId, 6384);
    expect(c.read(navIndexProvider), tabSearch);
  });

  testWidgets('cast without photo shows initials', (t) async {
    await open(t, setup: (r) => r.tmdbData[1] = sampleInfo(1));
    expect(find.text('LF'), findsOneWidget);
  });

  testWidgets('no key: one hint line, nothing else, no request', (t) async {
    final seen = <Uri>[];
    final c = await open(t, key: null, client: matrixClient(seen));
    expect(find.text('Add a TMDB key in Settings for details'), findsOneWidget);
    expect(find.text('Fix match'), findsNothing);
    expect(find.text('Find on TMDB'), findsNothing);
    expect(find.byKey(const Key('tmdb-loading')), findsNothing);
    expect(seen, isEmpty);
    await t.tap(find.byKey(const Key('tmdb-hint')));
    await t.pumpAndSettle();
    expect(c.read(navIndexProvider), tabSettings);
  });

  testWidgets('unmatched: says so and offers Find on TMDB', (t) async {
    await open(
      t,
      setup: (r) => r.tmdbData[1] = sampleInfo(1, status: TmdbStatus.unmatched),
    );
    expect(find.text('No match on TMDB'), findsOneWidget);
    expect(find.text('Find on TMDB'), findsOneWidget);
    expect(find.text('Fix match'), findsNothing);
    expect(find.byKey(const Key('tmdb-backdrop')), findsNothing);
  });

  testWidgets('loading row, then details after the on-open fetch', (t) async {
    final gate = Completer<void>();
    final seen = <Uri>[];
    final inner = matrixClient(seen);
    await open(
      t,
      client: MockClient((r) async {
        await gate.future;
        return inner.get(r.url);
      }),
      settle: false,
    );
    expect(find.byKey(const Key('tmdb-loading')), findsOneWidget);
    expect(find.text('7.8/10'), findsNothing);
    gate.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tmdb-loading')), findsNothing);
    expect(find.text('8.2/10'), findsOneWidget);
    expect(find.text('2h 16m'), findsOneWidget);
    expect(find.text('Keanu Reeves'), findsOneWidget);
    expect(repo.tmdbSaved.single.$1, 1);
  });

  testWidgets('offline: failed row with Retry, then recovers', (t) async {
    var up = false;
    final seen = <Uri>[];
    final inner = matrixClient(seen);
    await open(
      t,
      client: MockClient((r) async {
        if (!up) throw http.ClientException('down');
        return inner.get(r.url);
      }),
    );
    expect(find.byKey(const Key('tmdb-failed')), findsOneWidget);
    expect(find.textContaining('Cannot reach TMDB'), findsOneWidget);
    up = true;
    await t.tap(find.byKey(const Key('tmdb-retry')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tmdb-failed')), findsNothing);
    expect(find.text('8.2/10'), findsOneWidget);
  });

  testWidgets('offline with cached data: details stay, no error row', (
    t,
  ) async {
    await open(
      t,
      client: MockClient((_) async => throw http.ClientException('down')),
      setup: (r) => r.tmdbData[1] = sampleInfo(1),
    );
    expect(find.text('7.8/10'), findsOneWidget);
    expect(find.byKey(const Key('tmdb-failed')), findsNothing);
  });

  for (final shape in ShapeMode.values) {
    testWidgets('Find on TMDB: search, pick, saved as manual (${shape.name})', (
      t,
    ) async {
      final seen = <Uri>[];
      await open(
        t,
        client: matrixClient(seen),
        shape: shape,
        setup: (r) =>
            r.tmdbData[1] = sampleInfo(1, status: TmdbStatus.unmatched),
      );
      await t.tap(find.byKey(const Key('tmdb-find')));
      await t.pumpAndSettle();
      expect(find.text('Find on TMDB'), findsWidgets);
      final q = t.widget<TextField>(find.byKey(const Key('tmdb-match-query')));
      expect(q.controller!.text, 'The Matrix');
      expect(find.byKey(const Key('tmdb-hit-603')), findsOneWidget);
      expect(find.text('1999 · Movie'), findsOneWidget);
      expect(find.byKey(const Key('tmdb-hit-604')), findsOneWidget);
      await t.tap(find.byKey(const Key('tmdb-hit-603')));
      await t.pumpAndSettle();
      expect(repo.tmdbSaved.single.$1, 1);
      expect(repo.tmdbSaved.single.$2.id, 603);
      expect(repo.tmdbSaved.single.$3, isTrue, reason: 'manual');
      // Sheet closed; details now shown.
      expect(find.byKey(const Key('tmdb-match-query')), findsNothing);
      expect(find.text('8.2/10'), findsOneWidget);
      expect(find.text('Fix match'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('Fix match: re-search with another query and type', (t) async {
    final seen = <Uri>[];
    await open(
      t,
      client: matrixClient(seen),
      setup: (r) => r.tmdbData[1] = sampleInfo(1),
    );
    await t.tap(find.byKey(const Key('tmdb-fix')));
    await t.pumpAndSettle();
    expect(find.text('Fix match'), findsWidgets);
    await t.tap(find.byKey(const Key('tmdb-type-tv')));
    await t.pumpAndSettle();
    expect(seen.last.path, '/3/search/tv');
    expect(find.byKey(const Key('tmdb-match-empty')), findsOneWidget);
    await t.enterText(find.byKey(const Key('tmdb-match-query')), 'Matrix');
    await t.tap(find.byKey(const Key('tmdb-type-movie')));
    await t.pumpAndSettle();
    expect(seen.last.queryParameters['query'], 'Matrix');
    expect(find.byKey(const Key('tmdb-hit-603')), findsOneWidget);
  });

  testWidgets('match sheet shows a failure without closing', (t) async {
    await open(
      t,
      client: MockClient((_) async => jsonResp({}, 401)),
      setup: (r) => r.tmdbData[1] = sampleInfo(1),
    );
    await t.tap(find.byKey(const Key('tmdb-fix')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tmdb-match-error')), findsOneWidget);
    expect(find.textContaining('TMDB rejected the key'), findsOneWidget);
    expect(find.textContaining(fakeKey), findsNothing);
  });
}
