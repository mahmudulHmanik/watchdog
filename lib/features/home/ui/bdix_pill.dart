import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';

import '../home_providers.dart';

/// "BDIX online" / "Offline" pill from the cached host probe; tap re-probes.
class BdixPill extends ConsumerWidget {
  const BdixPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final st = ref.watch(bdixOnlineProvider);
    final (label, color, bg) = st.when(
      data: (on) => on
          ? ('BDIX online', t.palette.ok, t.okBg)
          : (
              'Offline',
              t.palette.error,
              t.palette.error.withValues(alpha: .18),
            ),
      loading: () => ('Checking', t.palette.muted, t.hi),
      error: (_, _) =>
          ('Offline', t.palette.error, t.palette.error.withValues(alpha: .18)),
    );
    return InkWell(
      onTap: () => ref.invalidate(bdixOnlineProvider),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        key: const Key('bdix-pill'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(t.box ? 0 : 999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: t.box ? BoxShape.rectangle : BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
