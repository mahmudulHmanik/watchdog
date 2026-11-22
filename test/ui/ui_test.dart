import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/platform/external_player.dart';

import 'fakes.dart';

Category cat(int id, String name) =>
    Category(id: id, sourceId: 1, name: name, url: 'http://h/$id/');

late FakeActions actions;

Future<(FakeRepository, FakePlatform)> boot(
  WidgetTester tester,
  FakeRepository repo,
) async {
  useTallView(tester);
  final platform = FakePlatform();
  actions = FakeActions();
  await tester.pumpWidget(
    ProviderScope(
      overrides: testOverrides(repo, platform, actions),
      child: const WatchdogApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, platform);
}

Future<void> tapNav(WidgetTester t, String label) async {
  await t.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('first-run screen when index is empty, off-BDIX message', (
    tester,
  ) async {
    await boot(tester, FakeRepository());
    expect(find.text('Build the index'), findsOneWidget);
    expect(find.text('Index now'), findsOneWidget);
    await tester.tap(find.text('Index now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BDIX', skipOffstage: false), findsWidgets);
    expect(find.text('Skip for now'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Build the index'), findsNothing);
  });

  testWidgets('home lists titles and filters by category chip', (tester) async {
    await boot(
      tester,
      FakeRepository(
        cats: [cat(1, 'English'), cat(2, 'Hindi')],
        titles: [
          mkTitle(1, 'Alpha', categoryId: 1, year: 2020),
          mkTitle(2, 'Beta', categoryId: 2),
        ],
      ),
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Hindi'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('search filters by debounced query', (tester) async {
    await boot(
      tester,
      FakeRepository(titles: [mkTitle(1, 'Dune'), mkTitle(2, 'Arrival')]),
    );
    await tapNav(tester, 'Search');
    expect(find.text('Arrival'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('search-field')), 'dun');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Arrival'), findsOneWidget); // still debouncing
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Arrival'), findsNothing);
  });

  testWidgets('search year facet sheet filters', (tester) async {
    await boot(
      tester,
      FakeRepository(
        titles: [
          mkTitle(1, 'Dune', year: 2021),
          mkTitle(2, 'Arrival', year: 2016),
        ],
      ),
    );
    await tapNav(tester, 'Search');
    await tester.tap(find.byKey(const Key('pill-Year')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('facet-2010s')));
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
  });

  group('title detail', () {
    final movie = mkTitle(1, 'Dune', quality: 1080);
    final archive = mkFile(11, 1, 'Dune.1080p.mkv', sizeKb: 2 * 1024 * 1024);
    final rar = mkFile(12, 1, 'Dune.rar', playable: false);

    testWidgets('movie file actions call platform', (tester) async {
      final (repo, platform) = await boot(
        tester,
        FakeRepository(titles: [movie], files: [archive, rar]),
      );
      await tester.tap(find.text('Dune'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1080p · MKV · 2.0 GB'), findsOneWidget);
      expect(find.textContaining('not playable'), findsOneWidget);

      await tester.tap(find.text('Dune.1080p.mkv'));
      await tester.pumpAndSettle();
      expect(actions.calls, ['file:11']); // row tap plays in-app

      await tester.longPress(find.text('Dune.1080p.mkv'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(actions.calls, ['file:11', 'file:11']);

      await tester.longPress(find.text('Dune.1080p.mkv'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open in external player'));
      await tester.pumpAndSettle();
      expect(platform.opened.single.single.url, archive.url);

      await tester.longPress(find.text('Dune.1080p.mkv'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(platform.copied, [archive.url]);

      await tester.longPress(find.text('Dune.1080p.mkv'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(platform.downloads_, [archive.url]);

      await tester.longPress(find.text('Dune.1080p.mkv'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as watched'));
      await tester.pumpAndSettle();
      expect(repo.watched[11], isTrue);
      expect(find.text('Watched'), findsOneWidget);
    });

    testWidgets('archive offers only copy and download; player error shown', (
      tester,
    ) async {
      final (_, platform) = await boot(
        tester,
        FakeRepository(titles: [movie], files: [archive, rar]),
      );
      await tester.tap(find.text('Dune'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dune.rar'));
      await tester.pumpAndSettle();
      expect(find.text('Open in external player'), findsNothing);
      expect(find.text('Mark as watched'), findsNothing);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5)); // dismiss
      await tester.pumpAndSettle();

      platform.openError = const ExternalPlayerException(
        ExternalPlayerError.noPlayer,
      );
      await tester.longPress(find.text('Dune.1080p.mkv'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open in external player'));
      await tester.pumpAndSettle();
      expect(find.text('No player installed'), findsOneWidget);
    });

    testWidgets('series shows language-labelled season sections', (
      tester,
    ) async {
      final show = mkTitle(5, 'Show', kind: TitleKind.series);
      final e1 = mkFile(51, 5, 'Show.S01E01.mkv', seasonId: 1);
      final e2 = mkFile(52, 5, 'Show.S01E01.hin.mkv', seasonId: 2);
      await boot(
        tester,
        FakeRepository(
          titles: [show],
          seasonList: [
            SeasonEpisodes(
              season: const Season(
                id: 1,
                titleId: 5,
                number: 1,
                label: 'Season 1',
              ),
              files: [e1],
            ),
            SeasonEpisodes(
              season: const Season(
                id: 2,
                titleId: 5,
                number: 1,
                label: 'Season 1',
                language: 'Hindi',
              ),
              files: [e2],
            ),
          ],
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Season 1 · Hindi'), findsOneWidget);
      expect(find.byKey(const ValueKey('file-51')), findsOneWidget);
    });
  });

  testWidgets('settings shows about and index actions', (tester) async {
    await boot(tester, FakeRepository(titles: [mkTitle(1, 'A')]));
    await tapNav(tester, 'Settings');
    await tester.scrollUntilVisible(find.text('Author: mhm'), 200);
    expect(find.text('Author: mhm'), findsOneWidget);
    expect(find.text('License: Apache-2.0'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Full re-index'), -200);
    expect(find.text('Full re-index'), findsOneWidget);
  });
}
