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
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/features/player/ui/player_gestures.dart';
import 'package:watchdog/features/player/ui/track_sheet.dart';
import 'package:watchdog/features/title/episode_title.dart';
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

  /// Set when the player could not be created (never leave a silent spinner).
  String? _fatal;
  bool _disposed = false;
  bool _controls = true;
  bool _fullscreen = false;
  Timer? _hide;
  final _focus = FocusNode();
  final _videoKey = GlobalKey();

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// Side-by-side layout (video | playlist) from this width up (desktop).
  static const _wideBreakpoint = 840.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Opens like YouTube: video pinned to the top in portrait, fullscreen on
    // demand.
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setPreferredOrientations(_portrait));
    }
    unawaited(_create());
  }

  static const _portrait = [DeviceOrientation.portraitUp];

  Future<void> _create() async {
    try {
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
    } catch (e, st) {
      debugPrint('player create failed: $e\n$st');
      if (mounted) setState(() => _fatal = '$e');
    }
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
    // Restores system bars and lets the rest of the app rotate freely.
    if (Platform.isAndroid || _fullscreen) {
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

  void _onVideoTap() => _controls ? setState(() => _controls = false) : _poke();

  Future<void> _setFullscreen(bool on) async {
    if (_fullscreen == on) return;
    setState(() => _fullscreen = on);
    if (on) {
      await defaultEnterNativeFullscreen();
    } else {
      await defaultExitNativeFullscreen();
      // Back to the pinned-top portrait layout.
      if (Platform.isAndroid) {
        await SystemChrome.setPreferredOrientations(_portrait);
      }
    }
    _poke();
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
    } else if (k == LogicalKeyboardKey.arrowUp) {
      s.player.setVolume((s.player.state.volume + 5).clamp(0.0, 100.0));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      s.player.setVolume((s.player.state.volume - 5).clamp(0.0, 100.0));
    } else if (k == LogicalKeyboardKey.keyF) {
      _setFullscreen(!_fullscreen);
    } else if (k == LogicalKeyboardKey.escape) {
      if (_fullscreen) {
        _setFullscreen(false);
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
    return PopScope(
      // In fullscreen, back (button / gesture) first returns to the pinned
      // layout instead of closing the player.
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) unawaited(_setFullscreen(false));
      },
      child: Scaffold(
        backgroundColor: _fullscreen ? Colors.black : null,
        body: Focus(
          autofocus: true,
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: s != null
              ? _body(context, s)
              : _fatal != null
              ? _fatalView(context, _fatal!)
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Widget _fatalView(BuildContext context, String msg) => SafeArea(
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BackButton(onPressed: () => Navigator.maybePop(context)),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 36),
                  const SizedBox(height: 8),
                  const Text("Couldn't start the player"),
                  const SizedBox(height: 8),
                  Text(
                    msg,
                    textAlign: TextAlign.center,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _body(BuildContext context, PlayerSession s) {
    if (_fullscreen) return _videoBox(context, s);
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= _wideBreakpoint) {
          return Row(
            children: [
              Expanded(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _videoBox(context, s),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 360, child: _infoPanel(context, s)),
            ],
          );
        }
        return Column(
          children: [
            ColoredBox(
              color: Colors.black,
              child: SafeArea(
                bottom: false,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _videoBox(context, s),
                ),
              ),
            ),
            Expanded(child: _infoPanel(context, s)),
          ],
        );
      },
    );
  }

  /// Video + gestures + controls. One [GlobalKey] keeps the texture alive
  /// while the box moves between the pinned and fullscreen layouts.
  Widget _videoBox(BuildContext context, PlayerSession s) => KeyedSubtree(
    key: _videoKey,
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
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
                  fontSize: (_fullscreen ? 32.0 : 20.0) * st.scale,
                  color: st.yellow
                      ? const Color(0xFFFFFF00)
                      : const Color(0xFFFFFFFF),
                  backgroundColor: st.box ? const Color(0xAA000000) : null,
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  24 + (100 - st.pos) * (_fullscreen ? 3.0 : 1.0),
                ),
              ),
            ),
          ),
          PlayerGestureLayer(session: s, onTap: _onVideoTap, onActivity: _poke),
          ValueListenableBuilder<SessionState>(
            valueListenable: s.state,
            builder: (context, st, _) => Stack(
              fit: StackFit.expand,
              children: [
                _buffering(s),
                if (_controls) _controlsLayer(context, s, st),
                if (st.error != null)
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _errorCard(context, s, st),
                    ),
                  ),
                if (st.countdown != null && st.error == null)
                  _countdownCard(context, s, st),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _infoPanel(BuildContext context, PlayerSession s) =>
      ValueListenableBuilder<SessionState>(
        valueListenable: s.state,
        builder: (context, st, _) => _InfoPanel(
          title: widget.title,
          state: st,
          onPick: (i) {
            s.playIndex(i);
            _poke();
          },
        ),
      );

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
    return Stack(
      fit: StackFit.expand,
      children: [
        // Shade only: never absorbs taps, so gestures work under the controls.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xCC000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                ],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
        ),
        SafeArea(
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
                  IconButton(
                    tooltip: _fullscreen ? 'Exit fullscreen' : 'Fullscreen (F)',
                    color: Colors.white,
                    icon: Icon(
                      _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                    onPressed: () => _setFullscreen(!_fullscreen),
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
      ],
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

/// Title block + playlist under (or beside) the video.
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.state,
    required this.onPick,
  });
  final MediaTitle? title;
  final SessionState state;
  final ValueChanged<int> onPick;

  static final _ext = RegExp(r'\.[A-Za-z0-9]{2,4}$');

  String _label(MediaFile f) => f.seasonId == null
      ? f.name.replaceFirst(_ext, '')
      : cleanEpisodeTitle(f.name, title?.name ?? '', episode: f.episode);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pl = state.playlist;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title?.name ?? _label(state.file),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _label(state.file),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: t.border),
        if (pl.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              'Playlist · ${pl.index + 1}/${pl.length}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        Expanded(
          child: pl.length > 1
              ? _PlaylistList(
                  labels: [for (final f in pl.items) _label(f)],
                  index: pl.index,
                  onPick: onPick,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _PlaylistList extends StatefulWidget {
  const _PlaylistList({
    required this.labels,
    required this.index,
    required this.onPick,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onPick;

  @override
  State<_PlaylistList> createState() => _PlaylistListState();
}

class _PlaylistListState extends State<_PlaylistList> {
  static const _extent = 56.0;
  late final ScrollController _ctl;

  double _offsetFor(int i) =>
      (i * _extent - _extent).clamp(0.0, double.infinity);

  @override
  void initState() {
    super.initState();
    _ctl = ScrollController(initialScrollOffset: _offsetFor(widget.index));
  }

  @override
  void didUpdateWidget(_PlaylistList old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && _ctl.hasClients) {
      final max = _ctl.position.maxScrollExtent;
      _ctl.animateTo(
        _offsetFor(widget.index).clamp(0.0, max),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView.builder(
      controller: _ctl,
      // No inherited status-bar padding (this list is not at the screen top);
      // keep the last row clear of the gesture bar.
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      itemExtent: _extent,
      itemCount: widget.labels.length,
      itemBuilder: (_, i) {
        final cur = i == widget.index;
        return InkWell(
          onTap: () => widget.onPick(i),
          child: Container(
            decoration: cur
                ? BoxDecoration(
                    color: t.hi,
                    border: Border(left: BorderSide(color: t.accent, width: 3)),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: cur
                      ? Icon(Icons.play_arrow, size: 18, color: t.accent)
                      : Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: Text(
                    widget.labels[i],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: cur ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
