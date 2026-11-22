import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/search/search_providers.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';

import 'fakes.dart';

FakeRepository tmdbRepo({bool data = true}) =>
    FakeRepository(
        titles: [mkTitle(1, 'Dune'), mkTitle(2, 'Arrival'), mkTitle(3, 'Heat')],
      )
      ..tmdbProgressValue = TmdbProgress(eligible: 3, matched: data ? 2 : 0)
      ..genreFacets = const [
        FacetValue(TmdbGenre(18, 'Drama'), 5),
        FacetValue(TmdbGenre(878, 'Science Fiction'), 3),
        FacetValue(TmdbGenre(28, 'Action'), 2),
      ]
      ..tmdbLanguageFacets = const [FacetValue('en', 4), FacetValue('hi', 2)]
      ..people = const [
        PersonHit(id: 10, name: 'Tom Hanks', titleCount: 7),
        PersonHit(id: 11, name: 'Tomas Ray', titleCount: 1),
      ];

Future<ProviderContainer> openSearch(
  WidgetTester t,
  FakeRepository repo, {
  ShapeMode shape = ShapeMode.box,
  double width = 360,
  BrowseFilter? preset,
}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(repo, FakePlatform()),
        initialThemeProvider.overrideWithValue(ThemeSettings(shape: shape)),
      ],
      child: const WatchdogApp(),
    ),
  );
  await t.pumpAndSettle();
  final c = ProviderScope.containerOf(t.element(find.byType(WatchdogApp)));
  if (preset != null) c.read(searchFilterProvider.notifier).set(preset);
  await t.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Search'),
    ),
  );
  await t.pumpAndSettle();
  return c;
}

/// Scrolls the horizontal pill list until [key] is built, then taps it.
Future<void> tapPill(WidgetTester t, String name) async {
  final pill = find.byKey(Key('pill-$name'));
  await t.scrollUntilVisible(
    pill,
    80,
    scrollable: find.descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Scrollable),
    ),
  );
  await t.ensureVisible(pill);
  await t.pumpAndSettle();
  await t.tap(pill);
  await t.pumpAndSettle();
}

/// True when [name] exists anywhere in the (lazy, horizontal) filter bar.
Future<bool> pillExists(WidgetTester t, String name) async {
  final list = find.byType(ListView).first;
  final pill = find.byKey(Key('pill-$name'));
  for (var i = 0; i < 12; i++) {
    if (pill.evaluate().isNotEmpty) return true;
    await t.drag(list, const Offset(-150, 0));
    await t.pumpAndSettle();
  }
  return pill.evaluate().isNotEmpty;
}

