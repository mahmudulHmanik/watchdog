import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';

/// Opens [url] in the default browser. Android: ACTION_VIEW intent;
/// Linux: `xdg-open`. Throws when it cannot (caller falls back to copying).
Future<void> openUrlDefault(Uri url) async {
  if (url.scheme != 'http' && url.scheme != 'https') {
    throw ArgumentError('Only http(s) URLs: $url');
  }
  if (Platform.isAndroid) {
    await AndroidIntent(action: 'action_view', data: url.toString()).launch();
  } else if (Platform.isLinux) {
    await Process.start('xdg-open', [
      url.toString(),
    ], mode: ProcessStartMode.detached);
  } else {
    throw UnsupportedError('Cannot open URLs on this OS');
  }
}
