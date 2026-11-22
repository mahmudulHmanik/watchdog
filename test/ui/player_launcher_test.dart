import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/player/player_launcher.dart';

import 'fakes.dart';

class _Obs extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) =>
      pushed.add(route);
}

/// Files appear only once [loaded]; every read is logged in [log].
class _LazyRepo extends FakeRepository {
  _LazyRepo(this.log);
  final List<String> log;
  bool loaded = false;

  @override
  Future<List<SeasonEpisodes>> seasons(int titleId) async {
    log.add('seasons:$loaded');
    if (!loaded) return const [];
    return [
      SeasonEpisodes(
        season: Season(id: 1, titleId: titleId, number: 1, label: 'Season 1'),
        files: [mkFile(51, titleId, 'e1.mkv', seasonId: 1)],
      ),
    ];
  }

  @override
  Future<List<MediaFile>> titleFiles(int titleId) async {
    log.add('files:$loaded');
    return loaded ? [mkFile(11, titleId, 'm.mkv')] : const [];
  }
}

Future<(BuildContext, _Obs)> host(WidgetTester t) async {
  late BuildContext ctx;
  final obs = _Obs();
  await t.pumpWidget(
    MaterialApp(
      navigatorObservers: [obs],
      home: Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    ),
  );
  obs.pushed.clear();
  return (ctx, obs);
}

void main() {
  testWidgets('openEpisode waits for the files before reading the season', (
    t,
  ) async {
    final (ctx, obs) = await host(t);
    final log = <String>[];
    final repo = _LazyRepo(log);
    final gate = Completer<void>();
    // Not awaited: it completes only when the player route is popped. No
    // frame is pumped afterwards, so the (media_kit) screen never builds.
    unawaited(
      PlayerLauncher.openEpisode(
        ctx,
        repo,
        titleId: 5,
        fileId: 51,
        ensureLoaded: (id) async {
          log.add('ensure:$id');
          await gate.future;
          repo.loaded = true;
        },
      ),
    );
    await t.idle();
    expect(log, ['ensure:5'], reason: 'nothing read before the load');
    expect(obs.pushed, isEmpty);
    gate.complete();
    await t.idle();
    expect(log, ['ensure:5', 'seasons:true']);
    expect(obs.pushed, hasLength(1), reason: 'playback started');
  });

  testWidgets('openSeason waits too', (t) async {
    final (ctx, obs) = await host(t);
    final log = <String>[];
    final repo = _LazyRepo(log);
    unawaited(
      PlayerLauncher.openSeason(
        ctx,
        repo,
        titleId: 5,
        seasonId: 1,
        ensureLoaded: (_) async {
          log.add('ensure');
          repo.loaded = true;
        },
      ),
    );
    await t.idle();
    expect(log, ['ensure', 'seasons:true']);
    expect(obs.pushed, hasLength(1));
  });

  testWidgets('openTitle (movie) loads, then plays the first file', (t) async {
    final (ctx, obs) = await host(t);
    final log = <String>[];
    final repo = _LazyRepo(log);
    unawaited(
      PlayerLauncher.openTitle(
        ctx,
        repo,
        title: mkTitle(1, 'Film'),
        ensureLoaded: (_) async {
          log.add('ensure');
          repo.loaded = true;
        },
      ),
    );
    await t.idle();
    expect(log, ['ensure', 'files:true']);
    expect(obs.pushed, hasLength(1));
  });

  testWidgets('a failing load propagates; nothing is read or pushed', (
    t,
  ) async {
    final (ctx, obs) = await host(t);
    final log = <String>[];
    final err = FetchException(
      Uri.parse('http://h/'),
      FetchFailure.connect,
      'no route',
    );
    await expectLater(
      PlayerLauncher.openEpisode(
        ctx,
        _LazyRepo(log),
        titleId: 5,
        fileId: 51,
        ensureLoaded: (_) async => throw err,
      ),
      throwsA(same(err)),
    );
    expect(log, isEmpty);
    expect(obs.pushed, isEmpty);
  });

  testWidgets('without ensureLoaded it reads straight away (old behaviour)', (
    t,
  ) async {
    final (ctx, obs) = await host(t);
    final log = <String>[];
    final repo = _LazyRepo(log)..loaded = true;
    unawaited(PlayerLauncher.openEpisode(ctx, repo, titleId: 5, fileId: 51));
    await t.idle();
    expect(log, ['seasons:true']);
    expect(obs.pushed, hasLength(1));
  });

  testWidgets('empty after the load -> false, no route', (t) async {
    final (ctx, obs) = await host(t);
    final repo = _LazyRepo([]);
    final ok = await PlayerLauncher.openEpisode(
      ctx,
      repo,
      titleId: 5,
      fileId: 51,
      ensureLoaded: (_) async {}, // stays empty
    );
    expect(ok, isFalse);
    expect(obs.pushed, isEmpty);
  });
}
