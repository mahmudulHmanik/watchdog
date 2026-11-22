import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/tmdb/tmdb_client.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';

MediaTitle title(
  int id,
  String name, {
  TitleKind kind = TitleKind.movie,
  int? year,
  int? yearEnd,
}) => MediaTitle(
  id: id,
  categoryId: 1,
  name: name,
  kind: kind,
  folderUrl: 'http://h/$id/',
  year: year,
  yearEnd: yearEnd,
  addedAt: DateTime(2020),
);

TmdbHit hit(
  int id,
  String title,
  int? year, {
  String? original,
  double pop = 10,
  TmdbMediaType type = TmdbMediaType.movie,
}) => TmdbHit(
  id: id,
  mediaType: type,
  title: title,
  originalTitle: original ?? title,
  year: year,
  popularity: pop,
);

TmdbDetails details(int id, TmdbMediaType type, {String name = 'x'}) =>
    TmdbDetails(id: id, mediaType: type, title: name);

/// One recorded API call.
class Call {
  Call(this.kind, this.query, this.year, this.at);
  final String kind; // movie | tv | details
  final String query;
  final int? year;
  final DateTime at;
  @override
  String toString() => '$kind:$query:$year';
}

/// Scriptable [TmdbApi]. [now] is the test's virtual clock.
class FakeApi implements TmdbApi {
  FakeApi(this.now);
  final DateTime Function() now;
  final calls = <Call>[];

  /// Throw these (in order) on the next requests, one per request.
  final errors = <TmdbException>[];

  /// Search results by (type, query, year).
  List<TmdbHit> Function(String kind, String query, int? year) results = (
    _,
    _,
    _,
  ) => const [];

  /// Runs before each request returns (to block it in a test).
  Future<void> Function(Call c)? gate;

  Future<T> _do<T>(Call c, T Function() ok) async {
    calls.add(c);
    final g = gate;
    if (g != null) await g(c);
    if (errors.isNotEmpty) throw errors.removeAt(0);
    return ok();
  }

  @override
  Future<List<TmdbHit>> searchMovies(String query, {int? year}) => _do(
    Call('movie', query, year, now()),
    () => results('movie', query, year),
  );

  @override
  Future<List<TmdbHit>> searchTv(String query, {int? year}) =>
      _do(Call('tv', query, year, now()), () => results('tv', query, year));

  @override
  Future<TmdbDetails> details(int id, TmdbMediaType type) => _do(
    Call('details', '$id', null, now()),
    () => TmdbDetails(id: id, mediaType: type, title: 'T$id'),
  );
}

class SavedMatch {
  SavedMatch(this.titleId, this.d, this.manual);
  final int titleId;
  final TmdbDetails d;
  final bool manual;
}

/// Just the TMDB part of [Repository], like the real one: a title leaves the
/// "needing" list once something is saved for it.
class FakeRepo implements Repository {
  FakeRepo(this.titles);
  final List<MediaTitle> titles;
  final matches = <SavedMatch>[];
  final unmatched = <int>[];
  final infos = <int, TmdbInfo>{};
  Object? failNeeding;

  @override
  Future<List<MediaTitle>> titlesNeedingTmdb({
    int limit = 50,
    Duration retryUnmatchedAfter = const Duration(days: 30),
  }) async {
    if (failNeeding != null) throw failNeeding!;
    final done = {...matches.map((m) => m.titleId), ...unmatched};
    return [
      for (final t in titles)
        if (!done.contains(t.id) && !infos.containsKey(t.id)) t,
    ].take(limit).toList();
  }

  @override
  Future<void> saveTmdbMatch(
    int titleId,
    TmdbDetails d, {
    bool manual = false,
  }) async => matches.add(SavedMatch(titleId, d, manual));

  @override
  Future<void> saveTmdbUnmatched(int titleId) async => unmatched.add(titleId);

  @override
  Future<TmdbInfo?> tmdbInfo(int titleId) async => infos[titleId];

  @override
  Future<MediaTitle?> title(int id) async =>
      titles.where((t) => t.id == id).firstOrNull;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}
