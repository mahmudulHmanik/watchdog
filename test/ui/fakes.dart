import 'package:flutter_test/flutter_test.dart' show addTearDown, WidgetTester;

import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart' show BuildContext, Size;
import 'package:watchdog/features/player/domain/player_settings.dart';
import 'package:watchdog/features/player/player_providers.dart';
import 'package:watchdog/features/title/player_actions.dart';
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/platform/platform_api.dart';

MediaTitle mkTitle(
  int id,
  String name, {
  TitleKind kind = TitleKind.movie,
  int categoryId = 1,
  int? year,
  int? quality,
}) => MediaTitle(
  id: id,
  categoryId: categoryId,
  name: name,
  kind: kind,
  folderUrl: 'http://h/$id/',
  year: year,
  quality: quality,
  addedAt: DateTime(2020),
);

MediaFile mkFile(
  int id,
  int titleId,
  String name, {
  int? seasonId,
  bool playable = true,
  int? sizeKb,
}) => MediaFile(
  id: id,
  titleId: titleId,
  name: name,
  url: 'http://h/$titleId/$name',
  ext: name.split('.').last,
  playable: playable,
  seasonId: seasonId,
  sizeKb: sizeKb,
);

/// In-memory Repository for widget tests; unneeded methods throw.
class FakeRepository implements Repository {
  FakeRepository({
    this.cats = const [],
    this.titles = const [],
    this.files = const [],
    this.seasonList = const [],
  });
  final List<Category> cats;
  final List<MediaTitle> titles;
  final List<MediaFile> files;
  final List<SeasonEpisodes> seasonList;
  final watched = <int, bool>{};
  final progress = <int, WatchState>{};
  final resumeItems = <ResumeItem>[];
  final seasonMarks = <(int, int?, bool)>[];
  final _changes = StreamController<void>.broadcast();

  List<MediaTitle> _filtered(BrowseFilter f) => [
    for (final t in titles)
      if ((f.categoryId == null || t.categoryId == f.categoryId) &&
          (!f.hasYearFilter ||
              f.years.contains(t.year) ||
              f.yearRanges.any((r) => t.year != null && r.contains(t.year!))) &&
          (f.qualities.isEmpty || f.qualities.contains(t.quality)))
        t,
  ];

