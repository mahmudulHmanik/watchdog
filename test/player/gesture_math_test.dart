import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/features/player/domain/gesture_math.dart';

void main() {
  test('tap zones are thirds', () {
    expect(tapZone(10, 300), TapZone.left);
    expect(tapZone(150, 300), TapZone.center);
    expect(tapZone(290, 300), TapZone.right);
    expect(tapZone(0, 0), TapZone.center);
  });

  test('dragLevel: up raises, clamps, full height sweeps the range', () {
    expect(dragLevel(0.5, -100, 200), closeTo(1.0, 1e-9));
    expect(dragLevel(0.5, 50, 200), closeTo(0.25, 1e-9));
    expect(dragLevel(0.2, 500, 200), 0);
    expect(dragLevel(0.9, -500, 200), 1);
    expect(dragLevel(0.4, 10, 0), 0.4);
  });

  test('dragSeekTarget spans 90 s over the width and clamps', () {
    const start = Duration(minutes: 10);
    const dur = Duration(minutes: 20);
    expect(
      dragSeekTarget(start, 100, 200, dur),
      start + const Duration(seconds: 45),
    );
    expect(
      dragSeekTarget(start, -200, 200, dur),
      start - const Duration(seconds: 90),
    );
    expect(
      dragSeekTarget(const Duration(seconds: 5), -400, 200, dur),
      Duration.zero,
    );
    expect(
      dragSeekTarget(const Duration(minutes: 19, seconds: 50), 400, 200, dur),
      dur,
    );
    // Unknown duration: no upper clamp.
    expect(
      dragSeekTarget(start, 200, 200, Duration.zero),
      start + const Duration(seconds: 90),
    );
  });

  test('clock formats', () {
    expect(formatClock(const Duration(seconds: 65)), '1:05');
    expect(
      formatClock(const Duration(hours: 1, minutes: 5, seconds: 9)),
      '1:05:09',
    );
    expect(formatDelta(const Duration(seconds: 23)), '+0:23');
    expect(formatDelta(const Duration(seconds: -65)), '-1:05');
  });
}