Future<void> pickSheet(WidgetTester t, List<String> labels) async {
  for (final l in labels) {
    await t.tap(find.byKey(Key('facet-$l')));
    await t.pump();
  }
  await t.tap(find.text('Show results'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('no TMDB chips without TMDB data', (t) async {
    await openSearch(t, tmdbRepo(data: false));
    expect(await pillExists(t, 'Category'), isTrue);
    for (final n in ['Genre', 'Rating', 'OrigLanguage', 'Runtime', 'Actor']) {
      expect(await pillExists(t, n), isFalse, reason: n);
    }
  });

  testWidgets('TMDB chips appear with data', (t) async {
    await openSearch(t, tmdbRepo());
    for (final n in ['Genre', 'Rating', 'OrigLanguage', 'Runtime']) {
      expect(await pillExists(t, n), isTrue, reason: n);
    }
    expect(await pillExists(t, 'Actor'), isFalse);
  });

  testWidgets('genre multi-select with counts, chip label, clear', (t) async {
    final c = await openSearch(t, tmdbRepo());
    await tapPill(t, 'Genre');
    expect(find.text('Drama (5)'), findsOneWidget);
    expect(find.text('Science Fiction (3)'), findsOneWidget);
    await pickSheet(t, ['Drama', 'Action']);
    final f = c.read(searchFilterProvider);
    expect(f.genreIds, {18, 28});
    expect(f.activeCount, 1);
    expect(find.text('Drama, Action'), findsOneWidget);
    await t.tap(find.byKey(const Key('pill-icon-Genre')));
    await t.pumpAndSettle();
    expect(c.read(searchFilterProvider).hasGenreFilter, isFalse);
    expect(find.text('Genre'), findsOneWidget);
  });

  testWidgets('rating minimum is single-select, Any clears', (t) async {
    final c = await openSearch(t, tmdbRepo());
    await tapPill(t, 'Rating');
    await t.tap(find.byKey(const Key('facet-7+')));
    await t.pump();
    await t.tap(find.byKey(const Key('facet-8+'))); // replaces 7+
    await t.pump();
    await t.tap(find.text('Show results'));
    await t.pumpAndSettle();
    expect(c.read(searchFilterProvider).minRating, 8);
    expect(find.text('8+ rating'), findsOneWidget);
    await tapPill(t, 'Rating');
    await pickSheet(t, ['Any']);
    expect(c.read(searchFilterProvider).minRating, isNull);
    expect(find.text('Rating'), findsOneWidget);
  });

  testWidgets('original language shows readable names, stores codes', (
    t,
  ) async {
    final c = await openSearch(t, tmdbRepo());
    await tapPill(t, 'OrigLanguage');
    expect(find.text('Hindi (2)'), findsOneWidget);
    await pickSheet(t, ['Hindi']);
    expect(c.read(searchFilterProvider).originalLanguages, {'hi'});
    expect(find.text('Hindi'), findsOneWidget);
  });

  testWidgets('runtime buckets multi-select', (t) async {
    final c = await openSearch(t, tmdbRepo());
    await tapPill(t, 'Runtime');
    await pickSheet(t, ['< 90 min', '150+ min']);
    final f = c.read(searchFilterProvider);
    expect(f.runtimes, {RuntimeBucket.short, RuntimeBucket.epic});
    expect(f.activeCount, 1);
    expect(find.text('< 90 min, 150+ min'), findsOneWidget);
  });

  testWidgets('all TMDB filters + actor count together', (t) async {
    final c = await openSearch(t, tmdbRepo());
    c
        .read(searchFilterProvider.notifier)
        .set(
          const BrowseFilter(
            genreIds: {18},
            minRating: 7,
            originalLanguages: {'en'},
            runtimes: {RuntimeBucket.long},
            personId: 10,
          ),
        );
    await t.pumpAndSettle();
    expect(c.read(searchFilterProvider).activeCount, 5);
    expect(find.text('Tom Hanks'), findsOneWidget);
  });

  testWidgets('actor strip: match, tap sets personId + Actor chip', (t) async {
    final c = await openSearch(t, tmdbRepo());
    expect(find.byKey(const Key('people-strip')), findsNothing);
    await t.enterText(find.byKey(const Key('search-field')), 'tom');
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('people-strip')), findsOneWidget);
    expect(find.text('Tom Hanks'), findsOneWidget);
    expect(find.text('7 titles'), findsOneWidget);
    expect(find.text('1 title'), findsOneWidget);
    expect(find.text('TH'), findsOneWidget); // initials, no photo
    await t.tap(find.byKey(const Key('person-10')));
    await t.pumpAndSettle();
    expect(c.read(searchFilterProvider).personId, 10);
    expect(find.byKey(const Key('people-strip')), findsNothing);
    expect(
      find.textContaining('Showing all', findRichText: true),
      findsOneWidget,
    ); // text query cleared
    expect(
      t
          .widget<TextField>(find.byKey(const Key('search-field')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const Key('pill-Actor')), findsOneWidget);
    expect(find.text('Tom Hanks'), findsOneWidget);
    await t.tap(find.byKey(const Key('pill-icon-Actor')));
    await t.pumpAndSettle();
    expect(c.read(searchFilterProvider).personId, isNull);
    expect(find.byKey(const Key('pill-Actor')), findsNothing);
  });

  testWidgets('no strip when no name matches or no TMDB data', (t) async {
    await openSearch(t, tmdbRepo());
    await t.enterText(find.byKey(const Key('search-field')), 'dune');
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('people-strip')), findsNothing);
    expect(find.text('Dune'), findsWidgets);
  });

  testWidgets('no strip without TMDB data', (t) async {
    await openSearch(t, tmdbRepo(data: false));
    await t.enterText(find.byKey(const Key('search-field')), 'tom');
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('people-strip')), findsNothing);
  });

  testWidgets('preset filter from elsewhere is honoured', (t) async {
    final c = await openSearch(
      t,
      tmdbRepo(),
      preset: const BrowseFilter(personId: 10, genreIds: {18}),
    );
    expect(find.byKey(const Key('pill-Actor')), findsOneWidget);
    expect(find.text('Tom Hanks'), findsOneWidget);
    expect(await pillExists(t, 'Genre'), isTrue);
    expect(find.text('Drama'), findsOneWidget);
    expect(c.read(searchFilterProvider).activeCount, 2);
    expect(find.text('Dune'), findsOneWidget);
  });

  for (final shape in ShapeMode.values) {
    testWidgets('360px no overflow with all TMDB state (${shape.name})', (
      t,
    ) async {
      await openSearch(
        t,
        tmdbRepo(),
        shape: shape,
        preset: const BrowseFilter(
          personId: 10,
          genreIds: {18, 28, 878},
          minRating: 8,
          originalLanguages: {'hi', 'en', 'xx'},
          runtimes: {RuntimeBucket.short, RuntimeBucket.long},
        ),
      );
      expect(t.takeException(), isNull);
      await t.enterText(find.byKey(const Key('search-field')), 'tom');
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('people-strip')), findsOneWidget);
      expect(t.takeException(), isNull);
      await tapPill(t, 'Genre');
      expect(find.text('Show results'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
