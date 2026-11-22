import 'dart:io';

import 'package:flutter/widgets.dart';

import 'release.dart';

/// Marks the APK handed to the system installer as "in use" so cleanup never
/// deletes it under the installer. Set by [begin] when the installer is
/// launched; cleared by [end] or when the app comes back to the foreground
/// after having left it (installer dismissed or finished).
class InstallGuard with WidgetsBindingObserver {
  String? _path;
  bool _left = false;
  bool _observing = false;

  /// True while an install is in progress.
  bool get active => _path != null;

  /// Absolute path of the APK being installed; null when none.
  String? get path => _path;

  void begin(String path) {
    _path = path;
    _left = false;
    if (!_observing) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      } catch (_) {
        // No binding (plain Dart test): [end] must be called explicitly.
      }
    }
  }

  void end() {
    _path = null;
    _left = false;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_path == null) return;
    if (state == AppLifecycleState.resumed) {
      if (_left) end();
    } else {
      _left = true;
    }
  }
}

/// First `major.minor[.patch]` found in an APK file name
/// (`watchdog-0.2.1-arm64.apk` -> `0.2.1`); null when there is none.
String? versionInApkName(String name) =>
    RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(name)?.group(0);

String _base(File f) => f.uri.pathSegments.last;

bool _guarded(File f, InstallGuard? g) =>
    g != null && g.active && g.path == f.path;

/// Orphaned partial downloads older than this are removed on launch (a younger
/// one may belong to a download running right now).
const stalePartAge = Duration(minutes: 5);

/// Launch cleanup: deletes downloaded APKs whose version is <=
/// [currentVersion] (the update was installed, or is obsolete) and stale
/// `.part` files. Never touches the APK of an active install ([guard]).
/// Returns the number of files deleted.
Future<int> cleanInstalledUpdates(
  Directory dir, {
  required String currentVersion,
  InstallGuard? guard,
  DateTime? now,
}) async {
  if (!dir.existsSync()) return 0;
  final t = now ?? DateTime.now();
  var n = 0;
  for (final e in dir.listSync(followLinks: false)) {
    if (e is! File || _guarded(e, guard)) continue;
    final name = _base(e);
    var drop = false;
    if (name.endsWith('.apk')) {
      final v = versionInApkName(name);
      drop = v != null && compareVersions(v, currentVersion) <= 0;
    } else if (name.endsWith('.apk.part')) {
      drop = t.difference(e.lastModifiedSync()) >= stalePartAge;
    }
    if (drop && _tryDelete(e)) n++;
  }
  return n;
}

/// Before downloading a new update: deletes every other APK / partial file in
/// [dir]; [keepName] (the verified file a re-download would reuse) and the
/// APK of an active install ([guard]) stay. Returns the number deleted.
Future<int> cleanBeforeDownload(
  Directory dir, {
  String? keepName,
  InstallGuard? guard,
}) async {
  if (!dir.existsSync()) return 0;
  var n = 0;
  for (final e in dir.listSync(followLinks: false)) {
    if (e is! File || _guarded(e, guard)) continue;
    final name = _base(e);
    if (name == keepName) continue;
    if (!name.endsWith('.apk') && !name.endsWith('.apk.part')) continue;
    if (_tryDelete(e)) n++;
  }
  return n;
}

bool _tryDelete(File f) {
  try {
    f.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}
