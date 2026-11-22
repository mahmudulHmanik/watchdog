import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/features/player/domain/subtitle_style.dart';
import 'package:watchdog/features/player/domain/track_prefs.dart';
import 'package:watchdog/features/player/ui/track_sheet.dart';

// Dual-audio sample as returned by real libmpv 0.41 for the Alice MKV.
const tracks = Tracks(
  video: [
    VideoTrack('auto', null, null),
    VideoTrack('no', null, null),
    VideoTrack('1', 'mkvCinemas', null, codec: 'h264', w: 1280, h: 720),
  ],
  audio: [
    AudioTrack('auto', null, null),
    AudioTrack('no', null, null),
    AudioTrack('1', 'mkvCinemas', 'hi', codec: 'aac', channels: 'stereo'),
    AudioTrack('2', 'mkvCinemas', 'en', codec: 'eac3', channels: 'unknown6'),
  ],
  subtitle: [
    SubtitleTrack('auto', null, null),
    SubtitleTrack('no', null, null),
    SubtitleTrack('1', null, 'en', codec: 'subrip'),
    SubtitleTrack('2', 'SDH', 'en', codec: 'subrip'),
  ],
);

Widget host(Widget child, {ShapeMode shape = ShapeMode.box}) => MaterialApp(
  theme: buildTheme(everforest, shape),
  home: Scaffold(body: child),
);

TrackSheetView view({Track? sel, Tracks t = tracks, List<String>? log}) =>
    TrackSheetView(
      tracks: t,
      selected: sel ?? const Track(),
      onAudio: (a) => log?.add('a${a.id}'),
      onSubtitle: (s) => log?.add('s${s.id}'),
      onVideo: (v) => log?.add('v${v.id}'),
      onLoadFile: () => log?.add('file'),
      onLoadUrl: (u) async => log?.add('url:$u'),
      onStyle: () => log?.add('style'),
    );

