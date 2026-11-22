import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/app.dart';
import 'package:watchdog/features/update/apk_installer.dart';
import 'package:watchdog/features/update/release.dart';
import 'package:watchdog/features/update/update_prefs.dart';
import 'package:watchdog/features/update/update_providers.dart';
import 'package:watchdog/features/update/update_service.dart';

import '../ui/fakes.dart';

class _Service extends UpdateService {
  _Service({this.release, this.error, required this.apk});
  final ReleaseInfo? release;
  final UpdateException? error;
  final File apk;
  int downloads = 0;

  @override
  Future<ReleaseInfo?> check({
    required String currentVersion,
    bool prerelease = true,
  }) async {
    if (error != null) throw error!;
    return release;
  }

  @override
  Future<File> download(
    ReleaseInfo r,
    Directory dir, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    downloads++;
    onProgress?.call(50, 100);
    onProgress?.call(100, 100);
    return apk;
  }
}

class _Installer implements ApkInstaller {
  _Installer({this.supported = true, this.can = true});
  @override
  final bool supported;
  bool can;
  final installed = <String>[];
  var openedSettings = 0;
  @override
  Future<bool> canInstall() async => can;
  @override
  Future<void> openInstallSettings() async => openedSettings++;
  @override
  Future<void> install(String path) async => installed.add(path);
}

class _MemPrefs implements UpdatePrefsStore {
  UpdatePrefs v = const UpdatePrefs();
  @override
  Future<UpdatePrefs> load() async => v;
  @override
  Future<void> save(UpdatePrefs p) async => v = p;
}

const _newer = ReleaseInfo(
  tag: 'v0.2.0',
  version: '0.2.0',
  notes: 'Faster player and gestures',
  pageUrl: 'https://github.com/x/y/releases/tag/v0.2.0',
  apkUrl: 'https://dl/x.apk',
  apkSize: 20 * 1024 * 1024,
);

void main() {
  late Directory tmp;
  late FakePlatform platform;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('uf');
    platform = FakePlatform();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> openSettings(
    WidgetTester tester, {
    required _Service service,
    required _Installer installer,
  }) async {
    useTallView(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testOverrides(FakeRepository(), platform, FakeActions()),
          updateServiceProvider.overrideWithValue(service),
          apkInstallerProvider.overrideWithValue(installer),
          updatePrefsStoreProvider.overrideWithValue(_MemPrefs()),
          updateDirProvider.overrideWithValue(() async => tmp),
        ],
        child: const WatchdogApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-updates')));
    await tester.pumpAndSettle();
  }

  File apk() => File('${tmp.path}/new.apk')..writeAsBytesSync([1, 2, 3]);

  testWidgets('up to date -> toast, no dialog', (tester) async {
    await openSettings(
      tester,
      service: _Service(apk: apk()),
      installer: _Installer(),
    );
    expect(find.textContaining("You're up to date"), findsOneWidget);
    expect(find.textContaining('Update available'), findsNothing);
  });

  testWidgets('update check removes APKs of already installed versions', (
    tester,
  ) async {
    final old = File('${tmp.path}/watchdog-0.1.0-arm64.apk')
      ..writeAsBytesSync([1]);
    final newer = File('${tmp.path}/watchdog-9.0.0-arm64.apk')
      ..writeAsBytesSync([1]);
    await openSettings(
      tester,
      service: _Service(apk: apk()),
      installer: _Installer(),
    );
    expect(old.existsSync(), isFalse);
    expect(newer.existsSync(), isTrue);
  });

  testWidgets('check error is shown', (tester) async {
    await openSettings(
      tester,
      service: _Service(
        error: const UpdateException('No internet'),
        apk: apk(),
      ),
      installer: _Installer(),
    );
    expect(find.text('No internet'), findsOneWidget);
  });

  testWidgets('newer release: notes shown; Later does nothing', (tester) async {
    final svc = _Service(release: _newer, apk: apk());
    final inst = _Installer();
    await openSettings(tester, service: svc, installer: inst);
    expect(find.text('Update available: v0.2.0'), findsOneWidget);
    expect(find.textContaining('Faster player and gestures'), findsOneWidget);
    expect(find.textContaining('20 MB'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(svc.downloads, 0);
    expect(inst.installed, isEmpty);
  });

  testWidgets('Update downloads then starts the installer', (tester) async {
    final file = apk();
    final svc = _Service(release: _newer, apk: file);
    final inst = _Installer();
    await openSettings(tester, service: svc, installer: inst);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(svc.downloads, 1);
    expect(inst.installed, [file.path]);
  });

  testWidgets('installs not allowed -> explains and opens settings', (
    tester,
  ) async {
    final svc = _Service(release: _newer, apk: apk());
    final inst = _Installer(can: false);
    await openSettings(tester, service: svc, installer: inst);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text('Allow installing updates'), findsOneWidget);
    expect(inst.installed, isEmpty);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(inst.openedSettings, 1);
  });

  testWidgets('platform without self-update opens the release page', (
    tester,
  ) async {
    final svc = _Service(release: _newer, apk: apk());
    final inst = _Installer(supported: false);
    await openSettings(tester, service: svc, installer: inst);
    await tester.tap(find.text('Open release page'));
    await tester.pumpAndSettle();
    expect(svc.downloads, 0);
    expect(platform.openedUrls.single.toString(), _newer.pageUrl);
  });
}
