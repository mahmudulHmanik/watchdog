import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'player_settings.dart';

/// Hardware decoding for Android: mpv's "auto-safe" list (well-tested hw
/// decoders, software fallback).
const kHwdecAutoSafe = 'auto-safe';

/// Kept for callers that want the portable default.
const kHwdec = kHwdecAutoSafe;

/// mpv `hwdec` value for software decoding.
const kHwdecOff = 'no';

/// mpv `hwdec` value for a [HwdecMode]. Diagnostic override for "auto":
/// environment variable `WATCHDOG_HWDEC` (e.g. `auto-safe`, `vaapi`, `no`).
///
/// Linux note (2026-11-23): `mpv` on the command line also tries Vulkan decoding under
/// "auto-safe", which fails on Intel Haswell and logs `Error parsing NAL unit`; inside the app
/// (libmpv render API) that attempt is not made, and measured playback is identical with or without
/// a VA-API/NVDEC-only list, so "auto-safe" stays everywhere.
String hwdecValue(HwdecMode m, {String? override}) {
  if (m == HwdecMode.off) return kHwdecOff;
  final o = override ?? Platform.environment['WATCHDOG_HWDEC'];
  if (o != null && o.trim().isNotEmpty) return o.trim();
  return kHwdecAutoSafe;
}

/// Opt-in diagnostics: with `WATCHDOG_MPV_STATS=1` prints mpv's own counters
/// (decoder in use, dropped frames, fps, A/V sync) to stderr every 2 seconds.
Timer? startMpvStatsLog(Player player, {Map<String, String>? env}) {
  if ((env ?? Platform.environment)['WATCHDOG_MPV_STATS'] != '1') return null;
  final p = player.platform;
  if (p is! NativePlayer) return null;
  const props = [
    'hwdec-current',
    'video-params/pixelformat',
    'container-fps',
    'estimated-vf-fps',
    'vo-drop-frame-count',
    'decoder-frame-drop-count',
    'avsync',
  ];
  return Timer.periodic(const Duration(seconds: 2), (_) async {
    final out = <String>[];
    for (final k in props) {
      try {
        out.add('$k=${await p.getProperty(k)}');
      } catch (_) {
        out.add('$k=?');
      }
    }
    stderr.writeln('[mpv-stats] ${out.join(' ')}');
  });
}

/// Set mpv's `hwdec` at runtime (takes effect when the decoder is next
/// initialised, i.e. on the next open). Returns false when it could not be
/// applied (not a native player, or the property call failed).
Future<bool> setHwdec(Player player, String value) async {
  final p = player.platform;
  if (p is! NativePlayer) return false;
  try {
    await p.setProperty('hwdec', value);
    return true;
  } catch (_) {
    return false;
  }
}

/// Demuxer cache size: 32 MiB on Android (RAM), 64 MiB elsewhere.
int bufferBytes({required bool android}) => (android ? 32 : 64) << 20;

/// mpv options for LAN/BDIX HTTP streams: fail fast when the server is
/// unreachable (default network-timeout is 60 s), read ahead ~60 s, and let
/// ffmpeg reconnect dropped connections. Best effort: a failing property is
/// ignored so a libmpv without one of them still plays.
Future<void> applyStreamTuning(Player player) async {
  final p = player.platform;
  if (p is! NativePlayer) return;
  const props = {
    'network-timeout': '15',
    'cache': 'yes',
    'cache-secs': '60',
    'demuxer-readahead-secs': '60',
    'stream-lavf-o':
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
        'reconnect_delay_max=5',
  };
  for (final e in props.entries) {
    try {
      await p.setProperty(e.key, e.value);
    } catch (_) {}
  }
}
