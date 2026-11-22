import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/player/domain/decoder_recovery.dart';

/// Manual timers: [fire] runs the pending one, no real time passes.
class _Clock {
  final pending = <_FakeTimer>[];
  Timer make(Duration d, void Function() cb) {
    final t = _FakeTimer(d, cb);
    pending.add(t);
    return t;
  }

  Duration? get lastDelay => pending.isEmpty ? null : pending.last.d;
  bool get hasActive => pending.any((t) => t.isActive);
  void fire() {
    final t = pending.lastWhere((t) => t.isActive);
    t._fire();
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.d, this.cb);
  final Duration d;
  final void Function() cb;
  bool _active = true;
  void _fire() {
    _active = false;
    cb();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

class _Rig {
  _Rig({bool hwOn = true}) {
    r = DecoderRecovery(
      hwOn: hwOn,
      started: () => started,
      timer: clock.make,
      onRetrySoftware: () => log.add('retry'),
      onGiveUp: (raw) => log.add('giveup:$raw'),
      onSoftwareWorked: () => log.add('worked'),
    );
  }
  final clock = _Clock();
  final log = <String>[];
  bool started = false;
  late final DecoderRecovery r;
}

void main() {
  group('isDecoderError', () {
    test('decoder-ish lines', () {
      for (final s in [
        'Could not open codec.',
        'Failed to initialize a decoder for codec h264',
        'MediaCodec hwdec init failed',
        'No video or audio streams selected.',
        'Cannot decode this',
        'HWDEC error',
        'Failed to Initialize something',
      ]) {
        expect(isDecoderError(s), isTrue, reason: s);
      }
    });
    test('network / file lines are not', () {
      for (final s in [
        'tcp: ffurl_read returned 0xdeadbeef',
        'HTTP error 404 Not Found',
        'Failed to open http://172.16.50.7/a.mkv.',
        'Connection timed out',
        '',
      ]) {
        expect(isDecoderError(s), isFalse, reason: s);
      }
    });
  });

  group('playbackStarted', () {
    bool go({
      int dur = 100,
      int pos = 0,
      int resume = 0,
      bool playing = false,
      bool buffering = false,
      bool vExp = false,
      bool vShown = true,
    }) => playbackStarted(
      duration: Duration(seconds: dur),
      position: Duration(seconds: pos),
      resumeStart: Duration(seconds: resume),
      playing: playing,
      buffering: buffering,
      videoExpected: vExp,
      videoShown: vShown,
    );
    test('needs a duration', () {
      expect(go(dur: 0, pos: 5, playing: true), isFalse);
    });
    test('position advanced from the resume point', () {
      expect(go(pos: 1), isTrue);
      expect(go(pos: 600, resume: 600), isFalse);
      expect(go(pos: 602, resume: 600), isTrue);
    });
    test('playing without buffering', () {
      expect(go(playing: true), isTrue);
      expect(go(playing: true, buffering: true), isFalse);
      expect(go(), isFalse);
    });
    test('video track without a decoded frame is not playback', () {
      expect(go(pos: 5, playing: true, vExp: true, vShown: false), isFalse);
      expect(go(pos: 5, playing: true, vExp: true, vShown: true), isTrue);
    });
  });

  group('DecoderRecovery', () {
    test('network error fails at once, no grace', () {
      final g = _Rig();
      expect(g.r.onError('HTTP error 404'), ErrorVerdict.failNow);
      expect(g.clock.hasActive, isFalse);
    });

    test('network error after start still fails (today behaviour)', () {
      final g = _Rig()..started = true;
      expect(g.r.onError('tcp: broken pipe'), ErrorVerdict.failNow);
    });

    test('decoder error after start is ignored', () {
      final g = _Rig()..started = true;
      expect(g.r.onError('Could not open codec.'), ErrorVerdict.ignore);
      expect(g.clock.hasActive, isFalse);
      expect(g.log, isEmpty);
    });

    test('decoder error starts a 3 s grace, no failure yet', () {
      final g = _Rig();
      expect(g.r.onError('Could not open codec.'), ErrorVerdict.grace);
      expect(g.clock.lastDelay, const Duration(seconds: 3));
      expect(g.log, isEmpty);
      // more decoder noise does not restart/duplicate the window
      expect(g.r.onError('Failed to initialize a decoder'), ErrorVerdict.grace);
      expect(g.clock.pending, hasLength(1));
    });

    test('playback starting inside the window drops the error', () {
      final g = _Rig();
      g.r.onError('Could not open codec.');
      g.started = true;
      g.r.onProgress();
      expect(g.r.graceActive, isFalse);
      expect(g.log, isEmpty);
    });

    test('playback started when the window ends: nothing happens', () {
      final g = _Rig();
      g.r.onError('Could not open codec.');
      g.started = true;
      g.clock.fire();
      expect(g.log, isEmpty);
      expect(g.r.retried, isFalse);
    });

    test('window ends without playback + hw on: one software retry', () {
      final g = _Rig();
      g.r.onError('Could not open codec.');
      g.clock.fire();
      expect(g.log, ['retry']);
      expect(g.r.hwOn, isFalse);
      expect(g.r.retried, isTrue);
    });

    test('software then plays: remembered once', () {
      final g = _Rig();
      g.r.onError('Could not open codec.');
      g.clock.fire();
      g.r.beginRequest(automatic: true); // the retry's own open
      g.started = true;
      g.r.onProgress();
      g.r.onProgress();
      expect(g.log, ['retry', 'worked']);
    });

    test('software fails too: gives up with the raw detail, never loops', () {
      final g = _Rig();
      g.r.onError('Could not open codec.');
      g.clock.fire();
      g.r.beginRequest(automatic: true);
      expect(g.r.onError('Could not open codec. (sw)'), ErrorVerdict.grace);
      g.clock.fire();
      expect(g.log, ['retry', 'giveup:Could not open codec. (sw)']);
      // further noise after giving up is ignored, no second retry
      expect(g.r.onError('Could not open codec.'), ErrorVerdict.ignore);
      expect(g.clock.pending.where((t) => t.isActive), isEmpty);
      expect(g.log.where((e) => e == 'retry'), hasLength(1));
    });

    test('hardware already off: no retry, straight to give up', () {
      final g = _Rig(hwOn: false);
      g.r.onError('Could not open codec.');
      g.clock.fire();
      expect(g.log, ['giveup:Could not open codec.']);
    });

    test('non-decoder error during grace fails immediately', () {
      final g = _Rig();
      g.r.onError('Could not open codec.');
      expect(g.r.onError('HTTP error 404'), ErrorVerdict.failNow);
      expect(g.clock.hasActive, isFalse);
      expect(g.log, isEmpty);
    });

    test('a new user request resets the one-retry allowance', () {
      final g = _Rig();
      g.r.onError('Could not open codec.');
      g.clock.fire();
      g.r.beginRequest(automatic: true);
      g.r.onError('Could not open codec.');
      g.clock.fire(); // gave up
      g.r.hwOn = true; // session restores hardware
      g.r.beginRequest(); // user pressed Retry
      g.r.onError('Could not open codec.');
      g.clock.fire();
      expect(g.log.where((e) => e == 'retry'), hasLength(2));
    });

    test('new request cancels a running window', () {
      final g = _Rig();
      g.r.onError('Could not open codec.');
      g.r.beginRequest();
      expect(g.r.graceActive, isFalse);
      expect(g.log, isEmpty);
    });

    test('dispose cancels; later events do nothing', () {
      final g = _Rig();
      g.r.onError('Could not open codec.');
      g.r.dispose();
      expect(g.r.graceActive, isFalse);
      expect(g.r.onError('Could not open codec.'), ErrorVerdict.ignore);
    });

    test('ignored first error does not mark software as working', () {
      final g = _Rig()..started = true;
      g.r.onError('Could not open codec.');
      g.r.onProgress();
      expect(g.log, isEmpty);
    });
  });
}
