import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/tmdb/tmdb_client.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart';

import 'fakes.dart';

/// Virtual time: delays advance [now] and never sleep for real.
class Clock {
  DateTime now = DateTime(2024);
  final delays = <Duration>[];
  Future<void> delay(Duration d) async {
    delays.add(d);
    now = now.add(d);
    await Future<void>.delayed(Duration.zero);
  }
}

const _slow = TmdbException(
  TmdbErrorKind.rateLimited,
  'TMDB rate limit hit. Slowing down.',
  retryAfter: Duration(seconds: 7),
);
const _net = TmdbException(TmdbErrorKind.network, 'offline');

void main() {
  late Clock clock;
  late FakeApi api;
  late FakeRepo repo;

  /// Search answers with one exact hit per title name "Film N" (id 1000+N).
  void answerAll() => api.results = (kind, q, year) {
    final n = int.tryParse(q.split(' ').last) ?? 0;
    return [hit(1000 + n, q, year ?? 2000)];
  };

  setUp(() {
    clock = Clock();
    api = FakeApi(() => clock.now);
    answerAll();
  });

  List<MediaTitle> films(int n) => [
    for (var i = 1; i <= n; i++) title(i, 'Film $i', year: 2000),
  ];

  TmdbSyncService svc({
    double rps = 5,
    int maxRetries = 3,
    int consecutive = 3,
    int batch = 50,
  }) => TmdbSyncService(
    repo: repo,
    api: api,
    requestsPerSecond: rps,
    maxRetries: maxRetries,
    maxConsecutiveFailures: consecutive,
    batchSize: batch,
    delay: clock.delay,
    clock: () => clock.now,
  );

  Future<TmdbSyncProgress> finished(TmdbSyncService s) => s.progress
      .firstWhere(
        (p) => p.state == TmdbSyncState.idle || p.state == TmdbSyncState.error,
      )
      .timeout(const Duration(seconds: 5));

  Future<void> spin([int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('background run', () {
    test('matches titles and saves details', () async {
      repo = FakeRepo(films(3));
      final s = svc();
      s.start();
      final p = await finished(s);
      expect(p.state, TmdbSyncState.idle);
      expect((p.processed, p.matched, p.unmatched, p.failed), (3, 3, 0, 0));
      expect(repo.matches.map((m) => m.titleId), [1, 2, 3]);
      expect(repo.matches.every((m) => !m.manual), isTrue);
      expect(repo.matches.first.d.id, 1001);
      expect(p.current, isNull);
      await s.dispose();
    });

    test('empty library finishes idle at once', () async {
      repo = FakeRepo([]);
      final s = svc();
      s.start();
      expect((await finished(s)).processed, 0);
      expect(api.calls, isEmpty);
      await s.dispose();
    });

    test('records unmatched, no details call', () async {
      repo = FakeRepo(films(2));
      api.results = (_, _, _) => const [];
      final s = svc();
      s.start();
      final p = await finished(s);
      expect((p.matched, p.unmatched), (0, 2));
      expect(repo.unmatched, [1, 2]);
      expect(repo.matches, isEmpty);
      expect(api.calls.where((c) => c.kind == 'details'), isEmpty);
      await s.dispose();
    });

    test('details 404 counts as unmatched', () async {
      repo = FakeRepo(films(1));
      api.gate = (c) async {
        if (c.kind == 'details') {
          api.errors.add(
            const TmdbException(TmdbErrorKind.notFound, 'Not found'),
          );
        }
      };
      final s = svc();
      s.start();
      final p = await finished(s);
      expect((p.matched, p.unmatched), (0, 1));
      expect(repo.unmatched, [1]);
      await s.dispose();
    });

    test(
      'progress stream: current value first, current title, final state',
      () async {
        repo = FakeRepo(films(2));
        final s = svc();
        final seen = <TmdbSyncProgress>[];
        final sub = s.progress.listen(seen.add);
        await spin(2);
        expect(seen.first.state, TmdbSyncState.idle);
        s.start();
        await finished(s);
        await spin(2);
        await sub.cancel();
        expect(seen.any((p) => p.current == 'Film 1'), isTrue);
        expect(seen.any((p) => p.state == TmdbSyncState.running), isTrue);
        expect(seen.last.state, TmdbSyncState.idle);
        expect(seen.last.processed, 2);
        // late subscribers still get the final state
        expect((await s.progress.first).processed, 2);
        await s.dispose();
      },
    );

    test('counters restart on a new run', () async {
      repo = FakeRepo(films(2));
      final s = svc();
      s.start();
      await finished(s);
      repo.titles.add(title(3, 'Film 3', year: 2000));
      s.start();
      final p = await finished(s);
      expect(p.processed, 1);
      await s.dispose();
    });

    test('repository failure ends in the stream, never throws', () async {
      repo = FakeRepo(films(1))..failNeeding = StateError('db closed');
      final s = svc();
      s.start();
      final p = await finished(s);
      expect(p.state, TmdbSyncState.error);
      expect(p.message, contains('db closed'));
      await s.dispose();
    });

    test('saving failure is a failed title, run continues', () async {
      repo = FakeRepo(films(2));
      var n = 0;
      final real = repo;
      final flaky = _Flaky(real, () => n++ == 0);
      final s = TmdbSyncService(
        repo: flaky,
        api: api,
        delay: clock.delay,
        clock: () => clock.now,
      );
      s.start();
      final p = await finished(s);
      expect((p.failed, p.matched), (1, 1));
      await s.dispose();
    });
  });

  group('throttle and retries', () {
    test('requests start at least 1/rps apart', () async {
      repo = FakeRepo(films(5));
      final s = svc(rps: 5);
      s.start();
      await finished(s);
      final t = [for (final c in api.calls) c.at];
      expect(t, hasLength(10)); // search + details per title
      for (var i = 1; i < t.length; i++) {
        expect(
          t[i].difference(t[i - 1]),
          greaterThanOrEqualTo(const Duration(milliseconds: 200)),
        );
      }
      await s.dispose();
    });

    test('rate is configurable', () async {
      repo = FakeRepo(films(3));
      final s = svc(rps: 1);
      s.start();
      await finished(s);
      final t = [for (final c in api.calls) c.at];
      expect(
        t.last.difference(t.first),
        greaterThanOrEqualTo(const Duration(seconds: 5)),
      );
      await s.dispose();
    });

    test('429 waits Retry-After, retries, and then runs slower', () async {
      repo = FakeRepo(films(3));
      api.errors.add(_slow);
      final s = svc(rps: 5);
      s.start();
      final seen = <TmdbSyncProgress>[];
      final sub = s.progress.listen(seen.add);
      final p = await finished(s);
      await sub.cancel();
      expect(p.matched, 3);
      // first request failed, its retry came >= 7 s later
      expect(
        api.calls[1].at.difference(api.calls[0].at),
        greaterThanOrEqualTo(const Duration(seconds: 7)),
      );
      expect(
        seen.any((x) => x.message?.contains('Rate limited') ?? false),
        isTrue,
      );
      // pace doubled to 400 ms after the 429
      expect(
        api.calls[2].at.difference(api.calls[1].at),
        greaterThanOrEqualTo(const Duration(milliseconds: 400)),
      );
      await s.dispose();
    });

    test('pace recovers after clean requests', () async {
      repo = FakeRepo(films(20));
      api.errors.add(_slow);
      final s = svc(rps: 5);
      s.start();
      await finished(s);
      final gaps = [
        for (var i = 1; i < api.calls.length; i++)
          api.calls[i].at.difference(api.calls[i - 1].at),
      ];
      expect(gaps.last, const Duration(milliseconds: 200));
      await s.dispose();
    });

    test('transient error is retried with growing delay', () async {
      repo = FakeRepo(films(1));
      api.errors.addAll([_net, _net]);
      final s = svc();
      s.start();
      final p = await finished(s);
      expect(p.matched, 1);
      expect(
        api.calls[1].at.difference(api.calls[0].at),
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
      expect(
        api.calls[2].at.difference(api.calls[1].at),
        greaterThanOrEqualTo(const Duration(seconds: 2)),
      );
      await s.dispose();
    });

    test('retries are bounded; the title is skipped, run goes on', () async {
      repo = FakeRepo(films(2));
      api.errors.addAll([_net, _net, _net, _net]); // 1 try + 3 retries
      final s = svc(maxRetries: 3);
      s.start();
      final p = await finished(s);
      expect((p.failed, p.matched), (1, 1));
      expect(repo.unmatched, isEmpty, reason: 'a failure is not "not found"');
      expect(repo.matches.single.titleId, 2);
      await s.dispose();
    });

    test(
      'several titles failing in a row stop the run with the reason',
      () async {
        repo = FakeRepo(films(10));
        api.gate = (c) async => api.errors.add(_net);
        final s = svc(maxRetries: 0, consecutive: 3);
        s.start();
        final p = await finished(s);
        expect(p.state, TmdbSyncState.error);
        expect(p.error, TmdbErrorKind.network);
        expect(p.failed, 3);
        expect(api.calls, hasLength(3));
        await s.dispose();
      },
    );

    test('unauthorized stops at once and says so', () async {
      repo = FakeRepo(films(5));
      api.errors.add(
        const TmdbException(
          TmdbErrorKind.unauthorized,
          'TMDB rejected the key.',
        ),
      );
      final s = svc();
      s.start();
      final p = await finished(s);
      expect(p.state, TmdbSyncState.error);
      expect(p.error, TmdbErrorKind.unauthorized);
      expect(p.message, contains('rejected'));
      expect(api.calls, hasLength(1));
      expect(repo.matches, isEmpty);
      expect(repo.unmatched, isEmpty);

      // on-demand calls do not hammer the bad key either
      final r = await s.fetchNow(title(9, 'Film 9', year: 2000));
      expect(r.status, TmdbFetchStatus.failed);
      expect(r.error!.kind, TmdbErrorKind.unauthorized);
      expect(api.calls, hasLength(1));

      // an explicit restart tries again (key may have been fixed)
      s.start();
      await finished(s);
      expect(api.calls.length, greaterThan(1));
      await s.dispose();
    });
  });

  group('pause, resume, cancel', () {
    test('pause holds after the current title; resume finishes', () async {
      repo = FakeRepo(films(4));
      final gate = Completer<void>();
      api.gate = (c) => c.query == 'Film 1' ? gate.future : Future.value();
      final s = svc();
      s.start();
      await spin();
      s.pause();
      expect(s.current.state, TmdbSyncState.paused);
      gate.complete();
      await spin(60);
      // Film 1 finished, nothing after it started
      expect(repo.matches.map((m) => m.titleId), [1]);
      expect(s.current.state, TmdbSyncState.paused);
      final callsWhilePaused = api.calls.length;
      await spin(30);
      expect(api.calls.length, callsWhilePaused);

      s.resume();
      expect(s.current.state, TmdbSyncState.running);
      final p = await finished(s);
      expect(p.matched, 4);
      await s.dispose();
    });

    test('cancel ends the run as idle with partial counts', () async {
      repo = FakeRepo(films(6));
      final gate = Completer<void>();
      api.gate = (c) => c.query == 'Film 2' ? gate.future : Future.value();
      final s = svc();
      s.start();
      await spin(40);
      final done = s.cancel();
      gate.complete();
      await done;
      expect(s.current.state, TmdbSyncState.idle);
      expect(repo.matches.map((m) => m.titleId), [1, 2]);
      expect(s.isRunning, isFalse);
      final n = api.calls.length;
      await spin(30);
      expect(api.calls.length, n);
      await s.dispose();
    });

    test('cancel while paused returns', () async {
      repo = FakeRepo(films(3));
      final gate = Completer<void>();
      api.gate = (c) => c.query == 'Film 1' ? gate.future : Future.value();
      final s = svc();
      s.start();
      await spin();
      s.pause();
      gate.complete();
      await s.cancel().timeout(const Duration(seconds: 5));
      expect(s.current.state, TmdbSyncState.idle);
      await s.dispose();
    });

    test('start while running just resumes; pause is idempotent', () async {
      repo = FakeRepo(films(2));
      final s = svc();
      s.start();
      s.pause();
      s.pause();
      s.start(); // resumes
      final p = await finished(s);
      expect(p.matched, 2);
      await s.dispose();
    });
  });

  group('on demand', () {
    test('fetchNow jumps ahead of the background queue', () async {
      repo = FakeRepo(films(30));
      // The background loop is stuck on Film 3's search.
      final hold = Completer<void>();
      api.gate = (c) => c.query == 'Film 3' ? hold.future : Future.value();
      final s = svc();
      s.start();
      await spin(40);
      expect(api.calls.last.query, 'Film 3');
      final r = await s.fetchNow(title(99, 'Film 99', year: 2000));
      expect(r.status, TmdbFetchStatus.matched);
      // Looked up (search + details) while the queue was still at Film 3.
      final order = [for (final c in api.calls) c.query];
      expect(order, contains('Film 99'));
      expect(order, isNot(contains('Film 4')));
      expect(repo.matches.any((m) => m.titleId == 99), isTrue);
      hold.complete();
      await s.cancel();
      await s.dispose();
    });

    test(
      'on-demand request beats the next queued background request',
      () async {
        repo = FakeRepo(films(30));
        // Stall the pacer itself: hold the first delay so both callers queue.
        final release = Completer<void>();
        var held = false;
        Future<void> delay(Duration d) async {
          if (!held && d > Duration.zero) {
            held = true;
            await release.future;
          }
          await clock.delay(d);
        }

        final s = TmdbSyncService(
          repo: repo,
          api: api,
          delay: delay,
          clock: () => clock.now,
        );
        s.start();
        await spin(40); // loop did request 1 (no wait), now waits for slot 2
        expect(api.calls, hasLength(1));
        final f = s.fetchNow(title(99, 'Film 99', year: 2000));
        await spin(10);
        release.complete();
        await f;
        final order = [for (final c in api.calls) '${c.kind}:${c.query}'];
        expect(order[1], 'movie:Film 99');
        await s.cancel();
        await s.dispose();
      },
    );

    test('works without the background loop and shares the throttle', () async {
      repo = FakeRepo(films(3));
      final s = svc();
      final a = s.fetchNow(repo.titles[0]);
      final b = s.fetchNow(repo.titles[1]);
      await Future.wait([a, b]);
      final t = [for (final c in api.calls) c.at];
      for (var i = 1; i < t.length; i++) {
        expect(
          t[i].difference(t[i - 1]),
          greaterThanOrEqualTo(const Duration(milliseconds: 200)),
        );
      }
      expect(s.isRunning, isFalse);
      await s.dispose();
    });

    test('same title twice shares one lookup', () async {
      repo = FakeRepo(films(1));
      final s = svc();
      final r = await Future.wait([
        s.fetchNow(repo.titles[0]),
        s.fetchNow(repo.titles[0]),
      ]);
      expect(r.map((x) => x.status), everyElement(TmdbFetchStatus.matched));
      expect(repo.matches, hasLength(1));
      await s.dispose();
    });

    test('stored data means no request', () async {
      repo = FakeRepo(films(1));
      repo.infos[1] = TmdbInfo(
        titleId: 1,
        status: TmdbStatus.matched,
        fetchedAt: clock.now,
      );
      final s = svc();
      expect((await s.fetchNow(repo.titles[0])).status, TmdbFetchStatus.cached);
      expect(api.calls, isEmpty);
      // force overrides
      expect(
        (await s.fetchNow(repo.titles[0], force: true)).status,
        TmdbFetchStatus.matched,
      );
      await s.dispose();
    });

    test('old unmatched row is retried, fresh one is not', () async {
      repo = FakeRepo(films(1));
      final s = svc();
      repo.infos[1] = TmdbInfo(
        titleId: 1,
        status: TmdbStatus.unmatched,
        fetchedAt: clock.now.subtract(const Duration(hours: 1)),
      );
      expect((await s.fetchNow(repo.titles[0])).status, TmdbFetchStatus.cached);
      repo.infos[1] = TmdbInfo(
        titleId: 1,
        status: TmdbStatus.unmatched,
        fetchedAt: clock.now.subtract(const Duration(days: 3)),
      );
      expect(
        (await s.fetchNow(repo.titles[0])).status,
        TmdbFetchStatus.matched,
      );
      await s.dispose();
    });

    test('fetchNowById resolves the title; unknown id fails softly', () async {
      repo = FakeRepo(films(2));
      final s = svc();
      expect((await s.fetchNowById(2)).status, TmdbFetchStatus.matched);
      final r = await s.fetchNowById(77);
      expect(r.status, TmdbFetchStatus.failed);
      expect(r.error!.kind, TmdbErrorKind.notFound);
      await s.dispose();
    });

    test('failure comes back as a result, not an exception', () async {
      repo = FakeRepo(films(1));
      api.errors.addAll([_net, _net, _net, _net]);
      final s = svc(maxRetries: 3);
      final r = await s.fetchNow(repo.titles[0]);
      expect(r.status, TmdbFetchStatus.failed);
      expect(r.error!.kind, TmdbErrorKind.network);
      await s.dispose();
    });

    test('events are not looked up', () async {
      repo = FakeRepo([]);
      final s = svc();
      final r = await s.fetchNow(title(1, 'WWE', kind: TitleKind.event));
      expect(r.status, TmdbFetchStatus.unmatched);
      expect(api.calls, isEmpty);
      await s.dispose();
    });
  });

  group('manual', () {
    test('rematch saves details with manual: true', () async {
      repo = FakeRepo(films(1));
      final s = svc();
      final r = await s.rematch(1, 4242, TmdbMediaType.tv);
      expect(r.status, TmdbFetchStatus.matched);
      expect(r.details!.id, 4242);
      expect(r.details!.mediaType, TmdbMediaType.tv);
      final m = repo.matches.single;
      expect((m.titleId, m.manual, m.d.id), (1, true, 4242));
      expect(api.calls.single.kind, 'details');
      await s.dispose();
    });

    test('rematch failure is a result and saves nothing', () async {
      repo = FakeRepo(films(1));
      api.errors.add(const TmdbException(TmdbErrorKind.notFound, 'nope'));
      final s = svc();
      final r = await s.rematch(1, 1, TmdbMediaType.movie);
      expect(r.status, TmdbFetchStatus.failed);
      expect(r.error!.kind, TmdbErrorKind.notFound);
      expect(repo.matches, isEmpty);
      await s.dispose();
    });

    test(
      'searchCandidates passes query and year, uses the right endpoint',
      () async {
        repo = FakeRepo([]);
        api.results = (kind, q, year) => [hit(1, '$kind $q', year)];
        final s = svc();
        final a = await s.searchCandidates(
          ' Heat ',
          TmdbMediaType.movie,
          year: 1995,
        );
        final b = await s.searchCandidates('Heat', TmdbMediaType.tv);
        expect(a.single.title, 'movie Heat');
        expect(b.single.title, 'tv Heat');
        expect(api.calls.map((c) => c.year), [1995, null]);
        expect(await s.searchCandidates('  ', TmdbMediaType.movie), isEmpty);
        await s.dispose();
      },
    );

    test('searchCandidates throws a typed error', () async {
      repo = FakeRepo([]);
      api.errors.add(
        const TmdbException(
          TmdbErrorKind.unauthorized,
          'TMDB rejected the key.',
        ),
      );
      final s = svc();
      await expectLater(
        s.searchCandidates('x', TmdbMediaType.movie),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.kind,
            'kind',
            TmdbErrorKind.unauthorized,
          ),
        ),
      );
      await s.dispose();
    });

    test(
      'manual rematch while the loop is busy is not queued behind it',
      () async {
        repo = FakeRepo(films(30));
        final hold = Completer<void>();
        api.gate = (c) => c.query == 'Film 3' ? hold.future : Future.value();
        final s = svc();
        s.start();
        await spin(40);
        await s.rematch(5, 777, TmdbMediaType.movie);
        final order = [for (final c in api.calls) '${c.kind}:${c.query}'];
        expect(order, contains('details:777'));
        expect(order, isNot(contains('movie:Film 4')));
        hold.complete();
        await s.cancel();
        await s.dispose();
      },
    );
  });
}

/// Repository whose first save fails.
class _Flaky extends FakeRepo {
  _Flaky(FakeRepo base, this.shouldFail) : super(base.titles);
  final bool Function() shouldFail;
  @override
  Future<void> saveTmdbMatch(
    int titleId,
    TmdbDetails d, {
    bool manual = false,
  }) {
    if (shouldFail()) throw StateError('disk full');
    return super.saveTmdbMatch(titleId, d, manual: manual);
  }
}
