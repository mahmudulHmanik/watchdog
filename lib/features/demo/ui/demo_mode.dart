/// Debug-only demo data for screenshots. Inert unless the process is started
/// with `WATCHDOG_DEMO=<screen>` in a non-release build.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/search/search_providers.dart';
import 'package:watchdog/features/search/ui/facet_sheet.dart';
import 'package:watchdog/features/title/ui/file_actions_sheet.dart';
import 'package:watchdog/features/title/ui/title_screen.dart';
import 'package:watchdog/platform/platform_api.dart';

String? get demoScreen =>
    kReleaseMode ? null : Platform.environment['WATCHDOG_DEMO'];

class _OnlineClient implements ListingClient {
  @override
  Future<String> fetch(Uri url, {required Duration timeout}) async => '';
  @override
  void close() {}
}

class DemoPlatform implements PlatformApi {
  @override
  Future<void> openLocalFile(String path, {String? mimeType}) async {}
  @override
  Future<void> openExternal(List<ExternalMedia> items) async {}
  @override
  Future<void> copyUrl(String url) async {}
  @override
  Future<String> enqueueDownload(
    String url,
    String filename, {
    int? fileId,
    String? directory,
  }) async => 'x';
  @override
  Stream<DownloadProgress> get downloadUpdates => const Stream.empty();
  @override
  Future<List<DownloadProgress>> downloads() async => const [
    DownloadProgress(
      id: '1',
      filename: 'Northbound.2024.1080p.WEB-DL.mkv',
      state: DownloadState.running,
      progress: 0.42,
      bytesReceived: 1100 * 1024 * 1024,
      bytesTotal: 2600 * 1024 * 1024,
    ),
    DownloadProgress(
      id: '2',
      filename: 'Undertow.S02E06.720p.mkv',
      state: DownloadState.paused,
      progress: 0.1,
      bytesReceived: 130 * 1024 * 1024,
      bytesTotal: 1300 * 1024 * 1024,
    ),
    DownloadProgress(
      id: '3',
      filename: 'Harbor.Lights.2021.mkv',
      state: DownloadState.complete,
      progress: 1,
      filePath: '/tmp/Harbor.Lights.2021.mkv',
      bytesReceived: 1800 * 1024 * 1024,
      bytesTotal: 1800 * 1024 * 1024,
    ),
    DownloadProgress(
      id: '4',
      filename: 'Old.Show.S01E01.mkv',
      state: DownloadState.failed,
      progress: 0,
      error: 'Server unreachable',
    ),
  ];
  @override
  Future<String> defaultDownloadDirectory() async => '/tmp';
  @override
  Future<void> pauseDownload(String id) async {}
  @override
  Future<void> resumeDownload(String id) async {}
  @override
  Future<void> cancelDownload(String id) async {}
  @override
  Future<void> removeDownload(String id, {bool deleteFile = false}) async {}
}

FileDraft _f(String base, String name, {int? ep, int kb = 1300000}) =>
    FileDraft(
      name: name,
      url: '$base/$name',
      ext: name.split('.').last,
      playable: true,
      episode: ep,
      sizeKb: kb,
    );

