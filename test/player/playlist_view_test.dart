import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/player/ui/playlist_view.dart';
import 'package:watchdog/features/series/domain/playlist.dart';
import 'package:watchdog/features/series/domain/playlist_labels.dart';

Widget host(Widget child, ShapeMode shape) => MaterialApp(
  theme: buildTheme(everforest, shape),
  home: Scaffold(body: SizedBox(height: 400, child: child)),
);

Playlist lupin({int index = 0}) {
  var id = 0;
  final seasons = <SeasonEpisodes>[];
  for (var s = 1; s <= 3; s++) {
    final sid = 100 + s;
    seasons.add(
      SeasonEpisodes(
        season: Season(id: sid, titleId: 1, number: s, label: 'Season $s'),
        files: [
          for (var e = 1; e <= 8; e++)
            MediaFile(
              id: ++id,
              titleId: 1,
              seasonId: sid,
              name: 'Lupin S0${s}E0$e.mkv',
              url: 'http://h/$id.mkv',
              ext: 'mkv',
              playable: true,
              episode: e,
            ),
        ],
      ),
    );
  }
  final pl = PlaylistBuilder.forSeason(seasons, 101)!;
  return Playlist(pl.items, index: index, seasons: pl.seasons);
}

void main() {
  for (final shape in ShapeMode.values) {
    group('PlaylistView ($shape)', () {
      testWidgets('shows season headers and picks item indices', (t) async {
        final picked = <int>[];
        final pl = lupin();
        await t.pumpWidget(
          host(
            PlaylistView(
              rows: PlaylistLabels(pl, 'Lupin').rows(),
              index: 0,
              onPick: picked.add,
            ),
            shape,
          ),
        );
        expect(find.text('Season 1'), findsOneWidget);
        expect(pl.length, 24);
        // Header taps do nothing.
        await t.tap(find.text('Season 1'));
        expect(picked, isEmpty);
        await t.tap(find.byKey(const ValueKey('playlist-item-1')));
        expect(picked, [1]);
      });

      testWidgets('current item in a later season is scrolled into view', (
        t,
      ) async {
        final pl = lupin(index: 18); // Season 3, episode 3
        await t.pumpWidget(
          host(
            PlaylistView(
              rows: PlaylistLabels(pl, 'Lupin').rows(),
              index: pl.index,
              onPick: (_) {},
            ),
            shape,
          ),
        );
        await t.pump();
        final cur = find.byKey(const ValueKey('playlist-item-18'));
        expect(cur, findsOneWidget);
        final box = t.getRect(cur);
        final view = t.getRect(find.byType(PlaylistView));
        expect(view.contains(box.center), isTrue);
        expect(find.text('Season 1'), findsNothing);
      });

      testWidgets('first episode of a season is scrolled in with its header', (
        t,
      ) async {
        final pl = lupin(index: 16); // Season 3, episode 1
        await t.pumpWidget(
          host(
            PlaylistView(
              rows: PlaylistLabels(pl, 'Lupin').rows(),
              index: pl.index,
              onPick: (_) {},
            ),
            shape,
          ),
        );
        await t.pump();
        expect(find.text('Season 3'), findsOneWidget);
        expect(find.byKey(const ValueKey('playlist-item-16')), findsOneWidget);
      });

      testWidgets('advancing to next season scrolls and keeps highlight', (
        t,
      ) async {
        Widget build(int i) {
          final pl = lupin(index: i);
          return host(
            PlaylistView(
              rows: PlaylistLabels(pl, 'Lupin').rows(),
              index: i,
              onPick: (_) {},
            ),
            shape,
          );
        }

        await t.pumpWidget(build(0));
        await t.pumpWidget(build(17));
        await t.pumpAndSettle();
        final cur = find.byKey(const ValueKey('playlist-item-17'));
        expect(cur, findsOneWidget);
        expect(
          t.getRect(find.byType(PlaylistView)).contains(t.getRect(cur).center),
          isTrue,
        );
        // Current row shows the play marker.
        expect(
          find.descendant(of: cur, matching: find.byIcon(Icons.play_arrow)),
          findsOneWidget,
        );
      });
    });
  }
}
