import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'apk_installer.dart';
import 'update_cleanup.dart';
import 'update_prefs.dart';
import 'update_service.dart';

/// Shared by the service (never delete the APK being installed) and the
/// install step in `update_flow.dart`.
final installGuardProvider = Provider<InstallGuard>((ref) {
  final g = InstallGuard();
  ref.onDispose(g.end);
  return g;
});

final updateServiceProvider = Provider<UpdateService>((ref) {
  final s = UpdateService(guard: ref.watch(installGuardProvider));
  ref.onDispose(s.close);
  return s;
});

final apkInstallerProvider = Provider<ApkInstaller>(
  (ref) => const MethodChannelApkInstaller(),
);

/// Where downloaded APKs live (the cache dir; exposed by file_paths.xml).
final updateDirProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory('${(await getTemporaryDirectory()).path}/updates'),
);

/// Whether the app checks for updates by itself shortly after launch. Off by
/// default so tests and the demo never touch the network; `main` turns it on.
final autoUpdateCheckProvider = Provider<bool>((ref) => false);

class _LazyPrefsStore implements UpdatePrefsStore {
  FileUpdatePrefsStore? _s;
  Future<FileUpdatePrefsStore> _get() async => _s ??= FileUpdatePrefsStore(
    File('${(await getApplicationSupportDirectory()).path}/update_prefs.json'),
  );
  @override
  Future<UpdatePrefs> load() async => (await _get()).load();
  @override
  Future<void> save(UpdatePrefs p) async => (await _get()).save(p);
}

final updatePrefsStoreProvider = Provider<UpdatePrefsStore>(
  (ref) => _LazyPrefsStore(),
);

final updatePrefsProvider =
    AsyncNotifierProvider<UpdatePrefsNotifier, UpdatePrefs>(
      UpdatePrefsNotifier.new,
    );

class UpdatePrefsNotifier extends AsyncNotifier<UpdatePrefs> {
  @override
  Future<UpdatePrefs> build() => ref.watch(updatePrefsStoreProvider).load();

  Future<void> _set(UpdatePrefs p) async {
    state = AsyncData(p);
    await ref.read(updatePrefsStoreProvider).save(p);
  }

  Future<void> setAutoCheck(bool on) async =>
      _set((state.value ?? const UpdatePrefs()).copyWith(autoCheck: on));

  Future<void> markChecked(DateTime now) async => _set(
    (state.value ?? const UpdatePrefs()).copyWith(
      lastCheckMs: now.millisecondsSinceEpoch,
    ),
  );
}
