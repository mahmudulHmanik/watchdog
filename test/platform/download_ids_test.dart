import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/downloads/download_ids.dart';
import 'package:watchdog/platform/platform_api.dart';

const cat = 'http://h/en/';
const folderA = '${cat}Film%20A/';
const folderB = '${cat}Film%20B/';
const urlA = '${folderA}Film.A.mkv';
const urlB = '${folderB}Film.B.mkv';

class _Api implements PlatformApi {
  _Api(this.list);
  final List<DownloadProgress> list;
  @override
  Future<List<DownloadProgress>> downloads() async => list;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

DownloadProgress dl(String id, String? url, {int? fileId, bool done = true}) =>
    DownloadProgress(
      id: id,
      filename: '$id.mkv',
      state: done ? DownloadState.complete : DownloadState.running,
      url: url,
      fileId: fileId,
    );

void main() {
  late DriftRepository repo;
  late int catId, titleA, titleB;

  setUp(() async {
    repo = DriftRepository.memory();
    final m = await repo.upsertCategories(const [
      CategoryDraft(
        sourceHost: 'h',
        name: 'English',
        url: cat,
        language: 'English',
      ),
    ]);
    catId = m[cat]!;
    // Skeletons: no file rows stored.
    Future<int> skeleton(String name, String folder) => repo.upsertTitle(
      TitleDraft(
        categoryId: catId,
        name: name,
        kind: TitleKind.movie,
        folderUrl: folder,
        filesLoaded: false,
        fileCount: 1,
      ),
    );
    titleA = await skeleton('Film A', folderA);
    titleB = await skeleton('Film B', folderB);
  });
  tearDown(() => repo.close());

  group('resolveDownloadFileId', () {
    test('dangling stored id is replaced by a stable one', () async {
      expect(await repo.fileByUrl(urlA), isNull);
      final id = await resolveDownloadFileId(repo, dl('a', urlA, fileId: 9999));
      expect(id, isNotNull);
      expect(id, isNot(9999));
      expect((await repo.file(id!))!.url, urlA);
      // Same id on every call.
      expect(
        await resolveDownloadFileId(repo, dl('a', urlA, fileId: 9999)),
        id,
      );
    });

    test('resume position is saved and restored through the id', () async {
      final d = dl('a', urlA, fileId: 9999);
      // The raw stale id silently drops the write.
      await repo.setProgress(9999, positionMs: 1000, durationMs: 10000);
      expect(await repo.watchState(9999), isNull);

      final id = (await resolveDownloadFileId(repo, d))!;
      await repo.setProgress(id, positionMs: 4000, durationMs: 10000);
      // Resolving again (a later play) lands on the same row.
      final again = (await resolveDownloadFileId(repo, d))!;
      expect(again, id);
      final ws = (await repo.watchState(again))!;
      expect((ws.positionMs, ws.durationMs, ws.watched), (4000, 10000, false));

      await repo.markWatched(again);
      expect((await repo.watchState(id))!.watched, isTrue);
    });

    test('existing row keeps its id', () async {
      final fs = await repo.ensureFileByUrl(urlA);
      expect(
        await resolveDownloadFileId(repo, dl('a', urlA, fileId: 5)),
        fs!.id,
      );
    });

    test('unknown url or no url falls back to the stored id', () async {
      expect(
        await resolveDownloadFileId(
          repo,
          dl('x', 'http://other/x.mkv', fileId: 7),
        ),
        7,
      );
      expect(await resolveDownloadFileId(repo, dl('x', null, fileId: 8)), 8);
      expect(await resolveDownloadFileId(repo, dl('x', null)), isNull);
    });
  });

  group('downloadedTitleIds', () {
    test('every state, deduped, unmatched urls skipped', () async {
      final api = _Api([
        dl('1', urlA),
        dl('2', '${folderA}Other.mkv', done: false),
        dl('3', urlB, done: false),
        dl('4', 'http://nowhere/x.mkv'),
        dl('5', null),
        dl('6', ''),
      ]);
      expect(await downloadedTitleIds(api, repo), {titleA, titleB});
    });

    test('no downloads -> empty', () async {
      expect(await downloadedTitleIds(_Api(const []), repo), isEmpty);
    });

    test('provider returns a callable that reads fresh data', () async {
      final list = <DownloadProgress>[];
      final c = ProviderContainer(
        overrides: [
          platformApiProvider.overrideWithValue(_Api(list)),
          repositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      final f = c.read(downloadedTitleIdsProvider);
      expect(await f(), isEmpty);
      list.add(dl('1', urlB));
      expect(await f(), {titleB});
    });
  });
}
