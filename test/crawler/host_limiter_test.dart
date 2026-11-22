import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/bounded_queue.dart';
import 'package:watchdog/crawler/host_limiter.dart';
import 'package:watchdog/crawler/listing_client.dart';

final _u = Uri.parse('http://h/');
FetchException _timeout() =>
    FetchException(_u, FetchFailure.timeout, 'timed out');
FetchException _http(int s) =>
    FetchException(_u, FetchFailure.http, 'HTTP $s', status: s);

void main() {
  group('AdaptiveLimiter', () {
    test('starts at 6, grows to 12 while fast, never above', () {
      final l = AdaptiveLimiter();
      expect(l.limit, 6);
      for (var i = 0; i < 200; i++) {
        l.recordSuccess(const Duration(milliseconds: 40));
      }
      expect(l.limit, 12);
    });

    test('does not grow while p90 is slow', () {
      final l = AdaptiveLimiter();
      for (var i = 0; i < 100; i++) {
        l.recordSuccess(const Duration(milliseconds: 400));
      }
      expect(l.limit, 6);
      expect(l.p90, const Duration(milliseconds: 400));
    });

    test('one slow outlier in ten does not block growth (p90 of window)', () {
      final l = AdaptiveLimiter();
      for (var i = 0; i < 40; i++) {
        l.recordSuccess(Duration(milliseconds: i % 20 == 0 ? 900 : 50));
      }
      expect(l.limit, greaterThan(6));
    });

    test(
      'halves on timeout / 5xx / 429 with floor 2, not on 404 or connect',
      () async {
        final l = AdaptiveLimiter(start: 12);
        Future<void> fail(Object e) async {
          try {
            await l.run<void>(() async => throw e);
          } catch (_) {}
        }

        await fail(_timeout());
        expect(l.limit, 6);
        await fail(_http(503));
        expect(l.limit, 3);
        await fail(_http(429));
        expect(l.limit, 2);
        await fail(_timeout());
        expect(l.limit, 2); // floor
        await fail(_http(404));
        await fail(FetchException(_u, FetchFailure.connect, 'down'));
        expect(l.limit, 2);
      },
    );

    test(
      'failures of requests started before a halving do not halve again',
      () async {
        final l = AdaptiveLimiter(start: 8);
        final gates = [for (var i = 0; i < 4; i++) Completer<void>()];
        final runs = [
          for (final g in gates)
            l
                .run<void>(() async {
                  await g.future;
                  throw _timeout();
                })
                .catchError((_) {}),
        ];
        await Future<void>.delayed(Duration.zero);
        for (final g in gates) {
          g.complete();
        }
        await Future.wait(runs);
        expect(l.limit, 4); // one halving for the whole burst, not 8 -> 2
      },
    );

    test('run() enforces the limit and queues the rest in order', () async {
      final l = AdaptiveLimiter(start: 3, min: 3, max: 3);
      var inFlight = 0, peak = 0;
      final order = <int>[];
      await Future.wait([
        for (var i = 0; i < 20; i++)
          l.run(() async {
            order.add(i);
            peak = peak > ++inFlight ? peak : inFlight;
            await Future<void>.delayed(const Duration(milliseconds: 2));
            inFlight--;
          }),
      ]);
      expect(peak, 3);
      expect(order, List.generate(20, (i) => i));
      expect(l.active, 0);
      expect(l.waiting, 0);
    });

    test('growth wakes extra waiters', () async {
      final l = AdaptiveLimiter(start: 2, min: 2, max: 4, step: 2);
      var peak = 0, cur = 0;
      await Future.wait([
        for (var i = 0; i < 30; i++)
          l.run(() async {
            peak = peak > ++cur ? peak : cur;
            await Future<void>.delayed(const Duration(milliseconds: 1));
            cur--;
          }),
      ]);
      expect(peak, greaterThan(2));
      expect(peak, lessThanOrEqualTo(4));
    });

    test('HostLimiters keeps one limiter per host', () {
      final h = HostLimiters();
      expect(identical(h.forHost('a'), h.forHost('a')), isTrue);
      expect(identical(h.forHost('a'), h.forHost('b')), isFalse);
      h.forHost('a').recordOverload();
      expect(h.limits, {'a': 3, 'b': 6});
    });
  });

  group('BoundedQueue', () {
    test(
      'producers wait for a slow consumer; buffer never exceeds capacity',
      () async {
        final q = BoundedQueue<int>(3);
        var produced = 0, maxLen = 0;
        final producer = () async {
          for (var i = 0; i < 50; i++) {
            await q.add(i);
            produced++;
            if (q.length > maxLen) maxLen = q.length;
          }
          q.close();
        }();
        final got = <int>[];
        await for (final x in q.stream) {
          got.add(x);
          await Future<void>.delayed(const Duration(milliseconds: 1));
          expect(produced - got.length, lessThanOrEqualTo(4));
        }
        await producer;
        expect(got, List.generate(50, (i) => i));
        expect(maxLen, lessThanOrEqualTo(3));
      },
    );

    test('reserve/put/release accounting', () async {
      final q = BoundedQueue<int>(2);
      await q.reserve();
      await q.reserve();
      var third = false;
      unawaited(q.reserve().then((_) => third = true));
      await Future<void>.delayed(Duration.zero);
      expect(third, isFalse); // full: 2 reserved
      q.release();
      await Future<void>.delayed(Duration.zero);
      expect(third, isTrue);
      q.put(1);
      q.put(2);
      expect(q.length, 2);
    });

    test('consumer cancel unblocks producers and reports', () async {
      final q = BoundedQueue<int>(1);
      var gone = false;
      q.onConsumerCancel = () => gone = true;
      final sub = q.stream.listen((_) {});
      await q.add(1);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(gone, isTrue);
      await q.add(2).timeout(const Duration(seconds: 1)); // does not hang
      await q.add(3).timeout(const Duration(seconds: 1));
    });

    test('abort wakes waiting producers', () async {
      final q = BoundedQueue<int>(1);
      await q.add(1);
      var done = false;
      unawaited(q.add(2).then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      q.abort();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });
  });
}
