import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/image_store.dart';
import 'package:watchdog/features/browse/ui/app_image.dart';
import 'package:watchdog/features/browse/ui/title_tile.dart';

// 1x1 PNG.
final _png = List<int>.unmodifiable(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

const _url = 'http://172.16.50.7/Movies/Dune/poster.jpg';

void main() {
  late Directory dir;
  late int hits;
  var offline = true;

  ImageStore store() => ImageStore(
    dir: () async => dir,
    client: MockClient((req) async {
      hits++;
      if (offline) throw const SocketException('offline');
      return http.Response.bytes(
        _png,
        200,
        headers: {'content-type': 'image/png'},
      );
    }),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('appimg');
    hits = 0;
    offline = true;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Widget host(ImageStore s, Widget child, {ShapeMode shape = ShapeMode.box}) =>
      ProviderScope(
        overrides: [imageStoreProvider.overrideWithValue(s)],
        child: MaterialApp(
          theme: buildTheme(everforest, shape),
          home: Scaffold(body: child),
        ),
      );

  const fb = Text('fallback');

  testWidgets('cached image shows from disk without any network call', (
    t,
  ) async {
    final s = store();
    await t.runAsync(() async {
      await s.init();
      s.fileFor(_url)!.writeAsBytesSync(_png);
    });
    await t.pumpWidget(host(s, const AppImage(_url, fallback: fb)));
    final img = t.widget<Image>(find.byType(Image));
    expect(img.image, isA<FileImage>());
    expect(find.text('fallback'), findsNothing);
    expect(hits, 0);
  });

  testWidgets('offline and uncached: placeholder, no exception', (t) async {
    final s = store();
    await t.pumpWidget(host(s, const AppImage(_url, fallback: fb)));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
    expect(find.text('fallback'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(t.takeException(), isNull);
    expect(hits, 1);
  });

  testWidgets('miss downloads into the cache then renders it', (t) async {
    offline = false;
    final s = store();
    await t.pumpWidget(host(s, const AppImage(_url, fallback: fb)));
    for (var i = 0; i < 40 && find.byType(Image).evaluate().isEmpty; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump();
    }
    expect(find.byType(Image), findsOneWidget);
    expect(dir.listSync().length, 1, reason: 'stored in the disk cache');
    // Second widget: served from disk, still one download.
    await t.pumpWidget(host(s, const AppImage('$_url?x=1', fallback: fb)));
    await t.pumpWidget(host(s, const AppImage(_url, fallback: fb)));
    expect(find.byType(Image), findsOneWidget);
    expect(hits, 2); // the ?x=1 variant is a different url
  });

  testWidgets('Poster uses the cache and keeps its icon fallback offline', (
    t,
  ) async {
    final s = store();
    await t.pumpWidget(host(s, const Poster(_url)));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byType(AppImage), findsOneWidget);
  });

  for (final shape in ShapeMode.values) {
    testWidgets('TitleTile at 360 px, $shape: no overflow', (t) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final title = MediaTitle(
        id: 1,
        categoryId: 1,
        name: 'A very long movie title that must wrap or ellipsize properly',
        kind: TitleKind.movie,
        folderUrl: 'http://h/1/',
        posterUrl: _url,
        addedAt: DateTime(2020),
      );
      await t.pumpWidget(host(store(), TitleTile(title), shape: shape));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }
}
