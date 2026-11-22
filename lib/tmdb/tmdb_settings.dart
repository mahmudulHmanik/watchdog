/// User settings for TMDB: the credential (secret) and plain preferences.
///
/// The credential is never logged, printed or put in the JSON settings file.
/// Android: Android Keystore through `flutter_secure_storage`.
/// Linux: a 0600 file in the app support dir (see [FileSecretStore]); the
/// libsecret keyring is not used because it needs a running secret-service
/// daemon, which a plain user-space desktop often lacks.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Non-secret TMDB preferences.
class TmdbSettings {
  const TmdbSettings({this.backgroundFetch = true, this.language = 'en-US'});

  /// Fill metadata for the whole library in the background (needs a key).
  final bool backgroundFetch;

  /// TMDB `language` parameter, e.g. `en-US`.
  final String language;

  TmdbSettings copyWith({bool? backgroundFetch, String? language}) =>
      TmdbSettings(
        backgroundFetch: backgroundFetch ?? this.backgroundFetch,
        language: language ?? this.language,
      );

  Map<String, Object?> toJson() => {
    'backgroundFetch': backgroundFetch,
    'language': language,
  };

  /// Missing or malformed values fall back to the defaults.
  factory TmdbSettings.fromJson(Map<String, Object?> j) => TmdbSettings(
    backgroundFetch: j['backgroundFetch'] != false,
    language: _validLanguage(j['language']) ?? 'en-US',
  );

  static final _lang = RegExp(r'^[a-z]{2,3}(-[A-Z]{2})?$');
  static String? _validLanguage(Object? v) =>
      v is String && _lang.hasMatch(v) ? v : null;

  /// True for tags like `en-US`, `hi-IN`, `fr`.
  static bool isValidLanguage(String v) => _lang.hasMatch(v);
}

/// Where the credential lives. Implementations must not log values.
abstract interface class SecretStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class MemorySecretStore implements SecretStore {
  MemorySecretStore([this.value]);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

/// Android Keystore (Linux/other platforms: see [FileSecretStore]).
class KeystoreSecretStore implements SecretStore {
  KeystoreSecretStore({FlutterSecureStorage? storage})
    : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _key = 'tmdb_credential';

  @override
  Future<String?> read() async {
    try {
      return await _s.read(key: _key);
    } catch (_) {
      // A broken keystore entry (restored backup, changed lock screen) reads
      // as "no key"; the user just pastes it again.
      return null;
    }
  }

  @override
  Future<void> write(String v) => _s.write(key: _key, value: v);

  @override
  Future<void> delete() => _s.delete(key: _key);
}

/// Credential in a file only the current user can read (mode 0600, parent
/// directory 0700), written atomically. Used on Linux.
class FileSecretStore implements SecretStore {
  FileSecretStore(this.file);
  final File file;

  @override
  Future<String?> read() async {
    try {
      final v = (await file.readAsString()).trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String v) async {
    await file.parent.create(recursive: true);
    await _chmod('700', file.parent.path);
    final tmp = File('${file.path}.tmp');
    // Create empty, restrict, only then put the secret in.
    await tmp.writeAsString('');
    await _chmod('600', tmp.path);
    await tmp.writeAsString(v, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete() async {
    try {
      await file.delete();
    } on FileSystemException {
      // already gone
    }
  }

  static Future<void> _chmod(String mode, String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', [mode, path]);
    } catch (_) {
      // best effort; the parent directory is app-private anyway
    }
  }
}

/// Settings plus credential. [load] never throws.
abstract interface class TmdbSettingsStore {
  Future<TmdbSettings> load();
  Future<void> save(TmdbSettings s);

  /// The stored credential text, or null when none is set.
  Future<String?> readCredential();
  Future<void> writeCredential(String credential);
  Future<void> clearCredential();
}

class MemoryTmdbSettingsStore implements TmdbSettingsStore {
  MemoryTmdbSettingsStore({
    this.value = const TmdbSettings(),
    String? credential,
  }) : _secret = MemorySecretStore(credential);
  TmdbSettings value;
  final MemorySecretStore _secret;

  @override
  Future<TmdbSettings> load() async => value;
  @override
  Future<void> save(TmdbSettings s) async => value = s;
  @override
  Future<String?> readCredential() => _secret.read();
  @override
  Future<void> writeCredential(String c) => _secret.write(c);
  @override
  Future<void> clearCredential() => _secret.delete();
}

/// JSON file for the plain settings (like the theme store) and a
/// [SecretStore] for the credential.
class FileTmdbSettingsStore implements TmdbSettingsStore {
  FileTmdbSettingsStore(this.file, this.secrets);
  final File file;
  final SecretStore secrets;

  /// Keystore on Android, 0600 file on Linux, in [supportDir].
  factory FileTmdbSettingsStore.platform(Directory supportDir) =>
      FileTmdbSettingsStore(
        File('${supportDir.path}/tmdb.json'),
        Platform.isAndroid
            ? KeystoreSecretStore()
            : FileSecretStore(File('${supportDir.path}/secrets/tmdb.key')),
      );

  @override
  Future<TmdbSettings> load() async {
    try {
      return TmdbSettings.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return const TmdbSettings();
    }
  }

  @override
  Future<void> save(TmdbSettings s) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(s.toJson()));
  }

  @override
  Future<String?> readCredential() => secrets.read();
  @override
  Future<void> writeCredential(String c) => secrets.write(c.trim());
  @override
  Future<void> clearCredential() => secrets.delete();
}
