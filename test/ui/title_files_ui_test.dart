import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/crawler/title_files.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/title/title_providers.dart';
import 'package:watchdog/features/title/ui/title_screen.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_settings.dart';

import '../crawler/page_fixture.dart';
import 'fakes.dart';

const fast = TitleLoadOptions(backoffBase: Duration.zero);

/// FakeRepository with lazy files: a title is `filesLoaded == false` and has
/// no file rows until upsertTitleFiles.
class LazyRepo extends FakeRepository {
  LazyRepo(this.base, {this.storedSeasons = const [], this.loaded = false})
    : super(titles: [base]);
  final MediaTitle base;
  final List<Season> storedSeasons;
  bool loaded;
  var _files = <MediaFile>[];
  var _seasons = <SeasonEpisodes>[];
  final trims = <Set<int>>[];

  @override
  Future<MediaTitle?> title(int id) async => MediaTitle(
    id: base.id,
    categoryId: base.categoryId,
    name: base.name,
    kind: base.kind,
    folderUrl: base.folderUrl,
    addedAt: base.addedAt,
    fileCount: base.fileCount,
    seasonCount: base.seasonCount,
    filesLoaded: loaded,
  );

  @override
  Future<List<SeasonEpisodes>> seasons(int titleId) async => loaded
      ? _seasons
      : [for (final s in storedSeasons) SeasonEpisodes(season: s, files: [])];

  @override
  Future<List<MediaFile>> titleFiles(int titleId) async => loaded ? _files : [];

  @override
  Future<void> upsertTitleFiles(
    int titleId, {
    List<FileDraft> files = const [],
    List<SeasonDraft> seasons = const [],
  }) async {
    var n = 100;
    MediaFile mk(FileDraft d, int? sid) => MediaFile(
      id: n++,
      titleId: titleId,
      seasonId: sid,
      name: d.name,
      url: d.url,
      ext: d.ext,
      playable: d.playable,
      episode: d.episode,
    );
    _files = [for (final f in files) mk(f, null)];
    _seasons = [
      for (final (i, s) in seasons.indexed)
        SeasonEpisodes(
          season: Season(
            id: i + 1,
            titleId: titleId,
            number: s.number,
            label: s.label,
            language: s.language,
            folderUrl: s.folderUrl,
            episodeCount: s.files.length,
          ),
          files: [for (final f in s.files) mk(f, i + 1)],
        ),
    ];
    loaded = true;
  }

  @override
  Future<int> trimFileCache({
    int maxRows = 20000,
    Set<int> protectedTitleIds = const {},
  }) async {
    trims.add(protectedTitleIds);
    return 0;
  }
}

MediaTitle lazyTitle(
  int id,
  String name, {
  TitleKind kind = TitleKind.movie,
  int fileCount = 0,
  int seasonCount = 0,
}) => MediaTitle(
  id: id,
  categoryId: 1,
  name: name,
  kind: kind,
  folderUrl: 'http://h/$id/',
  addedAt: DateTime(2020),
  filesLoaded: false,
  fileCount: fileCount,
  seasonCount: seasonCount,
);

late LazyRepo repo;
late ScriptedClient client;

