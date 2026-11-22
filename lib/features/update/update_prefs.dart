import 'dart:convert';
import 'dart:io';

/// Update preferences (persisted as JSON).
class UpdatePrefs {
  const UpdatePrefs({this.autoCheck = true, this.lastCheckMs = 0});

  /// Look for a newer release on launch (at most once a day).
  final bool autoCheck;

  /// Epoch ms of the last successful check; 0 = never.
  final int lastCheckMs;

  UpdatePrefs copyWith({bool? autoCheck, int? lastCheckMs}) => UpdatePrefs(
    autoCheck: autoCheck ?? this.autoCheck,
    lastCheckMs: lastCheckMs ?? this.lastCheckMs,
  );

  /// True when an automatic check is due at [now].
  bool due(DateTime now, {Duration every = const Duration(hours: 20)}) =>
      autoCheck &&
      now.millisecondsSinceEpoch - lastCheckMs >= every.inMilliseconds;

  Map<String, Object> toJson() => {
    'autoCheck': autoCheck,
    'lastCheckMs': lastCheckMs,
  };

  static UpdatePrefs fromJson(Object? j) => j is Map
      ? UpdatePrefs(
          autoCheck: j['autoCheck'] is bool ? j['autoCheck'] as bool : true,
          lastCheckMs: j['lastCheckMs'] is int ? j['lastCheckMs'] as int : 0,
        )
      : const UpdatePrefs();
}

abstract class UpdatePrefsStore {
  Future<UpdatePrefs> load();
  Future<void> save(UpdatePrefs p);
}

class FileUpdatePrefsStore implements UpdatePrefsStore {
  FileUpdatePrefsStore(this.file);
  final File file;

  @override
  Future<UpdatePrefs> load() async {
    try {
      if (!file.existsSync()) return const UpdatePrefs();
      return UpdatePrefs.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return const UpdatePrefs();
    }
  }

  @override
  Future<void> save(UpdatePrefs p) async {
    try {
      await file.writeAsString(jsonEncode(p.toJson()));
    } catch (_) {}
  }
}
