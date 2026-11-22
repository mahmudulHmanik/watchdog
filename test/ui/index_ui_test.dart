import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/index/index_service.dart';

import 'fakes.dart';

/// Scripted index service: tests push [IndexState]s; no crawling, no network.
class FakeIndexService implements IndexService {
  FakeIndexService([this._s = const IndexState()]);
  final _c = StreamController<IndexState>.broadcast();
  IndexState _s;
  final forced = <bool>[];
  var cancels = 0;

  void emit(IndexState s) {
    _s = s;
    _c.add(s);
  }

  @override
  IndexState get state => _s;
  @override
  Stream<IndexState> get states => _c.stream;
  @override
  bool get isRunning => _s.running;
  @override
  Future<IndexResult> ensureIndexed({bool force = false}) async {
    forced.add(force);
    return const IndexResult(
      outcome: IndexOutcome.success,
      elapsed: Duration.zero,
    );
  }

  @override
  void cancel() => cancels++;
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

CategoryProgress cp(
  String name,
  CategoryStatus st, {
  int titles = 0,
  int? est,
  int errors = 0,
  String? lastError,
  bool html = false,
}) => CategoryProgress(
  name: name,
  host: '172.16.50.7',
  url: 'http://172.16.50.7/$name/',
  status: st,
  titles: titles,
  estimatedTotal: est,
  errors: errors,
  lastError: lastError,
  htmlFallback: html,
);

const _cats = [
  CategoryProgress(
    name: 'English Movies',
    host: '172.16.50.7',
    url: 'u1',
    status: CategoryStatus.running,
    titles: 900,
    estimatedTotal: 1800,
  ),
  CategoryProgress(
    name: 'Hindi Movies',
    host: '172.16.50.14',
    url: 'u2',
    status: CategoryStatus.done,
    titles: 4000,
    htmlFallback: true,
  ),
  CategoryProgress(
    name: 'Anime',
    host: '172.16.50.10',
    url: 'u3',
    status: CategoryStatus.failed,
    titles: 10,
    errors: 3,
    lastError: 'timeout',
  ),
];

IndexState running({
  bool first = true,
  bool usable = true,
  int written = 18400,
  int? est = 39000,
  IndexPhase phase = IndexPhase.crawling,
  List<CategoryProgress> cats = _cats,
}) => IndexState(
  phase: phase,
  isFirstRun: first,
  hasUsableData: usable,
  titlesWritten: written,
  estimatedTotal: est,
  categories: cats,
);

const _gap = Duration(milliseconds: 350);

/// A stream event reaches the widgets only once the fake clock moves.
const _tick = Duration(milliseconds: 1);

Future<(FakeIndexService, FakeRepository)> boot(
  WidgetTester tester,
  IndexState initial, {
  FakeRepository? repo,
  Size size = const Size(360, 1600),
  ShapeMode shape = ShapeMode.box,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final svc = FakeIndexService(initial);
  final r = repo ?? FakeRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(r, FakePlatform()),
        initialThemeProvider.overrideWithValue(
          ThemeSettings(shape: shape, followSystem: false),
        ),
        indexServiceProvider.overrideWithValue(svc),
      ],
      child: const WatchdogApp(),
    ),
  );
  await tester.pump(_tick);
  await tester.pump(_gap);
  return (svc, r);
}

Future<void> emit(WidgetTester t, FakeIndexService s, IndexState st) async {
  s.emit(st);
  await t.pump(_tick);
  await t.pump(_gap);
}

/// pumpAndSettle never ends while an indeterminate bar animates.
Future<void> settle(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 400));
}

ProviderContainer containerOf(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(WatchdogApp)));

