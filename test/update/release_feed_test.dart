import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/features/update/release_feed.dart';
import 'package:watchdog/features/update/update_service.dart';

const _feed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en-US">
  <id>tag:github.com,2008:https://github.com/o/r/releases</id>
  <link type="text/html" rel="alternate" href="https://github.com/o/r/releases"/>
  <title>Release notes from r</title>
  <entry>
    <id>tag:github.com,2008:Repository/1/v0.3.0</id>
    <updated>2026-11-22T11:58:44Z</updated>
    <link rel="alternate" type="text/html" href="https://github.com/o/r/releases/tag/v0.3.0"/>
    <title>watchdog v0.3.0</title>
    <content type="html">&lt;h2&gt;What&#39;s new&lt;/h2&gt;
&lt;ul&gt;
&lt;li&gt;&lt;strong&gt;Fast first run.&lt;/strong&gt; Usable in seconds.&lt;/li&gt;
&lt;li&gt;Settings -&amp;gt; Library&lt;/li&gt;
&lt;/ul&gt;</content>
  </entry>
  <entry>
    <id>tag:github.com,2008:Repository/1/v0.2.0</id>
    <link rel="alternate" type="text/html" href="https://github.com/o/r/releases/tag/v0.2.0"/>
    <title>watchdog v0.2.0</title>
    <content type="html">&lt;p&gt;old&lt;/p&gt;</content>
  </entry>
