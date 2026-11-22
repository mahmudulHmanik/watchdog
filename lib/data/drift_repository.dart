/// drift/SQLite implementation of [Repository]. drift types stay in here.
library;

import '../tmdb/tmdb_models.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import 'database.dart';
import 'file_names.dart';
import 'filter_sql.dart';
import 'models.dart';
import 'repository.dart';
import 'search/engine.dart';

/// Facet methods (years/languages/qualities) apply `within` but ignore that
/// facet's own selection, so a picker still shows the alternatives.
class DriftRepository implements Repository, ChangeThrottling {
  DriftRepository(this._db);

  /// In-memory database for tests.
  DriftRepository.memory() : _db = AppDatabase.memory();

  final AppDatabase _db;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  final _tmdbChanges = StreamController<void>.broadcast();
  @override
  Stream<void> get tmdbChanges => _tmdbChanges.stream;

  Future<void> close() async {
    _throttleTimer?.cancel();
    await _changes.close();
    await _tmdbChanges.close();
    await _db.close();
  }

  // ---------------------------------------------------------------- mapping

  /// Poster paths for a page of titles: one `tmdb_meta` PK-range query
  /// (matched/manual rows only). Done after paging on purpose: a LEFT JOIN
  /// inside the paged query probes tmdb_meta for every row skipped by OFFSET
  /// (deep pages went 2 -> 25 ms on 35k titles).
  Future<Map<int, String>> _posters(Iterable<int> titleIds) async {
    final ids = titleIds.toList();
    final out = <int, String>{};
    final m = _db.tmdbMeta;
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final q = _db.selectOnly(m)
        ..addColumns([m.titleId, m.posterPath])
        ..where(
          m.titleId.isIn(chunk) &
              m.status.isInValues(const [
                TmdbStatus.matched,
                TmdbStatus.manual,
              ]) &
              m.posterPath.isNotNull(),
        );
      for (final r in await q.get()) {
        out[r.read(m.titleId)!] = r.read(m.posterPath)!;
      }
    }
    return out;
  }

  /// category id -> absolute category url (tiny table, cached; urls compose
  /// with the stored relative paths).
  Map<int, String>? _catUrlCache;

  Future<Map<int, String>> _catUrls() async => _catUrlCache ??= {
    for (final c in await _db.select(_db.categories).get()) c.id: c.url,
  };

  static String _folderUrl(TitleRow r, Map<int, String> cats) =>
      composeUrl(cats[r.categoryId] ?? '', r.folderRel);

  Future<List<MediaTitle>> _hydrate(List<TitleRow> rows) async {
    final p = await _posters(rows.map((r) => r.id));
    final cats = await _catUrls();
    return [for (final r in rows) _title(r, cats, p[r.id])];
  }

  MediaTitle _title(
    TitleRow r,
    Map<int, String> cats, [
    String? tmdbPosterPath,
  ]) {
    final folder = _folderUrl(r, cats);
    return MediaTitle(
      id: r.id,
      categoryId: r.categoryId,
      name: r.name,
      kind: r.kind,
      folderUrl: folder,
      year: r.year,
      yearEnd: r.yearEnd,
      quality: r.quality,
      tags: (jsonDecode(r.tags) as List).cast<String>(),
      posterUrl: r.posterRel == null ? null : composeUrl(folder, r.posterRel!),
      language: r.language,
      folderMtime: r.folderMtime,
      addedAt: r.addedAt,
      seasonCount: r.seasonCount,
      fileCount: r.fileCount,
      tmdbPosterPath: tmdbPosterPath,
      filesLoaded: r.filesLoadedAt != null,
    );
  }

  /// [folderUrl] = absolute url of the file's title folder.
  MediaFile _file(FileRow r, String folderUrl) {
    final name = nameOfRel(r.rel);
    final ext = extOfName(name);
    return MediaFile(
      id: r.id,
      titleId: r.titleId,
      seasonId: r.seasonId,
      name: name,
      url: composeUrl(folderUrl, r.rel),
      ext: ext,
      playable: isPlayableExt(ext),
      episode: r.episode,
      episodeEnd: r.episodeEnd,
      sizeKb: r.sizeKb,
      mtime: r.mtime,
    );
  }

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
    return _hydrate(await q.get());
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
    return r == null ? null : (await _hydrate([r])).single;
  }

  @override
  Future<List<MediaTitle>> titlesByIds(List<int> ids) async {
    final byId = <int, MediaTitle>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final rows = await (_db.select(
        _db.titles,
      )..where((t) => t.id.isIn(chunk))).get();
      for (final m in await _hydrate(rows)) {
        byId[m.id] = m;
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

  /// Absolute folder url of a title, null when the title does not exist.
  Future<String?> _titleFolder(int titleId) async {
    final t = await (_db.select(
      _db.titles,
    )..where((t) => t.id.equals(titleId))).getSingleOrNull();
    return t == null ? null : _folderUrl(t, await _catUrls());
  }

  @override
  Future<List<SeasonEpisodes>> seasons(int titleId) async {
    final folder = await _titleFolder(titleId);
    if (folder == null) return const [];
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
      (bySeason[f.seasonId!] ??= []).add(_file(f, folder));
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
            folderUrl: s.folderRel == null
                ? null
                : composeUrl(folder, s.folderRel!),
            episodeCount: s.episodeCount ?? bySeason[s.id]?.length ?? 0,
          ),
          files: [...?bySeason[s.id]]..sort(_cmpFiles),
        ),
    ];
  }

  @override
  Future<List<MediaFile>> titleFiles(int titleId) async {
    final folder = await _titleFolder(titleId);
    if (folder == null) return const [];
    final fs = await (_db.select(
      _db.files,
    )..where((f) => f.titleId.equals(titleId) & f.seasonId.isNull())).get();
    return fs.map((f) => _file(f, folder)).toList()..sort(_cmpFiles);
  }

  @override
  Future<MediaFile?> file(int id) async {
    final f = _db.files, t = _db.titles;
    final r = await (_db.select(f).join([
      innerJoin(t, t.id.equalsExp(f.titleId)),
    ])..where(f.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    return _file(r.readTable(f), _folderUrl(r.readTable(t), await _catUrls()));
  }

  /// Titles whose folder is a prefix of [url], deepest first, with the file
  /// path relative to each. No file rows involved.
  Future<List<(TitleRow, String)>> _titlesForUrl(String url) async {
    final cats = await _catUrls();
    final out = <(TitleRow, String)>[];
    // Longest matching category url first (nested category urls).
    final matches = [
      for (final e in cats.entries)
        if (url.startsWith(e.value)) e,
    ]..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final c in matches) {
      final rest = url.substring(c.value.length);
      // Every '/'-terminated prefix of rest can be a title folder (flat or
      // (Year)/Title layouts); the unique (category, folder_rel) index answers.
      final prefixes = <String>[
        for (var i = rest.indexOf('/'); i >= 0; i = rest.indexOf('/', i + 1))
          rest.substring(0, i + 1),
      ];
      if (prefixes.isEmpty) continue;
      final ts =
          await (_db.select(_db.titles)..where(
                (t) => t.categoryId.equals(c.key) & t.folderRel.isIn(prefixes),
              ))
              .get();
      for (final t in ts) {
        out.add((t, rest.substring(t.folderRel.length)));
      }
    }
    out.sort((a, b) => b.$1.folderRel.length.compareTo(a.$1.folderRel.length));
    // Titles stored with an absolute folder (see [relativeTo]).
    final absPrefixes = <String>[
      for (
        var i = url.length > 8 ? url.indexOf('/', 8) : -1;
        i >= 0;
        i = url.indexOf('/', i + 1)
      )
        url.substring(0, i + 1),
    ];
    if (absPrefixes.isNotEmpty) {
      for (final t in await (_db.select(
        _db.titles,
      )..where((t) => t.folderRel.isIn(absPrefixes))).get()) {
        out.add((t, url.substring(t.folderRel.length)));
      }
    }
    return out;
  }

  @override
  Future<MediaFile?> fileByUrl(String url) async {
    final cats = await _catUrls();
    for (final (t, rel) in await _titlesForUrl(url)) {
      final f =
          await (_db.select(_db.files)
                ..where((f) => f.titleId.equals(t.id) & f.rel.equals(rel)))
              .getSingleOrNull();
      if (f != null) return _file(f, _folderUrl(t, cats));
    }
    // A file stored with an absolute path (not under its title folder).
    final absFile = await (_db.select(
      _db.files,
    )..where((f) => f.rel.equals(url))).getSingleOrNull();
    return absFile == null ? null : _file(absFile, '');
  }

  @override
  Future<int?> titleIdForUrl(String url) async {
    final c = await _titlesForUrl(url);
    return c.isEmpty ? null : c.first.$1.id;
  }

  @override
  Future<MediaFile?> ensureFileByUrl(String url) async {
    final have = await fileByUrl(url);
    if (have != null) return have;
    final c = await _titlesForUrl(url);
    if (c.isEmpty) return null;
    final (t, rel) = c.first;
    if (rel.isEmpty || rel.endsWith('/')) return null;
    int? sid;
    for (final s in await (_db.select(
      _db.seasons,
    )..where((s) => s.titleId.equals(t.id))).get()) {
      if (s.folderRel != null && rel.startsWith(s.folderRel!)) sid = s.id;
    }
    final id = await _db
        .into(_db.files)
        .insert(
          FilesCompanion.insert(titleId: t.id, seasonId: Value(sid), rel: rel),
        );
    return file(id);
  }

  @override
  Future<bool> titleFilesLoaded(int titleId) async {
    final t = await (_db.select(
      _db.titles,
    )..where((t) => t.id.equals(titleId))).getSingleOrNull();
    return t?.filesLoadedAt != null;
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
    final rows =
        await (_db.select(_db.files)..where(
              (f) =>
                  f.titleId.equals(titleId) &
                  (seasonId == null
                      ? const Constant(true)
                      : f.seasonId.equals(seasonId)),
            ))
            .get();
    // playable is derived from the extension, so it is filtered here.
    final ids = [
      for (final f in rows)
        if (isPlayableExt(extOfName(nameOfRel(f.rel)))) f.id,
    ];
    if (ids.isEmpty) return;
    await _db.batch((b) {
      for (final id in ids) {
        b.customStatement(
          'INSERT INTO watch (file_id, position_ms, duration_ms, watched, updated_at) '
          'VALUES (?, 0, 0, ?, ?) '
          'ON CONFLICT(file_id) DO UPDATE SET watched = excluded.watched, '
          'position_ms = CASE WHEN excluded.watched = 1 THEN position_ms ELSE 0 END, '
          'updated_at = excluded.updated_at',
          [id, w, now],
        );
      }
    });
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
    final picked = <TypedResult>[];
    for (final r in await q.get()) {
      if (!seen.add(r.readTable(t).id)) continue;
      picked.add(r);
      if (picked.length >= limit) break;
    }
    final posters = await _posters(seen);
    final cats = await _catUrls();
    final seasonIds = {
      for (final r in picked)
        if (r.readTable(f).seasonId != null) r.readTable(f).seasonId!,
    };
    final seasonNumbers = <int, int>{};
    if (seasonIds.isNotEmpty) {
      final rows = await (_db.select(
        _db.seasons,
      )..where((s) => s.id.isIn(seasonIds))).get();
      for (final s in rows) {
        seasonNumbers[s.id] = s.number;
      }
    }
    return [
      for (final r in picked)
        ResumeItem(
          title: _title(r.readTable(t), cats, posters[r.readTable(t).id]),
          file: _file(r.readTable(f), _folderUrl(r.readTable(t), cats)),
          state: _watch(r.readTable(w)),
          seasonNumber: seasonNumbers[r.readTable(f).seasonId],
        ),
    ];
  }

  // ---------------------------------------------------------------- crawler

  Duration? _throttle;
  Timer? _throttleTimer;
  bool _throttlePending = false;

  @override
  void throttleChanges(Duration? every) {
    _throttle = every;
    if (every == null) {
      _throttleTimer?.cancel();
      _throttleTimer = null;
      if (_throttlePending) {
        _throttlePending = false;
        _add();
      }
    }
  }

  void _add() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Leading edge immediately, then at most one more per throttle window.
  void _emit() {
    final every = _throttle;
    if (every == null) return _add();
    if (_throttleTimer != null) {
      _throttlePending = true;
      return;
    }
    _add();
    _throttleTimer = Timer(every, () {
      _throttleTimer = null;
      if (_throttlePending && _throttle != null) {
        _throttlePending = false;
        _emit();
      }
    });
  }

  void _emitTmdb() {
    if (!_tmdbChanges.isClosed) _tmdbChanges.add(null);
  }

  @override
  Future<Map<String, int>> upsertCategories(
    List<CategoryDraft> categories,
  ) async {
    final out = <String, int>{};
    _catUrlCache = null;
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
    _catUrlCache = null;
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
      final cats = <int, CategoryRow?>{};
      var rest = drafts;
      // Fast path for skeleton drafts of titles that are not stored yet (the
      // first crawl): set-based selects and batched inserts instead of
      // several statements per title. Not used while watch_keep holds parked
      // rows (they must be re-attached per title).
      if (!keep) rest = await _insertNewSkeletons(drafts, cats);
      for (final d in rest) {
        await _upsert(d, Future.value(keep), cats);
      }
    });
    _emit();
  }

  /// Inserts the skeleton drafts whose title is new; returns the others (full
  /// drafts, existing titles, repeated folders) for the per-title path.
  Future<List<TitleDraft>> _insertNewSkeletons(
    List<TitleDraft> drafts,
    Map<int, CategoryRow?> cats,
  ) async {
    final byCat = <int, List<TitleDraft>>{};
    final rest = <TitleDraft>[];
    for (final d in drafts) {
      if (d.filesLoaded) {
        rest.add(d);
      } else {
        (byCat[d.categoryId] ??= []).add(d);
      }
    }
    final t = _db.titles;
    for (final e in byCat.entries) {
      final cat = cats.containsKey(e.key)
          ? cats[e.key]
          : cats[e.key] = await (_db.select(
              _db.categories,
            )..where((c) => c.id.equals(e.key))).getSingleOrNull();
      if (cat == null) {
        throw ArgumentError(
          'unknown categoryId ${e.key} for "${e.value.first.name}"',
        );
      }
      final rels = [for (final d in e.value) relativeTo(cat.url, d.folderUrl)];
      final existing = <String>{};
      for (var i = 0; i < rels.length; i += _inChunk) {
        final chunk = rels.sublist(i, min(i + _inChunk, rels.length));
        final q = _db.selectOnly(t)
          ..addColumns([t.folderRel])
          ..where(t.categoryId.equals(e.key) & t.folderRel.isIn(chunk));
        for (final r in await q.get()) {
          existing.add(r.read(t.folderRel)!);
        }
      }
      final fresh = <TitleDraft>[];
      final freshRels = <String>[];
      final seen = <String>{};
      for (var i = 0; i < rels.length; i++) {
        if (existing.contains(rels[i]) || !seen.add(rels[i])) {
          rest.add(e.value[i]);
        } else {
          fresh.add(e.value[i]);
          freshRels.add(rels[i]);
        }
      }
      if (fresh.isEmpty) continue;
      final now = DateTime.now();
      await _db.batch((b) {
        b.insertAll(t, [
          for (var i = 0; i < fresh.length; i++)
            _newTitleRow(fresh[i], freshRels[i], cat, now),
        ]);
      });
      final withSeasons = [
        for (var i = 0; i < fresh.length; i++)
          if (fresh[i].seasons.isNotEmpty) i,
      ];
      if (withSeasons.isEmpty) continue;
      final ids = <String, int>{};
      for (var i = 0; i < withSeasons.length; i += _inChunk) {
        final chunk = [
          for (final k in withSeasons.sublist(
            i,
            min(i + _inChunk, withSeasons.length),
          ))
            freshRels[k],
        ];
        final q = _db.selectOnly(t)
          ..addColumns([t.id, t.folderRel])
          ..where(t.categoryId.equals(e.key) & t.folderRel.isIn(chunk));
        for (final r in await q.get()) {
          ids[r.read(t.folderRel)!] = r.read(t.id)!;
        }
      }
      await _db.batch((b) {
        for (final k in withSeasons) {
          final id = ids[freshRels[k]]!;
          final d = fresh[k];
          for (var i = 0; i < d.seasons.length; i++) {
            final sd = d.seasons[i];
            b.insert(
              _db.seasons,
              SeasonsCompanion.insert(
                titleId: id,
                number: sd.number,
                label: sd.label,
                language: Value(sd.language),
                folderRel: Value(
                  sd.folderUrl == null
                      ? null
                      : relativeTo(d.folderUrl, sd.folderUrl!),
                ),
                episodeCount: Value(sd.episodeCount),
                ord: Value(i),
              ),
            );
          }
        }
      });
    }
    return rest;
  }

  /// SQLite allows 32766 variables; stay well below.
  static const _inChunk = 500;

  TitlesCompanion _newTitleRow(
    TitleDraft d,
    String folderRel,
    CategoryRow cat,
    DateTime now,
  ) => TitlesCompanion.insert(
    categoryId: d.categoryId,
    name: d.name,
    sortKey: d.name.toLowerCase(),
    kind: d.kind,
    folderRel: folderRel,
    year: Value(d.year),
    yearEnd: Value(d.yearEnd),
    quality: Value(d.quality),
    tags: Value(jsonEncode(d.tags)),
    posterRel: Value(
      d.posterUrl == null ? null : relativeTo(d.folderUrl, d.posterUrl!),
    ),
    language: Value(cat.language),
    folderMtime: Value(d.folderMtime),
    addedAt: _addedAt(d, now),
    seasonCount: Value(d.seasons.length),
    fileCount: Value(d.fileCount ?? 0),
  );

  static DateTime _addedAt(TitleDraft d, DateTime now) {
    final a = d.addedAt;
    return a == null || a.isAfter(now) ? now : a;
  }

  Future<bool> _hasKeep() async {
    final c = countAll();
    final q = _db.selectOnly(_db.watchKeep)..addColumns([c]);
    return (await q.getSingle()).read(c)! > 0;
  }

  /// Files of a draft keyed by relative path (first occurrence wins), with
  /// the index of their season (-1 = directly under the title).
  _FilePlan _plan(
    String folderUrl,
    TitleKind kind,
    List<SeasonDraft> seasons,
    List<FileDraft> files,
  ) {
    final seen = <String>{};
    final items = <(int, String, FileDraft)>[];
    final perSeason = List<int>.filled(seasons.length, 0);
    void add(int si, FileDraft f) {
      final rel = relativeTo(folderUrl, f.url);
      if (!seen.add(rel)) return;
      items.add((si, rel, f));
      if (si >= 0) perSeason[si]++;
    }

    if (kind == TitleKind.series) {
      for (var i = 0; i < seasons.length; i++) {
        for (final f in seasons[i].files) {
          add(i, f);
        }
      }
    } else {
      for (final f in files) {
        add(-1, f);
      }
    }
    return _FilePlan(items, perSeason);
  }

  Future<int> _upsert(
    TitleDraft d,
    Future<bool> hasKeepF, [
    Map<int, CategoryRow?>? catCache,
  ]) async {
    final cat = (catCache != null && catCache.containsKey(d.categoryId))
        ? catCache[d.categoryId]
        : await (_db.select(
            _db.categories,
          )..where((c) => c.id.equals(d.categoryId))).getSingleOrNull();
    catCache?[d.categoryId] = cat;
    if (cat == null) {
      throw ArgumentError('unknown categoryId ${d.categoryId} for "${d.name}"');
    }
    final folderRel = relativeTo(cat.url, d.folderUrl);
    final posterRel = d.posterUrl == null
        ? null
        : relativeTo(d.folderUrl, d.posterUrl!);
    final plan = _plan(d.folderUrl, d.kind, d.seasons, d.files);
    final tags = jsonEncode(d.tags);

    final ex =
        await (_db.select(_db.titles)..where(
              (t) =>
                  t.categoryId.equals(d.categoryId) &
                  t.folderRel.equals(folderRel),
            ))
            .getSingleOrNull();

    // What happens to stored file rows.
    final _FilesMode mode;
    if (d.filesLoaded) {
      mode = _FilesMode.replace;
    } else if (ex == null) {
      mode = _FilesMode.none;
    } else if (ex.kind != d.kind) {
      mode = _FilesMode.drop;
    } else if (ex.filesLoadedAt != null &&
        d.folderMtime != null &&
        ex.folderMtime != null &&
        _secs(ex.folderMtime) == _secs(d.folderMtime)) {
      mode = _FilesMode.keep;
    } else {
      mode = _FilesMode.stale;
    }
    final fileCount = mode == _FilesMode.replace
        ? plan.items.length
        : d.fileCount ?? (mode == _FilesMode.drop ? 0 : ex?.fileCount ?? 0);
    // Loaded-at: set on a full draft, kept when files are kept, else cleared.
    final Value<DateTime?> loadedAt = switch (mode) {
      _FilesMode.replace => Value(DateTime.now()),
      _FilesMode.keep => const Value.absent(),
      _ => const Value(null),
    };

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
              folderRel: folderRel,
              year: Value(d.year),
              yearEnd: Value(d.yearEnd),
              quality: Value(d.quality),
              tags: Value(tags),
              posterRel: Value(posterRel),
              language: Value(cat.language),
              folderMtime: Value(d.folderMtime),
              addedAt: _addedAt(d, DateTime.now()),
              seasonCount: Value(d.seasons.length),
              fileCount: Value(fileCount),
              filesLoadedAt: loadedAt,
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
          posterRel: Value(posterRel),
          language: Value(cat.language),
          folderMtime: Value(d.folderMtime),
          seasonCount: Value(d.seasons.length),
          fileCount: Value(fileCount),
          filesLoadedAt: loadedAt,
        ),
      );
    }
    await _syncChildren(
      id: id,
      folderUrl: d.folderUrl,
      seasonDrafts: d.seasons,
      plan: plan,
      mode: mode,
      existed: ex != null,
      hasKeep: await hasKeepF,
    );
    return id;
  }

  @override
  Future<void> upsertTitleFiles(
    int titleId, {
    List<FileDraft> files = const [],
    List<SeasonDraft> seasons = const [],
  }) async {
    await _db.transaction(() async {
      final t = await (_db.select(
        _db.titles,
      )..where((t) => t.id.equals(titleId))).getSingleOrNull();
      if (t == null) throw ArgumentError('unknown titleId $titleId');
      if (t.kind == TitleKind.series) {
        if (files.isNotEmpty) {
          throw ArgumentError('series "${t.name}": files must be empty');
        }
      } else if (seasons.isNotEmpty) {
        throw ArgumentError(
          '${t.kind.name} "${t.name}": seasons must be empty',
        );
      }
      final folderUrl = _folderUrl(t, await _catUrls());
      final plan = _plan(folderUrl, t.kind, seasons, files);
      await (_db.update(_db.titles)..where((x) => x.id.equals(titleId))).write(
        TitlesCompanion(
          seasonCount: Value(seasons.length),
          fileCount: Value(plan.items.length),
          filesLoadedAt: Value(DateTime.now()),
        ),
      );
      await _syncChildren(
        id: titleId,
        folderUrl: folderUrl,
        seasonDrafts: seasons,
        plan: plan,
        mode: _FilesMode.replace,
        existed: true,
        hasKeep: await _hasKeep(),
      );
    });
    _emit();
  }

  /// Seasons (identity match, ids kept) and, per [mode], file rows (identity
  /// = relative path, ids kept).
  Future<void> _syncChildren({
    required int id,
    required String folderUrl,
    required List<SeasonDraft> seasonDrafts,
    required _FilePlan plan,
    required _FilesMode mode,
    required bool existed,
    required bool hasKeep,
  }) async {
    final exSeasons = existed
        ? await (_db.select(
            _db.seasons,
          )..where((s) => s.titleId.equals(id))).get()
        : <SeasonRow>[];
    final used = <int>{};
    final seasonIds = <int>[];
    final seasonRels = <String?>[];
    for (var i = 0; i < seasonDrafts.length; i++) {
      final sd = seasonDrafts[i];
      final rel = sd.folderUrl == null
          ? null
          : relativeTo(folderUrl, sd.folderUrl!);
      seasonRels.add(rel);
      SeasonRow? m;
      for (final e in exSeasons) {
        if (used.contains(e.id)) continue;
        final same = rel != null
            ? e.folderRel == rel
            : e.folderRel == null &&
                  e.number == sd.number &&
                  e.language == sd.language &&
                  e.label == sd.label;
        if (same) {
          m = e;
          break;
        }
      }
      final count = mode == _FilesMode.replace
          ? plan.perSeason[i]
          : sd.episodeCount ?? m?.episodeCount;
      if (m != null) {
        used.add(m.id);
        seasonIds.add(m.id);
        await (_db.update(_db.seasons)..where((s) => s.id.equals(m!.id))).write(
          SeasonsCompanion(
            number: Value(sd.number),
            label: Value(sd.label),
            language: Value(sd.language),
            folderRel: Value(rel),
            episodeCount: Value(count),
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
                  folderRel: Value(rel),
                  episodeCount: Value(count),
                  ord: Value(i),
                ),
              ),
        );
      }
    }

    var inserted = 0;
    if (mode == _FilesMode.replace) {
      inserted = await _replaceFiles(id, plan, seasonIds, existed: existed);
    } else if (mode == _FilesMode.drop) {
      await (_db.delete(_db.files)..where((f) => f.titleId.equals(id))).go();
    }
    // Unmatched old seasons last; their files go with them.
    for (final e in exSeasons) {
      if (!used.contains(e.id)) {
        await (_db.delete(
          _db.files,
        )..where((f) => f.seasonId.equals(e.id))).go();
        await (_db.delete(_db.seasons)..where((s) => s.id.equals(e.id))).go();
      }
    }

    if (hasKeep && (inserted > 0 || mode != _FilesMode.replace)) {
      await _reattachKeep(
        id,
        folderUrl,
        createStubs: mode != _FilesMode.replace,
        seasonIds: seasonIds,
        seasonRels: seasonRels,
      );
    }
  }

  /// Replaces the file rows of [id] with [plan]; returns rows inserted.
  Future<int> _replaceFiles(
    int id,
    _FilePlan plan,
    List<int> seasonIds, {
    required bool existed,
  }) async {
    final exFiles = existed
        ? {
            for (final f in await (_db.select(
              _db.files,
            )..where((f) => f.titleId.equals(id))).get())
              f.rel: f,
          }
        : <String, FileRow>{};
    final seenRels = <String>{};
    final inserts = <FilesCompanion>[];
    final updates = <(int, FilesCompanion)>[];
    for (final (si, rel, f) in plan.items) {
      seenRels.add(rel);
      final sid = si < 0 ? null : seasonIds[si];
      final e = exFiles[rel];
      if (e == null) {
        inserts.add(
          FilesCompanion.insert(
            titleId: id,
            seasonId: Value(sid),
            rel: rel,
            episode: Value(f.episode),
            episodeEnd: Value(f.episodeEnd),
            sizeKb: Value(f.sizeKb),
            mtime: Value(f.mtime),
          ),
        );
      } else if (e.seasonId != sid ||
          e.episode != f.episode ||
          e.episodeEnd != f.episodeEnd ||
          e.sizeKb != f.sizeKb ||
          _secs(e.mtime) != _secs(f.mtime)) {
        updates.add((
          e.id,
          FilesCompanion(
            seasonId: Value(sid),
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
        if (!seenRels.contains(e.rel)) e.id,
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
    return inserts.length;
  }

  /// Re-attach parked watch state (watch_keep, by absolute url) to this
  /// title's files. With [createStubs] (no file list in this write: skeleton
  /// crawl) a parked url without a row gets a bare file row, so "continue
  /// watching" survives a re-index; a later [upsertTitleFiles] matches it by
  /// relative path and fills it in.
  Future<void> _reattachKeep(
    int titleId,
    String folderUrl, {
    required bool createStubs,
    required List<int> seasonIds,
    required List<String?> seasonRels,
  }) async {
    final k = _db.watchKeep;
    final keeps =
        await (_db.select(k)..where(
              (r) =>
                  r.url.isBiggerOrEqualValue(folderUrl) &
                  r.url.isSmallerThanValue('$folderUrl￿'),
            ))
            .get();
    if (keeps.isEmpty) return;
    final byRel = {
      for (final f in await (_db.select(
        _db.files,
      )..where((f) => f.titleId.equals(titleId))).get())
        f.rel: f.id,
    };
    for (final r in keeps) {
      final rel = r.url.substring(folderUrl.length);
      var fid = byRel[rel];
      if (fid == null) {
        if (!createStubs) continue;
        int? sid;
        for (var i = 0; i < seasonRels.length; i++) {
          if (seasonRels[i] != null && rel.startsWith(seasonRels[i]!)) {
            sid = seasonIds[i];
            break;
          }
        }
        fid = await _db
            .into(_db.files)
            .insert(
              FilesCompanion.insert(
                titleId: titleId,
                seasonId: Value(sid),
                rel: rel,
              ),
            );
      }
      await _db.customStatement(
        'INSERT OR IGNORE INTO watch (file_id, position_ms, duration_ms, watched, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          fid,
          r.positionMs,
          r.durationMs,
          r.watched ? 1 : 0,
          r.updatedAt.millisecondsSinceEpoch ~/ 1000,
        ],
      );
      await (_db.delete(k)..where((x) => x.url.equals(r.url))).go();
    }
  }

  @override
  Future<int> trimFileCache({
    int maxRows = 20000,
    Set<int> protectedTitleIds = const {},
  }) async {
    final removed = await _db.transaction(() async {
      final f = _db.files;
      final c = countAll();
      var total = (await (_db.selectOnly(
        f,
      )..addColumns([c])).getSingle()).read(c)!;
      if (total <= maxRows) return 0;
      final watched = {
        for (final r
            in await _db
                .customSelect(
                  'SELECT DISTINCT f.title_id AS id FROM watch w '
                  'JOIN files f ON f.id = w.file_id',
                )
                .get())
          r.read<int>('id'),
      };
      final rows = await _db
          .customSelect(
            'SELECT f.title_id AS id, COUNT(*) AS n, t.files_loaded_at AS at '
            'FROM files f JOIN titles t ON t.id = f.title_id '
            'GROUP BY f.title_id',
          )
          .get();
      // Stale (null) first, then oldest load first.
      final cand =
          [
            for (final r in rows)
              if (!watched.contains(r.read<int>('id')) &&
                  !protectedTitleIds.contains(r.read<int>('id')))
                (
                  r.read<int>('id'),
                  r.read<int>('n'),
                  r.readNullable<int>('at'),
                ),
          ]..sort((a, b) {
            final c = (a.$3 ?? -1).compareTo(b.$3 ?? -1);
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });
      var dropped = 0;
      for (final (id, n, _) in cand) {
        if (total <= maxRows) break;
        await (_db.delete(f)..where((x) => x.titleId.equals(id))).go();
        await (_db.update(_db.titles)..where((t) => t.id.equals(id))).write(
          const TitlesCompanion(filesLoadedAt: Value(null)),
        );
        total -= n;
        dropped += n;
      }
      return dropped;
    });
    if (removed > 0) _emit();
    return removed;
  }

  @override
  Future<void> compact() async {
    // No-op unless the file is in auto_vacuum=INCREMENTAL mode.
    await _db.customSelect('PRAGMA incremental_vacuum').get();
    await _db.customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
  }

  @override
  Future<Map<String, DateTime?>> knownFolders(int categoryId) async {
    final cat = (await _catUrls())[categoryId];
    if (cat == null) return {};
    final rows =
        await (_db.selectOnly(_db.titles)
              ..addColumns([_db.titles.folderRel, _db.titles.folderMtime])
              ..where(_db.titles.categoryId.equals(categoryId)))
            .get();
    return {
      for (final r in rows)
        composeUrl(cat, r.read(_db.titles.folderRel)!): r.read(
          _db.titles.folderMtime,
        ),
    };
  }

  @override
  Future<int> removeMissing(int categoryId, Set<String> keep) async {
    final cat = (await _catUrls())[categoryId];
    if (cat == null) return 0;
    final rows =
        await (_db.selectOnly(_db.titles)
              ..addColumns([_db.titles.id, _db.titles.folderRel])
              ..where(_db.titles.categoryId.equals(categoryId)))
            .get();
    final drop = [
      for (final r in rows)
        if (!keep.contains(composeUrl(cat, r.read(_db.titles.folderRel)!)))
          r.read(_db.titles.id)!,
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
          'SELECT c.url || t.folder_rel || f.rel, w.position_ms, w.duration_ms, '
          'w.watched, w.updated_at '
          'FROM watch w JOIN files f ON f.id = w.file_id '
          'JOIN titles t ON t.id = f.title_id '
          'JOIN categories c ON c.id = t.category_id',
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
    _catUrlCache = null;
    _emit();
    _emitTmdb(); // cascade removed the TMDB data too
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
    if (wrote) _emitTmdb();
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
    if (wrote) _emitTmdb();
  }

  static int _cutoff(Duration d) =>
      DateTime.now().subtract(d).millisecondsSinceEpoch ~/ 1000;

  @override
  Future<List<MediaTitle>> titlesNeedingTmdb({
    int limit = 50,
    Duration retryUnmatchedAfter = const Duration(days: 30),
    TmdbQueueCursor? after,
  }) async {
    if (limit <= 0) return const [];
    // Anti-join: walks idx_titles_added newest first, probes tmdb_meta by PK.
    // Keyset: the row-value-free form keeps the index range scan.
    final rows = await _db
        .customSelect(
          'SELECT t.* FROM titles t LEFT JOIN tmdb_meta m ON m.title_id = t.id '
          'WHERE t.kind IN ($_tmdbKinds) AND (m.title_id IS NULL OR '
          '(m.status = ? AND m.fetched_at <= ?)) '
          '${after == null ? '' : 'AND (t.added_at < ? OR (t.added_at = ? AND t.id < ?)) '}'
          'ORDER BY t.added_at DESC, t.id DESC LIMIT ?',
          variables: [
            Variable<int>(TmdbStatus.unmatched.index),
            Variable<int>(_cutoff(retryUnmatchedAfter)),
            if (after != null) ...[
              Variable<DateTime>(after.addedAt),
              Variable<DateTime>(after.addedAt),
              Variable<int>(after.id),
            ],
            Variable<int>(limit),
          ],
        )
        .get();
    final cats = await _catUrls();
    return [for (final r in rows) _title(_db.titles.map(r.data), cats)];
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
    _emitTmdb();
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

  /// Sum of the stored per-title counts (valid for lazily loaded titles).
  Future<int> _fileTotal() async {
    final sum = _db.titles.fileCount.sum();
    final q = _db.selectOnly(_db.titles)..addColumns([sum]);
    return (await q.getSingle()).read(sum) ?? 0;
  }

  @override
  Future<IndexCounts> counts() async => IndexCounts(
    categories: await _count(_db.categories),
    titles: await _count(_db.titles),
    series: await _count(
      _db.titles,
      _db.titles.kind.equals(TitleKind.series.index),
    ),
    files: await _fileTotal(),
    watched: await _count(_db.watch, _db.watch.watched.equals(true)),
  );
}

enum _FilesMode {
  /// Full draft: rows replaced.
  replace,

  /// New skeleton title: nothing stored.
  none,

  /// Skeleton re-crawl, folder unchanged: loaded rows stay loaded.
  keep,

  /// Skeleton re-crawl, folder changed/unknown: rows kept but not loaded.
  stale,

  /// Kind changed: rows dropped.
  drop,
}

class _FilePlan {
  _FilePlan(this.items, this.perSeason);

  /// (season index or -1, relative path, draft), deduplicated by path.
  final List<(int, String, FileDraft)> items;
  final List<int> perSeason;
}
