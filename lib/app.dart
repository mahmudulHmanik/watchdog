import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_providers.dart';
import 'features/browse/browse_providers.dart';
import 'features/downloads/ui/downloads_screen.dart';
import 'features/home/ui/home_screen.dart';
import 'features/search/ui/search_screen.dart';
import 'features/settings/ui/settings_screen.dart';
import 'features/update/ui/update_flow.dart';
import 'features/update/update_providers.dart';

/// Hook run once after the first frame (used by the debug demo mode).
typedef ReadyHook = void Function(BuildContext context, WidgetRef ref);

class WatchdogApp extends ConsumerWidget {
  const WatchdogApp({super.key, this.onReady});
  final ReadyHook? onReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'watchdog',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(ref.watch(paletteProvider), ref.watch(shapeModeProvider)),
    home: AppShell(onReady: onReady),
  );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.onReady});
  final ReadyHook? onReady;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _screens = [
    HomeScreen(),
    SearchScreen(),
    DownloadsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    if (ref.read(autoUpdateCheckProvider)) {
      // Give startup a moment first; silent unless a newer release exists.
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (mounted) checkForUpdate(context, ref, manual: false);
      });
    }
    final hook = widget.onReady;
    if (hook != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) hook(context, ref);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navIndexProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.tokens.border)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) =>
              ref.read(navIndexProvider.notifier).go(i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              label: 'Downloads',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
