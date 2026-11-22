import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the index run remembers about one category (keyed by category url).
class CategoryMeta {
  CategoryMeta({this.completedAt, this.titles = 0, Map<String, int>? sigs})
    : sigs = sigs ?? {};

  /// Last time the category was crawled completely. While the first full run
  /// is unfinished it marks categories a restarted run can skip.
  DateTime? completedAt;

  /// Titles seen at that time (progress estimate for the next run).
  int titles;

  /// Group signatures (see skeleton_probe.dart): child folder href -> hash of
  /// its listing, for the cheap "anything changed?" check.
  Map<String, int> sigs;

  Map<String, Object?> toJson() => {
    if (completedAt != null)
      'completedAt': completedAt!.toUtc().toIso8601String(),
    'titles': titles,
    if (sigs.isNotEmpty) 'sigs': sigs,
  };

  factory CategoryMeta.fromJson(Map<String, Object?> j) {
    final s = j['sigs'];
    final c = j['completedAt'];
    return CategoryMeta(
      completedAt: c is String ? DateTime.tryParse(c) : null,
      titles: (j['titles'] as num?)?.toInt() ?? 0,
      sigs: s is Map
          ? {
              for (final e in s.entries)
                if (e.value is num) '${e.key}': (e.value as num).toInt(),
            }
          : null,
    );
  }
}

/// Index metadata (small JSON document; no database schema change).
class IndexMetaData {
  IndexMetaData({this.lastIndexedAt, Map<String, CategoryMeta>? categories})
    : categories = categories ?? {};

  /// The "indexed" marker: set only when a run completed EVERY category. Null
  /// = the first full run is not finished (UI keeps showing the banner and the
  /// next launch continues).
  DateTime? lastIndexedAt;
  final Map<String, CategoryMeta> categories;

  CategoryMeta category(String url) =>
      categories.putIfAbsent(url, CategoryMeta.new);

  Map<String, Object?> toJson() => {
    'v': 2,
    if (lastIndexedAt != null)
      'lastIndexedAt': lastIndexedAt!.toUtc().toIso8601String(),
    'categories': {for (final e in categories.entries) e.key: e.value.toJson()},
  };

  factory IndexMetaData.fromJson(Map<String, Object?> j) {
    final l = j['lastIndexedAt'];
    final c = j['categories'];
    return IndexMetaData(
      lastIndexedAt: l is String ? DateTime.tryParse(l) : null,
      categories: {
        if (c is Map)
          for (final e in c.entries)
            if (e.value is Map)
              '${e.key}': CategoryMeta.fromJson(
                (e.value as Map).cast<String, Object?>(),
              ),
      },
    );
  }

  IndexMetaData copy() => IndexMetaData.fromJson(toJson());
}

/// Key-value place for index metadata.
abstract class IndexMetaStore {
  /// A snapshot (changes to it are not stored).
  Future<IndexMetaData> read();

  /// Applies [change] to the stored document, atomically with respect to
  /// other [update] calls, and persists it.
  Future<void> update(void Function(IndexMetaData m) change);

  Future<DateTime?> lastIndexedAt() async => (await read()).lastIndexedAt;
  Future<void> setLastIndexedAt(DateTime? t) =>
      update((m) => m.lastIndexedAt = t);
}

class MemoryIndexMeta extends IndexMetaStore {
  final IndexMetaData _d = IndexMetaData();

  @override
  Future<IndexMetaData> read() async => _d.copy();

  @override
  Future<void> update(void Function(IndexMetaData m) change) async =>
      change(_d);
}

/// JSON file (e.g. in the app support dir). Corrupt/missing file reads as
/// empty. Writes go through a temp file + rename.
class FileIndexMeta extends IndexMetaStore {
  FileIndexMeta(this.file);
  final File file;

  IndexMetaData? _d;
  Future<void> _chain = Future.value();

  Future<IndexMetaData> _load() async {
    if (_d != null) return _d!;
    try {
      _d = IndexMetaData.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      _d = IndexMetaData();
    }
    return _d!;
  }

  Future<T> _serial<T>(Future<T> Function() f) {
    final r = _chain.then((_) => f());
    _chain = r.then((_) {}, onError: (_) {});
    return r;
  }

  @override
  Future<IndexMetaData> read() => _serial(() async => (await _load()).copy());

  @override
  Future<void> update(void Function(IndexMetaData m) change) =>
      _serial(() async {
        final d = await _load();
        change(d);
        await file.parent.create(recursive: true);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(jsonEncode(d.toJson()), flush: true);
        await tmp.rename(file.path);
      });
}
