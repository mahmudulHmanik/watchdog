import 'package:media_kit/media_kit.dart';

import 'player_settings.dart';

/// Hardware decoding mode for the VideoController ("auto-safe" = only
/// well-tested hw decoders, software fallback).
const kHwdec = 'auto-safe';

/// mpv `hwdec` value for software decoding.
const kHwdecOff = 'no';

/// mpv `hwdec` value for a [HwdecMode].
String hwdecValue(HwdecMode m) => m == HwdecMode.off ? kHwdecOff : kHwdec;

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
