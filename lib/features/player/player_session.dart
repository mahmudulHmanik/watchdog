import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/series/domain/playlist.dart';

import 'domain/decoder_recovery.dart';
import 'domain/mpv_tuning.dart';
import 'domain/player_settings.dart';
import 'domain/resume.dart';
import 'domain/start_gate.dart';
import 'domain/subtitle_style.dart';
import 'domain/track_prefs.dart';

/// UI-visible session state (everything not exposed by player streams).
@immutable
class SessionState {
  const SessionState({
    required this.playlist,
    this.error,
    this.countdown,
    this.countdownLabel,
    this.resumedFrom,
    this.decoderFailure = false,
  });
  final Playlist playlist;

  /// Human readable failure for the current file; null when fine.
  final String? error;

  /// Seconds left before the next file starts (autoplay / skip-after-error).
  final int? countdown;

  /// Why the countdown runs: "Next episode" or "Skipping broken file".
  final String? countdownLabel;

  /// Position this file was resumed from, if it was.
  final Duration? resumedFrom;

  /// [error] is a decoder failure (software retry done / not possible): the
  /// UI offers the external player and nothing auto-skips.
  final bool decoderFailure;

  MediaFile get file => playlist.current;

  SessionState copyWith({
    Playlist? playlist,
    Object? error = _k,
    Object? countdown = _k,
    Object? countdownLabel = _k,
    Object? resumedFrom = _k,
    bool? decoderFailure,
  }) => SessionState(
    playlist: playlist ?? this.playlist,
    error: identical(error, _k) ? this.error : error as String?,
    countdown: identical(countdown, _k) ? this.countdown : countdown as int?,
    countdownLabel: identical(countdownLabel, _k)
        ? this.countdownLabel
        : countdownLabel as String?,
    resumedFrom: identical(resumedFrom, _k)
        ? this.resumedFrom
        : resumedFrom as Duration?,
    decoderFailure: decoderFailure ?? this.decoderFailure,
  );

  static const _k = Object();
}

