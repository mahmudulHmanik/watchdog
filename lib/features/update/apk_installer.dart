import 'dart:io';

import 'package:flutter/services.dart';

/// Hands a downloaded APK to Android's package installer.
abstract class ApkInstaller {
  /// False on platforms that cannot self-update (anything but Android).
  bool get supported;

  /// Whether this app may start package installs (Android 8+ per-app switch).
  Future<bool> canInstall();

  /// Opens the system screen where the user allows installs from watchdog.
  Future<void> openInstallSettings();

  /// Opens the installer for the APK at [path].
  Future<void> install(String path);
}

/// Talks to `MainActivity.kt` (channel `dev.watchdog/installer`).
class MethodChannelApkInstaller implements ApkInstaller {
  const MethodChannelApkInstaller();
  static const _ch = MethodChannel('dev.watchdog/installer');

  @override
  bool get supported => Platform.isAndroid;

  @override
  Future<bool> canInstall() async =>
      supported && (await _ch.invokeMethod<bool>('canInstall') ?? false);

  @override
  Future<void> openInstallSettings() => _ch.invokeMethod('openSettings');

  @override
  Future<void> install(String path) =>
      _ch.invokeMethod('install', {'path': path});
}
