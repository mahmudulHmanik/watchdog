import 'dart:convert';
import 'dart:io';

/// Tiny key-value place for index metadata (no schema change).
abstract interface class IndexMetaStore {
  Future<DateTime?> lastIndexedAt();
  Future<void> setLastIndexedAt(DateTime t);
}

class MemoryIndexMeta implements IndexMetaStore {
  DateTime? _t;
  @override
  Future<DateTime?> lastIndexedAt() async => _t;
  @override
  Future<void> setLastIndexedAt(DateTime t) async => _t = t;
}

/// JSON file (e.g. in the app support dir). Corrupt/missing file reads as null.
class FileIndexMeta implements IndexMetaStore {
  FileIndexMeta(this.file);
  final File file;

  Future<Map<String, Object?>> _read() async {
    try {
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<DateTime?> lastIndexedAt() async {
    final v = (await _read())['lastIndexedAt'];
    return v is String ? DateTime.tryParse(v) : null;
  }

  @override
  Future<void> setLastIndexedAt(DateTime t) async {
    final m = await _read();
    m['lastIndexedAt'] = t.toUtc().toIso8601String();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(m));
  }
}
