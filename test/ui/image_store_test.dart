import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/features/browse/image_store.dart';

void main() {
  late Directory dir;
  late int hits;
  var offline = false;
  var now = DateTime(2026, 11, 22);

  ImageStore make({int max = 10, Duration? stale}) => ImageStore(
    dir: () async => dir,
    maxObjects: max,
    stalePeriod: stale ?? const Duration(days: 60),
    now: () => now,
    client: MockClient((req) async {
      hits++;
      if (offline) throw const SocketException('offline');
      if (req.url.path.endsWith('.html')) {
        return http.Response(
          '<html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      }
      if (req.url.path.endsWith('.404')) return http.Response('', 404);
      return http.Response(
        'img-${req.url.path}',
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    }),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('imgstore');
    hits = 0;
    offline = false;
    now = DateTime.now();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('miss downloads once, hit serves from disk', () async {
    final s = make();
    final f = await s.fetch('http://172.16.50.7/p/a.jpg');
    expect(f, isNotNull);
    expect(f!.readAsStringSync(), 'img-/p/a.jpg');
    expect(hits, 1);
    offline = true; // a hit must not touch the network
    expect((await s.fetch('http://172.16.50.7/p/a.jpg'))!.path, f.path);
    expect(s.peek('http://172.16.50.7/p/a.jpg'), isNotNull);
    expect(hits, 1);
  });

  test('concurrent fetches of one url share a download', () async {
    final s = make();
    final r = await Future.wait([
      s.fetch('http://x/p/b.jpg'),
      s.fetch('http://x/p/b.jpg'),
      s.fetch('http://x/p/b.jpg'),
    ]);
    expect(r.every((f) => f != null), isTrue);
    expect(hits, 1);
  });

  test(
    'offline / http error / non-image give null and are not retried at once',
    () async {
      final s = make();
      offline = true;
      expect(await s.fetch('http://x/p/c.jpg'), isNull);
      expect(await s.fetch('http://x/p/c.jpg'), isNull);
      expect(hits, 1, reason: 'failure memoised for 60 s');
      offline = false;
      expect(await s.fetch('http://x/p/missing.404'), isNull);
      expect(await s.fetch('http://x/p/page.html'), isNull);
      expect(await s.count(), 0);
      now = now.add(const Duration(seconds: 61));
      expect(await s.fetch('http://x/p/c.jpg'), isNotNull);
    },
  );

  test(
    'hard cap: never more than maxObjects files, least recently used go first',
    () async {
      final s = make(max: 20);
      for (var i = 0; i < 20; i++) {
        final f = (await s.fetch('http://x/p/$i.jpg'))!;
        // Spread mtimes so order is deterministic: 0 is the oldest.
        f.setLastModifiedSync(
          DateTime.now().subtract(Duration(minutes: 100 - i)),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Use 0 again: it becomes the most recently used.
      final f0 = s.peek('http://x/p/0.jpg')!;
      f0.setLastModifiedSync(DateTime.now());
      for (var i = 20; i < 30; i++) {
        await s.fetch('http://x/p/$i.jpg');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(await s.count(), lessThanOrEqualTo(20), reason: 'after $i');
      }
      expect(s.peek('http://x/p/29.jpg'), isNotNull, reason: 'newest kept');
      expect(
        s.peek('http://x/p/0.jpg'),
        isNotNull,
        reason: 'recently used kept',
      );
      expect(s.peek('http://x/p/1.jpg'), isNull, reason: 'LRU evicted');
    },
  );

  test('default cap is 1500 and stale period 60 days', () {
    expect(kImageCacheMaxObjects, 1500);
    expect(kImageCacheStalePeriod, const Duration(days: 60));
  });

  test('stale files are dropped on peek and on trim', () async {
    final s = make();
    final f = (await s.fetch('http://x/p/old.jpg'))!;
    final g = (await s.fetch('http://x/p/new.jpg'))!;
    f.setLastModifiedSync(now.subtract(const Duration(days: 61)));
    expect(s.peek('http://x/p/old.jpg'), isNull);
    expect(f.existsSync(), isFalse);
    final h = (await s.fetch('http://x/p/old2.jpg'))!;
    h.setLastModifiedSync(now.subtract(const Duration(days: 90)));
    await s.trim();
    expect(h.existsSync(), isFalse);
    expect(g.existsSync(), isTrue);
  });

  test('clear empties the dir and the cache refills', () async {
    final s = make();
    await s.fetch('http://x/p/1.jpg');
    await s.fetch('http://x/p/2.jpg');
    expect(await s.count(), 2);
    await s.clear();
    expect(await s.count(), 0);
    expect(s.peek('http://x/p/1.jpg'), isNull);
    expect(await s.fetch('http://x/p/1.jpg'), isNotNull);
  });

  test('no cache dir: fetch quietly returns null', () async {
    final s = ImageStore(dir: () async => null);
    expect(await s.fetch('http://x/p/1.jpg'), isNull);
    expect(s.peek('http://x/p/1.jpg'), isNull);
  });
}
