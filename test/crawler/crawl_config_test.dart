import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/data/models.dart';

void main() {
  final cfg = CrawlConfig.defaults();

  test('defaults: servers .7 .10 .12 .14 only; .8 and Tutorial excluded', () {
    expect(cfg.servers.map((s) => s.host), [
      '172.16.50.7',
      '172.16.50.10',
      '172.16.50.12',
      '172.16.50.14',
    ]);
    final all = cfg.servers.expand((s) => s.categories).toList();
    expect(all.any((c) => c.url.contains('FLIX-8/')), isFalse);
    expect(
      all.any(
        (c) =>
            c.name.toLowerCase().contains('tutorial') ||
            c.url.toLowerCase().contains('tutorial'),
      ),
      isFalse,
    );
    expect(
      all.every((c) => c.url.endsWith('/') && c.url.startsWith('http://')),
      isTrue,
    );
  });

  test('layouts and kinds', () {
    CategoryConfig c(String n) =>
        cfg.servers.expand((s) => s.categories).firstWhere((c) => c.name == n);
    expect(c('Korean TV & Web Series').layout, LayoutKind.series);
    expect(c('Korean TV & Web Series').language, 'korean');
    expect(c('TV & Web Series').layout, LayoutKind.series);
    expect(c('Anime & Cartoon').layout, LayoutKind.series);
    expect(c('WWE & AEW').kind, TitleKind.event);
    expect(c('English Movies').layout, LayoutKind.yearBuckets);
    expect(c('Hindi Movies').language, 'hindi');
  });

  test('JSON round trip is lossless', () {
    final text = jsonEncode(cfg.toJson());
    final back = CrawlConfig.fromJson(jsonDecode(text) as Map<String, Object?>);
    expect(jsonEncode(back.toJson()), text);
  });

  test('enabledCategories honours server and category flags', () {
    final n = cfg.enabledCategories.length;
    final off = cfg.copyWith(
      servers: [
        cfg.servers[0].copyWith(enabled: false),
        ...cfg.servers.skip(1),
      ],
    );
    expect(off.enabledCategories.length, n - cfg.servers[0].categories.length);
    final cat = cfg.servers[1].categories;
    final one = cfg.copyWith(
      servers: [
        cfg.servers[0],
        cfg.servers[1].copyWith(
          categories: [cat[0].copyWith(enabled: false), ...cat.skip(1)],
        ),
        ...cfg.servers.skip(2),
      ],
    );
    expect(one.enabledCategories.length, n - 1);
  });

  test('bad layout/kind throws FormatException', () {
    expect(
      () => CategoryConfig.fromJson({
        'name': 'x',
        'url': 'u',
        'layout': 'nope',
        'kind': 'movie',
      }),
      throwsFormatException,
    );
    expect(
      () => CategoryConfig.fromJson({
        'name': 'x',
        'url': 'u',
        'layout': 'flat',
        'kind': 'nope',
      }),
      throwsFormatException,
    );
  });

  group('migration', () {
    Map<String, Object?> stored({int? version, String layout = 'flat'}) => {
      'version': ?version,
      'servers': [
        {
          'host': '172.16.50.7',
          'enabled': true,
          'categories': [
            {
              'name': 'Foreign Language Movies',
              'url': 'http://172.16.50.7/DHAKA-FLIX-7/Foreign%20Language%20Movies/',
              'layout': layout,
              'kind': 'movie',
              'language': null,
              'enabled': true,
            },
            {
              'name': '3D Movies',
              'url': 'http://172.16.50.7/DHAKA-FLIX-7/3D%20Movies/',
              'layout': 'flat',
              'kind': 'movie',
              'enabled': true,
            },
          ],
        },
      ],
    };

    LayoutKind layoutOf(CrawlConfig c, String name) => c.servers
        .expand((s) => s.categories)
        .firstWhere((x) => x.name == name)
        .layout;

    test('old stored Foreign Language Movies `flat` becomes yearBuckets', () {
      for (final v in [null, 1]) {
        final c = CrawlConfig.fromJson(stored(version: v));
        expect(layoutOf(c, 'Foreign Language Movies'), LayoutKind.yearBuckets);
        expect(layoutOf(c, '3D Movies'), LayoutKind.flat); // others untouched
      }
    });

    test('current documents are left alone; defaults round trip as v2', () {
      final c = CrawlConfig.fromJson(stored(version: 2));
      expect(layoutOf(c, 'Foreign Language Movies'), LayoutKind.flat);
      expect(CrawlConfig.currentVersion, 2);
      expect(cfg.toJson()['version'], 2);
    });

    test('migration is idempotent and re-saves as the new version', () {
      final once = CrawlConfig.fromJson(stored());
      final twice = once.migrated();
      expect(jsonEncode(twice.toJson()), jsonEncode(once.toJson()));
      expect(once.toJson()['version'], 2);
      final back = CrawlConfig.fromJson(
        jsonDecode(jsonEncode(once.toJson())) as Map<String, Object?>,
      );
      expect(layoutOf(back, 'Foreign Language Movies'), LayoutKind.yearBuckets);
    });

    test('defaults already use buckets for Foreign Language Movies', () {
      expect(layoutOf(cfg, 'Foreign Language Movies'), LayoutKind.yearBuckets);
    });
  });
}
