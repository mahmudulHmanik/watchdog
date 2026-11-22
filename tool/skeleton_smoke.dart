// ignore_for_file: avoid_print
// Live, polite smoke run of the skeleton (API) crawl, one category per layout
// kind, compared with the existing HTML crawl. Needs BDIX. Writes NOTHING but
// stdout. Max 8 parallel requests per host (adaptive 6..8 here).
//
// Usage: dart run tool/skeleton_smoke.dart [--no-html] [--only "<category>"]
//
//  Full API run (timing)      : English Movies, 3D Movies, TV & Web Series,
//                               Anime & Cartoon, Documentary
//  API vs HTML (same folder)  : English "(1996)", 3D Movies, smallest TV
//                               bucket, smallest Anime bucket, Documentary
import 'dart:io';

import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/crawler.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/host_limiter.dart';
import 'package:watchdog/crawler/listing_client.dart';
import 'package:watchdog/crawler/skeleton.dart';
import 'package:watchdog/crawler/skeleton_crawler.dart';
import 'package:watchdog/data/models.dart';

(ServerConfig, CategoryConfig) _find(String name) {
  for (final s in CrawlConfig.defaults().servers) {
    for (final c in s.categories) {
      if (c.name == name) return (s, c);
    }
  }
  throw ArgumentError('no default category $name');
}

class Run {
  Run(this.titles, this.summary, this.seconds, this.bytes);
  final List<SkeletonTitle> titles;
  final SkeletonSummary summary;
  final double seconds;
  final int bytes;
  int get seasons => titles.fold(0, (a, t) => a + t.seasons.length);
}

Future<Run> _skeleton(
  String host,
  CategoryConfig cat, {
  bool seasonsAsSeries = true,
}) async {
  final api = H5aiApiClient(limiters: HostLimiters(max: 8));
  final sw = Stopwatch()..start();
  final run = SkeletonCrawler(
    api,
    seasonContainersAsSeries: seasonsAsSeries,
  ).crawlCategory(host, cat);
  final titles = await run.titles.toList();
  final s = await run.done;
  api.close();
  return Run(titles, s, sw.elapsedMilliseconds / 1000, api.bytes);
}

Future<(List<TitleDraft>, CrawlSummary)> _html(
  ServerConfig s,
  CategoryConfig cat,
) async {
  final client = HttpListingClient();
  final crawler = Crawler(client, limiters: HostLimiters(max: 8));
  final run = crawler.start(
    CrawlConfig(
      servers: [
        s.copyWith(categories: [cat]),
      ],
    ),
  );
  final out = <TitleDraft>[];
  await for (final i in run.items) {
    if (i is TitleItem) out.add(i.draft);
  }
  final sum = await run.done;
  client.close();
  return (out, sum);
}

String _mb(int b) => (b / 1e6).toStringAsFixed(1);

void _report(String label, Run r) {
  final series = r.titles.where((t) => t.isSeries).length;
  print(
    '  API $label: ${r.summary.requests} req, ${_mb(r.bytes)} MB, '
    '${r.seconds.toStringAsFixed(1)} s, ${r.titles.length} titles '
    '($series series, ${r.seasons} seasons), complete=${r.summary.complete}'
    '${r.summary.issues.isEmpty ? '' : ' issues=${r.summary.issues.take(3).toList()}'}'
    '${r.summary.warnings.isEmpty ? '' : ' warnings=${r.summary.warnings.take(2).toList()}'}',
  );
}

Future<CategoryConfig> _smallestBucket(String host, CategoryConfig cat) async {
  final api = H5aiApiClient();
  final root = await api.getFolder(Uri.parse(cat.url));
  api.close();
  final buckets = [
    for (final b in root.folders)
      if (b.isListed && b.children!.any((c) => c.isFolder)) b,
  ]..sort((a, b) => a.children!.length.compareTo(b.children!.length));
  if (buckets.isEmpty) return cat;
  print(
    '  smallest bucket: ${buckets.first.name} '
    '(${buckets.first.children!.length} children)',
  );
  return cat.copyWith(url: 'http://$host${buckets.first.href}');
}

