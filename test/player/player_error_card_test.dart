import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/features/player/ui/player_error_card.dart';

Widget host(PlayerErrorCard c) => MaterialApp(home: Scaffold(body: c));

void main() {
  testWidgets('decoder failure: external player, no countdown / cancel', (
    t,
  ) async {
    var ext = 0;
    await t.pumpWidget(
      host(
        PlayerErrorCard(
          message: "This phone can't decode this video format.\nraw",
          decoderFailure: true,
          hasNext: true,
          // a stale countdown must not be shown for decoder failures
          countdown: 2,
          countdownLabel: 'Skipping to next file',
          onRetry: () {},
          onClose: () {},
          onSkip: () {},
          onExternal: () => ext++,
        ),
      ),
    );
    expect(find.textContaining("can't decode this video format"), findsOne);
    expect(find.text('Open in external player'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.textContaining('Skipping to next file in'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    await t.tap(find.byKey(const Key('error-external')));
    expect(ext, 1);
  });

  testWidgets('other errors keep Retry/Cancel/Skip/Close + countdown', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        PlayerErrorCard(
          message: "Can't open this file.",
          hasNext: true,
          countdown: 2,
          countdownLabel: 'Skipping to next file',
          onRetry: () {},
          onClose: () {},
          onCancel: () {},
          onSkip: () {},
          onExternal: () {},
        ),
      ),
    );
    expect(find.text('Skipping to next file in 2s'), findsOneWidget);
    for (final b in ['Retry', 'Cancel', 'Skip', 'Close']) {
      expect(find.text(b), findsOneWidget, reason: b);
    }
    expect(find.text('Open in external player'), findsNothing);
  });
}
