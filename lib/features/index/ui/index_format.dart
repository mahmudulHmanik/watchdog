import 'dart:math' as math;

import 'package:watchdog/features/index/index_service.dart';

/// 18400 -> "18,400".
String fmtCount(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// One-line status for banners: "Indexing 18,400 / ~39,000 titles".
String indexLabel(IndexState s) {
  final n = s.titlesIndexed;
  final est = s.estimatedTotal;
  final verb = s.isFirstRun ? 'Indexing' : 'Updating library';
  return switch (s.phase) {
    IndexPhase.probing => 'Searching the servers…',
    IndexPhase.writing => 'Saving the index…',
    _ =>
      est == null || est <= 0
          ? (n == 0 ? '$verb…' : '$verb ${fmtCount(n)} titles')
          : '$verb ${fmtCount(n)} / ~${fmtCount(math.max(est, n))} titles',
  };
}

/// Bar value: null (indeterminate) while probing or when the total is unknown.
double? indexBarValue(IndexState s) =>
    s.phase == IndexPhase.probing ? null : s.progress;
