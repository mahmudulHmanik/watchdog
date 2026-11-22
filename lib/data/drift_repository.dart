/// drift/SQLite implementation of [Repository]. drift types stay in here.
library;

import '../tmdb/tmdb_models.dart';

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';
import 'filter_sql.dart';
import 'models.dart';
import 'repository.dart';
import 'search/engine.dart';

/// Facet methods (years/languages/qualities) apply `within` but ignore that
/// facet's own selection, so a picker still shows the alternatives.
class DriftRepository implements Repository {
  DriftRepository(this._db);

  /// In-memory database for tests.
  DriftRepository.memory() : _db = AppDatabase.memory();

  final AppDatabase _db;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  Future<void> close() async {
    await _changes.close();
    await _db.close();
  }

  // ---------------------------------------------------------------- mapping

  MediaTitle _title(TitleRow r) => MediaTitle(
    id: r.id,
    categoryId: r.categoryId,
    name: r.name,
    kind: r.kind,
    folderUrl: r.folderUrl,
    year: r.year,
    yearEnd: r.yearEnd,
    quality: r.quality,
    tags: (jsonDecode(r.tags) as List).cast<String>(),
    posterUrl: r.posterUrl,
    language: r.language,
    folderMtime: r.folderMtime,
    addedAt: r.addedAt,
    seasonCount: r.seasonCount,
    fileCount: r.fileCount,
  );

  MediaFile _file(FileRow r) => MediaFile(
    id: r.id,
    titleId: r.titleId,
    seasonId: r.seasonId,
    name: r.name,
    url: r.url,
    ext: r.ext,
    playable: r.playable,
    episode: r.episode,
    episodeEnd: r.episodeEnd,
    sizeKb: r.sizeKb,
    mtime: r.mtime,
  );

  WatchState _watch(WatchRow r) => WatchState(
    fileId: r.fileId,
    positionMs: r.positionMs,
    durationMs: r.durationMs,
    watched: r.watched,
    updatedAt: r.updatedAt,
  );

  // ----------------------------------------------------------------- browse

  @override
  Future<List<Category>> categories() async {
    final cnt = countAll();
    final counts =
        await (_db.selectOnly(_db.titles)
              ..addColumns([_db.titles.categoryId, cnt])
              ..groupBy([_db.titles.categoryId]))
            .get();
    final byCat = {
      for (final r in counts) r.read(_db.titles.categoryId)!: r.read(cnt)!,
    };
    final rows = await (_db.select(
      _db.categories,
    )..orderBy([(c) => OrderingTerm.asc(c.id)])).get();
    return [
      for (final c in rows)
        Category(
          id: c.id,
          sourceId: c.sourceId,
          name: c.name,
          url: c.url,
          language: c.language,
          titleCount: byCat[c.id] ?? 0,
        ),
    ];
  }

  /// Typed twin of [filterSql]; [skip] drops one facet (for facet counts).
  Expression<bool> _where($TitlesTable t, BrowseFilter f, {Facet? skip}) {
    Expression<bool> e = const Constant(true);
    if (f.categoryId != null) e = e & t.categoryId.equals(f.categoryId!);
    if (skip != Facet.year && f.hasYearFilter) {
      Expression<bool> y = const Constant(false);
      if (f.years.isNotEmpty) y = y | t.year.isIn(f.years);
      for (final r in f.yearRanges) {
        Expression<bool> c = t.year.isNotNull();
        if (r.from != null) c = c & t.year.isBiggerOrEqualValue(r.from!);
        if (r.to != null) c = c & t.year.isSmallerOrEqualValue(r.to!);
        y = y | c;
      }
      e = e & y;
    }
    if (skip != Facet.language && f.languages.isNotEmpty) {
      e = e & t.language.isIn(f.languages);
    }
    if (skip != Facet.quality && f.qualities.isNotEmpty) {
      e = e & t.quality.isIn(f.qualities);
    }
    if (f.kind != null) e = e & t.kind.equals(f.kind!.index);
    if (skip != Facet.genre && f.genreIds.isNotEmpty) {
      final g = _db.titleGenres;
      e =
          e &
          t.id.isInQuery(
            _db.selectOnly(g)
              ..addColumns([g.titleId])
              ..where(g.genreId.isIn(f.genreIds)),
          );
    }
    final m = _db.tmdbMeta;
    Expression<bool> me = const Constant(true);
    var metaUsed = false;
    if (f.minRating != null) {
      me = me & m.rating.isBiggerOrEqualValue(f.minRating!);
      metaUsed = true;
    }
    if (skip != Facet.tmdbLanguage && f.originalLanguages.isNotEmpty) {
      me = me & m.originalLanguage.isIn(f.originalLanguages);
      metaUsed = true;
    }
    if (f.runtimes.isNotEmpty) {
      Expression<bool> r = const Constant(false);
      for (final b in f.runtimes) {
        Expression<bool> c = const Constant(true);
        if (b.minMinutes != null) {
          c = c & m.runtime.isBiggerOrEqualValue(b.minMinutes!);
        }
        if (b.maxMinutes != null) {
          c = c & m.runtime.isSmallerThanValue(b.maxMinutes!);
        }
        r = r | c;
      }
      me = me & r;
      metaUsed = true;
    }
    if (metaUsed) {
      e =
          e &
          t.id.isInQuery(
            _db.selectOnly(m)
              ..addColumns([m.titleId])
              ..where(me),
          );
    }
    if (f.personId != null) {
      final c = _db.titleCast;
      e =
          e &
          t.id.isInQuery(
            _db.selectOnly(c)
              ..addColumns([c.titleId])
              ..where(c.personId.equals(f.personId!)),
          );
    }
    return e;
  }

