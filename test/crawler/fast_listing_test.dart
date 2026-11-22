import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/crawler/fast_listing.dart';
import 'package:watchdog/crawler/listing.dart';

String _row(String alt, String href, String name, String date, String size) =>
    '<tr><td class="fb-i"><img src="/_h5ai/public/images/fallback/$alt.png" '
    'alt="$alt"/></td><td class="fb-n"><a href="$href">$name</a></td>'
    '<td class="fb-d">$date</td><td class="fb-s">$size</td></tr>';

String _page(List<String> rows, {String? head}) =>
    '<!DOCTYPE html><html><body><div id="fallback"><table>'
    '<tr><th class="fb-i"></th><th class="fb-n"><span>Name</span></th>'
    '<th class="fb-d"><span>Last modified</span></th>'
    '<th class="fb-s"><span>Size</span></th></tr>'
    '${head ?? _row('folder-parent', '..', 'Parent Directory', '', '')}'
    '${rows.join()}</table></div></body></html>';

void _same(String body) {
  final slow = parseListing(body);
  final fast = parseListingFast(body);
  expect(fast.length, slow.length);
  for (var i = 0; i < slow.length; i++) {
    expect(fast[i].name, slow[i].name, reason: 'name #$i');
    expect(fast[i].href, slow[i].href, reason: 'href #$i');
    expect(fast[i].isDir, slow[i].isDir, reason: 'isDir #$i');
    expect(fast[i].modified, slow[i].modified, reason: 'modified #$i');
    expect(fast[i].sizeKb, slow[i].sizeKb, reason: 'sizeKb #$i');
  }
}

void main() {
  final files = [
    ...Directory('test/fixtures').listSync().whereType<File>(),
    ...Directory('test/fixtures/crawl').listSync().whereType<File>(),
  ].where((f) => f.path.endsWith('.html')).toList();

  test('fixtures exist', () => expect(files.length, greaterThan(30)));

  for (final f in files) {
    test('identical to html parser: ${f.path}', () {
      final body = f.readAsStringSync();
      expect(
        tryParseListingFast(body),
        isNotNull,
        reason: 'fast path must recognise real pages',
      );
      _same(body);
    });
  }

  test('real 150-row year listing parses on the fast path', () {
    final body = File('test/fixtures/year_listing.html').readAsStringSync();
    final e = parseListingFast(body);
    expect(e.length, 150);
    expect(e.every((x) => x.isDir), isTrue);
  });

  test('entities, odd names, empty and missing fields', () {
    final body = _page([
      _row(
        'folder',
        '/a/Tom%20%26%20Jerry/',
        'Tom &amp; Jerry',
        '2020-01-02 03:04',
        '',
      ),
      _row(
        'file',
        '/a/x%27s.mkv',
        'It&#x27;s &quot;x&quot; &lt;3&gt;.mkv',
        '2020-12-31 23:59',
        '12 KB',
      ),
      _row('file', '/a/b.mkv', '  padded  ', 'garbage', 'NaN'),
      _row('file', '/a/c.mkv', 'no-size', '', ''),
      _row('file', '/a/d.mkv', 'big', '1999-02-03 04:05', '99999999999 KB'),
      _row('file', '/a/e&amp;f.mkv', 'e&amp;f', '2020-13-45 25:61', '5 kb'),
      _row('unknown', '/a/dir-by-href/', 'dir', '2000-01-01 00:00', ''),
      _row('file', '/a/★%20star.mkv', '★ star', '2000-01-01 00:00', '1 KB'),
    ]);
    expect(tryParseListingFast(body), isNotNull);
    _same(body);
    final e = parseListingFast(body);
    expect(e[1].name, 'It\'s "x" <3>.mkv');
    expect(e[5].href, '/a/e&f.mkv');
    expect(e[6].isDir, isTrue);
  });

  test('empty directory (only parent row) -> no entries', () {
    final body = _page([]);
    expect(parseListingFast(body), isEmpty);
    _same(body);
  });

  test('unrecognised structure falls back to the html parser', () {
    // Extra attribute on a td, entity the fast path will not decode, a
    // different row layout and a page without the fallback div.
    final variants = <String>[
      _page([_row('file', '/a/b.mkv', 'b.mkv', '2020-01-01 00:00', '1 KB')])
          .replaceAll('<td class="fb-n"', '<td class="fb-n" title="x"'),
      _page([
        _row('file', '/a/b.mkv', 'caf&eacute;.mkv', '2020-01-01 00:00', '1 KB'),
      ]),
      _page([_row('file', '/a/b.mkv', 'b.mkv', '2020-01-01 00:00', '1 KB')])
          .replaceAll('<tr><td', '<tr class="r"><td'),
      '<html><body><p>502 Bad Gateway</p></body></html>',
    ];
    for (final v in variants) {
      expect(tryParseListingFast(v), isNull);
      _same(v); // still correct through the fallback
    }
    expect(
      parseListingFast(variants[1]).single.name,
      'café.mkv',
    ); // html parser decoded it
  });
}