Future<void> _compare(
  String label,
  ServerConfig s,
  CategoryConfig cat, {
  bool seasonsAsSeries = false,
}) async {
  print('\n== compare $label  (${cat.url})');
  final r = await _skeleton(s.host, cat, seasonsAsSeries: seasonsAsSeries);
  _report('skeleton', r);
  final sw = Stopwatch()..start();
  final (html, sum) = await _html(s, cat);
  print(
    '  HTML crawl: ${sum.foldersFetched} req, '
    '${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, '
    '${html.length} titles (${html.where((t) => t.kind == TitleKind.series).length} '
    'series), complete=${sum.complete}',
  );
  final a = {for (final t in r.titles) t.folderUrl: t};
  final b = {for (final t in html) t.folderUrl: t};
  final onlyApi = a.keys.where((k) => !b.containsKey(k)).toList();
  final onlyHtml = b.keys.where((k) => !a.containsKey(k)).toList();
  var fieldDiff = 0;
  for (final k in a.keys.where(b.containsKey)) {
    final x = a[k]!, y = b[k]!;
    if (x.name != y.name ||
        x.year != y.year ||
        x.yearEnd != y.yearEnd ||
        x.quality != y.quality ||
        x.fingerprintAsListing != y.folderMtime ||
        (y.kind != TitleKind.series &&
            x.fileCount != y.files.where((f) => f.playable).length)) {
      fieldDiff++;
      if (fieldDiff <= 3) {
        print(
          '    diff $k: ${x.name}/${y.name} ${x.year}/${y.year} '
          '${x.fingerprintAsListing}/${y.folderMtime}',
        );
      }
    }
  }
  print(
    '  common ${a.keys.where(b.containsKey).length}, only-API ${onlyApi.length}, '
    'only-HTML ${onlyHtml.length}, field diffs $fieldDiff',
  );
  for (final k in onlyApi.take(3)) {
    print('    only-API : ${Uri.decodeFull(k)}');
  }
  for (final k in onlyHtml.take(3)) {
    print('    only-HTML: ${Uri.decodeFull(k)}');
  }
}

Future<void> main(List<String> args) async {
  final noHtml = args.contains('--no-html');
  final only = args.contains('--only')
      ? args[args.indexOf('--only') + 1]
      : null;
  bool want(String n) => only == null || only == n;

  // Probe first (what=0): decides API vs HTML.
  final probeApi = H5aiApiClient();
  for (final h in [
    '172.16.50.7',
    '172.16.50.10',
    '172.16.50.12',
    '172.16.50.14',
  ]) {
    final p = await probeApi.probe(h);
    print(
      'probe $h: ${p.supported ? 'API ok' : 'NO API ${p.reason} ${p.message}'}',
    );
  }
  probeApi.close();

  print('\n=== full API (skeleton) runs ===');
  for (final n in [
    'English Movies',
    '3D Movies',
    'TV & Web Series',
    'Anime & Cartoon',
    'Documentary',
  ]) {
    if (!want(n)) continue;
    final (s, c) = _find(n);
    print('\n$n  [${c.layout.name}]');
    _report('full', await _skeleton(s.host, c));
  }
  if (noHtml) return;

  print('\n=== API vs HTML crawl (same folder) ===');
  if (want('English Movies')) {
    final (s, c) = _find('English Movies');
    await _compare(
      'English Movies / (1996)',
      s,
      c.copyWith(url: '${c.url}%281996%29/', layout: LayoutKind.flat),
    );
  }
  if (want('3D Movies')) {
    final (s, c) = _find('3D Movies');
    await _compare('3D Movies', s, c);
  }
  if (want('TV & Web Series')) {
    final (s, c) = _find('TV & Web Series');
    await _compare('TV smallest bucket', s, await _smallestBucket(s.host, c));
  }
  if (want('Anime & Cartoon')) {
    final (s, c) = _find('Anime & Cartoon');
    await _compare(
      'Anime smallest bucket',
      s,
      await _smallestBucket(s.host, c),
    );
  }
  if (want('Documentary')) {
    final (s, c) = _find('Documentary');
    // The HTML crawler makes every season folder its own "title"; the
    // skeleton (default) makes the show a series. Compare in the exact mode.
    await _compare('Documentary (seasons as titles, exact mode)', s, c);
    exit(0);
  }
}
