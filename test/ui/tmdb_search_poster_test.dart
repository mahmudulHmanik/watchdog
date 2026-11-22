import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/ui/app_image.dart';
import 'package:watchdog/features/browse/ui/title_tile.dart';

MediaTitle title({String? poster, String? tmdb}) => MediaTitle(
  id: 1,
  categoryId: 1,
  name: 'Dune',
  kind: TitleKind.movie,
  folderUrl: 'http://h/1/',
  posterUrl: poster,
  tmdbPosterPath: tmdb,
  addedAt: DateTime(2020),
);

void main() {
  test('server poster wins, TMDB is the fallback, else null', () {
    expect(
      title(poster: 'http://h/1/p.jpg', tmdb: '/x.jpg').bestPosterUrl,
      'http://h/1/p.jpg',
    );
    expect(
      title(tmdb: '/x.jpg').bestPosterUrl,
      'https://image.tmdb.org/t/p/w185/x.jpg',
    );
    expect(title().bestPosterUrl, isNull);
  });

  String? shownUrl(WidgetTester t) {
    final imgs = t.widgetList<AppImage>(find.byType(AppImage)).toList();
    return imgs.isEmpty ? null : imgs.first.url;
  }

  for (final (name, poster, tmdb, want) in [
    (
      'uses TMDB poster when server poster is null',
      null,
      '/x.jpg',
      'https://image.tmdb.org/t/p/w185/x.jpg',
    ),
    ('prefers server poster', 'http://h/1/p.jpg', '/x.jpg', 'http://h/1/p.jpg'),
    ('placeholder when neither', null, null, null),
  ]) {
    testWidgets('TitleTile $name', (t) async {
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildTheme(everforest, ShapeMode.box),
            home: Scaffold(
              body: TitleTile(title(poster: poster, tmdb: tmdb)),
            ),
          ),
        ),
      );
      expect(shownUrl(t), want);
    });
  }
}
