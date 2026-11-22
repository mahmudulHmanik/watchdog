import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';

/// 40x24 toggle (44px touch target). Box: square track/knob with a 2px border;
/// Rounded: pill track and round knob.
class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = value;
    return Semantics(
      toggled: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!on),
        child: SizedBox(
          width: 48,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 40,
              height: 24,
              padding: const EdgeInsets.all(3),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on && !t.box ? t.accent : Colors.transparent,
                border: Border.all(
                  color: on ? t.accent : t.border,
                  width: t.box ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(t.box ? 0 : 12),
              ),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: on
                      ? (t.box ? t.accent : t.palette.onAccent)
                      : t.palette.muted,
                  shape: t.box ? BoxShape.rectangle : BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
