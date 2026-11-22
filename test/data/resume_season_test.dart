import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/ui/format.dart';

FileDraft _f(String name, int ep, String base) => FileDraft(
  name: name,
  url: '$base/$name',
  ext: 'mkv',
  playable: true,
  episode: ep,
  sizeKb: 100,
);

void main() {
  late DriftRepository repo;
  late int cat;
  setUp(() async {
    repo = DriftRepository.memory();
    final m = await repo.upsertCategories(const [
      CategoryDraft(
        sourceHost: '172.16.50.12',
        name: 'TV',
        url: 'http://h/tv/',
        language: 'English',
      ),
    ]);
    cat = m['http://h/tv/']!;
  });
  tearDown(() => repo.close());

  Future<int> show() => repo.upsertTitle(
    TitleDraft(
      categoryId: cat,
      name: 'Lupin',
      kind: TitleKind.series,
      folderUrl: 'http://h/tv/Lupin/',
      seasons: [
        SeasonDraft(
          number: 1,
          label: 'Season 1',
          folderUrl: 'http://h/tv/Lupin/S1/',
          // File names carry no season token, like the reported bug.
          files: [_f('Episode 1.mkv', 1, 'http://h/tv/Lupin/S1')],
        ),
        SeasonDraft(
          number: 2,
          label: 'Season 2',
          folderUrl: 'http://h/tv/Lupin/S2/',
          files: [_f('Episode 1.mkv', 1, 'http://h/tv/Lupin/S2')],
        ),
        SeasonDraft(
          number: 0,
          label: 'Specials',
          folderUrl: 'http://h/tv/Lupin/S0/',
          files: [_f('Episode 1.mkv', 1, 'http://h/tv/Lupin/S0')],
        ),
      ],
    ),
  );

  Future<ResumeItem> resumeFor(int titleId, int season) async {
    final eps = await repo.seasons(titleId);
    final file = eps.firstWhere((e) => e.season.number == season).files.single;
    await repo.setProgress(file.id, positionMs: 1000, durationMs: 10000);
    return (await repo.continueWatching()).single;
  }

  test('continueWatching carries the season number', () async {
    final id = await show();
    expect((await resumeFor(id, 2)).seasonNumber, 2);
  });

  test('a movie has no season number', () async {
    final id = await repo.upsertTitle(
      TitleDraft(
        categoryId: cat,
        name: 'Film',
        kind: TitleKind.movie,
        folderUrl: 'http://h/tv/Film/',
        files: [_f('Film.mkv', 0, 'http://h/tv/Film')],
      ),
    );
    final file = (await repo.titleFiles(id)).single;
    await repo.setProgress(file.id, positionMs: 1000, durationMs: 10000);
    expect((await repo.continueWatching()).single.seasonNumber, isNull);
  });

  test('resumeMeta uses the season folder, not the file name', () async {
    final id = await show();
    final it = await resumeFor(id, 2);
    expect(it.file.name, 'Episode 1.mkv'); // no S02 token in the name
    expect(resumeMeta(it), startsWith('S02 · E01'));
  });

  test('resumeMeta: specials and file-name fallback', () async {
    final id = await show();
    expect(resumeMeta(await resumeFor(id, 0)), startsWith('Specials · E01'));
    // No season number from the repository: fall back to the file name.
    final base = await resumeFor(id, 1);
    final noSeason = ResumeItem(
      title: base.title,
      file: MediaFile(
        id: base.file.id,
        titleId: base.file.titleId,
        seasonId: base.file.seasonId,
        name: 'Lupin.S03E04.mkv',
        url: 'u',
        ext: 'mkv',
        playable: true,
        episode: 4,
      ),
      state: base.state,
    );
    expect(resumeMeta(noSeason), startsWith('S03 · E04'));

    // Unparsed season folder (number 0) but the file name says S03.
    final unparsed = ResumeItem(
      title: base.title,
      file: noSeason.file,
      state: base.state,
      seasonNumber: 0,
    );
    expect(resumeMeta(unparsed), startsWith('S03 · E04'));
  });
}
