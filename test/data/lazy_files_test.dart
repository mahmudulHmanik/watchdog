import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/parsing.dart' as crawler;
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/file_names.dart';
import 'package:watchdog/data/models.dart';

const cat = 'http://h/en/';

FileDraft fd(String folder, String rel, {int? ep, int? size = 10}) => FileDraft(
  name: 'ignored',
  url: '$folder$rel',
  ext: 'ignored',
  playable: false,
  episode: ep,
  sizeKb: size,
);

void main() {
  group('derived names', () {
    test('nameOfRel / extOfName / playable', () {
      expect(nameOfRel('Season%201/Ep%2001.MKV'), 'Ep 01.MKV');
      expect(nameOfRel('a/b/'), 'b');
      expect(nameOfRel('bad%zz.mkv'), 'bad%zz.mkv');
      expect(nameOfRel(''), '');
      expect(extOfName('Ep 01.MKV'), 'mkv');
      expect(extOfName('noext'), '');
      expect(isPlayableExt('mkv'), isTrue);
      expect(isPlayableExt('rar'), isFalse);
    });

    test('playable list matches the crawler video list', () {
      expect(playableExts, crawler.videoExts);
    });

    test('composeUrl / relativeTo round trip, absolute passes through', () {
      expect(relativeTo('http://h/a/', 'http://h/a/b/c.mkv'), 'b/c.mkv');
      expect(composeUrl('http://h/a/', 'b/c.mkv'), 'http://h/a/b/c.mkv');
      expect(relativeTo('http://h/a/', 'http://x/y.mkv'), 'http://x/y.mkv');
      expect(composeUrl('http://h/a/', 'http://x/y.mkv'), 'http://x/y.mkv');
    });
  });

  group('repository', () {
    late AppDatabase db;
    late DriftRepository repo;
    late int catId;
    setUp(() async {
      db = AppDatabase.memory();
      repo = DriftRepository(db);
      final m = await repo.upsertCategories(const [
        CategoryDraft(
          sourceHost: 'h',
          name: 'English',
          url: cat,
          language: 'English',
        ),
      ]);
      catId = m[cat]!;
    });
    tearDown(() => repo.close());

    TitleDraft movie(
      String enc, {
      List<String> files = const ['Film.mkv'],
      bool loaded = true,
      DateTime? mtime,
      int? hint,
      String layout = '',
    }) {
      final folder = '$cat$layout$enc/';
      return TitleDraft(
        categoryId: catId,
        name: Uri.decodeComponent(enc),
        kind: TitleKind.movie,
        folderUrl: folder,
        posterUrl: '${folder}poster.jpg',
        folderMtime: mtime,
        filesLoaded: loaded,
        fileCount: hint,
        files: loaded ? [for (final f in files) fd(folder, f)] : const [],
      );
    }

    TitleDraft show(
      String enc, {
      int seasons = 2,
      int eps = 3,
      bool loaded = true,
      DateTime? mtime,
      List<int>? only,
    }) {
      final folder = '$cat$enc/';
      return TitleDraft(
        categoryId: catId,
        name: enc,
        kind: TitleKind.series,
        folderUrl: folder,
        folderMtime: mtime,
        filesLoaded: loaded,
        seasons: [
          for (var s = 1; s <= seasons; s++)
            if (only == null || only.contains(s))
              SeasonDraft(
                number: s,
                label: 'Season $s',
                folderUrl: '${folder}Season%20$s/',
                episodeCount: eps,
                files: loaded
                    ? [
                        for (var e = 1; e <= eps; e++)
                          fd(folder, 'Season%20$s/e0$e.mkv', ep: e),
                      ]
                    : const [],
              ),
        ],
      );
    }

    Future<int> rows(String table) async =>
        (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
            .read<int>('n');

    test('files expose absolute urls and derived name/ext/playable', () async {
      final id = await repo.upsertTitle(
        movie(
          'Some%20Film',
          files: ['Some%20Film.2019.MKV', 'Extras.rar', 'noext'],
        ),
      );
      final t = (await repo.title(id))!;
      expect(t.folderUrl, '${cat}Some%20Film/');
      expect(t.posterUrl, '${cat}Some%20Film/poster.jpg');
      expect(t.filesLoaded, isTrue);
      expect(t.fileCount, 3);
      final fs = {for (final f in await repo.titleFiles(id)) f.name: f};
      expect(fs.keys.toSet(), {'Some Film.2019.MKV', 'Extras.rar', 'noext'});
      final mkv = fs['Some Film.2019.MKV']!;
      expect(mkv.url, '${cat}Some%20Film/Some%20Film.2019.MKV');
      expect((mkv.ext, mkv.playable), ('mkv', true));
      expect(
        (fs['Extras.rar']!.ext, fs['Extras.rar']!.playable),
        ('rar', false),
      );
      expect((fs['noext']!.ext, fs['noext']!.playable), ('', false));
    });

    test(
      'file(id)/fileByUrl resolve flat, (Year)/Title and series layouts',
      () async {
        final a = await repo.upsertTitle(movie('Flat'));
        final b = await repo.upsertTitle(movie('Deep', layout: '(2019)/'));
        final c = await repo.upsertTitle(show('Show'));
        final fa = (await repo.titleFiles(a)).single;
        final fb = (await repo.titleFiles(b)).single;
        final fc = (await repo.seasons(c)).last.files.last;
        for (final f in [fa, fb, fc]) {
          expect((await repo.file(f.id))!.url, f.url);
          expect((await repo.fileByUrl(f.url))!.id, f.id);
        }
        expect(fb.url, '$cat(2019)/Deep/Film.mkv');
        expect(fc.url, '${cat}Show/Season%202/e03.mkv');
        expect(fc.seasonId, isNotNull);
        expect(await repo.fileByUrl('${cat}Show/Season%202/nope.mkv'), isNull);
        expect(await repo.fileByUrl('http://other/x.mkv'), isNull);
      },
    );

    test('skeleton draft: no files, counts from hints', () async {
      final id = await repo.upsertTitle(show('Sk', eps: 7, loaded: false));
      final t = (await repo.title(id))!;
      expect(t.filesLoaded, isFalse);
      expect(t.seasonCount, 2);
      expect(t.fileCount, 0);
      expect(await repo.titleFilesLoaded(id), isFalse);
      expect(await rows('files'), 0);
      final ss = await repo.seasons(id);
      expect(ss.map((s) => s.season.episodeCount), [7, 7]);
      expect(ss.every((s) => s.files.isEmpty), isTrue);
      expect(ss.first.season.folderUrl, '${cat}Sk/Season%201/');

      final m = await repo.upsertTitle(movie('Mv', loaded: false, hint: 3));
      expect((await repo.title(m))!.fileCount, 3);
      expect((await repo.title(m))!.filesLoaded, isFalse);
      expect(await repo.titleFiles(m), isEmpty);
      expect((await repo.counts()).files, 3);
    });

    test('skeleton draft with files is rejected', () {
      final d = TitleDraft(
        categoryId: catId,
        name: 'x',
        kind: TitleKind.movie,
        folderUrl: '${cat}x/',
        filesLoaded: false,
        files: [fd('${cat}x/', 'a.mkv')],
      );
      expect(d.validate, throwsArgumentError);
      expect(() => repo.upsertTitle(d), throwsArgumentError);
    });

    test(
      'upsertTitleFiles loads, keeps ids and watch, replaces the rest',
      () async {
        final id = await repo.upsertTitle(show('S', loaded: false));
        await repo.upsertTitleFiles(id, seasons: show('S').seasons);
        expect(await repo.titleFilesLoaded(id), isTrue);
        var t = (await repo.title(id))!;
        expect((t.fileCount, t.seasonCount, t.filesLoaded), (6, 2, true));
        var ss = await repo.seasons(id);
        final e2 = ss[0].files[1];
        final e3s2 = ss[1].files[2];
        final seasonIds = ss.map((s) => s.season.id).toList();
        await repo.setProgress(e2.id, positionMs: 100, durationMs: 1000);

        // Reload: season 1 loses e01, gains e09; season 2 unchanged; season 3 new.
        const folder = '${cat}S/';
        await repo.upsertTitleFiles(
          id,
          seasons: [
            SeasonDraft(
              number: 1,
              label: 'Season 1',
              folderUrl: '${folder}Season%201/',
              files: [
                fd(folder, 'Season%201/e02.mkv', ep: 2),
                fd(folder, 'Season%201/e03.mkv', ep: 3),
                fd(folder, 'Season%201/e09.mkv', ep: 9),
              ],
            ),
            ...show('S').seasons.skip(1),
            SeasonDraft(
              number: 3,
              label: 'Season 3',
              folderUrl: '${folder}Season%203/',
              files: [fd(folder, 'Season%203/e01.mkv', ep: 1)],
            ),
          ],
        );
        ss = await repo.seasons(id);
        expect(ss.map((s) => s.season.number), [1, 2, 3]);
        expect(ss.take(2).map((s) => s.season.id), seasonIds);
        expect(ss[0].files.map((f) => f.name), [
          'e02.mkv',
          'e03.mkv',
          'e09.mkv',
        ]);
        expect(ss[0].files[0].id, e2.id, reason: 'id kept for same rel');
        expect(ss[1].files[2].id, e3s2.id);
        expect((await repo.watchState(e2.id))!.positionMs, 100);
        expect((ss[0].season.episodeCount, ss[2].season.episodeCount), (3, 1));
        t = (await repo.title(id))!;
        expect((t.fileCount, t.seasonCount), (3 + 3 + 1, 3));
        expect(await rows('files'), 7);

        // Unlisted season disappears with its files.
        await repo.upsertTitleFiles(
          id,
          seasons: [
            SeasonDraft(
              number: 1,
              label: 'Season 1',
              folderUrl: '${folder}Season%201/',
              files: [fd(folder, 'Season%201/e02.mkv', ep: 2)],
            ),
          ],
        );
        expect((await repo.seasons(id)).length, 1);
        expect(await rows('files'), 1);
        expect((await repo.file(e2.id))!.name, 'e02.mkv');
      },
    );

    test('upsertTitleFiles argument errors', () async {
      final s = await repo.upsertTitle(show('S', loaded: false));
      final m = await repo.upsertTitle(movie('M', loaded: false));
      expect(
        () => repo.upsertTitleFiles(999, files: [fd('${cat}M/', 'a.mkv')]),
        throwsArgumentError,
      );
      expect(
        () => repo.upsertTitleFiles(s, files: [fd('${cat}S/', 'a.mkv')]),
        throwsArgumentError,
      );
      expect(
        () => repo.upsertTitleFiles(m, seasons: show('S').seasons),
        throwsArgumentError,
      );
      // Duplicate rels count once.
      await repo.upsertTitleFiles(
        m,
        files: [fd('${cat}M/', 'a.mkv'), fd('${cat}M/', 'a.mkv')],
      );
      expect((await repo.title(m))!.fileCount, 1);
    });

    test(
      're-crawl with a skeleton keeps loaded files unless the mtime moved',
      () async {
        final t0 = DateTime.utc(2024, 1, 1);
        final id = await repo.upsertTitle(show('S', loaded: true, mtime: t0));
        final ids = [
          for (final s in await repo.seasons(id)) ...s.files.map((f) => f.id),
        ];
        final seasonIds = [for (final s in await repo.seasons(id)) s.season.id];
        final watched = ids.first;
        await repo.setProgress(watched, positionMs: 5, durationMs: 10);

        // Same mtime: untouched and still loaded.
        await repo.upsertTitle(show('S', loaded: false, mtime: t0, eps: 3));
        expect(await repo.titleFilesLoaded(id), isTrue);
        expect(await rows('files'), 6);
        expect((await repo.seasons(id)).expand((s) => s.files).length, 6);

        // Changed mtime: stale, rows and ids stay.
        final t1 = t0.add(const Duration(days: 1));
        await repo.upsertTitle(show('S', loaded: false, mtime: t1, eps: 4));
        expect(await repo.titleFilesLoaded(id), isFalse);
        expect((await repo.title(id))!.filesLoaded, isFalse);
        expect(await rows('files'), 6);
        final stale = await repo.seasons(id);
        expect([for (final s in stale) s.season.id], seasonIds);
        expect(stale.expand((s) => s.files).map((f) => f.id), ids);
        expect(stale.map((s) => s.season.episodeCount), [4, 4]);
        expect((await repo.watchState(watched))!.positionMs, 5);
        expect((await repo.title(id))!.fileCount, 6, reason: 'no hint: kept');

        // Reload keeps ids and watch, marks loaded again.
        await repo.upsertTitleFiles(id, seasons: show('S', eps: 4).seasons);
        expect(await repo.titleFilesLoaded(id), isTrue);
        expect(
          (await repo.seasons(id))
              .expand((s) => s.files)
              .map((f) => f.id)
              .take(3),
          ids.take(3),
        );
        expect((await repo.watchState(watched))!.positionMs, 5);
        expect((await repo.title(id))!.fileCount, 8);

        // Unknown mtime counts as changed.
        await repo.upsertTitle(show('S', loaded: false));
        expect(await repo.titleFilesLoaded(id), isFalse);
        expect(await rows('files'), 8);
      },
    );

    test(
      'skeleton re-crawl: unlisted season goes, its files with it',
      () async {
        final id = await repo.upsertTitle(show('S'));
        await repo.upsertTitle(show('S', loaded: false, only: [1]));
        expect((await repo.seasons(id)).length, 1);
        expect(await rows('files'), 3);
        expect((await repo.title(id))!.seasonCount, 1);
      },
    );

    test(
      'trimFileCache: LRU, stale first, watched and protected survive',
      () async {
        final ids = <int>[];
        for (var i = 0; i < 5; i++) {
          ids.add(
            await repo.upsertTitle(
              movie('T$i', files: ['a.mkv', 'b.mkv', 'c.mkv', 'd.mkv']),
            ),
          );
        }
        // Load order (oldest first): ids[2], ids[0], ids[1], ids[3], ids[4].
        var ts = 1700000000;
        for (final i in [2, 0, 1, 3, 4]) {
          await db.customStatement(
            'UPDATE titles SET files_loaded_at = ? WHERE id = ?',
            [ts++, ids[i]],
          );
        }
        // ids[3] stale (rows kept, not loaded): goes first.
        await db.customStatement(
          'UPDATE titles SET files_loaded_at = NULL WHERE id = ?',
          [ids[3]],
        );
        // ids[2] has a watch row; ids[0] is protected (download).
        await repo.setProgress(
          (await repo.titleFiles(ids[2])).first.id,
          positionMs: 1,
          durationMs: 100,
        );
        expect(await repo.trimFileCache(maxRows: 100), 0, reason: 'under cap');
        // 20 rows, cap 12: drop ids[3] (4), ids[1] (4); ids[4] stays.
        final n = await repo.trimFileCache(
          maxRows: 12,
          protectedTitleIds: {ids[0]},
        );
        expect(n, 8);
        expect(await rows('files'), 12);
        expect(await repo.titleFilesLoaded(ids[3]), isFalse);
        expect(await repo.titleFilesLoaded(ids[1]), isFalse);
        for (final i in [0, 2, 4]) {
          expect(await repo.titleFilesLoaded(ids[i]), isTrue);
          expect((await repo.titleFiles(ids[i])).length, 4);
        }
        // Counts survive eviction.
        expect((await repo.title(ids[1]))!.fileCount, 4);
        expect(await repo.titleFiles(ids[1]), isEmpty);
        // Nothing evictable left: stays above the cap instead of dropping
        // watched/protected titles.
        expect(
          await repo.trimFileCache(maxRows: 0, protectedTitleIds: {ids[0]}),
          4,
        );
        expect(await rows('files'), 8);
        expect(await repo.titleFilesLoaded(ids[2]), isTrue);
        expect(await repo.titleFilesLoaded(ids[0]), isTrue);
      },
    );

    test('evicted file ids are gone, reload mints new ones', () async {
      final a = await repo.upsertTitle(movie('A'));
      final fid = (await repo.titleFiles(a)).single.id;
      expect(await repo.trimFileCache(maxRows: 0), 1);
      expect(await repo.file(fid), isNull);
      expect(await repo.fileByUrl('${cat}A/Film.mkv'), isNull);
      await repo.upsertTitleFiles(a, files: [fd('${cat}A/', 'Film.mkv')]);
      expect((await repo.titleFiles(a)).single.id, greaterThan(fid));
    });

    test(
      'clearIndex parks watch by composed url; re-crawl restores it',
      () async {
        final id = await repo.upsertTitle(movie('Keep%20Me'));
        final f = (await repo.titleFiles(id)).single;
        await repo.setProgress(f.id, positionMs: 7, durationMs: 100);
        await repo.clearIndex();
        final keep = await db.customSelect('SELECT url FROM watch_keep').get();
        expect(keep.single.read<String>('url'), '${cat}Keep%20Me/Film.mkv');
        final m = await repo.upsertCategories(const [
          CategoryDraft(sourceHost: 'h', name: 'English', url: cat),
        ]);
        catId = m[cat]!;
        // Skeleton crawl: a stub row carries the watch state.
        final id2 = await repo.upsertTitle(movie('Keep%20Me', loaded: false));
        final stub = (await repo.fileByUrl('${cat}Keep%20Me/Film.mkv'))!;
        expect((await repo.watchState(stub.id))!.positionMs, 7);
        expect((await repo.continueWatching()).single.file.id, stub.id);
        expect(await rows('watch_keep'), 0);
        // Opening the title fills the stub in, same id.
        await repo.upsertTitleFiles(
          id2,
          files: [fd('${cat}Keep%20Me/', 'Film.mkv', size: 99)],
        );
        final loaded = (await repo.titleFiles(id2)).single;
        expect(loaded.id, stub.id);
        expect(loaded.sizeKb, 99);
        expect((await repo.watchState(loaded.id))!.positionMs, 7);
      },
    );

    test('full re-crawl re-attaches watch_keep to inserted files', () async {
      final id = await repo.upsertTitle(movie('K'));
      final f = (await repo.titleFiles(id)).single;
      await repo.setProgress(f.id, positionMs: 3, durationMs: 100);
      await repo.clearIndex();
      final m = await repo.upsertCategories(const [
        CategoryDraft(sourceHost: 'h', name: 'English', url: cat),
      ]);
      catId = m[cat]!;
      final id2 = await repo.upsertTitle(movie('K'));
      final f2 = (await repo.titleFiles(id2)).single;
      expect((await repo.watchState(f2.id))!.positionMs, 3);
      expect(await rows('watch_keep'), 0);
    });

    test('markTitleWatched skips unplayable (derived) files', () async {
      final id = await repo.upsertTitle(
        movie('W', files: ['a.mkv', 'b.mp4', 'c.rar']),
      );
      await repo.markTitleWatched(id);
      final fs = await repo.titleFiles(id);
      final st = await repo.watchStates(fs.map((f) => f.id));
      expect(
        {for (final f in fs) f.name: st[f.id]?.watched},
        {'a.mkv': true, 'b.mp4': true, 'c.rar': null},
      );
    });

    test('knownFolders / removeMissing use absolute urls', () async {
      await repo.upsertTitles([
        movie('A', mtime: DateTime.utc(2020)),
        movie('B', layout: '(2019)/'),
      ]);
      final known = await repo.knownFolders(catId);
      expect(known.keys.toSet(), {'${cat}A/', '$cat(2019)/B/'});
      expect(known['${cat}A/']!.toUtc(), DateTime.utc(2020));
      expect(await repo.removeMissing(catId, {'${cat}A/'}), 1);
      expect((await repo.knownFolders(catId)).keys, ['${cat}A/']);
    });

    test('same folder name in two categories is two titles', () async {
      final m = await repo.upsertCategories(const [
        CategoryDraft(sourceHost: 'h', name: 'Hindi', url: 'http://h/hi/'),
      ]);
      final a = await repo.upsertTitle(movie('Same'));
      final b = await repo.upsertTitle(
        TitleDraft(
          categoryId: m['http://h/hi/']!,
          name: 'Same',
          kind: TitleKind.movie,
          folderUrl: 'http://h/hi/Same/',
          filesLoaded: false,
        ),
      );
      expect(a, isNot(b));
      expect((await repo.title(b))!.folderUrl, 'http://h/hi/Same/');
    });

    test('titleIdForUrl / ensureFileByUrl work without file rows', () async {
      final id = await repo.upsertTitle(show('S', loaded: false));
      final m = await repo.upsertTitle(
        movie('Deep', layout: '(2019)/', loaded: false),
      );
      expect(await repo.titleIdForUrl('${cat}S/Season%202/e01.mkv'), id);
      expect(await repo.titleIdForUrl('$cat(2019)/Deep/x.mkv'), m);
      expect(await repo.titleIdForUrl('http://other/x.mkv'), isNull);
      expect(await repo.fileByUrl('${cat}S/Season%202/e01.mkv'), isNull);

      final f = (await repo.ensureFileByUrl('${cat}S/Season%202/e01.mkv'))!;
      expect(f.url, '${cat}S/Season%202/e01.mkv');
      expect(f.titleId, id);
      expect(f.seasonId, (await repo.seasons(id))[1].season.id);
      expect((await repo.ensureFileByUrl(f.url))!.id, f.id, reason: 'stable');
      expect(await repo.ensureFileByUrl('http://other/x.mkv'), isNull);
      // Watch it, then load the real list: same id, now with metadata.
      await repo.setProgress(f.id, positionMs: 9, durationMs: 100);
      await repo.upsertTitleFiles(id, seasons: show('S').seasons);
      final again = (await repo.fileByUrl(f.url))!;
      expect(again.id, f.id);
      expect(again.episode, 1);
      expect((await repo.watchState(f.id))!.positionMs, 9);
    });

    test('compact runs on an empty and a populated database', () async {
      await repo.compact();
      await repo.upsertTitle(movie('A'));
      await repo.compact();
    });
  });
}