Future<void> open(
  WidgetTester t,
  LazyRepo r,
  ScriptedClient c, {
  ShapeMode shape = ShapeMode.box,
  AppPalette? palette,
}) async {
  repo = r;
  client = c;
  t.view.physicalSize = const Size(360, 740);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(r, FakePlatform()),
        tmdbSettingsStoreProvider.overrideWithValue(MemoryTmdbSettingsStore()),
        titleFilesLoaderProvider.overrideWith(
          (ref) => TitleFilesLoader(repo: r, client: c, options: fast),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(palette ?? everforest, shape),
        home: TitleScreen(titleId: r.base.id),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

const loading = Key('files-loading');
const error = Key('files-error');
const empty = Key('files-empty');

ScriptedClient movieClient({List<(String, {int? kb, String date})>? entries}) =>
    ScriptedClient({
      'http://h/1/': h5aiPage('/1/', entries ?? [f('Film.2020.mkv')]),
    });

ScriptedClient showClient() => ScriptedClient({
  'http://h/5/': h5aiPage('/5/', [d('Season 1'), d('Season 2')]),
  'http://h/5/Season%201/': h5aiPage('/5/Season%201/', [
    f('Show.S01E01.mkv'),
    f('Show.S01E02.mkv'),
  ]),
  'http://h/5/Season%202/': h5aiPage('/5/Season%202/', [f('Show.S02E01.mkv')]),
});

LazyRepo showRepo({bool loaded = false}) => LazyRepo(
  lazyTitle(5, 'Show', kind: TitleKind.series, fileCount: 8, seasonCount: 2),
  loaded: loaded,
  storedSeasons: const [
    Season(
      id: 1,
      titleId: 5,
      number: 1,
      label: 'Season 1',
      folderUrl: 'http://h/5/Season%201/',
      episodeCount: 8,
    ),
    Season(
      id: 2,
      titleId: 5,
      number: 2,
      label: 'Season 2',
      folderUrl: 'http://h/5/Season%202/',
    ),
  ],
);

void main() {
  for (final shape in ShapeMode.values) {
    group('360 px, ${shape.name}', () {
      testWidgets('movie: metadata at once, loading row, then the files', (
        t,
      ) async {
        final gate = Completer<void>();
        await open(
          t,
          LazyRepo(lazyTitle(1, 'Film', fileCount: 1)),
          movieClient()..gate = gate,
          shape: shape,
        );
        expect(find.text('Film'), findsWidgets); // header + app bar
        expect(find.byKey(loading), findsOneWidget);
        expect(find.text('Loading files…'), findsOneWidget);
        expect(find.byKey(error), findsNothing);
        expect(t.takeException(), isNull);
        gate.complete();
        await t.pumpAndSettle();
        expect(find.byKey(loading), findsNothing);
        expect(find.text('Film.2020.mkv'), findsOneWidget);
        expect(t.takeException(), isNull);
        // The cache is trimmed after the load.
        expect(repo.trims, hasLength(1));
      });

      testWidgets('series: season chips with counts before episodes load', (
        t,
      ) async {
        final gate = Completer<void>();
        await open(t, showRepo(), showClient()..gate = gate, shape: shape);
        expect(find.text('Loading episodes…'), findsOneWidget);
        final chips = [
          for (final c in t.widgetList<ChoiceChip>(find.byType(ChoiceChip)))
            (c.label as Text).data,
        ];
        expect(chips, ['Season 1 (8)', 'Season 2']);
        expect(find.widgetWithText(FilledButton, 'Play'), findsNothing);
        expect(find.text('Play season'), findsNothing);
        expect(t.takeException(), isNull);
        gate.complete();
        await t.pumpAndSettle();
        expect(find.byKey(loading), findsNothing);
        expect(find.textContaining('Episode 1'), findsWidgets);
        expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
        final after = [
          for (final c in t.widgetList<ChoiceChip>(find.byType(ChoiceChip)))
            (c.label as Text).data,
        ];
        expect(after, ['Season 1', 'Season 2']);
        expect(t.takeException(), isNull);
      });

      testWidgets('offline: BDIX message with Retry that recovers', (t) async {
        await open(
          t,
          LazyRepo(lazyTitle(1, 'Film', fileCount: 1)),
          movieClient()..down = true,
          shape: shape,
        );
        await t.pumpAndSettle();
        expect(find.byKey(error), findsOneWidget);
        expect(
          find.text("Can't reach the server. Playback needs BDIX."),
          findsOneWidget,
        );
        expect(find.byKey(loading), findsNothing);
        expect(find.text('Film'), findsWidgets);
        expect(t.takeException(), isNull);
        client.down = false;
        await t.tap(find.byKey(const Key('files-retry')));
        await t.pumpAndSettle();
        expect(find.byKey(error), findsNothing);
        expect(find.text('Film.2020.mkv'), findsOneWidget);
      });

      testWidgets('series offline: chips stay, error with Retry', (t) async {
        await open(t, showRepo(), showClient()..down = true, shape: shape);
        await t.pumpAndSettle();
        expect(find.byKey(error), findsOneWidget);
        expect(find.byType(ChoiceChip), findsNWidgets(2));
        client.down = false;
        await t.tap(find.byKey(const Key('files-retry')));
        await t.pumpAndSettle();
        expect(find.byKey(error), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('nothing playable: No playable files', (t) async {
        await open(
          t,
          LazyRepo(lazyTitle(1, 'Film')),
          movieClient(entries: [f('poster.jpg'), f('Film.srt')]),
          shape: shape,
        );
        await t.pumpAndSettle();
        expect(find.byKey(empty), findsOneWidget);
        expect(find.text('No playable files'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('loaded and fresh: no request at all', (t) async {
        final r = LazyRepo(lazyTitle(1, 'Film'), loaded: true);
        await r.upsertTitleFiles(
          1,
          files: const [
            FileDraft(
              name: 'Film.mkv',
              url: 'http://h/1/Film.mkv',
              ext: 'mkv',
              playable: true,
            ),
          ],
        );
        await open(t, r, ScriptedClient(), shape: shape);
        await t.pumpAndSettle();
        expect(find.text('Film.mkv'), findsOneWidget);
        expect(client.requests, isEmpty);
        expect(repo.trims, isEmpty);
      });

      testWidgets('pull to refresh forces a reload', (t) async {
        await open(
          t,
          LazyRepo(lazyTitle(1, 'Film')),
          movieClient(),
          shape: shape,
        );
        await t.pumpAndSettle();
        expect(client.requests, hasLength(1));
        await t.fling(find.byType(ListView), const Offset(0, 400), 1000);
        await t.pumpAndSettle();
        expect(client.requests, hasLength(2));
        expect(find.text('Film.2020.mkv'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    });
  }

  for (final p in [tokyoNight, catppuccinLatte]) {
    testWidgets('loading + error render in ${p.id} (box)', (t) async {
      await open(t, showRepo(), showClient()..down = true, palette: p);
      await t.pump();
      expect(find.byKey(loading), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.byKey(error), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
