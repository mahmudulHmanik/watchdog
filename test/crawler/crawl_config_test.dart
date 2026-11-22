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
}
