import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';

/// Widest content column on wide windows; phones use the full width.
const _maxContentWidth = 680.0;

/// Scaffold with a back button (when pushed) and a centered, capped column.
class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: LayoutBuilder(
      builder: (context, c) {
        final side = math.max(16.0, (c.maxWidth - _maxContentWidth) / 2);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 16, side, 24),
          children: children,
        );
      },
    ),
  );
}

/// Titled block of a settings page. Bordered blocks are a card holding rows
/// (ListTiles, switches) separated by hairlines; free-form content brings its
/// own padding.
class SettingsBlock extends StatelessWidget {
  const SettingsBlock({
    super.key,
    required this.title,
    required this.children,
    this.bordered = true,
    this.dividers = true,
  });
  final String title;
  final List<Widget> children;
  final bool bordered;
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final body = <Widget>[
      for (var i = 0; i < children.length; i++) ...[
        if (dividers && i > 0) Divider(height: 1, color: t.border),
        children[i],
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: muted,
              ),
            ),
          ),
          if (bordered)
            // Material (not a colored DecoratedBox) so row ink stays visible.
            Material(
              color: t.palette.card,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: t.radius(),
                side: BorderSide(color: t.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: body,
            ),
        ],
      ),
    );
  }
}

/// Padding for free-form content inside a bordered [SettingsBlock].
const settingsPad = EdgeInsets.all(14);

/// Home entry: icon, title, live one-line summary, chevron.
class SettingsGroupTile extends StatelessWidget {
  const SettingsGroupTile({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: t.plain(color: t.palette.card),
          child: InkWell(
            borderRadius: t.radius(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: t.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
