import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/search/ui/filter_bar.dart' show yearChipLabel;
import 'package:watchdog/features/player/player_providers.dart';
import 'package:watchdog/platform/platform_api.dart';

import 'fakes.dart';

late FakePlatform platform;

Future<ProviderContainer> boot(
  WidgetTester tester,
  FakeRepository repo, {
  bool online = false,
  FakePlatform? p,
}) async {
  useTallView(tester);
  platform = p ?? FakePlatform();
  await tester.pumpWidget(
    ProviderScope(
      overrides: testOverrides(repo, platform, FakeActions(), online),
      child: const WatchdogApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(WatchdogApp)));
}

Future<void> nav(WidgetTester t, String label) async {
  await t.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await t.pumpAndSettle();
}

DownloadProgress dl(
  String id,
  DownloadState s, {
  double p = 0.5,
  String? err,
  String? path,
}) => DownloadProgress(
  id: id,
  filename: 'file$id.mkv',
  state: s,
  progress: p,
  error: err,
  filePath: path,
  bytesReceived: 5 * 1024 * 1024,
  bytesTotal: 10 * 1024 * 1024,
);

void main() {
  final repo = FakeRepository(
    titles: [mkTitle(1, 'Dune', year: 2021, quality: 1080)],
  );

  testWidgets('bottom nav has 4 tabs incl. Downloads', (tester) async {
    await boot(tester, repo);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final l in ['Home', 'Search', 'Downloads', 'Settings']) {
      expect(
        find.descendant(of: find.byType(NavigationBar), matching: find.text(l)),
        findsOneWidget,
      );
    }
  });

  testWidgets('BDIX pill: offline when hosts unreachable', (tester) async {
    await boot(tester, repo);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('BDIX online'), findsNothing);
  });

  testWidgets('BDIX pill: online when a host answers', (tester) async {
    await boot(tester, repo, online: true);
    expect(find.text('BDIX online'), findsOneWidget);
  });

  testWidgets('home grid shows quality badge', (tester) async {
    await boot(tester, repo);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('Recently added'), findsOneWidget);
  });

  testWidgets('search: multi-select year buckets, chip summary, clear', (
    tester,
  ) async {
    await boot(
      tester,
      FakeRepository(
        titles: [
          mkTitle(1, 'Dune', year: 2021),
          mkTitle(2, 'Arrival', year: 2016),
          mkTitle(3, 'Gamma', year: 2023),
        ],
      ),
    );
    await nav(tester, 'Search');
    expect(find.textContaining('3 matches'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsWidgets);
    await tester.tap(find.byKey(const Key('pill-Year')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('facet-2021')));
    await tester.tap(find.byKey(const Key('facet-2023')));
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Arrival'), findsNothing);
    expect(find.textContaining('2 matches'), findsOneWidget);
    expect(find.text('2023, 2021'), findsOneWidget); // chip summary
    expect(find.byIcon(Icons.close), findsOneWidget);
    // Decade bucket: 2010s covers 2016.
    await tester.tap(find.byKey(const Key('pill-Year')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('facet-2010s')));
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('3 years'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pill-icon-Year')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 matches'), findsOneWidget);
  });

  testWidgets('search: match fragment is highlighted', (tester) async {
    await boot(tester, FakeRepository(titles: [mkTitle(1, 'Northbound')]));
    await nav(tester, 'Search');
    await tester.enterText(find.byKey(const Key('search-field')), 'north');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing results for'), findsOneWidget);
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((r) => r.text.toPlainText() == 'Northbound');
    expect(rich, isNotEmpty);
    final spans = <TextSpan>[];
    rich.first.text.visitChildren((s) {
      if (s is TextSpan && s.text != null) spans.add(s);
      return true;
    });
    expect(
      spans.any((s) => s.text == 'North' && s.style?.color != null),
      isTrue,
    );
  });

  group('downloads tab', () {
    testWidgets('empty state', (tester) async {
      await boot(tester, repo);
      await nav(tester, 'Downloads');
      expect(find.text('No downloads yet.'), findsOneWidget);
    });

    testWidgets('states, actions and remove with file delete', (tester) async {
      final p = FakePlatform()
        ..downloadList = [
          dl('1', DownloadState.running),
          dl('2', DownloadState.paused),
          dl('3', DownloadState.complete, p: 1, path: '/tmp/file3.mkv'),
          dl('4', DownloadState.failed, err: 'boom'),
        ];
      await boot(tester, repo, p: p);
      await nav(tester, 'Downloads');
      expect(find.textContaining('Downloading · 50%'), findsOneWidget);
      expect(find.textContaining('Paused'), findsOneWidget);
      expect(find.textContaining('Complete'), findsOneWidget);
      expect(find.textContaining('boom'), findsOneWidget);
      expect(find.textContaining('5 MB / 10 MB'), findsWidgets);

      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Resume'));
      await tester.pumpAndSettle();
      expect(p.calls, ['pause:1', 'resume:2']);

      await tester.tap(find.text('file3.mkv'));
      await tester.pumpAndSettle();
      expect(p.openedLocal, ['/tmp/file3.mkv']);

      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also delete file'));
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(p.calls.last, 'remove:3:true');
    });

    testWidgets('finished item opens via openLocalFile', (tester) async {
      final p = FakePlatform()
        ..downloadList = [
          dl('3', DownloadState.complete, p: 1, path: '/tmp/file3.mkv'),
        ];
      await boot(tester, repo, p: p);
      await nav(tester, 'Downloads');
      await tester.tap(find.text('file3.mkv'));
      await tester.pumpAndSettle();
      expect(p.openedLocal, ['/tmp/file3.mkv']);
      expect(p.opened, isEmpty);
    });

    testWidgets('live update changes state', (tester) async {
      final p = FakePlatform()..downloadList = [dl('1', DownloadState.running)];
      await boot(tester, repo, p: p);
      await nav(tester, 'Downloads');
      p.updates.add(dl('1', DownloadState.complete, p: 1, path: '/x'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Complete'), findsOneWidget);
    });
  });

  group('actions sheet', () {
    final movie = mkTitle(1, 'Dune');
    final file = mkFile(11, 1, 'Dune.1080p.mkv', sizeKb: 2048);

    Future<void> openSheet(WidgetTester t) async {
      await t.tap(find.text('Dune'));
      await t.pumpAndSettle();
      await t.longPress(find.text('Dune.1080p.mkv'));
      await t.pumpAndSettle();
    }

    testWidgets('header, sublabels, Link copied toast', (tester) async {
      await boot(tester, FakeRepository(titles: [movie], files: [file]));
      await openSheet(tester);
      expect(find.text('In-app player'), findsOneWidget);
      expect(find.text('Direct BDIX URL'), findsOneWidget);
      expect(find.textContaining('1080p · 2 MB · MKV'), findsOneWidget);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(find.text('Link copied'), findsOneWidget);
      expect(platform.copied, [file.url]);
    });

    testWidgets('download queued toast has View -> Downloads tab', (
      tester,
    ) async {
      await boot(tester, FakeRepository(titles: [movie], files: [file]));
      await openSheet(tester);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.text('Download queued'), findsOneWidget);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('No downloads yet.'), findsOneWidget);
    });

    for (final (err, msg) in [
      (UnimplementedError(), 'Not supported on this platform'),
      (Exception('Permission denied'), 'Storage permission denied'),
      (Exception('cleartext not permitted'), 'Host blocked'),
    ]) {
      testWidgets('download error: $msg', (tester) async {
        await boot(
          tester,
          FakeRepository(titles: [movie], files: [file]),
          p: FakePlatform()..downloadError = err,
        );
        await openSheet(tester);
        await tester.tap(find.text('Download'));
        await tester.pumpAndSettle();
        expect(find.textContaining(msg), findsOneWidget);
      });
    }
  });

  testWidgets('settings: palette rows and playback prefs', (tester) async {
    await boot(tester, repo);
    await nav(tester, 'Settings');
    expect(find.text('Follow system'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('palette-latte')),
      200,
    );
    await tester.tap(find.byKey(const Key('palette-latte')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary,
      const Color(0xFF1E66F5),
    );
    await tester.tap(find.byKey(const Key('preferred-audio')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hindi'));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(
      tester.element(find.byType(WatchdogApp)),
    );
    expect(c.read(preferredAudioProvider), 'hin');
  });

  testWidgets('series autoplay toggle writes playerSettings', (tester) async {
    final show = mkTitle(5, 'Show', kind: TitleKind.series);
    final e = MediaFile(
      id: 51,
      titleId: 5,
      seasonId: 1,
      name: 'Show.S01E01.mkv',
      url: 'http://h/5/51',
      ext: 'mkv',
      playable: true,
      episode: 1,
    );
    final c = await boot(
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
            files: [e],
          ),
        ],
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Autoplay next'), findsOneWidget);
    await tester.tap(find.byKey(const Key('autoplay-switch')));
    await tester.pumpAndSettle();
    expect(c.read(playerSettingsProvider).value!.autoplayNext, isFalse);
  });

  test('year chip label: singular, non-preset year shown, bucket labels', () {
    final presets = YearBucket.presets(2026);
    expect(yearChipLabel(const BrowseFilter(), presets), 'Year');
    expect(yearChipLabel(const BrowseFilter(years: {2019}), presets), '2019');
    expect(
      yearChipLabel(const BrowseFilter(years: {2024, 2023}), presets),
      '2024, 2023',
    );
    expect(
      yearChipLabel(const BrowseFilter(years: {2024, 2023, 2022}), presets),
      '3 years',
    );
    final m = YearBucket.merge([presets[6]]);
    final f = BrowseFilter(years: m.years, yearRanges: m.ranges);
    expect(yearChipLabel(f, presets), presets[6].label);
  });

  testWidgets('finished download has a visible Open button', (tester) async {
    final p = FakePlatform()
      ..downloadList = [
        dl('3', DownloadState.complete, p: 1, path: '/tmp/file3.mkv'),
      ];
    await boot(tester, repo, p: p);
    await nav(tester, 'Downloads');
    await tester.tap(find.byTooltip('Open'));
    await tester.pumpAndSettle();
    expect(p.openedLocal, ['/tmp/file3.mkv']);
  });

  testWidgets('settings About has licenses entry', (tester) async {
    await boot(tester, repo);
    await nav(tester, 'Settings');
    await tester.scrollUntilVisible(find.byKey(const Key('licenses')), 300);
    expect(find.text('Open source licenses'), findsOneWidget);
    expect(find.textContaining('libmpv and FFmpeg'), findsOneWidget);
  });

  testWidgets('episode row: no duplicated number in meta', (tester) async {
    final show = mkTitle(5, 'Show', kind: TitleKind.series);
    final e = MediaFile(
      id: 51,
      titleId: 5,
      seasonId: 1,
      name: 'Show.S01E01.1080p.mkv',
      url: 'http://h/5/51',
      ext: 'mkv',
      playable: true,
      episode: 1,
      sizeKb: 1300000,
    );
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
            files: [e],
          ),
        ],
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('E01 · Episode 1'), findsOneWidget);
    expect(find.textContaining('Up next · 1080p · '), findsOneWidget);
    expect(find.textContaining('E01 · 1080p'), findsNothing);
  });
}