</feed>''';

const _assets = '''
<a href="/o/r/releases/download/v0.3.0/watchdog-v0.3.0-arm64.apk">apk</a>
<a href="/o/r/releases/download/v0.3.0/watchdog-v0.3.0-arm64.apk.sha256">sha</a>
<a href="/o/r/archive/refs/tags/v0.3.0.zip">zip</a>
<a href="/o/r/archive/refs/tags/v0.3.0.tar.gz">tgz</a>''';

final _sum = 'ab' * 32;

void main() {
  group('parsing', () {
    test('feed entries, newest first, notes as plain text', () {
      final e = parseReleasesFeed(_feed);
      expect(e.map((x) => x.tag), ['v0.3.0', 'v0.2.0']);
      expect(e.first.pageUrl, 'https://github.com/o/r/releases/tag/v0.3.0');
      expect(e.first.title, 'watchdog v0.3.0');
      expect(e.first.notes, contains("What's new"));
      expect(e.first.notes, contains('- Fast first run. Usable in seconds.'));
      expect(e.first.notes, contains('Settings -> Library'));
      expect(e.first.notes, isNot(contains('<')));
    });

    test('garbage and entries without a tag link are ignored', () {
      expect(parseReleasesFeed('<html>nope</html>'), isEmpty);
      expect(
        parseReleasesFeed(
          '<entry><link rel="alternate" href="https://x/y"/></entry>',
        ),
        isEmpty,
      );
    });

    test('assets: downloads only, absolute urls, apk + checksum pairing', () {
      final a = parseExpandedAssets(_assets);
      expect(a.map((x) => x.name), [
        'watchdog-v0.3.0-arm64.apk',
        'watchdog-v0.3.0-arm64.apk.sha256',
      ]);
      expect(
        a.first.url,
        'https://github.com/o/r/releases/download/v0.3.0/watchdog-v0.3.0-arm64.apk',
      );
      final apk = pickApk(a)!;
      expect(apk.name, endsWith('.apk'));
      expect(pickChecksum(a, apk)?.name, endsWith('.apk.sha256'));
    });

    test('pickApk prefers the abi and ignores non-apks', () {
      final a = [
        const FeedAsset(name: 'x-x86.apk', url: 'u1'),
        const FeedAsset(name: 'x-arm64.apk', url: 'u2'),
        const FeedAsset(name: 'notes.txt', url: 'u3'),
      ];
      expect(pickApk(a)!.url, 'u2');
      expect(pickApk(const [FeedAsset(name: 'a.txt', url: 'u')]), isNull);
    });

    test('sha256 file: hash first, name after', () {
      expect(parseSha256File('${_sum.toUpperCase()}  app.apk\n'), _sum);
      expect(parseSha256File('no hash here'), isNull);
    });
  });

  group('UpdateService falls back to the feed', () {
    late List<Uri> seen;

    MockClient client({
      int api = 403,
      String? apiBody,
      int feed = 200,
      String feedBody = _feed,
      int assets = 200,
      Object? throwApi,
    }) {
      seen = [];
      return MockClient((r) async {
        seen.add(r.url);
        if (r.url.host == 'api.github.com') {
          if (throwApi != null) throw throwApi;
          return http.Response(apiBody ?? '{}', api);
        }
        if (r.url.path.endsWith('releases.atom')) {
          return http.Response(feedBody, feed);
        }
        if (r.url.path.contains('expanded_assets')) {
          return http.Response(_assets, assets);
        }
        if (r.url.path.endsWith('.sha256')) {
          return http.Response('$_sum  watchdog-v0.3.0-arm64.apk\n', 200);
        }
        return http.Response('', 404);
      });
    }

    test('API 403 -> newer release from the feed, with checksum', () async {
      final s = UpdateService(repo: 'o/r', client: client());
      final r = await s.check(currentVersion: '0.2.0+2');
      expect(r, isNotNull);
      expect(r!.tag, 'v0.3.0');
      expect(r.version, '0.3.0');
      expect(r.apkName, 'watchdog-v0.3.0-arm64.apk');
      expect(
        r.apkUrl,
        'https://github.com/o/r/releases/download/v0.3.0/watchdog-v0.3.0-arm64.apk',
      );
      expect(r.sha256, _sum);
      expect(r.notes, contains('Fast first run'));
      expect(seen.first.host, 'api.github.com');
      expect(seen.any((u) => u.path.endsWith('releases.atom')), isTrue);
    });

    test('API 429 and plain network failure also fall back', () async {
      final a = UpdateService(repo: 'o/r', client: client(api: 429));
      expect((await a.check(currentVersion: '0.2.0'))?.tag, 'v0.3.0');
      final b = UpdateService(
        repo: 'o/r',
        client: client(throwApi: http.ClientException('blocked')),
      );
      expect((await b.check(currentVersion: '0.2.0'))?.tag, 'v0.3.0');
    });

    test('already on the newest -> null, no asset requests', () async {
      final s = UpdateService(repo: 'o/r', client: client());
      expect(await s.check(currentVersion: '0.3.0+3'), isNull);
      expect(seen.any((u) => u.path.contains('expanded_assets')), isFalse);
    });

    test('both limited -> the rate-limit message', () async {
      final s = UpdateService(repo: 'o/r', client: client(feed: 429));
      await expectLater(
        s.check(currentVersion: '0.2.0'),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('rate limit'),
          ),
        ),
      );
    });

    test('feed fails for another reason -> the feed error is shown', () async {
      final s = UpdateService(repo: 'o/r', client: client(api: 500, feed: 503));
      await expectLater(
        s.check(currentVersion: '0.2.0'),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });

    test('release without an apk -> nothing to install', () async {
      final s = UpdateService(
        repo: 'o/r',
        client: MockClient((r) async {
          if (r.url.host == 'api.github.com') return http.Response('', 403);
          if (r.url.path.endsWith('releases.atom')) {
            return http.Response(_feed, 200);
          }
          return http.Response(
            '<a href="/o/r/archive/refs/tags/v.zip">z</a>',
            200,
          );
        }),
      );
      expect(await s.check(currentVersion: '0.1.0'), isNull);
    });

    test('garbage instead of a feed is an error, not "up to date"', () async {
      final s = UpdateService(
        repo: 'o/r',
        client: client(feedBody: '<html>blocked</html>'),
      );
      await expectLater(
        s.check(currentVersion: '0.2.0'),
        throwsA(isA<UpdateException>()),
      );
      final empty = UpdateService(
        repo: 'o/r',
        client: client(feedBody: '<feed xmlns="http://www.w3.org/2005/Atom"/>'),
      );
      expect(await empty.check(currentVersion: '0.2.0'), isNull);
    });

    test('pre-releases excluded -> no fallback (feed cannot tell)', () async {
      final s = UpdateService(repo: 'o/r', client: client());
      await expectLater(
        s.check(currentVersion: '0.2.0', prerelease: false),
        throwsA(isA<UpdateException>()),
      );
      expect(seen.every((u) => u.host == 'api.github.com'), isTrue);
    });

    test('a working API is used and the feed is never touched', () async {
      final s = UpdateService(
        repo: 'o/r',
        client: client(
          api: 200,
          apiBody: jsonEncode([
            {
              'tag_name': 'v0.4.0',
              'prerelease': true,
              'body': 'api',
              'html_url': 'u',
              'assets': [
                {'name': 'a-arm64.apk', 'browser_download_url': 'd', 'size': 1},
              ],
            },
          ]),
        ),
      );
      expect((await s.check(currentVersion: '0.3.0'))?.notes, 'api');
      expect(seen.every((u) => u.host == 'api.github.com'), isTrue);
    });
  });
}