Future<void> _seed(DriftRepository repo) async {
  final cats = await repo.upsertCategories(const [
    CategoryDraft(
      sourceHost: '10.0.0.7',
      name: 'English Movies',
      url: 'http://10.0.0.7/en/',
      language: 'English',
    ),
    CategoryDraft(
      sourceHost: '10.0.0.14',
      name: 'Hindi Movies',
      url: 'http://10.0.0.14/hi/',
      language: 'Hindi',
    ),
    CategoryDraft(
      sourceHost: '10.0.0.12',
      name: 'TV Series',
      url: 'http://10.0.0.12/tv/',
      language: 'English',
    ),
  ]);
  final en = cats['http://10.0.0.7/en/']!, hi = cats['http://10.0.0.14/hi/']!;
  final tv = cats['http://10.0.0.12/tv/']!;
  final drafts = <TitleDraft>[];
  final movies = [
    ('Northbound', 2025, 1080, en),
    ('Harbor Lights', 2021, 1080, en),
    ('The Long Night', 2023, 2160, en),
    ('Monsoon Road', 2022, 720, hi),
    ('Iron Valley', 2019, 1080, hi),
    ('Paper Tigers', 2020, 1080, en),
    ('বাংলা সিনেমা', 2022, 1080, en),
    ('東京物語 Tokyo Story', 2019, 1080, en),
    ('Война и мир', 2018, 1080, en),
  ];
  for (final (n, y, q, c) in movies) {
    final base = 'http://10.0.0.7/m/$n';
    drafts.add(
      TitleDraft(
        categoryId: c,
        name: n,
        kind: TitleKind.movie,
        folderUrl: '$base/',
        year: y,
        quality: q,
        files: [_f(base, '$n.$y.${q}p.WEB-DL.mkv', kb: 2400000)],
      ),
    );
  }
  for (final (n, y) in [
    ('Undertow', 2024),
    ('Glass Harbor', 2022),
    ('Nightshift', 2023),
  ]) {
    final base = 'http://10.0.0.12/tv/$n';
    drafts.add(
      TitleDraft(
        categoryId: tv,
        name: n,
        kind: TitleKind.series,
        folderUrl: '$base/',
        year: y,
        quality: 1080,
        seasons: [
          for (final s in [1, 2])
            SeasonDraft(
              number: s,
              label: 'Season $s',
              folderUrl: '$base/Season $s/',
              files: [
                for (var e = 1; e <= 8; e++)
                  _f('$base/Season $s', '$n.S0${s}E0$e.1080p.mkv', ep: e),
              ],
            ),
          SeasonDraft(
            number: 2,
            label: 'Season 2',
            language: 'Hindi',
            folderUrl: '$base/Season 2 Hindi/',
            files: [_f('$base/Season 2 Hindi', '$n.S02E01.Hindi.mkv', ep: 1)],
          ),
        ],
      ),
    );
  }
  await repo.upsertTitles(drafts);
  // Progress: Undertow S02E05 half way; E01-E04 watched.
  final base = 'http://10.0.0.12/tv/Undertow/Season 2';
  for (var e = 1; e <= 4; e++) {
    final f = await repo.fileByUrl('$base/Undertow.S02E0$e.1080p.mkv');
    if (f != null) await repo.markWatched(f.id);
  }
  final cur = await repo.fileByUrl('$base/Undertow.S02E05.1080p.mkv');
  if (cur != null) {
    await repo.setProgress(cur.id, positionMs: 1100000, durationMs: 2700000);
  }
  final m = await repo.fileByUrl(
    'http://10.0.0.7/m/Harbor Lights/Harbor Lights.2021.1080p.WEB-DL.mkv',
  );
  if (m != null) {
    await repo.setProgress(m.id, positionMs: 1800000, durationMs: 6200000);
  }
}

class DemoSetup {
  DemoSetup(this.overrides, this.onReady);
  final List<Override> overrides;
  final ReadyHook onReady;
}

Future<DemoSetup> buildDemo(String screen) async {
  final repo = DriftRepository.memory();
  await _seed(repo);
  final env = Platform.environment;
  final settings = ThemeSettings(
    palette:
        allPalettes.where((p) => p.id == env['WATCHDOG_THEME']).firstOrNull ??
        everforest,
    followOmarchy: env['WATCHDOG_THEME'] == 'omarchy',
    shape: env['WATCHDOG_SHAPE'] == 'rounded'
        ? ShapeMode.rounded
        : ShapeMode.box,
  );
  final tab = switch (screen) {
    'search' ||
    'search-year' ||
    'search-language' ||
    'search-foreign' => tabSearch,
    'downloads' => tabDownloads,
    'settings' => tabSettings,
    _ => tabHome,
  };
  return DemoSetup(
    [
      repositoryProvider.overrideWithValue(repo),
      platformApiProvider.overrideWithValue(DemoPlatform()),
      listingClientProvider.overrideWithValue(_OnlineClient()),
      initialThemeProvider.overrideWithValue(settings),
      initialTabProvider.overrideWithValue(tab),
    ],
    (context, ref) async {
      switch (screen) {
        case 'search-year':
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (!context.mounted) return;
          await showFacetSheet<YearBucket>(
            context,
            title: 'Year',
            options: Future.value([
              for (final b in YearBucket.presets(2025)) FacetOption(b.label, b),
            ]),
            selected: {
              YearBucket.presets(2025)[1],
              YearBucket.presets(2025)[2],
            },
          );
        case 'search-foreign':
          ref
              .read(searchFilterProvider.notifier)
              .set(const BrowseFilter(years: {2019}));
        case 'search-language':
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (!context.mounted) return;
          await showFacetSheet<String>(
            context,
            title: 'Language',
            options: repo.languages().then(
              (l) => [
                for (final v in l)
                  FacetOption(v.value, v.value, count: v.count),
              ],
            ),
            selected: {'Hindi'},
            columns: 2,
          );
        case 'series' || 'actions':
          final t = (await repo.search('Undertow')).first;
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => TitleScreen(titleId: t.id)),
          );
          if (screen == 'actions') {
            await Future<void>.delayed(const Duration(milliseconds: 800));
            final seasons = await repo.seasons(t.id);
            final f = seasons.first.files[5];
            if (!context.mounted) return;
            await showFileActions(
              context,
              ref,
              title: t,
              file: f,
              watched: false,
              siblings: seasons.first.files.sublist(5),
            );
          }
      }
    },
  );
}
