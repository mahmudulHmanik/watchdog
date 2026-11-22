import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/skeleton_probe.dart';
import 'package:watchdog/data/models.dart';

ApiItem folder(String href, {int t = 1, List<ApiItem>? kids}) => ApiItem(
  name: Uri.decodeComponent(href.split('/').where((s) => s.isNotEmpty).last),
  href: href,
  isFolder: true,
  time: DateTime.fromMillisecondsSinceEpoch(t * 60000, isUtc: true),
  children: kids,
);
ApiItem file(String href, {int t = 1, int size = 5}) => ApiItem(
  name: href.split('/').last,
  href: href,
  isFolder: false,
  time: DateTime.fromMillisecondsSinceEpoch(t * 60000, isUtc: true),
  size: size,
);

CategoryConfig cat(LayoutKind l) => CategoryConfig(
  name: 'C',
  url: 'http://h/C/',
  layout: l,
  kind: TitleKind.movie,
);

ApiItem root(List<ApiItem> kids) => folder('/C/', kids: kids);

void main() {
  ApiItem bucket(String y, List<(String, int)> titles) => folder(
    '/C/$y/',
    kids: [for (final (n, t) in titles) folder('/C/$y/$n/', t: t)],
  );

  test('signature changes with a title time, name, or an added title', () {
    final a = groupSignature(bucket('(2020)', [('A', 1), ('B', 2)]));
    expect(groupSignature(bucket('(2020)', [('B', 2), ('A', 1)])), a);
    expect(groupSignature(bucket('(2020)', [('A', 1), ('B', 3)])), isNot(a));
    expect(groupSignature(bucket('(2020)', [('A', 1), ('C', 2)])), isNot(a));
    expect(groupSignature(bucket('(2020)', [('A', 1)])), isNot(a));
    expect(a, lessThan(1 << 52));
    expect(a, greaterThanOrEqualTo(0));
  });

  test('extras folders are ignored by the signature', () {
    final a = bucket('(2020)', [('A', 1)]);
    final b = folder(
      '/C/(2020)/',
      kids: [folder('/C/(2020)/A/', t: 1), folder('/C/(2020)/Sample/', t: 99)],
    );
    expect(groupSignature(b), groupSignature(a));
  });

  test('probe: signatures per child folder + estimate (year buckets)', () {
    final r = root([
      bucket('(2020)', [('A', 1), ('B', 1)]),
      bucket('(2021)', [('C', 1)]),
      folder('/C/Sample/', kids: []),
    ]);
    final p = probeFromRoot(r, cat(LayoutKind.yearBuckets));
    expect(p.signatures.keys, ['/C/(2020)/', '/C/(2021)/']);
    expect(p.estimatedTitles, 3);
    expect(p.folders, 2);
    final r2 = root([
      bucket('(2020)', [('A', 1), ('B', 9)]),
      bucket('(2021)', [('C', 1)]),
    ]);
    final p2 = probeFromRoot(r2, cat(LayoutKind.yearBuckets));
    expect(p2.signatures['/C/(2021)/'], p.signatures['/C/(2021)/']);
    expect(p2.signatures['/C/(2020)/'], isNot(p.signatures['/C/(2020)/']));
  });

  test('estimate: flat counts folders, series counts shows not buckets', () {
    final flat = root([
      folder('/C/A/', kids: [file('/C/A/a.mkv')]),
      folder('/C/B/', kids: [file('/C/B/b.mkv')]),
    ]);
    expect(estimateTitles(flat, cat(LayoutKind.flat)), 2);
    final series = root([
      folder(
        '/C/A-F/',
        kids: [folder('/C/A-F/Show1/'), folder('/C/A-F/Show2/')],
      ),
      folder(
        '/C/Direct/',
        kids: [
          folder('/C/Direct/Season%201/'),
          folder('/C/Direct/Season%202/'),
        ],
      ),
    ]);
    expect(estimateTitles(series, cat(LayoutKind.series)), 3);
    // Unlisted children count as one title each.
    expect(
      estimateTitles(
        root([folder('/C/X/'), folder('/C/Y/')]),
        cat(LayoutKind.events),
      ),
      2,
    );
    expect(usesGroupSignatures(cat(LayoutKind.yearBuckets)), isTrue);
    expect(usesGroupSignatures(cat(LayoutKind.events)), isTrue);
    expect(usesGroupSignatures(cat(LayoutKind.flat)), isFalse);
    expect(usesGroupSignatures(cat(LayoutKind.series)), isFalse);
  });
}