void main() {
  testWidgets('no data yet: setup state, tabs stay usable, no wall', (
    tester,
  ) async {
    final (svc, _) = await boot(
      tester,
      running(usable: false, written: 0, est: null, phase: IndexPhase.probing),
    );
    expect(find.text('Setting up your library…'), findsOneWidget);
    expect(find.text('Searching the servers'), findsOneWidget);
    expect(find.byKey(const Key('index-banner')), findsNothing);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('setup-progress')),
    );
    expect(bar.value, isNull);
    expect(find.byType(NavigationBar), findsOneWidget);

    await emit(tester, svc, running(usable: false, written: 0, est: null));
    expect(find.textContaining('Reading the catalogue'), findsOneWidget);
    // Other tabs work right away.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Search'),
      ),
    );
    await tester.pump(_tick);
    expect(find.byKey(const Key('search-field')), findsOneWidget);
  });

  testWidgets('first results replace the setup state automatically', (
    tester,
  ) async {
    final (svc, _) = await boot(
      tester,
      running(usable: false, written: 0, est: 100),
    );
    expect(find.text('Setting up your library…'), findsOneWidget);
    await emit(tester, svc, running(usable: true, written: 400, est: 100));
    expect(find.text('Setting up your library…'), findsNothing);
    expect(find.byKey(const Key('index-banner')), findsOneWidget);
    expect(find.textContaining('Titles appear here'), findsOneWidget);
  });

  testWidgets('banner: progress, label, sheet with category rows, cancel', (
    tester,
  ) async {
    final (svc, _) = await boot(tester, running());
    expect(find.text('Indexing 18,400 / ~39,000 titles'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const Key('index-banner')),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(bar.value, closeTo(18400 / 39000, 0.001));

    await tester.tap(find.byKey(const Key('index-banner')));
    await settle(tester);
    expect(find.byKey(const Key('index-sheet-title')), findsOneWidget);
    for (final n in ['English Movies', 'Hindi Movies', 'Anime']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(find.textContaining('HTML fallback'), findsOneWidget);
    expect(find.textContaining('3 errors: timeout'), findsOneWidget);
    expect(find.text('900 / ~1,800'), findsOneWidget);
    await tester.tap(find.byKey(const Key('index-cancel')));
    await tester.pump(_tick);
    expect(svc.cancels, 1);
  });

  testWidgets('unknown total: indeterminate bar, count only', (tester) async {
    await boot(tester, running(est: null, written: 1200));
    expect(find.text('Indexing 1,200 titles'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const Key('index-banner')),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(bar.value, isNull);
  });

  testWidgets('banner hides when done; debounced, never flickers', (
    tester,
  ) async {
    final (svc, _) = await boot(tester, const IndexState(hasUsableData: true));
    expect(find.byKey(const Key('index-banner')), findsNothing);
    // A blip shorter than the debounce never shows.
    svc.emit(running(first: false));
    await tester.pump(_tick);
    await tester.pump(const Duration(milliseconds: 100));
    svc.emit(
      const IndexState(
        phase: IndexPhase.done,
        hasUsableData: true,
        outcome: IndexOutcome.success,
      ),
    );
    await tester.pump(_tick);
    await tester.pump(_gap);
    expect(find.byKey(const Key('index-banner')), findsNothing);
    // A real run shows, then hides after the debounce.
    await emit(tester, svc, running(first: false));
    expect(find.byKey(const Key('index-banner')), findsOneWidget);
    svc.emit(
      const IndexState(
        phase: IndexPhase.done,
        hasUsableData: true,
        outcome: IndexOutcome.success,
      ),
    );
    await tester.pump(_tick);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('index-banner')), findsOneWidget);
    await tester.pump(_gap);
    expect(find.byKey(const Key('index-banner')), findsNothing);
  });

  testWidgets('first run completes: one-time "Library ready" message', (
    tester,
  ) async {
    final repo = FakeRepository(
      titles: [mkTitle(1, 'Alpha'), mkTitle(2, 'Beta')],
    );
    final (svc, _) = await boot(tester, running(), repo: repo);
    await emit(
      tester,
      svc,
      const IndexState(
        phase: IndexPhase.done,
        hasUsableData: true,
        outcome: IndexOutcome.success,
        titlesWritten: 2,
      ),
    );
    await tester.pump(_tick);
    expect(find.text('Library ready · 2 titles'), findsOneWidget);
  });

  testWidgets('later (non-first) runs do not show the ready message', (
    tester,
  ) async {
    final (svc, _) = await boot(tester, running(first: false));
    await emit(
      tester,
      svc,
      const IndexState(
        phase: IndexPhase.done,
        hasUsableData: true,
        outcome: IndexOutcome.success,
      ),
    );
    expect(find.textContaining('Library ready'), findsNothing);
  });

  testWidgets('off BDIX, no data: calm card instead of setup; Retry forces', (
    tester,
  ) async {
    final (svc, _) = await boot(
      tester,
      const IndexState(
        phase: IndexPhase.failed,
        offBdix: true,
        isFirstRun: true,
        outcome: IndexOutcome.offBdix,
      ),
    );
    expect(find.text("Can't reach the DhakaFlix servers."), findsOneWidget);
    expect(find.textContaining('BDIX-peered network'), findsOneWidget);
    expect(find.text('Setting up your library…'), findsNothing);
    await tester.tap(find.byKey(const Key('index-retry')));
    await tester.pump(_tick);
    expect(svc.forced, [true]);
  });

  testWidgets('off BDIX with indexed data: card on Home, titles still shown', (
    tester,
  ) async {
    final (svc, _) = await boot(
      tester,
      const IndexState(
        phase: IndexPhase.failed,
        offBdix: true,
        hasUsableData: true,
        outcome: IndexOutcome.offBdix,
      ),
      repo: FakeRepository(titles: [mkTitle(1, 'Alpha')]),
    );
    expect(find.text("Can't reach the DhakaFlix servers."), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    await tester.tap(find.byKey(const Key('index-retry')));
    await tester.pump(_tick);
    expect(svc.forced, [true]);
  });

  testWidgets('partial run: quiet note with Retry, not blocking', (
    tester,
  ) async {
    final (svc, _) = await boot(
      tester,
      const IndexState(
        phase: IndexPhase.done,
        hasUsableData: true,
        isFirstRun: true,
        outcome: IndexOutcome.partial,
        message: '1 category incomplete.',
      ),
      repo: FakeRepository(titles: [mkTitle(1, 'Alpha')]),
    );
    expect(find.text('Some categories could not be indexed.'), findsOneWidget);
    expect(find.byKey(const Key('index-banner')), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    await tester.tap(find.byKey(const Key('index-retry')));
    await tester.pump(_tick);
    expect(svc.forced, [true]);
  });

  testWidgets('failed first run without data: error card + Try again', (
    tester,
  ) async {
    final (svc, _) = await boot(
      tester,
      const IndexState(
        phase: IndexPhase.failed,
        isFirstRun: true,
        outcome: IndexOutcome.failed,
        message: 'Index failed: boom',
      ),
    );
    expect(find.text("The library couldn't be set up."), findsOneWidget);
    expect(find.text('Index failed: boom'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump(_tick);
    expect(svc.forced, [true]);
  });

  testWidgets('empty library after a finished run offers Index now', (
    tester,
  ) async {
    final (svc, _) = await boot(
      tester,
      const IndexState(phase: IndexPhase.done, outcome: IndexOutcome.success),
    );
    await tester.tap(find.byKey(const Key('index-now')));
    await tester.pump(_tick);
    expect(svc.forced, [true]);
  });

  testWidgets('Search: still-indexing note only during a first-run index', (
    tester,
  ) async {
    final (svc, _) = await boot(tester, running());
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Search'),
      ),
    );
    await tester.pump(_gap);
    expect(
      find.text('Still indexing: more titles will appear.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('index-banner')), findsOneWidget);
    await emit(tester, svc, running(first: false));
    expect(find.byKey(const Key('still-indexing')), findsNothing);
    await emit(
      tester,
      svc,
      const IndexState(
        phase: IndexPhase.done,
        hasUsableData: true,
        outcome: IndexOutcome.success,
      ),
    );
    expect(find.byKey(const Key('index-banner')), findsNothing);
  });

  for (final shape in ShapeMode.values) {
    testWidgets('360 px, ${shape.name}: no overflow in any index state', (
      tester,
    ) async {
      final (svc, _) = await boot(
        tester,
        running(usable: false, written: 0, est: null),
        size: const Size(360, 640),
        shape: shape,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('setup-details')));
      await settle(tester);
      expect(find.byKey(const Key('index-sheet-title')), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester);

      await emit(tester, svc, running());
      await tester.tap(find.byKey(const Key('index-banner')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(180, 20));
      await settle(tester);

      await emit(
        tester,
        svc,
        const IndexState(
          phase: IndexPhase.failed,
          offBdix: true,
          hasUsableData: true,
          outcome: IndexOutcome.offBdix,
        ),
      );
      expect(find.byKey(const Key('index-offline')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wide window renders banner, card and sheet', (tester) async {
    final (svc, _) = await boot(tester, running(), size: const Size(1400, 900));
    await tester.tap(find.byKey(const Key('index-banner')));
    await settle(tester);
    expect(find.byKey(const Key('index-sheet-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
    svc.emit(running(usable: false, written: 0));
  });
}