  List<OrderingTerm Function($TitlesTable)> _order(BrowseSort s) => switch (s) {
    BrowseSort.nameAsc => [
      (t) => OrderingTerm.asc(t.sortKey),
      (t) => OrderingTerm.asc(t.id),
    ],
    BrowseSort.yearDesc => [
      (t) => OrderingTerm(
        expression: t.year,
        mode: OrderingMode.desc,
        nulls: NullsOrder.last,
      ),
      (t) => OrderingTerm.asc(t.sortKey),
      (t) => OrderingTerm.asc(t.id),
    ],
    BrowseSort.recentlyAdded => [
      (t) => OrderingTerm.desc(t.addedAt),
      (t) => OrderingTerm.desc(t.id),
    ],
  };

  @override
  Future<List<MediaTitle>> browse(
    BrowseFilter filter, {
    int offset = 0,
    int limit = 50,
  }) async {
    final q = _db.select(_db.titles)
      ..where((t) => _where(t, filter))
      ..orderBy(_order(filter.sort))
      ..limit(limit, offset: offset);
    return (await q.get()).map(_title).toList();
  }

  @override
  Future<int> countTitles([BrowseFilter filter = const BrowseFilter()]) async {
    final c = countAll();
    final q = _db.selectOnly(_db.titles)
      ..addColumns([c])
      ..where(_where(_db.titles, filter));
    return (await q.getSingle()).read(c)!;
  }

  Future<List<FacetValue<T>>> _facet<T extends Object>(
    GeneratedColumn<T> col,
    Facet facet,
    BrowseFilter within,
    OrderingTerm order,
  ) async {
    final c = countAll();
    final q = _db.selectOnly(_db.titles)
      ..addColumns([col, c])
      ..where(_where(_db.titles, within, skip: facet) & col.isNotNull())
      ..groupBy([col])
      ..orderBy([order]);
    return [
      for (final r in await q.get()) FacetValue<T>(r.read(col)!, r.read(c)!),
    ];
  }

  @override
  Future<List<FacetValue<int>>> years([
    BrowseFilter within = const BrowseFilter(),
  ]) => _facet(
    _db.titles.year,
    Facet.year,
    within,
    OrderingTerm.desc(_db.titles.year),
  );

  @override
  Future<List<FacetValue<String>>> languages([
    BrowseFilter within = const BrowseFilter(),
  ]) => _facet(
    _db.titles.language,
    Facet.language,
    within,
    OrderingTerm.asc(_db.titles.language),
  );

  @override
  Future<List<FacetValue<int>>> qualities([
    BrowseFilter within = const BrowseFilter(),
  ]) => _facet(
    _db.titles.quality,
    Facet.quality,
    within,
    OrderingTerm.desc(_db.titles.quality),
  );

  @override
  Future<List<FacetValue<TmdbGenre>>> genres([
    BrowseFilter within = const BrowseFilter(),
  ]) async {
    final fs = filterSql(within, skip: Facet.genre);
    final rows = await _db
        .customSelect(
          'SELECT g.id AS id, g.name AS name, COUNT(*) AS n FROM title_genres tg '
          'JOIN tmdb_genres g ON g.id = tg.genre_id '
          // Unfiltered: count straight off the genre index, no titles join.
          '${fs.cond.isEmpty ? '' : 'JOIN titles t ON t.id = tg.title_id'} '
          '${fs.cond.isEmpty ? '' : 'WHERE ${fs.cond.join(' AND ')}'} '
          'GROUP BY g.id ORDER BY n DESC, g.name, g.id',
          variables: fs.vars,
        )
        .get();
    return [
      for (final r in rows)
        FacetValue(
          TmdbGenre(r.read<int>('id'), r.read<String>('name')),
          r.read<int>('n'),
        ),
    ];
  }

  @override
  Future<List<FacetValue<String>>> tmdbLanguages([
    BrowseFilter within = const BrowseFilter(),
  ]) async {
    final fs = filterSql(within, skip: Facet.tmdbLanguage);
    final rows = await _db
        .customSelect(
          'SELECT m.original_language AS lang, COUNT(*) AS n FROM tmdb_meta m '
          '${fs.cond.isEmpty ? '' : 'JOIN titles t ON t.id = m.title_id'} '
          'WHERE m.original_language IS NOT NULL'
          '${fs.cond.isEmpty ? '' : ' AND ${fs.cond.join(' AND ')}'} '
          'GROUP BY m.original_language ORDER BY n DESC, m.original_language',
          variables: fs.vars,
        )
        .get();
    return [
      for (final r in rows)
        FacetValue(r.read<String>('lang'), r.read<int>('n')),
    ];
  }

  // ----------------------------------------------------------------- people

