import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'external_player.dart';
import 'platform_api.dart';

/// FileProvider authority declared in AndroidManifest.xml
/// (`<applicationId>.fileprovider`); exposes only `<cache>/m3u/` as `/m3u/`.
/// Matches `${applicationId}.fileprovider` in AndroidManifest.xml. Debug
/// builds (id suffix `.debug`) pass
/// `--dart-define=FILE_PROVIDER_AUTH=dev.watchdog.watchdog.debug.fileprovider`.
const androidFileProviderAuthority = String.fromEnvironment(
  'FILE_PROVIDER_AUTH',
  defaultValue: 'dev.watchdog.watchdog.fileprovider',
);

const m3uMimeType = 'audio/x-mpegurl';

/// Seam over android_intent_plus so tests need no platform channel.
abstract class IntentLauncher {
  /// True if some activity can handle ACTION_VIEW for [data] + [type].
  Future<bool> canView({required String data, required String type});

  /// Shows the chooser for ACTION_VIEW [data] + [type].
  Future<void> viewChooser({
    required String data,
    required String type,
    required String title,
    List<int> flags = const [],
  });
}

class AndroidIntentLauncher implements IntentLauncher {
  const AndroidIntentLauncher();

  AndroidIntent _intent(String data, String type, List<int> flags) =>
      AndroidIntent(
        action: 'action_view',
        data: data,
        type: type,
        flags: flags.isEmpty ? null : flags,
      );

  @override
  Future<bool> canView({required String data, required String type}) async =>
      await _intent(data, type, const []).canResolveActivity() ?? false;

  @override
  Future<void> viewChooser({
    required String data,
    required String type,
    required String title,
    List<int> flags = const [],
  }) => _intent(data, type, flags).launchChooser(title);
}

class AndroidExternalPlayer {
  AndroidExternalPlayer({
    IntentLauncher launcher = const AndroidIntentLauncher(),
    Future<Directory> Function()? cacheDir,
    Future<List<String>> Function()? downloadRoots,
    Future<String?> Function()? providerRoot,
    Future<String?> Function()? sharedRoot,
  }) : _launcher = launcher, // ignore: prefer_initializing_formals
       _cacheDir = cacheDir ?? getTemporaryDirectory,
       _roots = downloadRoots,
       _providerRoot = providerRoot, // ignore: prefer_initializing_formals
       _sharedRoot = sharedRoot; // ignore: prefer_initializing_formals

  final IntentLauncher _launcher;
  final Future<Directory> Function() _cacheDir;
  final Future<List<String>> Function()? _roots;

  /// `<external files dir>/watchdog` (what file_paths.xml exposes), or null
  /// when external storage is unavailable.
  final Future<String?> Function()? _providerRoot;

  /// `<primary storage>/Movies/watchdog` (served as `/movies/`): where
  /// finished downloads are moved so file managers and other apps see them.
  final Future<String?> Function()? _sharedRoot;

  /// Opens a finished download. [path] must resolve (symlinks included) into
  /// one of the known download roots, and into the FileProvider-exposed folder
  /// (`<external files dir>/watchdog`, `/downloads/` in file_paths.xml);
  /// downloads elsewhere cannot get a content URI and fail with
  /// [ExternalPlayerError.unsupportedLocation].
  Future<void> openLocal(String path, {String? mimeType}) async {
    final r = await resolveLocalPath(path, await _roots!());
    final candidates = [
      ('downloads', await _providerRoot!()),
      if (_sharedRoot != null) ('movies', await _sharedRoot()),
    ];
    var anyRoot = false;
    String? uriPrefix;
    String? rel;
    for (final (name, root) in candidates) {
      if (root == null) continue;
      final String real;
      try {
        real = await Directory(root).resolveSymbolicLinks();
      } on FileSystemException {
        continue;
      }
      anyRoot = true;
      if (p.isWithin(real, r.path)) {
        uriPrefix = name;
        rel = p
            .split(p.relative(r.path, from: real))
            .map(Uri.encodeComponent)
            .join('/');
        break;
      }
    }
    if (!anyRoot) {
      throw const ExternalPlayerException(
        ExternalPlayerError.unsupportedLocation,
        'external storage unavailable; FileProvider cannot serve this file',
      );
    }
    if (uriPrefix == null || rel == null) {
      throw ExternalPlayerException(
        ExternalPlayerError.unsupportedLocation,
        'outside FileProvider folders: ${r.path}',
      );
    }
    final norm = r.path;
    final uri = 'content://$androidFileProviderAuthority/$uriPrefix/$rel';
    await _guard(
      () => _view(uri, mimeType ?? inferVideoMime(norm), p.basename(norm), [
        Flag.FLAG_GRANT_READ_URI_PERMISSION,
      ]),
    );
  }

  Future<void> open(List<ExternalMedia> items) async {
    if (items.isEmpty) return;
    await _guard(() async {
      if (items.length == 1) {
        await _view(items.first.url, 'video/*', items.first.title, const []);
      } else {
        final dir = await _cacheDir();
        final m3uDir = Directory('${dir.path}/m3u')
          ..createSync(recursive: true);
        final file = File('${m3uDir.path}/watchdog_playlist.m3u');
        await file.writeAsString(buildM3u(items), flush: true);
        final uri =
            'content://$androidFileProviderAuthority/m3u/watchdog_playlist.m3u';
        await _view(uri, m3uMimeType, 'watchdog', [
          Flag.FLAG_GRANT_READ_URI_PERMISSION,
        ]);
      }
    });
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on ExternalPlayerException {
      rethrow;
    } on PlatformException catch (e) {
      // android_intent_plus reports every native failure (including
      // ActivityNotFoundException) as PlatformException(code: 'error').
      final msg = e.message ?? '';
      final none = msg.contains('No Activity found');
      throw ExternalPlayerException(
        none ? ExternalPlayerError.noPlayer : ExternalPlayerError.launchFailed,
        msg,
      );
    }
  }

  Future<void> _view(
    String data,
    String type,
    String title,
    List<int> flags,
  ) async {
    if (!await _launcher.canView(data: data, type: type)) {
      throw const ExternalPlayerException(ExternalPlayerError.noPlayer);
    }
    await _launcher.viewChooser(
      data: data,
      type: type,
      title: title,
      flags: flags,
    );
  }
}