/// Owns one media_kit [Player] for the lifetime of the player screen.
/// Created in the screen's initState, [dispose]d in its dispose: that is the
/// only place a Player exists.
class PlayerSession {
  PlayerSession({
    required this.repo,
    required this.settings,
    required Playlist playlist,
    this.countdownSeconds = 5,
    this.onSubtitleStyle,
    this.onHwdecAutoOff,
    this.cacheDir,
    this.graceTimer,
  }) : subStyle = ValueNotifier(settings.subtitleStyle),
       state = ValueNotifier(SessionState(playlist: playlist)) {
    _tracker = ProgressTracker(
      (id, {required positionMs, required durationMs}) =>
          repo.setProgress(id, positionMs: positionMs, durationMs: durationMs),
    );
    player = Player(
      configuration: PlayerConfiguration(
        title: 'watchdog',
        // mpv renders subtitles (ASS styling, sub-* props) on Linux. On Android
        // libass needs a bundled font (libassAndroidFont), so there the
        // Flutter SubtitleView draws plain text instead.
        libass: useMpvSubtitles,
        bufferSize: bufferBytes(android: Platform.isAndroid),
      ),
    );
    video = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        hwdec: hwdecValue(settings.hwdec),
      ),
    );
    _stats = startMpvStatsLog(player);
    _recovery = DecoderRecovery(
      hwOn: settings.hwdec == HwdecMode.auto,
      started: _started,
      timer: graceTimer,
      onRetrySoftware: () => unawaited(_retrySoftware()),
      onGiveUp: _failDecoder,
      onSoftwareWorked: () => onHwdecAutoOff?.call(),
    );
    _subs.addAll([
      player.stream.position.listen(_onPosition),
      player.stream.duration.listen(_onDuration),
      player.stream.playing.listen(_onPlaying),
      player.stream.completed.listen(_onCompleted),
      player.stream.error.listen(_onError),
      player.stream.tracks.listen(_onTracks),
    ]);
    _target = playlist;
    unawaited(_boot(playlist));
  }

  Future<void> _boot(Playlist first) async {
    try {
      // Bounded: a stuck property call must never keep the file from opening.
      await applyStreamTuning(player).timeout(const Duration(seconds: 5));
      if (_disposed) return;
      await _applyStyle(subStyle.value).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('player boot: $e');
    }
    if (_disposed) return;
    await _requestStart(first);
  }

  /// True when mpv/libass draws subtitles (Linux); false = Flutter SubtitleView.
  static bool get useMpvSubtitles => !Platform.isAndroid;

  final Repository repo;
  final ValueNotifier<SubtitleStyle> subStyle;
  final void Function(SubtitleStyle)? onSubtitleStyle;

  /// Called once when a software retry made a file play after hardware
  /// decoding failed: persist "hardware decoding off (automatic)".
  final void Function()? onHwdecAutoOff;

  /// Test hook for the decoder-error grace window.
  final GraceTimerFactory? graceTimer;
  final PlayerSettings settings;

  /// App cache dir: external subtitle copies made there (Android file picker)
  /// are deleted when replaced / on file change / on dispose. Files outside
  /// it are never deleted.
  final String? cacheDir;
  final int countdownSeconds;
  final ValueNotifier<SessionState> state;
  late final Player player;
  late final VideoController video;
  late final ProgressTracker _tracker;
  late final DecoderRecovery _recovery;
  Timer? _stats;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _countdown;
  bool _disposed = false;
  bool _opened = false;
  bool _armedOnce = false;
  bool _audioApplied = false;
  bool _userPickedAudio = false;
  Duration _resumeStart = Duration.zero;
  Duration _lastPosition = Duration.zero;
  final _runner = LatestWinsRunner();
  final _gate = EventGate();
  late Playlist _target;
  final _failures = FailureStreak();
  String? _ownedSub;

  // VideoController has no dispose(): media_kit_video releases it when
  // Player.dispose() runs (it listens for the player's disposal), so
  // disposing the Player in [dispose] is sufficient.

  Playlist get playlist => state.value.playlist;

  // ---------------------------------------------------------------- playback

  /// Queue an open of [p]; latest request wins, requests run one at a time.
  Future<void> _requestStart(
    Playlist p, {
    Duration? startAt,
    bool automatic = false,
  }) {
    _target = p;
    _recovery.beginRequest(automatic: automatic);
    final epoch = _gate.begin();
    return _runner.run(
      (current) => _start(p, epoch, current, startAt: startAt),
    );
  }

  Future<void> _start(
    Playlist p,
    int epoch,
    bool Function() current, {
    Duration? startAt,
  }) async {
    if (_disposed || !current()) return;
    _cancelCountdown();
    await _tracker.flush();
    _tracker.end();
    final file = p.current;
    // Ad-hoc local files (id <= 0) have no watch row: no resume, no progress.
    final tracked = file.id > 0;
    final ws = startAt == null && tracked
        ? await repo.watchState(file.id)
        : null;
    if (_disposed || !current()) return;
    await _dropOwnedSub();
    final start = startAt ?? resumePosition(ws);
    _resumeStart = start;
    _lastPosition = start;
    _audioApplied = false;
    _userPickedAudio = false;
    _armedOnce = false;
    if (tracked) _tracker.begin(file.id);
    state.value = state.value.copyWith(
      playlist: p,
      error: null,
      decoderFailure: false,
      countdown: null,
      countdownLabel: null,
      resumedFrom: start > Duration.zero ? start : null,
    );
    _opened = true;
    try {
      await player.open(
        Media(file.url, start: start > Duration.zero ? start : null),
      );
    } catch (e) {
      if (current()) _fail('$e');
      return;
    }
    _gate.ready(epoch);
  }

  /// Jump to queue item [i].
  Future<void> playIndex(int i) async {
    final p = _target.jumpTo(i);
    if (p != null) await _requestStart(p);
  }

  Future<void> next() async {
    final p = _target.next();
    if (p != null) await _requestStart(p);
  }

  Future<void> prev() async {
    // Restart the current file first when we are past the start (like most
    // players); a second press goes to the previous file.
    if (player.state.position > const Duration(seconds: 5) ||
        !_target.hasPrev) {
      await seek(Duration.zero);
      return;
    }
    final p = _target.prev();
    if (p != null) await _requestStart(p);
  }

  /// Reopen the current file at the last known position.
  Future<void> retry() => _requestStart(_target, startAt: _lastPosition);

  Future<void> seek(Duration to) async {
    // Seeking back after the file ended cancels the pending auto-advance.
    if (state.value.countdown != null && state.value.error == null) {
      cancelCountdown();
    }
    await player.seek(to);
    _lastPosition = to;
    await _tracker.update(to);
    await _tracker.flush();
  }

  void _safe(Future<void> f) => f.catchError(
    (Object e) => debugPrint('player progress write failed: $e'),
  );

  Future<void> seekBy(Duration delta) async {
    final dur = player.state.duration;
    var t = player.state.position + delta;
    if (t < Duration.zero) t = Duration.zero;
    if (dur > Duration.zero && t > dur) t = dur;
    await seek(t);
  }

  /// Persist progress now (pause, background, close).
  Future<void> flush() => _tracker.flush();

  // ------------------------------------------------------------- track API

  Future<void> selectAudio(AudioTrack t) async {
    _userPickedAudio = true;
    await player.setAudioTrack(t);
  }

  Future<void> selectSubtitle(SubtitleTrack t) => player.setSubtitleTrack(t);
  Future<void> selectVideo(VideoTrack t) => player.setVideoTrack(t);

  /// Load an external subtitle from a URL or local path and select it.
  Future<void> loadExternalSubtitle(String urlOrPath) async {
    final s = urlOrPath.trim();
    if (s.isEmpty) return;
    final name = Uri.tryParse(s)?.pathSegments.lastOrNull ?? s.split('/').last;
    final dir = cacheDir;
    if (dir != null && isInsideDir(s, dir) && s != _ownedSub) {
      await _dropOwnedSub();
      _ownedSub = s;
    }
    await player.setSubtitleTrack(SubtitleTrack.uri(s, title: name));
  }

  /// Delete the picker's cache copy of an external subtitle (only ever a file
  /// inside [cacheDir]; the user's original is never touched).
  Future<void> _dropOwnedSub() async {
    final f = _ownedSub;
    _ownedSub = null;
    final dir = cacheDir;
    if (f == null || dir == null || !isInsideDir(f, dir)) return;
    try {
      await File(f).delete();
    } catch (_) {}
  }

  /// Apply + persist a subtitle style live.
  Future<void> setSubtitleStyle(SubtitleStyle st) async {
    subStyle.value = st;
    onSubtitleStyle?.call(st);
    await _applyStyle(st);
  }

  Future<void> _applyStyle(SubtitleStyle st) async {
    final p = player.platform;
    if (!useMpvSubtitles || p is! NativePlayer) return;
    for (final e in st.mpvProps().entries) {
      try {
        await p.setProperty(e.key, e.value);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- events

  void _onPosition(Duration p) {
    if (!_opened || !_gate.live) return;
    _lastPosition = p;
    // Arm once the resume seek has landed (or there was none), so the initial
    // 0 can never overwrite the stored position.
    if (!_armedOnce &&
        player.state.duration > Duration.zero &&
        p >= _resumeStart - const Duration(seconds: 3)) {
      _armedOnce = true;
      _tracker.arm();
      _failures.reset();
    }
    _safe(_tracker.update(p));
    _recovery.onProgress();
  }

  void _onDuration(Duration d) {
    if (!_gate.live) return;
    _tracker.updateDuration(d);
  }

  void _onPlaying(bool playing) {
    if (!playing) _safe(_tracker.flush());
    if (_gate.live) _recovery.onProgress();
  }

  void _onCompleted(bool done) {
    if (!done || !_opened || !_gate.live) return;
    final dur = player.state.duration;
    unawaited(() async {
      if (dur > Duration.zero) {
        await _tracker.update(dur);
        await _tracker.flush();
      }
      if (_disposed) return;
      if (settings.autoplayNext && playlist.hasNext) {
        _runCountdown('Next episode', next);
      }
    }());
  }

  void _onError(String msg) {
    if (!_opened) return;
    // Decoder-ish errors are not fatal at once: mpv usually falls back to the
    // next decoder candidate. The recovery waits a grace window, then retries
    // once in software, then gives up (see DecoderRecovery).
    if (_recovery.onError(msg) == ErrorVerdict.failNow) _fail(msg);
  }

  /// Playback demonstrably started for the current open.
  bool _started() {
    final st = player.state;
    return playbackStarted(
      duration: st.duration,
      position: st.position,
      resumeStart: _resumeStart,
      playing: st.playing,
      buffering: st.buffering,
      videoExpected: st.tracks.video.any((v) => v.id != 'auto' && v.id != 'no'),
      videoShown: (st.width ?? 0) > 0,
    );
  }

  /// One automatic software retry: switch mpv's hwdec off and reopen the
  /// current file at the same position (the decoder is only chosen at open).
  Future<void> _retrySoftware() async {
    if (_disposed) return;
    final ok = await setHwdec(player, kHwdecOff);
    if (_disposed) return;
    if (!ok) {
      _recovery.hwOn = false;
      _failDecoder('could not switch to software decoding');
      return;
    }
    await _requestStart(_target, startAt: _lastPosition, automatic: true);
  }

  /// Software decoding failed too (or was already on): say so, do not skip.
  void _failDecoder(String raw) {
    if (_disposed) return;
    // Hardware was only switched off for the retry; the file is the problem,
    // so later files get hardware again (unless the user turned it off).
    if (_recovery.retried && settings.hwdec == HwdecMode.auto) {
      _recovery.hwOn = true;
      unawaited(setHwdec(player, hwdecValue(HwdecMode.auto)));
    }
    if (!_failures.record(_gate.epoch, playlist.current.id)) return;
    _cancelCountdown();
    state.value = state.value.copyWith(
      error: "This phone can't decode this video format.\n$raw",
      decoderFailure: true,
      countdown: null,
      countdownLabel: null,
    );
    _safe(_tracker.flush());
  }

  void _fail(String raw) {
    if (_disposed) return;
    // One broken file = one failure: mpv's error event and a throwing open()
    // both land here; only the first per open request counts.
    if (!_failures.record(_gate.epoch, playlist.current.id)) return;
    final reached = player.state.duration > Duration.zero;
    final msg = reached
        ? 'Playback failed: $raw'
        : "Can't open this file. The server may be unreachable (BDIX "
              'network needed) or the file is gone.\n$raw';
    state.value = state.value.copyWith(error: msg);
    _safe(_tracker.flush());
    // Skip to the next file after the message, but give up after 2 failures
    // in a row (server down would otherwise cascade through the season).
    if (playlist.hasNext && settings.autoplayNext && _failures.canSkip) {
      _runCountdown('Skipping to next file', next);
    }
  }

  void _onTracks(Tracks t) {
    if (_audioApplied || _userPickedAudio) return;
    final real = [
      for (final a in t.audio)
        if (a.id != 'auto' && a.id != 'no') a,
    ];
    if (real.isEmpty) return;
    _audioApplied = true;
    final pref = settings.preferredAudio;
    final i = pickPreferredIndex([
      for (final a in real) (a.language, a.title),
    ], pref);
    if (i == null) return;
    final cur = player.state.track.audio;
    if (cur.id == real[i].id) return;
    unawaited(player.setAudioTrack(real[i]));
  }

  // -------------------------------------------------------------- countdown

  void _runCountdown(String label, Future<void> Function() then) {
    _cancelCountdown();
    var left = countdownSeconds;
    state.value = state.value.copyWith(countdown: left, countdownLabel: label);
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      left--;
      if (left <= 0) {
        t.cancel();
        _countdown = null;
        unawaited(then());
      } else {
        state.value = state.value.copyWith(countdown: left);
      }
    });
  }

  /// Stop the pending auto-advance (user pressed Cancel).
  void cancelCountdown() {
    _cancelCountdown();
    state.value = state.value.copyWith(countdown: null, countdownLabel: null);
  }

  /// Skip the wait and advance immediately.
  Future<void> advanceNow() async {
    if (state.value.countdown != null) await next();
  }

  void _cancelCountdown() {
    _countdown?.cancel();
    _countdown = null;
  }

  // ---------------------------------------------------------------- dispose

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _opened = false;
    _gate.close();
    _recovery.dispose();
    _stats?.cancel();
    _cancelCountdown();
    for (final s in _subs) {
      await s.cancel();
    }
    try {
      await _tracker.flush();
    } catch (_) {}
    await player.dispose();
    await _dropOwnedSub();
    state.dispose();
    subStyle.dispose();
  }
}
