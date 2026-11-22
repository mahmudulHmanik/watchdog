import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/features/player/domain/gesture_math.dart';
import 'package:watchdog/features/player/player_session.dart';
import 'package:watchdog/platform/system_volume.dart';

/// VLC-style gestures over the video:
/// - drag up/down on the left half: brightness (Android)
/// - drag up/down on the right half: volume
/// - drag left/right: seek, applied on release
/// - double-tap left / right third: -10 s / +10 s; centre: play/pause
/// - hold: 2x speed while held
/// - single tap: [onTap] (show/hide controls)
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    super.key,
    required this.session,
    required this.onTap,
    this.onActivity,
  });
  final PlayerSession session;
  final VoidCallback onTap;

  /// Called on any gesture so the owner can keep the controls alive.
  final VoidCallback? onActivity;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

enum _Drag { none, level, seek }

class _Hud {
  const _Hud(this.icon, this.text, {this.level});
  final IconData icon;
  final String text;

  /// 0..1 bar under the text; null for text-only HUDs.
  final double? level;
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  final _hud = ValueNotifier<_Hud?>(null);
  Timer? _hudTimer;
  Size _size = Size.zero;

  Offset _tapAt = Offset.zero;

  _Drag _drag = _Drag.none;
  bool _leftSide = false;
  double _level = 0;
  double _dx = 0;
  double _dy = 0;
  Duration _seekFrom = Duration.zero;
  Duration _seekTo = Duration.zero;

  bool _brightnessTouched = false;
  double _rateBefore = 1;
  bool _holding = false;

  bool get _hasBrightness => Platform.isAndroid;

  static const _sysVolume = SystemVolume();

  void _show(_Hud h, {Duration hold = const Duration(milliseconds: 800)}) {
    _hud.value = h;
    _hudTimer?.cancel();
    _hudTimer = Timer(hold, () => _hud.value = null);
  }

  void _pin(_Hud h) {
    _hudTimer?.cancel();
    _hud.value = h;
  }

  void _clearSoon() {
    _hudTimer?.cancel();
    _hudTimer = Timer(
      const Duration(milliseconds: 500),
      () => _hud.value = null,
    );
  }

  // ------------------------------------------------------------------ taps

  void _onDoubleTap() {
    final s = widget.session;
    widget.onActivity?.call();
    switch (tapZone(_tapAt.dx, _size.width)) {
      case TapZone.left:
        unawaited(s.seekBy(const Duration(seconds: -10)));
        _show(const _Hud(Icons.fast_rewind, '-10 s'));
      case TapZone.right:
        unawaited(s.seekBy(const Duration(seconds: 10)));
        _show(const _Hud(Icons.fast_forward, '+10 s'));
      case TapZone.center:
        unawaited(s.player.playOrPause());
    }
  }

  // ------------------------------------------------------------------ drags

  Future<void> _startLevel(Offset local) async {
    _leftSide = local.dx < _size.width / 2;
    if (_leftSide && !_hasBrightness) {
      _drag = _Drag.none;
      return;
    }
    _drag = _Drag.level;
    _dy = 0;
    if (_leftSide) {
      try {
        _level = await ScreenBrightness.instance.application;
      } catch (_) {
        _level = 0.5;
      }
    } else if (_sysVolume.supported) {
      try {
        _level = await _sysVolume.get();
      } catch (_) {
        _level = 0.5;
      }
    } else {
      _level = (widget.session.player.state.volume / 100).clamp(0.0, 1.0);
    }
  }

  void _applyLevel() {
    final v = dragLevel(_level, _dy, _size.height);
    final pct = '${(v * 100).round()}%';
    if (_leftSide) {
      _brightnessTouched = true;
      unawaited(
        ScreenBrightness.instance
            .setApplicationScreenBrightness(v)
            .catchError((Object _) {}),
      );
      _pin(_Hud(Icons.brightness_6, pct, level: v));
    } else if (_sysVolume.supported) {
      unawaited(
        _sysVolume.set(v).then((applied) {
          if (_drag != _Drag.level) return;
          _pin(
            _Hud(
              applied == 0 ? Icons.volume_off : Icons.volume_up,
              '${(applied * 100).round()}%',
              level: applied,
            ),
          );
        }).catchError((Object _) {}),
      );
    } else {
      unawaited(widget.session.player.setVolume(v * 100));
      _pin(_Hud(v == 0 ? Icons.volume_off : Icons.volume_up, pct, level: v));
    }
  }

  void _startSeek() {
    _drag = _Drag.seek;
    _dx = 0;
    _seekFrom = widget.session.player.state.position;
    _seekTo = _seekFrom;
  }

  void _updateSeek() {
    final dur = widget.session.player.state.duration;
    _seekTo = dragSeekTarget(_seekFrom, _dx, _size.width, dur);
    _pin(
      _Hud(
        _seekTo >= _seekFrom ? Icons.fast_forward : Icons.fast_rewind,
        '${formatDelta(_seekTo - _seekFrom)}   ${formatClock(_seekTo)}',
      ),
    );
  }

  Future<void> _endDrag() async {
    final kind = _drag;
    _drag = _Drag.none;
    if (kind == _Drag.seek) {
      await widget.session.seek(_seekTo);
    }
    _clearSoon();
  }

  // ------------------------------------------------------------- long press

  void _holdStart() {
    final p = widget.session.player;
    _holding = true;
    _rateBefore = p.state.rate;
    unawaited(p.setRate(2.0));
    _pin(const _Hud(Icons.fast_forward, '2x speed'));
  }

  void _holdEnd() {
    if (!_holding) return;
    _holding = false;
    unawaited(widget.session.player.setRate(_rateBefore));
    _clearSoon();
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _hud.dispose();
    if (_holding) {
      unawaited(widget.session.player.setRate(_rateBefore));
    }
    if (_brightnessTouched) {
      unawaited(
        ScreenBrightness.instance.resetApplicationScreenBrightness().catchError(
          (Object _) {},
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _size = c.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onDoubleTapDown: (d) => _tapAt = d.localPosition,
              onDoubleTap: _onDoubleTap,
              onLongPressStart: (_) => _holdStart(),
              onLongPressEnd: (_) => _holdEnd(),
              onLongPressCancel: _holdEnd,
              onVerticalDragStart: (d) {
                widget.onActivity?.call();
                unawaited(_startLevel(d.localPosition));
              },
              onVerticalDragUpdate: (d) {
                if (_drag != _Drag.level) return;
                _dy += d.delta.dy;
                _applyLevel();
              },
              onVerticalDragEnd: (_) => _endDrag(),
              onVerticalDragCancel: () => _endDrag(),
              onHorizontalDragStart: (_) {
                widget.onActivity?.call();
                _startSeek();
              },
              onHorizontalDragUpdate: (d) {
                if (_drag != _Drag.seek) return;
                _dx += d.delta.dx;
                _updateSeek();
              },
              onHorizontalDragEnd: (_) => _endDrag(),
              onHorizontalDragCancel: () => _endDrag(),
            ),
            IgnorePointer(
              child: ValueListenableBuilder<_Hud?>(
                valueListenable: _hud,
                builder: (_, h, _) => Center(
                  child: AnimatedOpacity(
                    opacity: h == null ? 0 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: h == null ? const SizedBox.shrink() : _HudView(h),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HudView extends StatelessWidget {
  const _HudView(this.hud);
  final _Hud hud;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: context.tokens.radius(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hud.icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                hud.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (hud.level != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: hud.level,
                minHeight: 4,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
