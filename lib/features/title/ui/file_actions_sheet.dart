import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/platform/external_player.dart';
import 'package:watchdog/platform/platform_api.dart';

import '../player_actions.dart';
import '../episode_title.dart';
import '../resume.dart';
import '../title_providers.dart';
import 'file_tile.dart' show FileThumb;

/// Plays [file] in-app (episode: its queue from here) then refreshes marks.
Future<void> playInApp(
  BuildContext context,
  WidgetRef ref, {
  required MediaTitle title,
  required MediaFile file,
}) async {
  final repo = ref.read(repositoryProvider);
  final actions = ref.read(playerActionsProvider);
  if (file.seasonId != null) {
    await actions.playEpisode(context, repo, title, file);
  } else {
    await actions.playFile(context, file, title);
  }
  ref.invalidate(titleDetailProvider(title.id));
  ref.invalidate(continueWatchingProvider);
}

/// Human message for a failed download / platform call.
String describeError(Object e) {
  final s = '$e'.toLowerCase();
  if (e is ExternalPlayerException) return e.userMessage;
  if (e is UnimplementedError) return 'Not supported on this platform';
  if (s.contains('permission')) return 'Storage permission denied';
  if (s.contains('cleartext') || s.contains('not permitted')) {
    return 'Host blocked: cleartext HTTP is not allowed for this server';
  }
  if (s.contains('socket') || s.contains('connection')) {
    return 'Server unreachable. Are you on BDIX?';
  }
  return 'Failed: $e';
}

void showToast(
  BuildContext context,
  String text, {
  IconData icon = Icons.check_circle,
  SnackBarAction? action,
  bool error = false,
}) {
  final t = context.tokens;
  final color = error ? t.palette.error : t.palette.ok;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      action: action,
      shape: RoundedRectangleBorder(
        borderRadius: t.radius(12),
        side: t.box
            ? BorderSide(color: color, width: 2)
            : BorderSide(color: t.border),
      ),
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

/// Queue a download; toast with a "View" action to the Downloads tab.
Future<void> startDownload(
  BuildContext context,
  WidgetRef ref,
  MediaFile file,
) async {
  final platform = ref.read(platformApiProvider);
  try {
    await platform.enqueueDownload(file.url, file.name, fileId: file.id);
    if (!context.mounted) return;
    showToast(
      context,
      'Download queued',
      action: SnackBarAction(
        label: 'View',
        onPressed: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          ref.read(navIndexProvider.notifier).go(tabDownloads);
        },
      ),
    );
  } catch (e) {
    if (context.mounted) showToast(context, describeError(e), error: true);
  }
}

class _Action extends StatelessWidget {
  const _Action(
    this.icon,
    this.label,
    this.sub,
    this.onTap, {
    this.accent = false,
  });
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 24, color: accent ? context.tokens.accent : null),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Episode/file actions: header + Play, Play from here, external, Download,
/// Copy link, Mark watched.
Future<void> showFileActions(
  BuildContext context,
  WidgetRef ref, {
  required MediaTitle title,
  required MediaFile file,
  required bool watched,
  WatchState? state,
  List<MediaFile> siblings = const [],
}) {
  final platform = ref.read(platformApiProvider);
  final repo = ref.read(repositoryProvider);
  final isEpisode = file.seasonId != null;
  final last = siblings.isEmpty ? null : siblings.last;
  final fromHere = isEpisode && last != null && last.id != file.id
      ? '${episodeLabel(file)} -> ${episodeLabel(last)} as a playlist'
      : 'Continue through the season';
  final q = qualityOfName(file.name) ?? title.quality;
  final meta = [
    if (state != null && state.durationMs > 0) clock(state.durationMs),
    if (q != null) '${q}p',
    if (file.sizeKb != null) formatSizeKb(file.sizeKb),
    file.ext.toUpperCase(),
  ].join(' · ');

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      void run(Future<void> Function() f) {
        Navigator.pop(ctx);
        f().catchError((Object e) {
          if (context.mounted) {
            showToast(context, describeError(e), error: true);
          }
        });
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    FileThumb(width: 96, height: 54, state: state),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEpisode
                                ? [
                                    if (episodeLabel(file).isNotEmpty)
                                      episodeLabel(file),
                                    cleanEpisodeTitle(
                                      file.name,
                                      title.name,
                                      episode: file.episode,
                                    ),
                                  ].join(' · ')
                                : file.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isEpisode)
                            Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          Text(
                            file.playable ? meta : '$meta · Not playable',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (file.playable)
                _Action(
                  Icons.play_arrow,
                  'Play',
                  'In-app player',
                  accent: true,
                  () => run(() async {
                    if (isEpisode) {
                      await ref
                          .read(playerActionsProvider)
                          .playEpisode(context, repo, title, file);
                    } else {
                      await ref
                          .read(playerActionsProvider)
                          .playFile(context, file, title);
                    }
                    ref.invalidate(titleDetailProvider(title.id));
                    ref.invalidate(continueWatchingProvider);
                  }),
                ),
              if (file.playable && isEpisode)
                _Action(
                  Icons.playlist_play,
                  'Play from here',
                  fromHere,
                  () => run(
                    () => playInApp(context, ref, title: title, file: file),
                  ),
                ),
              if (file.playable)
                _Action(
                  Icons.open_in_new,
                  'Open in external player',
                  'VLC, MX Player, mpv...',
                  () => run(
                    () => platform.openExternal([
                      ExternalMedia(
                        url: file.url,
                        title: '${title.name} - ${file.name}',
                      ),
                    ]),
                  ),
                ),
              _Action(
                Icons.download,
                'Download',
                'Save to the downloads folder',
                () => run(() => startDownload(context, ref, file)),
              ),
              _Action(
                Icons.link,
                'Copy link',
                'Direct BDIX URL',
                () => run(() async {
                  await platform.copyUrl(file.url);
                  if (context.mounted) showToast(context, 'Link copied');
                }),
              ),
              if (file.playable)
                _Action(
                  watched ? Icons.visibility_off : Icons.check,
                  watched ? 'Mark as unwatched' : 'Mark as watched',
                  watched ? 'Reset progress' : 'Hide from continue watching',
                  () => run(() async {
                    await repo.markWatched(file.id, watched: !watched);
                    ref.invalidate(titleDetailProvider(title.id));
                    ref.invalidate(continueWatchingProvider);
                  }),
                ),
            ],
          ),
        ),
      );
    },
  );
}
