import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/player/player_launcher.dart';

/// In-app playback entry points used by the UI. A seam so widget tests can
/// fake playback without media_kit; the default delegates to [PlayerLauncher].
abstract class PlayerActions {
  Future<void> playFile(BuildContext c, MediaFile f, MediaTitle t);

  /// Episode with its season queue; "play from here" semantics.
  Future<bool> playEpisode(
    BuildContext c,
    Repository repo,
    MediaTitle t,
    MediaFile f,
  );

  Future<bool> playSeason(
    BuildContext c,
    Repository repo,
    MediaTitle t,
    int seasonId,
  );
}

class DefaultPlayerActions implements PlayerActions {
  const DefaultPlayerActions();

  @override
  Future<void> playFile(BuildContext c, MediaFile f, MediaTitle t) =>
      PlayerLauncher.openFile(c, f, title: t);

  @override
  Future<bool> playEpisode(
    BuildContext c,
    Repository repo,
    MediaTitle t,
    MediaFile f,
  ) => PlayerLauncher.openEpisode(
    c,
    repo,
    titleId: t.id,
    fileId: f.id,
    title: t,
  );

  @override
  Future<bool> playSeason(
    BuildContext c,
    Repository repo,
    MediaTitle t,
    int seasonId,
  ) => PlayerLauncher.openSeason(
    c,
    repo,
    titleId: t.id,
    seasonId: seasonId,
    title: t,
  );
}

final playerActionsProvider = Provider<PlayerActions>(
  (ref) => const DefaultPlayerActions(),
);
