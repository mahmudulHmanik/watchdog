// ignore_for_file: avoid_print
// Live smoke crawl of ONE default category (needs BDIX).
// Usage: dart run tool/crawl_smoke.dart "3D Movies"
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/crawler.dart';
import 'package:watchdog/crawler/listing_client.dart';

Future<void> main(List<String> args) async {
  final name = args.isEmpty ? '3D Movies' : args[0];
  final full = CrawlConfig.defaults();
  final servers = [
    for (final s in full.servers)
      s.copyWith(
        categories: [
          for (final c in s.categories)
            if (c.name == name) c,
        ],
      ),
  ].where((s) => s.categories.isNotEmpty).toList();
  if (servers.isEmpty) {
    print('no such default category: $name');
    return;
  }
  final client = HttpListingClient();
  final run = Crawler(client).start(CrawlConfig(servers: servers));
  run.progress.listen(
    (p) => print(
      'folders ${p.foldersFetched} titles ${p.titlesFound} errors ${p.errors}',
    ),
  );
  var shown = 0;
  await for (final i in run.items) {
    if (i is TitleItem && shown++ < 5) {
      final t = i.draft;
      print(
        '${t.kind.name} "${t.name}" ${t.year} q=${t.quality} '
        'files=${t.files.length} seasons=${t.seasons.length} poster=${t.posterUrl != null}',
      );
    }
  }
  final s = await run.done;
  print('complete=${s.complete} ${s.elapsed} ${s.failureMessage ?? ''}');
  for (final r in s.results) {
    print('${r.category.name}: ${r.titles} titles, complete=${r.complete}');
  }
  client.close();
}
