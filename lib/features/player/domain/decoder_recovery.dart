import 'dart:async';

/// Substrings (lower case) that mark an mpv/ffmpeg error line as a decoder
/// problem rather than a network/file one. Extend freely: a false positive
/// only delays the failure message by the grace window.
const decoderErrorMarkers = [
  'codec',
  'decoder',
  'hwdec',
  'mediacodec',
  'failed to initialize',
  'no video',
  'cannot decode',
  'could not open codec',
  'error while decoding',
];

/// True when [raw] (an mpv error-level log line) looks like a decoder failure.
/// mpv logs these when one decoder candidate (usually a hardware one) cannot
/// start and then normally falls back to the next candidate.
bool isDecoderError(String raw) {
  final s = raw.toLowerCase();
  return decoderErrorMarkers.any(s.contains);
}

/// Has playback demonstrably started? The duration is known and either the
/// position moved on from where this open began, or the player reports
/// playing without buffering. When the file has a video track, a decoded
/// frame must also exist ([videoShown]): audio on a black screen is not a
/// working playback.
bool playbackStarted({
  required Duration duration,
  required Duration position,
  required Duration resumeStart,
  required bool playing,
  required bool buffering,
  bool videoExpected = false,
  bool videoShown = true,
}) {
  if (duration <= Duration.zero) return false;
  if (videoExpected && !videoShown) return false;
  final advanced = position - resumeStart >= const Duration(milliseconds: 500);
  return advanced || (playing && !buffering);
}

/// What the caller should do with an error event.
enum ErrorVerdict {
  /// Fail the file now (network, 404, ...): the historical behaviour.
  failNow,

  /// Nothing to do: playback runs, or the decoder error is already handled.
  ignore,

  /// Decoder-ish error before playback began: a grace window is (still)
  /// running; the callbacks tell the outcome.
  grace,
}

typedef GraceTimerFactory = Timer Function(Duration d, void Function() cb);

/// Decides what a decoder-ish error means, once per open request.
///
/// * decoder error before playback starts -> wait [grace]; if playback began
///   meanwhile the error is dropped;
/// * grace ends without playback and hardware decoding is on -> one software
///   retry ([onRetrySoftware]); never more than one per request;
/// * grace ends without playback and software was already in use (or the
///   retry was used) -> [onGiveUp] (show "can't decode");
/// * playback starts after the retry -> [onSoftwareWorked] once, so the
///   caller can remember "hardware decoding is broken here".
///
/// Pure Dart: time comes from the injectable [timer] factory.
class DecoderRecovery {
  DecoderRecovery({
    required this.hwOn,
    required this.started,
    required this.onRetrySoftware,
    required this.onGiveUp,
    required this.onSoftwareWorked,
    this.grace = const Duration(seconds: 3),
    GraceTimerFactory? timer,
  }) : _timer = timer ?? Timer.new;

  /// Is hardware decoding currently in use? The caller sets this back to true
  /// when it restores the hardware mode.
  bool hwOn;

  /// Playback demonstrably started (see [playbackStarted]).
  final bool Function() started;
  final void Function() onRetrySoftware;
  final void Function(String raw) onGiveUp;
  final void Function() onSoftwareWorked;
  final Duration grace;
  final GraceTimerFactory _timer;

  Timer? _graceTimer;
  String _raw = '';
  bool _retried = false;
  bool _softwarePending = false;
  bool _gaveUp = false;
  bool _disposed = false;

  /// The software retry was used for the current file.
  bool get retried => _retried;

  /// A grace window is running.
  bool get graceActive => _graceTimer != null;

  /// A new open request began. [automatic] = it is our own software retry
  /// (keeps the "already retried" memory); anything else starts fresh.
  void beginRequest({bool automatic = false}) {
    _cancelTimer();
    _raw = '';
    _gaveUp = false;
    if (!automatic) {
      _retried = false;
      _softwarePending = false;
    }
  }

  ErrorVerdict onError(String raw) {
    if (_disposed) return ErrorVerdict.ignore;
    if (!isDecoderError(raw)) {
      _cancelTimer();
      return ErrorVerdict.failNow;
    }
    if (started()) {
      // Playback runs: mpv recovered (e.g. software after a failed hardware
      // candidate). Error after start is not fatal if it is a decoder one.
      _markStarted();
      return ErrorVerdict.ignore;
    }
    if (_gaveUp) return ErrorVerdict.ignore;
    _raw = raw;
    _graceTimer ??= _timer(grace, _expire);
    return ErrorVerdict.grace;
  }

  /// Call on position/playing events: ends a running grace window early and
  /// reports a successful software retry.
  void onProgress() {
    if (_disposed) return;
    if ((_graceTimer != null || _softwarePending) && started()) {
      _markStarted();
    }
  }

  void _markStarted() {
    _cancelTimer();
    if (_softwarePending) {
      _softwarePending = false;
      onSoftwareWorked();
    }
  }

  void _expire() {
    _graceTimer = null;
    if (_disposed) return;
    if (started()) {
      _markStarted();
      return;
    }
    if (hwOn && !_retried) {
      _retried = true;
      _softwarePending = true;
      hwOn = false;
      onRetrySoftware();
    } else {
      _gaveUp = true;
      _softwarePending = false;
      onGiveUp(_raw);
    }
  }

  void _cancelTimer() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  void dispose() {
    _disposed = true;
    _cancelTimer();
  }
}
