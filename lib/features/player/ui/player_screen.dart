import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/player/domain/subtitle_style.dart';
import 'package:watchdog/features/player/player_providers.dart';
import 'package:watchdog/features/player/player_session.dart';
import 'package:watchdog/features/player/ui/track_sheet.dart';
import 'package:watchdog/features/series/domain/playlist.dart';
import 'package:watchdog/data/repository.dart';

/// Full-screen player. The media_kit Player exists only while this screen is
/// mounted (created in initState, disposed in dispose). Open it through
/// `PlayerLauncher`.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.playlist, this.title});
  final Playlist playlist;

  /// Shown above the file name (series / movie name).
  final MediaTitle? title;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  PlayerSession? _session;
  bool _disposed = false;
  bool _controls = true;
  bool _fullscreen = false;
  bool _landscape = true;
  Timer? _hide;
  final _focus = FocusNode();

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      _fullscreen = true;
      unawaited(defaultEnterNativeFullscreen());
    }
    unawaited(_create());
  }

  Future<void> _create() async {
    final settings = await ref.read(playerSettingsProvider.future);
    if (_disposed) return;
    String? cache;
    try {
      cache = (await getTemporaryDirectory()).path;
    } catch (_) {}
    if (_disposed) return;
    final s = PlayerSession(
      cacheDir: cache,
      repo: ref.read(repositoryProvider),
      settings: settings,
      playlist: widget.playlist,
      onSubtitleStyle: (st) => unawaited(
        ref.read(playerSettingsProvider.notifier).setSubtitleStyle(st),
      ),
    );
    setState(() => _session = s);
    _poke();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding: persist the position. (The Video widget pauses playback
    // on background by default and releases the wakelock.)
    if (state != AppLifecycleState.resumed) unawaited(_session?.flush());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _hide?.cancel();
    _focus.dispose();
    unawaited(_session?.dispose());
    _session = null;
    if (Platform.isAndroid) {
      unawaited(defaultExitNativeFullscreen());
    } else if (_fullscreen) {
      unawaited(defaultExitNativeFullscreen());
    }
    super.dispose();
  }

  void _poke() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && (_session?.player.state.playing ?? false)) {
        setState(() => _controls = false);
      }
    });
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    if (_fullscreen) {
      await defaultEnterNativeFullscreen();
    } else {
      await defaultExitNativeFullscreen();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleOrientation() async {
    _landscape = !_landscape;
    await SystemChrome.setPreferredOrientations(
      _landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final s = _session;
    if (s == null || e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space) {
      s.player.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      s.seekBy(const Duration(seconds: -10));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      s.seekBy(const Duration(seconds: 10));
    } else if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.escape) {
      if (_fullscreen && !Platform.isAndroid) {
        _toggleFullscreen();
      } else {
        Navigator.maybePop(context);
      }
    } else {
      return KeyEventResult.ignored;
    }
    _poke();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: s == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                fit: StackFit.expand,
                children: [
                  ValueListenableBuilder<SubtitleStyle>(
                    valueListenable: s.subStyle,
                    builder: (_, st, _) => Video(
                      controller: s.video,
                      controls: NoVideoControls,
                      fill: Colors.black,
                      wakelock: true,
                      subtitleViewConfiguration: SubtitleViewConfiguration(
                        visible: !PlayerSession.useMpvSubtitles,
                        style: TextStyle(
                          height: 1.4,
                          fontSize: 32.0 * st.scale,
                          color: st.yellow
                              ? const Color(0xFFFFFF00)
                              : const Color(0xFFFFFFFF),
                          backgroundColor: st.box
                              ? const Color(0xAA000000)
                              : null,
                        ),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          24 + (100 - st.pos) * 3.0,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () =>
                        _controls ? setState(() => _controls = false) : _poke(),
                    onDoubleTap: s.player.playOrPause,
                  ),
                  ValueListenableBuilder<SessionState>(
                    valueListenable: s.state,
                    builder: (context, st, _) => Stack(
                      fit: StackFit.expand,
                      children: [
                        _buffering(s),
                        if (_controls) _controlsLayer(context, s, st),
                        if (st.error != null) _errorCard(context, s, st),
                        if (st.countdown != null && st.error == null)
                          _countdownCard(context, s, st),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buffering(PlayerSession s) => IgnorePointer(
    child: StreamBuilder<bool>(
      stream: s.player.stream.buffering,
      initialData: s.player.state.buffering,
      builder: (_, b) => Center(
        child: (b.data ?? false)
            ? const CircularProgressIndicator()
            : const SizedBox.shrink(),
      ),
    ),
  );

  Widget _controlsLayer(
    BuildContext context,
    PlayerSession s,
    SessionState st,
  ) {
    final p = s.player;
    final pl = st.playlist;
    const white = TextStyle(color: Colors.white);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000), Color(0xCC000000)],
          stops: [0, 0.5, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                BackButton(
                  color: Colors.white,
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.title != null)
                        Text(
                          widget.title!.name,
                          style: white,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        '${pl.length > 1 ? '${pl.index + 1}/${pl.length}  ' : ''}${st.file.name}',
                        style: white.copyWith(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Audio & subtitles',
                  color: Colors.white,
                  icon: const Icon(Icons.subtitles_outlined),
                  onPressed: () async {
                    _hide?.cancel();
                    await showTrackSheet(context, s);
                    _poke();
                  },
                ),
                PopupMenuButton<double>(
                  tooltip: 'Speed',
                  icon: const Icon(Icons.speed, color: Colors.white),
                  initialValue: p.state.rate,
                  onSelected: (v) {
                    p.setRate(v);
                    _poke();
                  },
                  itemBuilder: (_) => [
                    for (final v in _speeds)
                      PopupMenuItem(value: v, child: Text('${v}x')),
                  ],
                ),
                if (Platform.isAndroid)
                  IconButton(
                    tooltip: 'Rotate',
                    color: Colors.white,
                    icon: const Icon(Icons.screen_rotation),
                    onPressed: _toggleOrientation,
                  )
                else
                  IconButton(
                    tooltip: 'Fullscreen (F)',
                    color: Colors.white,
                    icon: Icon(
                      _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                    onPressed: _toggleFullscreen,
                  ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SeekBar(session: s, onInteract: _poke),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous',
                  color: Colors.white,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () {
                    s.prev();
                    _poke();
                  },
                ),
                IconButton(
                  tooltip: 'Back 10 s',
                  color: Colors.white,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () {
                    s.seekBy(const Duration(seconds: -10));
                    _poke();
                  },
                ),
                StreamBuilder<bool>(
                  stream: p.stream.playing,
                  initialData: p.state.playing,
                  builder: (_, pl) => IconButton(
                    tooltip: (pl.data ?? false) ? 'Pause' : 'Play',
                    iconSize: 44,
                    color: Colors.white,
                    icon: Icon(
                      (pl.data ?? false)
                          ? Icons.pause_circle
                          : Icons.play_circle,
                    ),
                    onPressed: () {
                      p.playOrPause();
                      _poke();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Forward 10 s',
                  color: Colors.white,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () {
                    s.seekBy(const Duration(seconds: 10));
                    _poke();
                  },
                ),
                IconButton(
                  tooltip: 'Next',
                  color: Colors.white,
                  icon: const Icon(Icons.skip_next),
                  onPressed: pl.hasNext
                      ? () {
                          s.next();
                          _poke();
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, PlayerSession s, SessionState st) =>
      Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 36),
                const SizedBox(height: 8),
                Text(
                  st.error!,
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
                if (st.countdown != null) ...[
                  const SizedBox(height: 8),
                  Text('${st.countdownLabel} in ${st.countdown}s'),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: s.retry,
                      child: const Text('Retry'),
                    ),
                    if (st.countdown != null)
                      TextButton(
                        onPressed: s.cancelCountdown,
                        child: const Text('Cancel'),
                      ),
                    if (st.playlist.hasNext)
                      TextButton(onPressed: s.next, child: const Text('Skip')),
                    TextButton(
                      onPressed: () => Navigator.maybePop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  Widget _countdownCard(
    BuildContext context,
    PlayerSession s,
    SessionState st,
  ) => Align(
    alignment: Alignment.bottomRight,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${st.countdownLabel} in ${st.countdown}s'),
                Text(
                  st.playlist.nextFile?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: s.advanceNow,
                      child: const Text('Play now'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: s.cancelCountdown,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Seek slider with a buffered-range bar behind it.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, required this.session, this.onInteract});
  final PlayerSession session;
  final VoidCallback? onInteract;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.session.player;
    return StreamBuilder<Duration>(
      stream: p.stream.duration,
      initialData: p.state.duration,
      builder: (_, d) => StreamBuilder<Duration>(
        stream: p.stream.position,
        initialData: p.state.position,
        builder: (_, pos) => StreamBuilder<Duration>(
          stream: p.stream.buffer,
          initialData: p.state.buffer,
          builder: (_, buf) {
            final dur = d.data ?? Duration.zero;
            final total = dur.inMilliseconds.toDouble();
            final cur =
                (_drag ?? (pos.data ?? Duration.zero).inMilliseconds.toDouble())
                    .clamp(0.0, total > 0 ? total : 1.0);
            final b = total > 0
                ? ((buf.data ?? Duration.zero).inMilliseconds / total).clamp(
                    0.0,
                    1.0,
                  )
                : 0.0;
            const white = TextStyle(color: Colors.white, fontSize: 12);
            return Row(
              children: [
                Text(_fmt(Duration(milliseconds: cur.toInt())), style: white),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: LinearProgressIndicator(
                          value: b,
                          minHeight: 3,
                          color: Colors.white38,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context)
                            .copyWith(inactiveTrackColor: Colors.transparent),
                        child: Slider(
                          value: cur,
                          max: total > 0 ? total : 1.0,
                          onChanged: total > 0
                              ? (v) {
                                  setState(() => _drag = v);
                                  widget.onInteract?.call();
                                }
                              : null,
                          onChangeEnd: (v) async {
                            await widget.session.seek(
                              Duration(milliseconds: v.toInt()),
                            );
                            if (mounted) setState(() => _drag = null);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Text(_fmt(dur), style: white),
              ],
            );
          },
        ),
      ),
    );
  }
}
