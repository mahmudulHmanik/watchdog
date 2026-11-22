import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// From the Settings home: open a group page (`appearance`, `playback`,
/// `library`, `tmdb`, `updates`, `about`).
Future<void> openGroup(WidgetTester t, String group) async {
  await t.tap(find.byKey(Key('settings-$group')));
  await t.pumpAndSettle();
}

/// Back from a group page to the Settings home.
Future<void> goBack(WidgetTester t) async {
  await t.tap(find.byType(BackButton));
  await t.pumpAndSettle();
}
