import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/player/domain/start_gate.dart';

void main() {
  group('LatestWinsRunner', () {
    test('rapid requests: only the latest runs, never interleaved', () async {
      final r = LatestWinsRunner();
      final log = <String>[];
      Future<void> job(String n, bool Function() cur) async {
        log.add('start $n');
        await Future<void>.delayed(Duration.zero);
        if (!cur()) {
          log.add('abort $n');
          return;
        }
        log.add('open $n');
      }

      final f1 = r.run((c) => job('1', c));
      final f2 = r.run((c) => job('2', c));
      final f3 = r.run((c) => job('3', c));
      await Future.wait([f1, f2, f3]);
      expect(log, ['start 3', 'open 3']); // 1 and 2 never started
    });

    test('running job sees supersession, next waits for it', () async {
      final r = LatestWinsRunner();
      final log = <String>[];
      final gate = Completer<void>();
      final f1 = r.run((cur) async {
        log.add('1 start');
        await gate.future;
        log.add(cur() ? '1 open' : '1 abort');
      });
      await Future<void>.delayed(Duration.zero);
      final f2 = r.run((cur) async => log.add('2 open'));
      gate.complete();
      await Future.wait([f1, f2]);
      expect(log, ['1 start', '1 abort', '2 open']);
    });

    test('job errors do not break the chain or escape', () async {
      final r = LatestWinsRunner();
      var ran = false;
      await r.run((_) async => throw StateError('x'));
      await r.run((_) async => ran = true);
      expect(ran, isTrue);
    });
  });

  group('EventGate with a fake stream', () {
    test('events before ready are dropped, after are accepted', () async {
      final g = EventGate();
      final pos = StreamController<int>.broadcast(sync: true);
      final seen = <int>[];
      pos.stream.listen((v) {
        if (g.live) seen.add(v);
      });
      pos.add(1); // before any begin: not live
      final e1 = g.begin();
      pos.add(99000); // stale tail of previous file
      g.ready(e1);
      pos.add(5);
      final e2 = g.begin(); // next file requested
      pos.add(6); // stale
      g.ready(e1); // late ready of an old epoch is ignored
      pos.add(7);
      g.ready(e2);
      pos.add(8);
      expect(seen, [5, 8]);
      g.close();
      pos.add(9);
      expect(seen, [5, 8]);
      await pos.close();
    });
  });

  group('FailureStreak', () {
    test('two signals for one file count once (two different files cap)', () {
      final f = FailureStreak();
      expect(f.record(1, 10), isTrue);
      expect(f.record(1, 10), isFalse); // open threw after mpv error
      expect(f.count, 1);
      expect(f.record(2, 11), isTrue);
      expect(f.canSkip, isTrue); // 2 files: still allowed
      expect(f.record(3, 12), isTrue);
      expect(f.canSkip, isFalse); // third distinct file: give up
      f.reset();
      expect(f.canSkip, isTrue);
    });
  });

  group('isInsideDir', () {
    test('only strictly inside the cache dir', () {
      expect(isInsideDir('/c/cache/file_picker/a.srt', '/c/cache'), isTrue);
      expect(isInsideDir('/c/cache', '/c/cache'), isFalse);
      expect(isInsideDir('/c/cache2/a.srt', '/c/cache'), isFalse);
      expect(isInsideDir('/c/cache/../home/a.srt', '/c/cache'), isFalse);
      expect(isInsideDir('/home/u/a.srt', '/c/cache'), isFalse);
      expect(isInsideDir('http://x/a.srt', '/c/cache'), isFalse);
      expect(isInsideDir('rel/a.srt', '/c/cache'), isFalse);
    });
  });
}
