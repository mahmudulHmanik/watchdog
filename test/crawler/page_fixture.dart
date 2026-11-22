import 'dart:async';

import 'package:watchdog/crawler/listing_client.dart';

/// One h5ai v0.29 fallback-table page for [entries] (what the listing client
/// returns). `name/` = folder, anything else = file. [hrefBase] is the
/// absolute path of the listed folder, e.g. `/DHAKA-FLIX-7/Show/`.
String h5aiPage(
  String hrefBase,
  List<(String name, {int? kb, String date})> entries,
) {
  final b = StringBuffer(
    '<!DOCTYPE html><html><body><div id="fallback"><table>'
    '<tr><th class="fb-i"></th><th class="fb-n"><span>Name</span></th>'
    '<th class="fb-d"><span>Last modified</span></th>'
    '<th class="fb-s"><span>Size</span></th></tr>'
    '<tr><td class="fb-i"><img src="/p.png" alt="folder-parent"/></td>'
    '<td class="fb-n"><a href="..">Parent Directory</a></td>'
    '<td class="fb-d"></td><td class="fb-s"></td></tr>',
  );
  for (final e in entries) {
    final dir = e.$1.endsWith('/');
    final label = dir ? e.$1.substring(0, e.$1.length - 1) : e.$1;
    final href =
        '$hrefBase${Uri.encodeComponent(label).replaceAll('+', '%20')}'
        '${dir ? '/' : ''}';
    b.write(
      '<tr><td class="fb-i"><img src="/p.png" alt="${dir ? 'folder' : 'file'}"/>'
      '</td><td class="fb-n"><a href="$href">$label</a></td>'
      '<td class="fb-d">${e.date}</td>'
      '<td class="fb-s">${dir || e.kb == null ? '' : '${e.kb} KB'}</td></tr>',
    );
  }
  b.write('</table></div></body></html>');
  return b.toString();
}

/// Entry shorthands.
(String, {int? kb, String date}) f(String name, {int kb = 1000}) =>
    (name, kb: kb, date: '2024-01-02 03:04');
(String, {int? kb, String date}) d(
  String name, {
  String date = '2024-01-02 03:04',
}) => ('$name/', kb: null, date: date);

/// Scripted client: url -> body, with latency, failure queues, request log
/// and an optional gate that holds every request until completed.
class ScriptedClient implements ListingClient {
  ScriptedClient([Map<String, String>? pages]) : pages = pages ?? {};
  final Map<String, String> pages;
  final requests = <String>[];
  final failures = <String, List<FetchException>>{};
  Duration latency = Duration.zero;
  bool down = false;

  /// When set, every request waits for it first.
  Completer<void>? gate;

  @override
  Future<String> fetch(Uri url, {required Duration timeout}) async {
    requests.add(url.toString());
    await gate?.future;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (down) {
      throw FetchException(url, FetchFailure.connect, 'no route to host');
    }
    final q = failures[url.toString()];
    if (q != null && q.isNotEmpty) throw q.removeAt(0);
    final p = pages[url.toString()];
    if (p == null) {
      throw FetchException(url, FetchFailure.http, 'HTTP 404', status: 404);
    }
    return p;
  }

  @override
  void close() {}
}
