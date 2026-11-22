import 'package:media_kit/media_kit.dart';

/// Hardware decoding mode for the VideoController ("auto-safe" = only
/// well-tested hw decoders, software fallback).
const kHwdec = 'auto-safe';

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
