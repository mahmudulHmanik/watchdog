import 'dart:convert';
import 'dart:io';

import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/classifier.dart';
import 'package:watchdog/crawler/listing.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/data/models.dart';

const fixtureDir = 'test/fixtures/crawl';

/// Serves the saved tiny h5ai pages in test/fixtures/crawl by exact URL.
class FakeListingClient implements ListingClient {
  FakeListingClient._(this.roots, this.pages);

  factory FakeListingClient.fromFixtures() {
    final m = jsonDecode(
      File('$fixtureDir/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final pages = <String, String>{
      for (final e in (m['pages'] as Map).entries)
        e.key as String: File('$fixtureDir/${e.value}').readAsStringSync(),
    };
    return FakeListingClient._(
      (m['roots'] as Map).cast<String, String>(),
      pages,
    );
  }

  final Map<String, String> roots;
  final Map<String, String> pages;

  /// Hosts that never answer (connect failure).
  final Set<String> downHosts = {};

  /// Hosts that answer the portal probe but fail every other request.
  final Set<String> flakyHosts = {};

  /// url -> failures to throw before succeeding.
  final Map<String, List<FetchException>> failures = {};
  Duration latency = Duration.zero;

  final List<String> requests = [];
  int inFlight = 0, maxInFlight = 0;

  @override
  Future<String> fetch(Uri url, {required Duration timeout}) async {
    requests.add(url.toString());
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (latency > Duration.zero) await Future<void>.delayed(latency);
      if (downHosts.contains(url.host)) {
        throw FetchException(url, FetchFailure.connect, 'no route to host');
      }
      if (url.path == '/' || url.path.isEmpty) return '<html>portal</html>';
      if (flakyHosts.contains(url.host)) {
        throw FetchException(url, FetchFailure.timeout, 'timed out');
      }
      final q = failures[url.toString()];
      if (q != null && q.isNotEmpty) throw q.removeAt(0);
      final p = pages[url.toString()];
      if (p == null) {
        throw FetchException(url, FetchFailure.http, 'HTTP 404', status: 404);
      }
      return p;
    } finally {
      inFlight--;
    }
  }

  @override
  void close() {}

  /// Fully listed tree below [url] using the fixture pages (for classifier tests).
  FolderNode tree(String url, {String? name, DateTime? mtime}) {
    final base = FolderNode.fromListing(
      url,
      parseListing(pages[url]!),
      name: name,
      mtime: mtime,
    );
    return FolderNode(
      name: base.name,
      url: base.url,
      mtime: base.mtime,
      files: base.files,
      folders: [
        for (final f in base.folders)
          pages.containsKey(f.url)
              ? tree(f.url, name: f.name, mtime: f.mtime)
              : f,
      ],
    );
  }

  /// Config covering every fixture category.
  CrawlConfig config() => CrawlConfig(
    servers: [
      ServerConfig(
        host: '172.16.50.7',
        categories: [
          CategoryConfig(
            name: 'English Movies',
            url: roots['English Movies']!,
            layout: LayoutKind.yearBuckets,
            kind: TitleKind.movie,
            language: 'english',
          ),
          CategoryConfig(
            name: 'Foreign Language Movies',
            url: roots['Foreign Language Movies']!,
            layout: LayoutKind.flat,
            kind: TitleKind.movie,
          ),
        ],
      ),
      ServerConfig(
        host: '172.16.50.14',
        categories: [
          CategoryConfig(
            name: 'Korean',
            url: roots['Korean Series']!,
            layout: LayoutKind.series,
            kind: TitleKind.series,
            language: 'korean',
          ),
        ],
      ),
      ServerConfig(
        host: '172.16.50.10',
        categories: [
          CategoryConfig(
            name: 'Anime & Cartoon',
            url: roots['Anime & Cartoon']!,
            layout: LayoutKind.series,
            kind: TitleKind.series,
          ),
          CategoryConfig(
            name: 'WWE & AEW',
            url: roots['WWE & AEW']!,
            layout: LayoutKind.events,
            kind: TitleKind.event,
          ),
        ],
      ),
    ],
  );
}
