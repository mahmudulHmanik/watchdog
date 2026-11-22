/// Raw-SQL rendering of [BrowseFilter] (used by search). Every value is a
/// bound variable; only placeholders are interpolated.
library;

import 'package:drift/drift.dart';

import 'models.dart';

enum Facet { year, language, quality, genre, tmdbLanguage }

class FilterSql {
  FilterSql(this.cond, this.vars);

  /// AND-ed conditions, each parenthesised, referencing alias columns.
  final List<String> cond;
  final List<Variable> vars;
}

String _marks(int n) => List.filled(n, '?').join(',');

FilterSql filterSql(BrowseFilter f, {String alias = 't', Facet? skip}) {
  final cond = <String>[];
  final vars = <Variable>[];
  final a = alias;
  if (f.categoryId != null) {
    cond.add('$a.category_id = ?');
    vars.add(Variable<int>(f.categoryId!));
  }
  if (skip != Facet.year && f.hasYearFilter) {
    final parts = <String>[];
    final ys = f.years;
    if (ys.isNotEmpty) {
      parts.add('$a.year IN (${_marks(ys.length)})');
      vars.addAll(ys.map(Variable<int>.new));
    }
    for (final r in f.yearRanges) {
      final c = <String>['$a.year IS NOT NULL'];
      if (r.from != null) {
        c.add('$a.year >= ?');
        vars.add(Variable<int>(r.from!));
      }
      if (r.to != null) {
        c.add('$a.year <= ?');
        vars.add(Variable<int>(r.to!));
      }
      parts.add('(${c.join(' AND ')})');
    }
    cond.add('(${parts.join(' OR ')})');
  }
  if (skip != Facet.language && f.languages.isNotEmpty) {
    cond.add('$a.language IN (${_marks(f.languages.length)})');
    vars.addAll(f.languages.map(Variable<String>.new));
  }
  if (skip != Facet.quality && f.qualities.isNotEmpty) {
    cond.add('$a.quality IN (${_marks(f.qualities.length)})');
    vars.addAll(f.qualities.map(Variable<int>.new));
  }
  if (f.kind != null) {
    cond.add('$a.kind = ?');
    vars.add(Variable<int>(f.kind!.index));
  }
  // TMDB facets: IN (subquery), so titles without TMDB rows never match.
  if (skip != Facet.genre && f.genreIds.isNotEmpty) {
    cond.add(
      '$a.id IN (SELECT title_id FROM title_genres '
      'WHERE genre_id IN (${_marks(f.genreIds.length)}))',
    );
    vars.addAll(f.genreIds.map(Variable<int>.new));
  }
  final m = <String>[];
  if (f.minRating != null) {
    m.add('rating >= ?');
    vars.add(Variable<double>(f.minRating!));
  }
  if (skip != Facet.tmdbLanguage && f.originalLanguages.isNotEmpty) {
    m.add('original_language IN (${_marks(f.originalLanguages.length)})');
    vars.addAll(f.originalLanguages.map(Variable<String>.new));
  }
  if (f.runtimes.isNotEmpty) {
    final parts = <String>[];
    for (final r in f.runtimes) {
      final c = <String>[];
      if (r.minMinutes != null) {
        c.add('runtime >= ?');
        vars.add(Variable<int>(r.minMinutes!));
      }
      if (r.maxMinutes != null) {
        c.add('runtime < ?');
        vars.add(Variable<int>(r.maxMinutes!));
      }
      parts.add('(${c.join(' AND ')})');
    }
    m.add('(${parts.join(' OR ')})');
  }
  if (m.isNotEmpty) {
    cond.add(
      '$a.id IN (SELECT title_id FROM tmdb_meta WHERE ${m.join(' AND ')})',
    );
  }
  if (f.personId != null) {
    cond.add('$a.id IN (SELECT title_id FROM title_cast WHERE person_id = ?)');
    vars.add(Variable<int>(f.personId!));
  }
  return FilterSql(cond, vars);
}
