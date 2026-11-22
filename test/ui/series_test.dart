import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/home/ui/continue_row.dart';
import 'package:watchdog/features/title/resume.dart';

import 'fakes.dart';

MediaFile ep(int id, int season, int e, {int? end}) => MediaFile(
  id: id,
  titleId: 5,
  seasonId: season,
  name: 'Show.S0${season}E$e.mkv',
  url: 'http://h/5/$id',
  ext: 'mkv',
  playable: true,
  episode: e,
  episodeEnd: end,
);

final show = mkTitle(5, 'Show', kind: TitleKind.series);
final e1 = ep(51, 1, 1);
final e2 = ep(52, 1, 2, end: 3);
final e3 = ep(53, 2, 1);
final sp = ep(54, 3, 1);
List<SeasonEpisodes> seasons() => [
  SeasonEpisodes(
    season: const Season(id: 3, titleId: 5, number: 0, label: 'Specials'),
    files: [sp],
  ),
  SeasonEpisodes(
    season: const Season(id: 1, titleId: 5, number: 1, label: 'Season 1'),
    files: [e1, e2],
  ),
  SeasonEpisodes(
    season: const Season(
      id: 2,
      titleId: 5,
      number: 2,
      label: 'Season 2',
      language: 'Hindi',
    ),
    files: [e3],
  ),
];

Future<(FakeRepository, FakeActions)> openShow(
  WidgetTester tester, {
  void Function(FakeRepository)? setup,
}) async {
  final repo = FakeRepository(titles: [show], seasonList: seasons());
  setup?.call(repo);
  useTallView(tester);
  final actions = FakeActions();
  await tester.pumpWidget(
    ProviderScope(
      overrides: testOverrides(repo, FakePlatform(), actions),
      child: const WatchdogApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Show'));
  await tester.pumpAndSettle();
  return (repo, actions);
}

void main() {
  test('pickResume: first unwatched, specials last, fallback first', () {
    final s = seasons();
    expect(pickResume(s, {})!.id, 51);
    expect(
      pickResume(s, {51: const WatchState(fileId: 51, watched: true)})!.id,
      52,
    );
    final all = {
      for (final id in [51, 52, 53, 54])
        id: WatchState(fileId: id, watched: true),
    };
    expect(pickResume(s, all)!.id, 51);
    final noSeasonOne = {
      for (final id in [51, 52, 53]) id: WatchState(fileId: id, watched: true),
    };
    expect(pickResume(s, noSeasonOne)!.id, 54);
    expect(episodeLabel(e2), 'E02-E03');
    expect(episodeLabel(e1), 'E01');
  });

  testWidgets('season selector switches, specials last', (tester) async {
    await openShow(tester);
    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((c) => (c.label as Text).data)
        .toList();
    expect(chips, ['Season 1', 'Season 2 · Hindi', 'Specials']);
    expect(find.byKey(const ValueKey('file-51')), findsOneWidget);
    expect(find.textContaining('E02-E03 · Episode 2'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Season 2 · Hindi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('file-51')), findsNothing);
    expect(find.byKey(const ValueKey('file-53')), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Specials'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('file-54')), findsOneWidget);
  });

  testWidgets('Play button picks first unwatched; Resume when in progress', (
    tester,
  ) async {
    final (_, a) = await openShow(tester, setup: (r) => r.watched[51] = true);
    expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pumpAndSettle();
    expect(a.calls, ['episode:52']);
  });

  testWidgets('Resume label for in-progress episode', (tester) async {
    final (_, a) = await openShow(
      tester,
      setup: (r) {
        r.watched[51] = true;
        r.progress[52] = const WatchState(
          fileId: 52,
          positionMs: 500,
          durationMs: 1000,
        );
      },
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pumpAndSettle();
    expect(a.calls, ['episode:52']);
  });

  testWidgets('play from here, play season, mark season watched', (
    tester,
  ) async {
    final (repo, a) = await openShow(tester);
    await tester.longPress(find.byKey(const ValueKey('file-51')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play from here'));
    await tester.pumpAndSettle();
    expect(a.calls, ['episode:51']);

    await tester.tap(
      find.byKey(const ValueKey('file-52')),
    ); // row tap = from here
    await tester.pumpAndSettle();
    expect(a.calls.last, 'episode:52');

    await tester.tap(find.text('Play season'));
    await tester.pumpAndSettle();
    expect(a.calls.last, 'season:1');

    await tester.tap(find.text('Mark season watched'));
    await tester.pumpAndSettle();
    expect(repo.seasonMarks, [(5, 1, true)]);
  });

  testWidgets('continue watching opens player directly', (tester) async {
    final repo = FakeRepository(titles: [show], seasonList: seasons());
    repo.resumeItems.add(
      ResumeItem(
        title: show,
        file: e2,
        state: const WatchState(fileId: 52, positionMs: 5, durationMs: 10),
      ),
    );
    final actions = FakeActions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(repo, FakePlatform(), actions),
        child: const WatchdogApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue watching'), findsOneWidget);
    await tester.tap(find.byType(ResumeCard));
    await tester.pumpAndSettle();
    expect(actions.calls, ['episode:52']);
  });

  group('theme persistence', () {
    test('file store round trip and corrupt file', () async {
      final dir = Directory.systemTemp.createTempSync('theme');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/theme.json');
      final store = FileThemeStore(f);
      expect((await store.load()).palette.id, 'everforest');
      await store.save(
        const ThemeSettings(
          palette: catppuccinLatte,
          shape: ShapeMode.rounded,
          followOmarchy: true,
        ),
      );
      final s = await FileThemeStore(f).load();
      expect(s.palette.id, 'latte');
      expect(s.shape, ShapeMode.rounded);
      expect(s.followOmarchy, isTrue);
      f.writeAsStringSync('{nope');
      expect((await store.load()).shape, ShapeMode.box);
    });

    test('notifier saves; restart restores', () async {
      final store = MemoryThemeStore();
      final c1 = ProviderContainer(
        overrides: [themeStoreProvider.overrideWithValue(store)],
      );
      c1.read(themeSettingsProvider.notifier)
        ..setPalette(tokyoNight)
        ..setShape(ShapeMode.rounded);
      await Future<void>.delayed(Duration.zero);
      final c2 = ProviderContainer(
        overrides: [initialThemeProvider.overrideWithValue(await store.load())],
      );
      expect(c2.read(paletteProvider).id, 'tokyo');
      expect(c2.read(shapeModeProvider), ShapeMode.rounded);
    });
  });
}
