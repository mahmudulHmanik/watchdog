/// Candidate retrieval (FTS5 trigram + LIKE) and paging for search.
///
/// Pipeline: [ParsedQuery.parse] -> stage 1 (AND of substring phrases,
/// LIKE for 1-2 char tokens) -> stage 2 (OR of trigrams, only when stage 1
/// found fewer than [relaxBelow]) -> Dart re-rank ([rank]) -> slice.
///
/// Paging runs on the RE-RANKED list. At most [candidateCap] candidates per
/// stage are re-ranked (grown to cover offset+limit, hard max [maxDepth]),
/// so results deeper than that are unreachable; filters are applied in SQL
/// before the cap, so a filtered search still reaches its own top results.
library;

import 'package:drift/drift.dart';

import '../models.dart';
import '../filter_sql.dart';
import 'query.dart';
import 'ranker.dart';

const candidateCap = 200;
const maxDepth = 1000;
const relaxBelow = 20;

class SearchEngine {
  SearchEngine(this._db);
  final GeneratedDatabase _db;

  /// Ranked title ids for [query]. Empty query returns an empty list (the
  /// caller falls back to browse).
  Future<List<int>> searchIds(
    String query, {
    BrowseFilter filter = const BrowseFilter(),
    int offset = 0,
    int limit = 50,
  }) async {
    final q = ParsedQuery.parse(query);
    final cap = (offset + limit).clamp(candidateCap, maxDepth);
    final cands = <int, Candidate>{};

    final longTok = [
      for (final t in q.tokens)
        if (t.length >= 3) t,
    ];
    final shortTok = [
      for (final t in q.tokens)
        if (t.length < 3) t,
    ];

    // Stage 1.
    await _fetch(
      cands,
      filter,
      q,
      cap,
      match: longTok.isEmpty ? null : longTok.map((t) => '"$t"').join(' AND '),
      like: shortTok,
      orderPrefix: q.tokens.isEmpty ? null : q.tokens.first,
    );
    // Stage 2: relax to typo-tolerant trigram OR.
    if (cands.length < relaxBelow && q.hasText) {
      final grams = _grams(q);
      if (grams.isNotEmpty) {
        await _fetch(
          cands,
          filter,
          q,
          cap,
          match: grams.map((g) => '"$g"').join(' OR '),
          like: const [],
          orderPrefix: null,
          byRank: true,
        );
      }
    }
    final ranked = rank(q, cands.values);
    final end = (offset + limit).clamp(0, ranked.length);
    if (offset >= ranked.length) return const [];
    return [for (final c in ranked.sublist(offset, end)) c.id];
  }

  static List<String> _grams(ParsedQuery q) {
    var toks = [
      for (final t in q.tokens)
        if (!stopwords.contains(t)) t,
    ];
    if (toks.isEmpty) toks = q.tokens;
    final out = <String>{};
    void add(String t) {
      for (var i = 0; i + 3 <= t.length && out.length < 48; i++) {
        out.add(t.substring(i, i + 3));
      }
    }

    toks.forEach(add);
    if (toks.length > 1) add(toks.join());
    return out.toList();
  }

  Future<void> _fetch(
    Map<int, Candidate> out,
    BrowseFilter f,
    ParsedQuery q,
    int cap, {
    required String? match,
    required List<String> like,
    required String? orderPrefix,
    bool byRank = false,
  }) async {
    final vars = <Variable>[];
    final cond = <String>[];
    if (match != null) {
      cond.add('titles_fts MATCH ?');
      vars.add(Variable<String>(match));
    }
    for (final t in like) {
      cond.add("t.sort_key LIKE ? ESCAPE '\\'");
      vars.add(Variable<String>('%${_esc(t)}%'));
    }
    final fs = filterSql(f);
    cond.addAll(fs.cond);
    vars.addAll(fs.vars);
    if (q.yearMin != null) {
      cond.add('t.year >= ?');
      vars.add(Variable<int>(q.yearMin!));
    }
    if (q.yearMax != null) {
      cond.add('t.year <= ?');
      vars.add(Variable<int>(q.yearMax!));
    }
    final String order;
    final orderVars = <Variable>[];
    if (byRank && match != null) {
      order = 'titles_fts.rank';
    } else if (orderPrefix != null) {
      order = "(t.sort_key LIKE ? ESCAPE '\\') DESC, length(t.sort_key), t.id";
      orderVars.add(Variable<String>('${_esc(orderPrefix)}%'));
    } else {
      order = 't.sort_key, t.id';
    }
    final from = match != null
        ? 'titles_fts JOIN titles t ON t.id = titles_fts.rowid'
        : 'titles t';
    final rows = await _db
        .customSelect(
          'SELECT t.id AS id, t.name AS name, t.year AS year, t.kind AS kind, '
          't.quality AS quality, c.name AS category FROM $from '
          'JOIN categories c ON c.id = t.category_id '
          '${cond.isEmpty ? '' : 'WHERE ${cond.join(' AND ')}'} '
          'ORDER BY $order LIMIT ?',
          variables: [...vars, ...orderVars, Variable<int>(cap)],
        )
        .get();
    for (final r in rows) {
      final id = r.read<int>('id');
      out.putIfAbsent(
        id,
        () => Candidate(
          id: id,
          name: r.read<String>('name'),
          year: r.readNullable<int>('year'),
          kind: TitleKind.values[r.read<int>('kind')],
          quality: r.readNullable<int>('quality'),
          category: r.read<String>('category'),
        ),
      );
    }
  }

  static String _esc(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
