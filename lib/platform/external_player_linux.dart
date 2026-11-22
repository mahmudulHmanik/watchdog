import 'dart:io';

import 'external_player.dart';
import 'platform_api.dart';

/// Seam over Process.start so tests can capture the command line.
abstract class ProcessRunner {
  Future<void> startDetached(String executable, List<String> args);
}

class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();

  @override
  Future<void> startDetached(String executable, List<String> args) async {
    await Process.start(executable, args, mode: ProcessStartMode.detached);
  }
}

/// mpv argument list: single item gets a media title; `--` stops option
/// parsing so a URL can never be read as a flag.
List<String> buildMpvArgs(List<ExternalMedia> items) => [
  if (items.length == 1)
    '--force-media-title=${items.first.title.replaceAll(RegExp(r'[\r\n]+'), ' ')}',
  '--',
  for (final m in items) m.url,
];

class LinuxExternalPlayer {
  const LinuxExternalPlayer({
    this.runner = const IoProcessRunner(),
    this.executable = 'mpv',
    this.downloadRoots,
    this.fallbackOpener = 'xdg-open',
  });

  /// Folders local files must live in (see [openLocal]).
  final Future<List<String>> Function()? downloadRoots;
  final String fallbackOpener;

  final ProcessRunner runner;
  final String executable;

  Future<void> open(List<ExternalMedia> items) async {
    if (items.isEmpty) return;
    try {
      await runner.startDetached(executable, buildMpvArgs(items));
    } on ProcessException catch (e) {
      // Thrown with errorCode 2 (ENOENT) when mpv is not on PATH.
      throw ExternalPlayerException(
        e.errorCode == 2
            ? ExternalPlayerError.noPlayer
            : ExternalPlayerError.launchFailed,
        e.message,
      );
    }
  }

  /// Opens a finished download: mpv first, xdg-open if mpv is missing.
  Future<void> openLocal(String path, {String? mimeType}) async {
    final norm = (await resolveLocalPath(path, await downloadRoots!())).path;
    try {
      await runner.startDetached(executable, ['--', norm]);
    } on ProcessException catch (e) {
      if (e.errorCode != 2) {
        throw ExternalPlayerException(
          ExternalPlayerError.launchFailed,
          e.message,
        );
      }
      try {
        await runner.startDetached(fallbackOpener, [norm]);
      } on ProcessException catch (e2) {
        throw ExternalPlayerException(
          e2.errorCode == 2
              ? ExternalPlayerError.noPlayer
              : ExternalPlayerError.launchFailed,
          e2.message,
        );
      }
    }
  }
}
