import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/player/domain/resume.dart';

WatchState ws(int pos, {int dur = 3600000, bool watched = false}) =>
    WatchState(fileId: 1, positionMs: pos, durationMs: dur, watched: watched);

void main() {
  group('resumePosition', () {
    test('no state / tiny position -> 0', () {
      expect(resumePosition(null), Duration.zero);
      expect(resumePosition(ws(10000)), Duration.zero);
      expect(resumePosition(ws(0)), Duration.zero);
    });
    test('> 10 s and unwatched -> saved position', () {
      expect(resumePosition(ws(10001)), const Duration(milliseconds: 10001));
      expect(resumePosition(ws(600000)), const Duration(minutes: 10));
    });
    test('watched or in watched zone -> 0', () {
      expect(resumePosition(ws(600000, watched: true)), Duration.zero);
      expect(resumePosition(ws(3300000)), Duration.zero); // 91.6 %
    });
    test('unknown duration still resumes', () {
      expect(resumePosition(ws(60000, dur: 0)), const Duration(minutes: 1));
    });
  });

  test('isWatchedPosition at 90 %', () {
    const d = Duration(minutes: 100);
    expect(isWatchedPosition(const Duration(minutes: 89), d), isFalse);
    expect(isWatchedPosition(const Duration(minutes: 90), d), isTrue);
    expect(
      isWatchedPosition(const Duration(minutes: 90), Duration.zero),
      isFalse,
    );
  });

  group('ProgressTracker', () {
    late List<(int, int, int)> writes;
    late DateTime clock;
    late ProgressTracker t;

    setUp(() {
      writes = [];
      clock = DateTime(2026);
      t = ProgressTracker(
        (id, {required positionMs, required durationMs}) async =>
            writes.add((id, positionMs, durationMs)),
        now: () => clock,
      );
    });

    void tick(int s) => clock = clock.add(Duration(seconds: s));

    test('nothing written before arm (resume seek pending)', () async {
      t.begin(7);
      t.updateDuration(const Duration(minutes: 60));
      await t.update(Duration.zero);
      await t.flush();
      expect(writes, isEmpty);
    });

    test('throttles to one write per 5 s', () async {
      t.begin(7);
      t.updateDuration(const Duration(minutes: 60));
      t.arm();
      await t.update(const Duration(seconds: 2)); // first: written
      for (var s = 3; s <= 6; s++) {
        tick(1);
        await t.update(Duration(seconds: s));
      }
      expect(writes.length, 1);
      tick(1); // 5 s since first write
      await t.update(const Duration(seconds: 7));
      expect(writes.length, 2);
      expect(writes.last, (7, 7000, 3600000));
    });

    test(
      'flush writes latest immediately; unchanged position skipped',
      () async {
        t.begin(7);
        t.arm();
        await t.update(const Duration(seconds: 30));
        tick(1);
        await t.update(const Duration(seconds: 31)); // throttled
        await t.flush();
        expect(writes.last.$2, 31000);
        await t.flush(); // same position again
        expect(writes.length, 2);
      },
    );

    test('position < 1 s is never written', () async {
      t.begin(7);
      t.arm();
      await t.update(const Duration(milliseconds: 500));
      await t.flush();
      expect(writes, isEmpty);
    });

    test('begin resets per file; end stops writes', () async {
      t.begin(1);
      t.arm();
      await t.update(const Duration(seconds: 20));
      t.begin(2);
      await t.flush(); // not armed for file 2
      expect(writes.length, 1);
      t.arm();
      await t.update(const Duration(seconds: 3));
      expect(writes.last.$1, 2);
      t.end();
      await t.flush();
      expect(writes.length, 2);
    });
  });
}
