// ignore_for_file: avoid_print
// Parse cost of an h5ai fallback table: `html` package vs the fast path.
// Usage: dart run tool/measure_parse.dart <listing.html>...
import 'dart:io';

import 'package:watchdog/crawler/fast_listing.dart';
import 'package:watchdog/crawler/listing.dart';

double _ms(String body, int iters, List<Entry> Function(String) f) {
  for (var i = 0; i < 3; i++) {
    f(body);
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iters; i++) {
    f(body);
  }
  return sw.elapsedMicroseconds / iters / 1000;
}

void main(List<String> a) {
  for (final path in a) {
    final body = File(path).readAsStringSync();
    final rows = parseListing(body).length;
    final iters = rows > 500 ? 20 : 300;
    final slow = _ms(body, iters, parseListing);
    final fast = _ms(body, iters, parseListingFast);
    print(
      '$path: $rows rows, ${body.length} chars, '
      'html ${slow.toStringAsFixed(3)} ms, fast ${fast.toStringAsFixed(3)} ms, '
      'x${(slow / fast).toStringAsFixed(1)}',
    );
  }
}
