// ignore_for_file: avoid_print
// Live, polite run of the REAL index service (API skeleton crawl + HTML
// fallback) against a TEMP database file (never the app's). Needs BDIX.
// Reports time-to-first-batch, time-to-complete, requests, bytes, DB size
// after compact(), titles per category; then a second (incremental) run.
//
// The service imports Flutter-only packages (riverpod), so run it through the
// Flutter test runner (it is a test file in disguise, never part of
// `flutter test` because it lives in tool/):
//
//   WATCHDOG_LIVE=1 flutter test tool/skeleton_index_smoke.dart
//   WATCHDOG_LIVE=1 WATCHDOG_ONLY="English Movies,3D Movies" flutter test tool/skeleton_index_smoke.dart
//   WATCHDOG_NO_INCREMENTAL=1 ...   (skip the second run)
//
// At most 8 requests in flight per host (adaptive 6..8). The temp directory is
// deleted at the end.
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/host_limiter.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/data/database.dart';
import 'package:watchdog/data/drift_repository.dart';
import 'package:watchdog/features/index/index_meta.dart';
import 'package:watchdog/features/index/index_service.dart';

/// Previous numbers (TASKS.md T6.3, full HTML crawl era / API vs HTML check).
const _reference = {
  'English Movies': 14832,
  'TV & Web Series': 2382, // CLAUDE.md says 2383 shows
};

String _mb(num b) => (b / 1e6).toStringAsFixed(1);

Future<int> _size(Directory d) async {
  var n = 0;
  await for (final f in d.list()) {
    if (f is File) n += await f.length();
  }
  return n;
}

Future<void> _smoke() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final only = Platform.environment['WATCHDOG_ONLY']
      ?.split(',')
      .map((s) => s.trim())
      .toSet();
  final defaults = CrawlConfig.defaults();
  final cfg = only == null
      ? defaults
      : CrawlConfig(
          servers: [
            for (final s in defaults.servers)
              s.copyWith(
                categories: [
                  for (final c in s.categories)
                    if (only.contains(c.name)) c,
                ],
              ),
          ].where((s) => s.categories.isNotEmpty).toList(),
        );

  final dir = Directory.systemTemp.createTempSync('wd_index_smoke');
  final db = openDatabaseAt(File('${dir.path}/smoke.db'));
  final repo = DriftRepository(db);
  final limiters = HostLimiters(max: 8);
  final api = H5aiApiClient(limiters: limiters);
  final html = HttpListingClient();
  final meta = MemoryIndexMeta();
  final svc = IndexService(
    repository: repo,
    client: html,
    api: api,
    limiters: limiters,
    configOf: () => cfg,
    meta: meta,
  );

  try {
    var maxLag = Duration.zero;
    final lagClock = Stopwatch()..start();
    var last = lagClock.elapsed;
    final lag = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = lagClock.elapsed;
      final l = now - last - const Duration(milliseconds: 5);
      if (l > maxLag) maxLag = l;
      last = now;
    });

    for (final pass in ['first run', 'incremental run']) {
      if (pass != 'first run' &&
          Platform.environment['WATCHDOG_NO_INCREMENTAL'] != null) {
        break;
      }
      print('\n=== $pass ===');
      var firstSeen = false;
      var nextLine = const Duration(seconds: 5);
      final sw = Stopwatch()..start();
      final sub = svc.states.listen((s) {
        if (!firstSeen && s.hasUsableData && s.titlesWritten > 0) {
          firstSeen = true;
          print(
            '  first batch committed after ${sw.elapsedMilliseconds} ms '
            '(${s.titlesWritten} titles)',
          );
        }
        if (sw.elapsed >= nextLine) {
          nextLine += const Duration(seconds: 5);
          print(
            '  ${sw.elapsed.inSeconds}s: ${s.titlesIndexed} titles'
            '${s.estimatedTotal == null ? '' : ' / ~${s.estimatedTotal}'}, '
            '${s.foldersFetched} requests, ${s.errors} errors',
          );
        }
      });
      final bytes0 = api.bytes;
      final res = await svc.reindex();
      await sub.cancel();
      final reqs = res.requests;
      print(
        '  outcome=${res.outcome.name} ${res.message ?? ''}\n'
        '  complete in ${res.elapsed.inMilliseconds} ms, '
        'first batch ${res.firstBatchAfter?.inMilliseconds ?? '-'} ms\n'
        '  requests=$reqs  API bytes=${_mb(api.bytes - bytes0)} MB  '
        'batches=${res.batches}\n'
        '  written=${res.titlesWritten} unchanged=${res.titlesUnchanged} '
        'removed=${res.titlesRemoved}  http limits=${limiters.limits}',
      );
      await repo.compact();
      print(
        '  DB after compact(): ${_mb(await _size(dir))} MB '
        '(all files in the temp dir)',
      );
      final c = await repo.counts();
      print(
        '  counts: ${c.titles} titles, ${c.series} series, '
        '${c.files} files (stored sum), ${c.categories} categories',
      );
      print('  titles per category:');
      for (final cat in await repo.categories()) {
        final ref = _reference[cat.name];
        final prog = res.categories.where((p) => p.name == cat.name);
        final how = prog.isEmpty
            ? ''
            : ' [${prog.first.status.name}${prog.first.htmlFallback ? ', HTML' : ''}'
                  '${prog.first.errors > 0 ? ', ${prog.first.errors} errors' : ''}]';
        print(
          '    ${cat.name.padRight(26)} ${cat.titleCount.toString().padLeft(6)}'
          '${ref == null ? '' : '   (previous crawl: $ref)'}$how',
        );
      }
      for (final p in res.categories.where((p) => p.lastError != null)) {
        print('    ! ${p.name}: ${p.lastError}');
      }
    }
    lag.cancel();
    print('\nmax event-loop lag: ${maxLag.inMilliseconds} ms');
  } finally {
    api.close();
    html.close();
    svc.dispose();
    await repo.close();
    dir.deleteSync(recursive: true);
    print('temp database deleted');
  }
}

void main() {
  test(
    'live index smoke (BDIX only)',
    _smoke,
    timeout: const Timeout(Duration(minutes: 15)),
    skip: Platform.environment['WATCHDOG_LIVE'] == null
        ? 'set WATCHDOG_LIVE=1 (needs BDIX); '
              'see the header for the other switches'
        : false,
  );
}