  List<T> _page<T>(List<T> l, int o, int n) => l.skip(o).take(n).toList();

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<List<Category>> categories() async => cats;
  @override
  Future<List<MediaTitle>> browse(
    BrowseFilter filter, {
    int offset = 0,
    int limit = 50,
  }) async => _page(_filtered(filter), offset, limit);
  @override
  Future<List<MediaTitle>> search(
    String query, {
    BrowseFilter filter = const BrowseFilter(),
    int offset = 0,
    int limit = 50,
  }) async => _page(
    [
      for (final t in _filtered(filter))
        if (t.name.toLowerCase().contains(query.toLowerCase())) t,
    ],
    offset,
    limit,
  );
  @override
  Future<IndexCounts> counts() async =>
      IndexCounts(titles: titles.length, files: files.length);
  @override
  Future<List<FacetValue<int>>> years([
    BrowseFilter within = const BrowseFilter(),
  ]) async => [
    for (final y in {for (final t in _filtered(within)) ?t.year})
      FacetValue(y, _filtered(within).where((t) => t.year == y).length),
  ];
  @override
  Future<List<FacetValue<String>>> languages([
    BrowseFilter within = const BrowseFilter(),
  ]) async => const [];
  @override
  Future<List<FacetValue<int>>> qualities([
    BrowseFilter within = const BrowseFilter(),
  ]) async => const [];
  @override
  Future<MediaTitle?> title(int id) async =>
      titles.where((t) => t.id == id).firstOrNull;
  @override
  Future<List<SeasonEpisodes>> seasons(int titleId) async => seasonList;
  @override
  Future<List<MediaFile>> titleFiles(int titleId) async =>
      files.where((f) => f.titleId == titleId && f.seasonId == null).toList();
  @override
  Future<Map<int, WatchState>> watchStates(Iterable<int> fileIds) async => {
    for (final id in fileIds)
      if (watched[id] == true)
        id: WatchState(fileId: id, watched: true)
      else if (progress[id] != null)
        id: progress[id]!,
  };
  @override
  Future<void> markTitleWatched(
    int titleId, {
    int? seasonId,
    bool watched = true,
  }) async => seasonMarks.add((titleId, seasonId, watched));
  @override
  Future<void> markWatched(int fileId, {bool watched = true}) async =>
      this.watched[fileId] = watched;
  @override
  Future<List<ResumeItem>> continueWatching({int limit = 20}) async =>
      resumeItems;
  @override
  Future<void> clearIndex({bool includeWatch = false}) async {}

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class FakePlatform implements PlatformApi {
  final openedLocal = <String>[];
  @override
  Future<void> openLocalFile(String path, {String? mimeType}) async {
    openedLocal.add(path);
  }

  List<DownloadProgress> downloadList = [];
  final updates = StreamController<DownloadProgress>.broadcast();
  Object? downloadError;
  final calls = <String>[];

  final opened = <List<ExternalMedia>>[];
  final copied = <String>[];
  final downloads_ = <String>[];
  Object? openError;

  @override
  Future<void> openExternal(List<ExternalMedia> items) async {
    if (openError != null) throw openError!;
    opened.add(items);
  }

  @override
  Future<void> copyUrl(String url) async => copied.add(url);

  @override
  Future<String> enqueueDownload(
    String url,
    String filename, {
    int? fileId,
    String? directory,
  }) async {
    if (downloadError != null) throw downloadError!;
    downloads_.add(url);
    return 'd1';
  }

  @override
  Stream<DownloadProgress> get downloadUpdates => updates.stream;
  @override
  Future<List<DownloadProgress>> downloads() async => downloadList;
  @override
  Future<void> pauseDownload(String id) async => calls.add('pause:$id');
  @override
  Future<void> resumeDownload(String id) async => calls.add('resume:$id');
  @override
  Future<void> cancelDownload(String id) async => calls.add('cancel:$id');
  @override
  Future<void> removeDownload(String id, {bool deleteFile = false}) async =>
      calls.add('remove:$id:$deleteFile');

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class FakeActions implements PlayerActions {
  final calls = <String>[];
  @override
  Future<void> playFile(BuildContext c, MediaFile f, MediaTitle t) async =>
      calls.add('file:${f.id}');
  @override
  Future<bool> playEpisode(
    BuildContext c,
    Repository repo,
    MediaTitle t,
    MediaFile f,
  ) async {
    calls.add('episode:${f.id}');
    return true;
  }

  @override
  Future<bool> playSeason(
    BuildContext c,
    Repository repo,
    MediaTitle t,
    int seasonId,
  ) async {
    calls.add('season:$seasonId');
    return true;
  }
}

class UpClient implements ListingClient {
  @override
  Future<String> fetch(Uri url, {required Duration timeout}) async => '';
  @override
  void close() {}
}

/// Listing client where every host is unreachable (off-BDIX).
class DownClient implements ListingClient {
  @override
  Future<String> fetch(Uri url, {required Duration timeout}) =>
      Future.error(Exception('unreachable'));
  @override
  void close() {}
}

List<Override> testOverrides(
  FakeRepository repo,
  FakePlatform platform, [
  FakeActions? actions,
  bool online = false,
]) => [
  playerSettingsStoreProvider.overrideWithValue(MemoryPlayerSettingsStore()),
  if (actions != null) playerActionsProvider.overrideWithValue(actions),
  repositoryProvider.overrideWithValue(repo),
  platformApiProvider.overrideWithValue(platform),
  listingClientProvider.overrideWithValue(online ? UpClient() : DownClient()),
  crawlConfigProvider.overrideWithValue(CrawlConfig.defaults()),
];

/// Tall viewport so lazy lists/grids build everything in tests.
void useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
