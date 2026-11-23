import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Developer self-test for the video output path, no UI interaction needed:
///
///   WATCHDOG_SELFTEST_VIDEO=1 watchdog
///
/// Opens a window for a moment, creates a Player + VideoController (media_kit prints which render
/// path it got: "H/W rendering..." or "S/W rendering." to stderr), plays a generated test pattern
/// for a few seconds and exits. Returns true when it ran (the app must not start normally).
Future<bool> runVideoSelfTestIfRequested() async {
  if (Platform.environment['WATCHDOG_SELFTEST_VIDEO'] != '1') return false;
  void log(String m) => stderr.writeln('[selftest] $m');
  // Hard stop so a hang can never leave a window open.
  Timer(const Duration(seconds: 20), () {
    log('timeout, exiting');
    exit(3);
  });
  runApp(const SizedBox.shrink()); // a window/view must exist for the texture
  log('app started');
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final player = Player();
  log('player created');
  VideoController(player);
  log('video controller created');
  unawaited(player.open(Media('av://lavfi:testsrc=size=1280x720:rate=24')));
  await Future<void>.delayed(const Duration(seconds: 5));
  log(
    'playing=${player.state.playing} '
    'size=${player.state.width}x${player.state.height} '
    'position=${player.state.position.inMilliseconds}ms',
  );
  log('done');
  exit(0);
}