  static String _esc(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  static const _castCount =
      '(SELECT COUNT(*) FROM title_cast c WHERE c.person_id = p.id)';

  PersonHit _person(QueryRow r) => PersonHit(
    id: r.read<int>('id'),
    name: r.read<String>('name'),
    profilePath: r.readNullable<String>('profile_path'),
    titleCount: r.read<int>('n'),
  );

  /// Ranking: exact name, then name prefix, then a word prefix, then any
  /// substring; ties by number of library titles, then name. Only people in
  /// at least one title are returned. 1-2 char tokens use LIKE (trigram FTS
  /// cannot match them), longer ones FTS5 phrases AND-ed together.
  @override
  Future<List<PersonHit>> searchPeople(String query, {int limit = 8}) async {
    final norm = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (norm.isEmpty || limit <= 0) return const [];
    final toks = norm.split(' ');
    final long = [
      for (final t in toks)
        if (t.length >= 3) t,
    ];
    final short = [
      for (final t in toks)
        if (t.length < 3) t,
    ];
    final cond = <String>[];
    final vars = <Variable>[];
    if (long.isNotEmpty) {
      cond.add('people_fts MATCH ?');
      vars.add(
        Variable<String>(
          long.map((t) => '"${t.replaceAll('"', '""')}"').join(' AND '),
        ),
      );
    }
    for (final t in short) {
      cond.add("lower(p.name) LIKE ? ESCAPE '\\'");
      vars.add(Variable<String>('%${_esc(t)}%'));
    }
    final from = long.isNotEmpty
        ? 'people_fts JOIN tmdb_people p ON p.id = people_fts.rowid'
        : 'tmdb_people p';
    // Inner: candidates with name class (lower() once) and cast count; outer:
    // drop people in no title, rank, limit.
    final rows = await _db
        .customSelect(
          'SELECT id, name, profile_path, n FROM ('
          'SELECT p.id AS id, p.name AS name, p.profile_path AS profile_path, '
          'lower(p.name) AS ln, $_castCount AS n FROM $from '
          'WHERE ${cond.join(' AND ')}) '
          'WHERE n > 0 '
          "ORDER BY CASE WHEN ln = ? THEN 0 WHEN ln LIKE ? ESCAPE '\\' THEN 1 "
          "WHEN ln LIKE ? ESCAPE '\\' THEN 2 ELSE 3 END, "
          'n DESC, name, id LIMIT ?',
          variables: [
            ...vars,
            Variable<String>(norm),
            Variable<String>('${_esc(norm)}%'),
            Variable<String>('% ${_esc(norm)}%'),
            Variable<int>(limit),
          ],
        )
        .get();
    return rows.map(_person).toList();
  }

  @override
  Future<PersonHit?> person(int id) async {
    final rows = await _db
        .customSelect(
          'SELECT p.id AS id, p.name AS name, p.profile_path AS profile_path, '
          '$_castCount AS n FROM tmdb_people p WHERE p.id = ?',
          variables: [Variable<int>(id)],
        )
        .get();
    return rows.isEmpty ? null : _person(rows.first);
  }

  // ----------------------------------------------------------------- detail

  @override
  Future<MediaTitle?> title(int id) async {
    final r = await (_db.select(
      _db.titles,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _title(r);
  }

  @override
  Future<List<MediaTitle>> titlesByIds(List<int> ids) async {
    final byId = <int, MediaTitle>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final rows = await (_db.select(
        _db.titles,
      )..where((t) => t.id.isIn(chunk))).get();
      for (final r in rows) {
        byId[r.id] = _title(r);
      }
    }
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  static int? _secs(DateTime? d) =>
      d == null ? null : d.millisecondsSinceEpoch ~/ 1000;

  static int _cmpFiles(MediaFile a, MediaFile b) {
    final ea = a.episode ?? 1 << 30, eb = b.episode ?? 1 << 30;
    if (ea != eb) return ea.compareTo(eb);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  @override
  Future<List<SeasonEpisodes>> seasons(int titleId) async {
    final ss =
        await (_db.select(_db.seasons)
              ..where((s) => s.titleId.equals(titleId))
              ..orderBy([
                (s) => OrderingTerm.asc(s.number),
                (s) => OrderingTerm.asc(s.ord),
                (s) => OrderingTerm.asc(s.id),
              ]))
            .get();
    final fs = await (_db.select(
      _db.files,
    )..where((f) => f.titleId.equals(titleId) & f.seasonId.isNotNull())).get();
    final bySeason = <int, List<MediaFile>>{};
    for (final f in fs) {
      (bySeason[f.seasonId!] ??= []).add(_file(f));
    }
    return [
      for (final s in ss)
        SeasonEpisodes(
          season: Season(
            id: s.id,
            titleId: s.titleId,
            number: s.number,
            label: s.label,
            language: s.language,
            folderUrl: s.folderUrl,
            episodeCount: bySeason[s.id]?.length ?? 0,
          ),
          files: (bySeason[s.id] ?? const <MediaFile>[])..sort(_cmpFiles),
        ),
    ];
  }

  @override
  Future<List<MediaFile>> titleFiles(int titleId) async {
    final fs = await (_db.select(
      _db.files,
    )..where((f) => f.titleId.equals(titleId) & f.seasonId.isNull())).get();
    return fs.map(_file).toList()..sort(_cmpFiles);
  }

  @override
  Future<MediaFile?> file(int id) async {
    final r = await (_db.select(
      _db.files,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    return r == null ? null : _file(r);
  }

  @override
  Future<MediaFile?> fileByUrl(String url) async {
    final r = await (_db.select(
      _db.files,
    )..where((f) => f.url.equals(url))).getSingleOrNull();
    return r == null ? null : _file(r);
  }

  @override
  Future<MediaFile?> nextEpisode(int fileId) async {
    final f = await file(fileId);
    if (f == null || f.seasonId == null) return null;
    final all = await seasons(f.titleId);
    final cur = all.where((s) => s.season.id == f.seasonId).firstOrNull;
    if (cur == null) return null;
    final lang = cur.season.language;
    final flat = [
      for (final s in all)
        if (s.season.language == lang) ...s.files,
    ];
    final i = flat.indexWhere((x) => x.id == fileId);
    if (i < 0) return null;
    for (var j = i + 1; j < flat.length; j++) {
      if (flat[j].playable) return flat[j];
    }
    return null;
  }

  // ---------------------------------------------------------------- search

  /// Typo-tolerant search; see lib/data/search/engine.dart for the pipeline
  /// and the paging limits (paging is on the re-ranked list).
  @override
  Future<List<MediaTitle>> search(
    String query, {
    BrowseFilter filter = const BrowseFilter(),
    int offset = 0,
    int limit = 50,
  }) async {
    if (query.trim().isEmpty) {
      return browse(filter, offset: offset, limit: limit);
    }
    final ids = await SearchEngine(_db)
        .searchIds(query, filter: filter, offset: offset, limit: limit);
    return titlesByIds(ids);
  }

  // ------------------------------------------------------------------ watch

  @override
  Future<WatchState?> watchState(int fileId) async {
    final r = await (_db.select(
      _db.watch,
    )..where((w) => w.fileId.equals(fileId))).getSingleOrNull();
    return r == null ? null : _watch(r);
  }

  @override
  Future<Map<int, WatchState>> watchStates(Iterable<int> fileIds) async {
    final ids = fileIds.toList();
    final out = <int, WatchState>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final rows = await (_db.select(
        _db.watch,
      )..where((w) => w.fileId.isIn(chunk))).get();
      for (final r in rows) {
        out[r.fileId] = _watch(r);
      }
    }
    return out;
  }

  Future<bool> _fileExists(int id) async =>
      await (_db.select(
        _db.files,
      )..where((f) => f.id.equals(id))).getSingleOrNull() !=
      null;

  @override
  Future<void> setProgress(
    int fileId, {
    required int positionMs,
    required int durationMs,
  }) async {
    if (!await _fileExists(fileId)) return;
    final prev = await watchState(fileId);
    final done = durationMs > 0 && positionMs / durationMs >= 0.9;
    await _db
        .into(_db.watch)
        .insertOnConflictUpdate(
          WatchCompanion.insert(
            fileId: Value(fileId),
            positionMs: Value(positionMs),
            durationMs: Value(durationMs),
            watched: Value(done || (prev?.watched ?? false)),
            updatedAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> markWatched(int fileId, {bool watched = true}) async {
    if (!await _fileExists(fileId)) return;
    final prev = await watchState(fileId);
    await _db
        .into(_db.watch)
        .insertOnConflictUpdate(
          WatchCompanion.insert(
            fileId: Value(fileId),
            positionMs: Value(watched ? (prev?.positionMs ?? 0) : 0),
            durationMs: Value(prev?.durationMs ?? 0),
            watched: Value(watched),
            updatedAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> markTitleWatched(
    int titleId, {
    int? seasonId,
    bool watched = true,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final w = watched ? 1 : 0;
    await _db.customStatement(
      'INSERT INTO watch (file_id, position_ms, duration_ms, watched, updated_at) '
      'SELECT id, 0, 0, ?, ? FROM files WHERE title_id = ? AND playable = 1'
      '${seasonId == null ? '' : ' AND season_id = ?'} '
      'ON CONFLICT(file_id) DO UPDATE SET watched = excluded.watched, '
      'position_ms = CASE WHEN excluded.watched = 1 THEN position_ms ELSE 0 END, '
      'updated_at = excluded.updated_at',
      [w, now, titleId, ?seasonId],
    );
  }

  @override
  Future<List<ResumeItem>> continueWatching({int limit = 20}) async {
    final w = _db.watch, f = _db.files, t = _db.titles;
    final q =
        _db.select(w).join([
            innerJoin(f, f.id.equalsExp(w.fileId)),
            innerJoin(t, t.id.equalsExp(f.titleId)),
          ])
          ..where(w.positionMs.isBiggerThanValue(0) & w.watched.equals(false))
          ..orderBy([OrderingTerm.desc(w.updatedAt)]);
    final seen = <int>{};
    final out = <ResumeItem>[];
    for (final r in await q.get()) {
      final tr = r.readTable(t);
      if (!seen.add(tr.id)) continue;
      out.add(
        ResumeItem(
          title: _title(tr),
          file: _file(r.readTable(f)),
          state: _watch(r.readTable(w)),
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---------------------------------------------------------------- crawler

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<Map<String, int>> upsertCategories(
    List<CategoryDraft> categories,
  ) async {
    final out = <String, int>{};
    await _db.transaction(() async {
      for (final c in categories) {
        await _db
            .into(_db.sources)
            .insert(
              SourcesCompanion.insert(host: c.sourceHost),
              mode: InsertMode.insertOrIgnore,
            );
        final src = await (_db.select(
          _db.sources,
        )..where((s) => s.host.equals(c.sourceHost))).getSingle();
        final ex = await (_db.select(
          _db.categories,
        )..where((x) => x.url.equals(c.url))).getSingleOrNull();
        if (ex == null) {
          out[c.url] = await _db
              .into(_db.categories)
              .insert(
                CategoriesCompanion.insert(
                  sourceId: src.id,
                  name: c.name,
                  url: c.url,
                  language: Value(c.language),
                ),
              );
        } else {
          await (_db.update(
            _db.categories,
          )..where((x) => x.id.equals(ex.id))).write(
            CategoriesCompanion(
              sourceId: Value(src.id),
              name: ex.name == c.name ? const Value.absent() : Value(c.name),
              language: Value(c.language),
            ),
          );
          if (ex.language != c.language) {
            await (_db.update(_db.titles)
                  ..where((t) => t.categoryId.equals(ex.id)))
                .write(TitlesCompanion(language: Value(c.language)));
          }
          out[c.url] = ex.id;
        }
      }
    });
    _emit();
    return out;
  }

  @override
  Future<int> upsertTitle(TitleDraft draft) async {
    draft.validate();
    final id = await _db.transaction(() => _upsert(draft, _hasKeep()));
    _emit();
    return id;
  }

  @override
  Future<void> upsertTitles(List<TitleDraft> drafts) async {
    for (final d in drafts) {
      d.validate();
    }
    await _db.transaction(() async {
      final keep = await _hasKeep();
      for (final d in drafts) {
        await _upsert(d, Future.value(keep));
      }
    });
    _emit();
  }

  Future<bool> _hasKeep() async {
    final c = countAll();
    final q = _db.selectOnly(_db.watchKeep)..addColumns([c]);
    return (await q.getSingle()).read(c)! > 0;
  }

  Future<int> _upsert(TitleDraft d, Future<bool> hasKeepF) async {
    final cat = await (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(d.categoryId))).getSingleOrNull();
    if (cat == null) {
      throw ArgumentError('unknown categoryId ${d.categoryId} for "${d.name}"');
    }
    final seasonDrafts = d.seasons;
    final fileTotal = d.kind == TitleKind.series
        ? seasonDrafts.fold<int>(0, (a, s) => a + s.files.length)
        : d.files.length;
    final tags = jsonEncode(d.tags);

    final ex = await (_db.select(
      _db.titles,
    )..where((t) => t.folderUrl.equals(d.folderUrl))).getSingleOrNull();
    final int id;
    if (ex == null) {
      id = await _db
          .into(_db.titles)
          .insert(
            TitlesCompanion.insert(
              categoryId: d.categoryId,
              name: d.name,
              sortKey: d.name.toLowerCase(),
              kind: d.kind,
              folderUrl: d.folderUrl,
              year: Value(d.year),
              yearEnd: Value(d.yearEnd),
              quality: Value(d.quality),
              tags: Value(tags),
              posterUrl: Value(d.posterUrl),
              language: Value(cat.language),
              folderMtime: Value(d.folderMtime),
              addedAt: DateTime.now(),
              seasonCount: Value(seasonDrafts.length),
              fileCount: Value(fileTotal),
            ),
          );
    } else {
      id = ex.id;
      await (_db.update(_db.titles)..where((t) => t.id.equals(id))).write(
        TitlesCompanion(
          // Name/category only when changed: avoids needless FTS rewrites.
          categoryId: ex.categoryId == d.categoryId
              ? const Value.absent()
              : Value(d.categoryId),
          name: ex.name == d.name ? const Value.absent() : Value(d.name),
          sortKey: Value(d.name.toLowerCase()),
          kind: Value(d.kind),
          year: Value(d.year),
          yearEnd: Value(d.yearEnd),
          quality: Value(d.quality),
          tags: Value(tags),
          posterUrl: Value(d.posterUrl),
          language: Value(cat.language),
          folderMtime: Value(d.folderMtime),
          seasonCount: Value(seasonDrafts.length),
          fileCount: Value(fileTotal),
        ),
      );
    }

    // Seasons: match by identity, keep ids.
    final exSeasons = ex == null
        ? <SeasonRow>[]
        : await (_db.select(
            _db.seasons,
          )..where((s) => s.titleId.equals(id))).get();
    final used = <int>{};
    final seasonIds = <int>[];
    for (var i = 0; i < seasonDrafts.length; i++) {
      final sd = seasonDrafts[i];
      SeasonRow? m;
      for (final e in exSeasons) {
        if (used.contains(e.id)) continue;
        final same = sd.folderUrl != null
            ? e.folderUrl == sd.folderUrl
            : e.folderUrl == null &&
                  e.number == sd.number &&
                  e.language == sd.language &&
                  e.label == sd.label;
        if (same) {
          m = e;
          break;
        }
      }
      if (m != null) {
        used.add(m.id);
        seasonIds.add(m.id);
        await (_db.update(_db.seasons)..where((s) => s.id.equals(m!.id))).write(
          SeasonsCompanion(
            number: Value(sd.number),
            label: Value(sd.label),
            language: Value(sd.language),
            folderUrl: Value(sd.folderUrl),
            ord: Value(i),
          ),
        );
      } else {
        seasonIds.add(
          await _db
              .into(_db.seasons)
              .insert(
                SeasonsCompanion.insert(
                  titleId: id,
                  number: sd.number,
                  label: sd.label,
                  language: Value(sd.language),
                  folderUrl: Value(sd.folderUrl),
                  ord: Value(i),
                ),
              ),
        );
      }
    }

    // Files: identity = url.
    final exFiles = ex == null
        ? <String, FileRow>{}
        : {
            for (final f in await (_db.select(
              _db.files,
            )..where((f) => f.titleId.equals(id))).get())
              f.url: f,
          };
    final pairs = <(int?, FileDraft)>[
      if (d.kind == TitleKind.series)
        for (var i = 0; i < seasonDrafts.length; i++)
          for (final f in seasonDrafts[i].files) (seasonIds[i], f)
      else
        for (final f in d.files) (null, f),
    ];
    final seenUrls = <String>{};
    final inserts = <FilesCompanion>[];
    final updates = <(int, FilesCompanion)>[];
    for (final (sid, f) in pairs) {
      if (!seenUrls.add(f.url)) continue;
      final e = exFiles[f.url];
      if (e == null) {
        inserts.add(
          FilesCompanion.insert(
            titleId: id,
            seasonId: Value(sid),
            name: f.name,
            url: f.url,
            ext: f.ext,
            playable: f.playable,
            episode: Value(f.episode),
            episodeEnd: Value(f.episodeEnd),
            sizeKb: Value(f.sizeKb),
            mtime: Value(f.mtime),
          ),
        );
      } else if (e.seasonId != sid ||
          e.name != f.name ||
          e.ext != f.ext ||
          e.playable != f.playable ||
          e.episode != f.episode ||
          e.episodeEnd != f.episodeEnd ||
          e.sizeKb != f.sizeKb ||
          _secs(e.mtime) != _secs(f.mtime)) {
        updates.add((
          e.id,
          FilesCompanion(
            seasonId: Value(sid),
            name: Value(f.name),
            ext: Value(f.ext),
            playable: Value(f.playable),
            episode: Value(f.episode),
            episodeEnd: Value(f.episodeEnd),
            sizeKb: Value(f.sizeKb),
            mtime: Value(f.mtime),
          ),
        ));
      }
    }
    final gone = [
      for (final e in exFiles.values)
        if (!seenUrls.contains(e.url)) e.id,
    ];
    if (inserts.isNotEmpty || updates.isNotEmpty) {
      await _db.batch((b) {
        b.insertAll(_db.files, inserts);
        for (final (fid, c) in updates) {
          b.update(_db.files, c, where: (f) => f.id.equals(fid));
        }
      });
    }
    for (var i = 0; i < gone.length; i += 500) {
      final chunk = gone.sublist(
        i,
        i + 500 > gone.length ? gone.length : i + 500,
      );
      await (_db.delete(_db.files)..where((f) => f.id.isIn(chunk))).go();
    }
    // Unmatched old seasons last, once no file references them.
    for (final e in exSeasons) {
      if (!used.contains(e.id)) {
        await (_db.delete(_db.seasons)..where((s) => s.id.equals(e.id))).go();
      }
    }

    if (inserts.isNotEmpty && await hasKeepF) {
      await _db.customStatement(
        'INSERT OR IGNORE INTO watch (file_id, position_ms, duration_ms, watched, updated_at) '
        'SELECT f.id, k.position_ms, k.duration_ms, k.watched, k.updated_at '
        'FROM watch_keep k JOIN files f ON f.url = k.url WHERE f.title_id = ?',
        [id],
      );
      await _db.customStatement(
        'DELETE FROM watch_keep WHERE url IN (SELECT url FROM files WHERE title_id = ?)',
        [id],
      );
    }
    return id;
  }

  @override
  Future<Map<String, DateTime?>> knownFolders(int categoryId) async {
    final rows =
        await (_db.selectOnly(_db.titles)
              ..addColumns([_db.titles.folderUrl, _db.titles.folderMtime])
              ..where(_db.titles.categoryId.equals(categoryId)))
            .get();
    return {
      for (final r in rows)
        r.read(_db.titles.folderUrl)!: r.read(_db.titles.folderMtime),
    };
  }

  @override
  Future<int> removeMissing(int categoryId, Set<String> keep) async {
    final rows = await (_db.select(
      _db.titles,
    )..where((t) => t.categoryId.equals(categoryId))).get();
    final drop = [
      for (final r in rows)
        if (!keep.contains(r.folderUrl)) r.id,
    ];
    for (var i = 0; i < drop.length; i += 500) {
      final chunk = drop.sublist(
        i,
        i + 500 > drop.length ? drop.length : i + 500,
      );
      await (_db.delete(_db.titles)..where((t) => t.id.isIn(chunk))).go();
    }
    if (drop.isNotEmpty) {
      await _dropTmdbOrphans();
      _emit();
    }
    return drop.length;
  }

  @override
  Future<void> clearIndex({bool includeWatch = false}) async {
    await _db.transaction(() async {
      await _db.delete(_db.watchKeep).go();
      if (!includeWatch) {
        await _db.customStatement(
          'INSERT OR REPLACE INTO watch_keep (url, position_ms, duration_ms, watched, updated_at) '
          'SELECT f.url, w.position_ms, w.duration_ms, w.watched, w.updated_at '
          'FROM watch w JOIN files f ON f.id = w.file_id',
        );
      }
      await _db.delete(_db.watch).go();
      await _db.delete(_db.titles).go(); // cascades seasons, files, fts, tmdb
      // Shared rows have no cascade; nothing references them any more.
      await _db.delete(_db.tmdbGenres).go();
      await _db.delete(_db.tmdbPeople).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.sources).go();
    });
    _emit();
  }

  // ------------------------------------------------------------------- TMDB

  static const _tmdbKinds = '0, 1'; // TitleKind.movie, TitleKind.series

  @override
  Future<TmdbInfo?> tmdbInfo(int titleId) async {
    final m = await (_db.select(
      _db.tmdbMeta,
    )..where((r) => r.titleId.equals(titleId))).getSingleOrNull();
    if (m == null) return null;
    final g = await _db
        .customSelect(
          'SELECT g.id AS id, g.name AS name FROM title_genres tg '
          'JOIN tmdb_genres g ON g.id = tg.genre_id WHERE tg.title_id = ? '
          'ORDER BY tg.rowid',
          variables: [Variable<int>(titleId)],
        )
        .get();
    final c = await _db
        .customSelect(
          'SELECT p.id AS id, p.name AS name, p.profile_path AS profile_path, '
          'tc.ord AS ord, tc.character AS character FROM title_cast tc '
          'JOIN tmdb_people p ON p.id = tc.person_id WHERE tc.title_id = ? '
          'ORDER BY tc.ord, tc.rowid',
          variables: [Variable<int>(titleId)],
        )
        .get();
    return TmdbInfo(
      titleId: m.titleId,
      status: m.status,
      fetchedAt: m.fetchedAt,
      tmdbId: m.tmdbId,
      mediaType: TmdbMediaType.values
          .where((t) => t.name == m.mediaType)
          .firstOrNull,
      overview: m.overview,
      tagline: m.tagline,
      rating: m.rating,
      voteCount: m.voteCount,
      runtime: m.runtime,
      originalLanguage: m.originalLanguage,
      releaseYear: m.releaseYear,
      posterPath: m.posterPath,
      backdropPath: m.backdropPath,
      genres: [
        for (final r in g) TmdbGenre(r.read<int>('id'), r.read<String>('name')),
      ],
      cast: [
        for (final r in c)
          TmdbCastMember(
            personId: r.read<int>('id'),
            name: r.read<String>('name'),
            character: r.readNullable<String>('character'),
            order: r.read<int>('ord'),
            profilePath: r.readNullable<String>('profile_path'),
          ),
      ],
    );
  }

  Future<bool> _titleExists(int id) async {
    final c = countAll();
    final q = _db.selectOnly(_db.titles)
      ..addColumns([c])
      ..where(_db.titles.id.equals(id));
    return (await q.getSingle()).read(c)! > 0;
  }

  /// Drops people/genres no title references any more (cheap: index probes).
  Future<void> _dropTmdbOrphans() async {
    await _db.customStatement(
      'DELETE FROM tmdb_people WHERE NOT EXISTS '
      '(SELECT 1 FROM title_cast c WHERE c.person_id = tmdb_people.id)',
    );
    await _db.customStatement(
      'DELETE FROM tmdb_genres WHERE NOT EXISTS '
      '(SELECT 1 FROM title_genres g WHERE g.genre_id = tmdb_genres.id)',
    );
  }

  @override
  Future<void> saveTmdbMatch(
    int titleId,
    TmdbDetails d, {
    bool manual = false,
  }) async {
    final wrote = await _db.transaction(() async {
      if (!await _titleExists(titleId)) return false;
      if (!manual) {
        final ex = await (_db.select(
          _db.tmdbMeta,
        )..where((r) => r.titleId.equals(titleId))).getSingleOrNull();
        if (ex?.status == TmdbStatus.manual) return false;
      }
      await _db
          .into(_db.tmdbMeta)
          .insertOnConflictUpdate(
            TmdbMetaCompanion.insert(
              titleId: Value(titleId),
              status: manual ? TmdbStatus.manual : TmdbStatus.matched,
              tmdbId: Value(d.id),
              mediaType: Value(d.mediaType.name),
              overview: Value(d.overview),
              tagline: Value(d.tagline),
              rating: Value(d.rating),
              voteCount: Value(d.voteCount),
              runtime: Value(d.runtime),
              originalLanguage: Value(d.originalLanguage),
              releaseYear: Value(d.year),
              posterPath: Value(d.posterPath),
              backdropPath: Value(d.backdropPath),
              fetchedAt: DateTime.now(),
            ),
          );
      final oldGenres = [
        for (final r
            in await _db
                .customSelect(
                  'SELECT genre_id AS id FROM title_genres WHERE title_id = ?',
                  variables: [Variable<int>(titleId)],
                )
                .get())
          r.read<int>('id'),
      ];
      final oldPeople = [
        for (final r
            in await _db
                .customSelect(
                  'SELECT person_id AS id FROM title_cast WHERE title_id = ?',
                  variables: [Variable<int>(titleId)],
                )
                .get())
          r.read<int>('id'),
      ];
      await _db.customStatement('DELETE FROM title_genres WHERE title_id = ?', [
        titleId,
      ]);
      await _db.customStatement('DELETE FROM title_cast WHERE title_id = ?', [
        titleId,
      ]);
      final seenG = <int>{};
      for (final g in d.genres) {
        if (!seenG.add(g.id)) continue;
        await _db.customStatement(
          'INSERT INTO tmdb_genres (id, name) VALUES (?, ?) '
          'ON CONFLICT(id) DO UPDATE SET name = excluded.name '
          'WHERE name IS NOT excluded.name',
          [g.id, g.name],
        );
        await _db.customStatement(
          'INSERT INTO title_genres (title_id, genre_id) VALUES (?, ?)',
          [titleId, g.id],
        );
      }
      final seenP = <int>{};
      for (final c in d.cast) {
        if (!seenP.add(c.personId)) continue;
        // Update only on a real change: the name trigger rewrites FTS rows.
        await _db.customStatement(
          'INSERT INTO tmdb_people (id, name, profile_path) VALUES (?, ?, ?) '
          'ON CONFLICT(id) DO UPDATE SET name = excluded.name, '
          'profile_path = COALESCE(excluded.profile_path, profile_path) '
          'WHERE name IS NOT excluded.name OR (excluded.profile_path IS NOT NULL '
          'AND profile_path IS NOT excluded.profile_path)',
          [c.personId, c.name, c.profilePath],
        );
        await _db.customStatement(
          'INSERT INTO title_cast (title_id, person_id, ord, character) '
          'VALUES (?, ?, ?, ?)',
          [titleId, c.personId, c.order, c.character],
        );
      }
      // Only what this title used to reference (a full scan is too slow here).
      for (final id in oldPeople) {
        if (seenP.contains(id)) continue;
        await _db.customStatement(
          'DELETE FROM tmdb_people WHERE id = ? AND NOT EXISTS '
          '(SELECT 1 FROM title_cast WHERE person_id = ?)',
          [id, id],
        );
      }
      for (final id in oldGenres) {
        if (seenG.contains(id)) continue;
        await _db.customStatement(
          'DELETE FROM tmdb_genres WHERE id = ? AND NOT EXISTS '
          '(SELECT 1 FROM title_genres WHERE genre_id = ?)',
          [id, id],
        );
      }
      return true;
    });
    if (wrote) _emit();
  }

  @override
  Future<void> saveTmdbUnmatched(int titleId) async {
    final wrote = await _db.transaction(() async {
      if (!await _titleExists(titleId)) return false;
      final ex = await (_db.select(
        _db.tmdbMeta,
      )..where((r) => r.titleId.equals(titleId))).getSingleOrNull();
      if (ex != null && ex.status != TmdbStatus.unmatched) return false;
      await _db
          .into(_db.tmdbMeta)
          .insertOnConflictUpdate(
            TmdbMetaCompanion.insert(
              titleId: Value(titleId),
              status: TmdbStatus.unmatched,
              fetchedAt: DateTime.now(),
            ),
          );
      return true;
    });
    if (wrote) _emit();
  }

  static int _cutoff(Duration d) =>
      DateTime.now().subtract(d).millisecondsSinceEpoch ~/ 1000;

  @override
  Future<List<MediaTitle>> titlesNeedingTmdb({
    int limit = 50,
    Duration retryUnmatchedAfter = const Duration(days: 30),
  }) async {
    if (limit <= 0) return const [];
    // Anti-join: walks idx_titles_added newest first, probes tmdb_meta by PK.
    final rows = await _db
        .customSelect(
          'SELECT t.* FROM titles t LEFT JOIN tmdb_meta m ON m.title_id = t.id '
          'WHERE t.kind IN ($_tmdbKinds) AND (m.title_id IS NULL OR '
          '(m.status = ? AND m.fetched_at <= ?)) '
          'ORDER BY t.added_at DESC, t.id DESC LIMIT ?',
          variables: [
            Variable<int>(TmdbStatus.unmatched.index),
            Variable<int>(_cutoff(retryUnmatchedAfter)),
            Variable<int>(limit),
          ],
        )
        .get();
    return [for (final r in rows) _title(_db.titles.map(r.data))];
  }

  @override
  Future<TmdbProgress> tmdbProgress({
    Duration retryUnmatchedAfter = const Duration(days: 30),
  }) async {
    final r = await _db
        .customSelect(
          'SELECT COUNT(*) AS eligible, '
          'COALESCE(SUM(m.status IN (?, ?)), 0) AS matched, '
          'COALESCE(SUM(m.status = ? AND m.fetched_at > ?), 0) AS unmatched '
          'FROM titles t LEFT JOIN tmdb_meta m ON m.title_id = t.id '
          'WHERE t.kind IN ($_tmdbKinds)',
          variables: [
            Variable<int>(TmdbStatus.matched.index),
            Variable<int>(TmdbStatus.manual.index),
            Variable<int>(TmdbStatus.unmatched.index),
            Variable<int>(_cutoff(retryUnmatchedAfter)),
          ],
        )
        .getSingle();
    return TmdbProgress(
      eligible: r.read<int>('eligible'),
      matched: r.read<int>('matched'),
      unmatched: r.read<int>('unmatched'),
    );
  }

  @override
  Future<void> clearTmdb() async {
    await _db.transaction(() async {
      await _db.delete(_db.tmdbMeta).go();
      await _db.delete(_db.titleGenres).go();
      await _db.delete(_db.titleCast).go();
      await _db.delete(_db.tmdbGenres).go();
      await _db.delete(_db.tmdbPeople).go(); // people_fts via trigger
    });
    _emit();
  }

  // ----------------------------------------------------------------- counts

  Future<int> _count(
    ResultSetImplementation<HasResultSet, dynamic> t, [
    Expression<bool>? where,
  ]) async {
    final c = countAll();
    final q = _db.selectOnly(t)..addColumns([c]);
    if (where != null) q.where(where);
    return (await q.getSingle()).read(c)!;
  }

  @override
  Future<IndexCounts> counts() async => IndexCounts(
    categories: await _count(_db.categories),
    titles: await _count(_db.titles),
    series: await _count(
      _db.titles,
      _db.titles.kind.equals(TitleKind.series.index),
    ),
    files: await _count(_db.files),
    watched: await _count(_db.watch, _db.watch.watched.equals(true)),
  );
}
