import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/crawler.dart';

import 'fakes.dart';

void main() {
  const fast = CrawlOptions(
    backoffBase: Duration.zero,
    probeTimeout: Duration(milliseconds: 50),
    progressInterval: Duration.zero,
  );
  Future<int> totalRequests() async {
    final f = FakeListingClient.fromFixtures();
    final run = Crawler(f, options: fast).start(f.config());
    await run.items.drain<void>();
    await run.done;
    return f.requests.length;
  }

  group('backpressure', () {
    test('a stalled consumer stops the crawl starting new folders', () async {
      final total = await totalRequests();

      final fake = FakeListingClient.fromFixtures();
      final run = Crawler(
        fake,
        options: const CrawlOptions(
          backoffBase: Duration.zero,
          itemBuffer: 1,
          concurrency: 1,
        ),
      ).start(fake.config());
      var atFirst = -1, n = 0;
      await for (final _ in run.items) {
        if (n++ == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          atFirst = fake.requests.length;
        }
      }
      final s = await run.done;
      expect(n, 11);
      expect(s.complete, isTrue);
      expect(atFirst, lessThan(total), reason: 'crawl ran ahead of consumer');
      expect(fake.requests.length, total);
    });

    test('consumer that stops listening cancels the crawl, no hang', () async {
      final fake = FakeListingClient.fromFixtures();
      final run = Crawler(
        fake,
        options: const CrawlOptions(backoffBase: Duration.zero, itemBuffer: 1),
      ).start(fake.config());
      await run.items.first; // cancels the subscription
      final s = await run.done.timeout(const Duration(seconds: 5));
      expect(s.cancelled, isTrue);
    });

    test(
      'itemBuffer 0 = unbounded: crawl finishes with nobody reading',
      () async {
        final fake = FakeListingClient.fromFixtures();
        final run = Crawler(
          fake,
          options: const CrawlOptions(
            backoffBase: Duration.zero,
            itemBuffer: 0,
          ),
        ).start(fake.config());
        final s = await run.done.timeout(const Duration(seconds: 5));
        expect(s.complete, isTrue);
      },
    );
  });
}
