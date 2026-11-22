/// Pure maths behind the VLC-style player gestures (no Flutter imports).
library;

enum TapZone { left, center, right }

/// Which third of a [width]-wide box [x] falls in.
TapZone tapZone(double x, double width) {
  if (width <= 0) return TapZone.center;
  if (x < width / 3) return TapZone.left;
  if (x > width * 2 / 3) return TapZone.right;
  return TapZone.center;
}

/// New 0..1 level (volume / brightness) after a vertical drag of [dy] pixels
/// (down is positive, so dragging up raises the level). Dragging the full
/// [height] of the box sweeps the whole range.
double dragLevel(double start, double dy, double height) {
  if (height <= 0) return start.clamp(0.0, 1.0);
  return (start - dy / height).clamp(0.0, 1.0);
}

/// Seek target after a horizontal drag of [dx] pixels over a [width]-wide
/// box: the full width spans [span]. Clamped to `0..duration` (no upper clamp
/// while [duration] is unknown/zero).
Duration dragSeekTarget(
  Duration start,
  double dx,
  double width,
  Duration duration, {
  Duration span = const Duration(seconds: 90),
}) {
  if (width <= 0) return start;
  final ms = start.inMilliseconds + (dx / width * span.inMilliseconds).round();
  var t = Duration(milliseconds: ms < 0 ? 0 : ms);
  if (duration > Duration.zero && t > duration) t = duration;
  return t;
}

/// `1:05:09` / `5:09`.
String formatClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final base = '${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  return h > 0 ? '$h:$base' : '${d.inMinutes % 60}:${two(d.inSeconds % 60)}';
}

/// Signed offset like `+0:23` / `-1:05`.
String formatDelta(Duration d) =>
    '${d.isNegative ? '-' : '+'}${formatClock(d.abs())}';
