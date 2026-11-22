import 'dart:io';

import 'package:flutter/services.dart';

/// Android system media volume (`STREAM_MUSIC`), the level the hardware
/// volume keys change. Talks to `MainActivity.kt` (channel `dev.watchdog/audio`).
/// Not supported elsewhere: callers fall back to the player's own volume.
class SystemVolume {
  const SystemVolume();

  static const _ch = MethodChannel('dev.watchdog/audio');

  bool get supported => Platform.isAndroid;

  /// Current volume, 0..1.
  Future<double> get() async =>
      (await _ch.invokeMethod<double>('getVolume')) ?? 0.5;

  /// Sets the volume (0..1) and returns the level Android actually applied
  /// (it is quantised to the device's volume steps).
  Future<double> set(double level) async =>
      (await _ch.invokeMethod<double>('setVolume', {'level': level})) ?? level;
}
