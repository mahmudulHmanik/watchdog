import 'package:material_ui/material_ui.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/player/ui/player_screen.dart';
import 'package:watchdog/features/series/domain/playlist.dart';

/// Public entry points for starting playback (used by title/episode UI).
///
/// Every method pushes a [PlayerScreen]; the media_kit Player is created
/// when that route builds and disposed when it is popped. Resume position is
/// applied automatically from `Repository.watchState`.
abstract final class PlayerLauncher {
  /// Play [playlist] (non-playable files are dropped) starting at
  /// [startIndex] of the list as given. Returns false when nothing playable.
  /// Earlier items stay reachable through "previous"; use
  /// `Playlist.fromIndex` semantics yourself if you want them dropped.
  static Future<bool> open(
    BuildContext context, {
    required List<MediaFile> playlist,
    int startIndex = 0,
    MediaTitle? title,
  }) async {
    final startId = startIndex >= 0 && startIndex < playlist.length
        ? playlist[startIndex].id
        : null;
    final pl = PlaylistBuilder.fromFiles(playlist, startFileId: startId);
    if (pl == null) return false;
    await openPlaylist(context, pl, title: title);
    return true;
  }

  /// Play a file that is already on this device (a finished download).
  /// [fileId] links it to the indexed `MediaFile` so resume / watched marks
  /// work; without it the file just plays.
  static Future<void> openLocal(
    BuildContext context, {
    required String path,
    int? fileId,
    MediaTitle? title,
  }) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final file = MediaFile(
      id: fileId ?? -1,
      titleId: title?.id ?? -1,
      name: name,
      url: path,
      ext: dot < 0 ? '' : name.substring(dot + 1).toLowerCase(),
      playable: true,
    );
    return openPlaylist(context, PlaylistBuilder.single(file), title: title);
  }

  /// Play one file (e.g. a movie).
  static Future<void> openFile(
    BuildContext context,
    MediaFile file, {
    MediaTitle? title,
  }) => openPlaylist(context, PlaylistBuilder.single(file), title: title);

  /// Play an episode of a series: queue is its season plus following seasons
  /// of the same language variant (specials stay separate). Prev/next and
  /// autoplay work across the whole queue. Returns false when [fileId] is not
  /// a playable episode of [titleId].
  static Future<bool> openEpisode(
    BuildContext context,
    Repository repo, {
    required int titleId,
    required int fileId,
    MediaTitle? title,
  }) async {
    final pl = PlaylistBuilder.forEpisode(await repo.seasons(titleId), fileId);
    if (pl == null || !context.mounted) return false;
    await openPlaylist(context, pl, title: title);
    return true;
  }

  /// Play a season from its first playable episode ("Play season").
  static Future<bool> openSeason(
    BuildContext context,
    Repository repo, {
    required int titleId,
    required int seasonId,
    MediaTitle? title,
  }) async {
    final pl = PlaylistBuilder.forSeason(await repo.seasons(titleId), seasonId);
    if (pl == null || !context.mounted) return false;
    await openPlaylist(context, pl, title: title);
    return true;
  }

  /// Lowest-level: push the screen for a prepared [Playlist].
  static Future<void> openPlaylist(
    BuildContext context,
    Playlist playlist, {
    MediaTitle? title,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlayerScreen(playlist: playlist, title: title),
    ),
  );
}