void main() {
  testWidgets('groups, rows and right-aligned meta', (tester) async {
    await tester.pumpWidget(host(view()));
    expect(find.text('AUDIO'), findsOneWidget);
    expect(find.text('SUBTITLES'), findsOneWidget);
    expect(find.text('VIDEO'), findsNothing); // one video track only
    expect(find.text('Hindi'), findsOneWidget);
    expect(find.text('English'), findsNWidgets(2)); // audio + plain sub
    expect(find.text('AAC 2.0'), findsOneWidget);
    expect(find.text('E-AC3 5.1'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('SRT'), findsNWidgets(2));
    expect(find.text('English (SDH)'), findsOneWidget);
    // Meta sits right of the name.
    expect(
      tester.getTopLeft(find.text('AAC 2.0')).dx,
      greaterThan(tester.getTopLeft(find.text('Hindi')).dx + 100),
    );
    expect(tester.getSize(find.byType(TrackRow).first).height, 48);
  });

  testWidgets('auto selection resolves to first audio and Off subs', (
    tester,
  ) async {
    await tester.pumpWidget(host(view()));
    // Track() defaults to auto/auto/auto; mpv would have picked audio 1.
    expect(find.byKey(const ValueKey('radio-on')), findsNWidgets(2));
    final onRows = find.ancestor(
      of: find.byKey(const ValueKey('radio-on')),
      matching: find.byType(TrackRow),
    );
    final names = [for (final w in tester.widgetList<TrackRow>(onRows)) w.name];
    expect(names, ['Hindi', 'Off']);
  });

  testWidgets('explicit selection and taps', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      host(
        view(
          sel: Track(
            audio: tracks.audio[3],
            subtitle: tracks.subtitle[3],
            video: tracks.video[2],
          ),
          log: log,
        ),
      ),
    );
    final on = tester.widgetList<TrackRow>(
      find.ancestor(
        of: find.byKey(const ValueKey('radio-on')),
        matching: find.byType(TrackRow),
      ),
    );
    expect([for (final r in on) r.name], ['English', 'English (SDH)']);
    await tester.tap(find.text('Hindi'));
    await tester.tap(find.text('Off'));
    await tester.tap(find.text('Load .srt file'));
    await tester.tap(find.text('Subtitle style'));
    expect(log, ['a1', 'sno', 'file', 'style']);
  });

  testWidgets('video group appears with more than one track', (tester) async {
    const t = Tracks(
      video: [
        VideoTrack('1', null, null, codec: 'hevc', w: 1920, h: 1080),
        VideoTrack('2', null, null, codec: 'h264', w: 1280, h: 720),
      ],
    );
    await tester.pumpWidget(host(view(t: t)));
    expect(find.text('VIDEO'), findsOneWidget);
    expect(find.text('HEVC 1920x1080'), findsOneWidget);
  });

  testWidgets('From URL dialog calls onLoadUrl', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(everforest, ShapeMode.box),
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: c,
              isScrollControlled: true,
              builder: (_) => view(log: log),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('From URL...'));
    await tester.tap(find.text('From URL...'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'http://x/a.srt');
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    expect(log, ['url:http://x/a.srt']);
  });

  testWidgets('radio is square in Box, round in Rounded', (tester) async {
    for (final (mode, shape) in [
      (ShapeMode.box, BoxShape.rectangle),
      (ShapeMode.rounded, BoxShape.circle),
    ]) {
      await tester.pumpWidget(host(view(), shape: mode));
      await tester.pumpAndSettle();
      final c = tester.widget<Container>(
        find.byKey(const ValueKey('radio-on')).first,
      );
      expect((c.decoration! as BoxDecoration).shape, shape);
    }
  });

  testWidgets('selected row: Box has 3px accent left edge, Rounded none', (
    tester,
  ) async {
    BoxDecoration deco() =>
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.ancestor(
                          of: find.byKey(const ValueKey('radio-on')).first,
                          matching: find.byType(TrackRow),
                        ),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    await tester.pumpWidget(host(view()));
    expect((deco().border! as Border).left.width, 3);
    expect(deco().color, everforest.highlight);
    await tester.pumpWidget(host(view(), shape: ShapeMode.rounded));
    await tester.pumpAndSettle();
    expect(deco().border, isNull);
  });

  testWidgets('global sheet theme applies: Rounded shows drag handle', (
    tester,
  ) async {
    for (final (mode, handle) in [
      (ShapeMode.box, false),
      (ShapeMode.rounded, true),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(everforest, mode),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: c,
                builder: (_) => const SizedBox(height: 100),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString().contains('DragHandle'),
        ),
        handle ? findsOneWidget : findsNothing,
      );
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('style sheet applies changes live', (tester) async {
    final got = <SubtitleStyle>[];
    await tester.pumpWidget(
      host(
        SubtitleStyleView(initial: const SubtitleStyle(), onChanged: got.add),
      ),
    );
    await tester.tap(find.text('120%'));
    await tester.tap(find.text('Yellow'));
    await tester.tap(find.text('Background box'));
    expect(got.last, const SubtitleStyle(scale: 1.2, yellow: true, box: false));
  });

  test('SubtitleStyle mpv props + json', () {
    const s = SubtitleStyle(scale: 1.5, pos: 90, yellow: true, box: false);
    final p = s.mpvProps();
    expect(p['sub-scale'], '1.5');
    expect(p['sub-pos'], '90');
    expect(p['sub-color'], '#FFFFFF00');
    expect(p['sub-border-style'], 'outline-and-shadow');
    expect(SubtitleStyle.fromJson(s.toJson()), s);
    expect(SubtitleStyle.fromJson('junk'), const SubtitleStyle());
  });

  test('effectiveTrackId: media_kit reports auto even when mpv chose', () {
    final real = [('1', false), ('2', true)];
    expect(effectiveTrackId(real, 'auto', autoPicksFirst: true), '2');
    expect(effectiveTrackId([('1', null)], 'auto', autoPicksFirst: true), '1');
    expect(
      effectiveTrackId([('1', null)], 'auto', autoPicksFirst: false),
      isNull,
    );
    expect(effectiveTrackId(real, 'no', autoPicksFirst: true), isNull);
    expect(effectiveTrackId(real, '1', autoPicksFirst: true), '1');
  });
}
