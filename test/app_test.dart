import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';

import 'ui/fakes.dart';

int _stackIndex(WidgetTester t) =>
    t.widget<IndexedStack>(find.byType(IndexedStack)).index!;

void main() {
  testWidgets('nav switches tabs and keeps tab state alive', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(FakeRepository(), FakePlatform()),
        child: const WatchdogApp(),
      ),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(_stackIndex(tester), 0);

    final nav = find.byType(NavigationBar);
    await tester.tap(find.descendant(of: nav, matching: find.text('Search')));
    await tester.pump();
    expect(_stackIndex(tester), 1);
    expect(find.byKey(const Key('search-screen')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search-field')), 'dune');
    await tester.pump();

    await tester.tap(find.descendant(of: nav, matching: find.text('Settings')));
    await tester.pump();
    expect(_stackIndex(tester), 3);

    await tester.tap(find.descendant(of: nav, matching: find.text('Search')));
    await tester.pump();
    expect(_stackIndex(tester), 1);
    expect(find.text('dune'), findsOneWidget);
  });
}
