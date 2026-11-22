import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/core/theme/theme_providers.dart';

String paletteSub(AppPalette p) =>
    '${p.dark ? 'Dark' : 'Light'} · ${switch (p.id) {
      'everforest' => 'green',
      _ => 'blue',
    }} accent';

class _Swatches extends StatelessWidget {
  const _Swatches(this.p);
  final AppPalette p;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final c in [p.bg, p.card, p.text, p.accent])
        Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: c,
            border: Border.all(color: p.border),
            borderRadius: context.tokens.radius(4),
          ),
        ),
    ],
  );
}

class ThemeSection extends ConsumerWidget {
  const ThemeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final s = ref.watch(themeSettingsProvider);
    final n = ref.read(themeSettingsProvider.notifier);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final omarchy = ref.watch(omarchyProvider);
    final following = s.followOmarchy && omarchy != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in allPalettes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Opacity(
              opacity: following ? 0.4 : 1,
              child: InkWell(
                key: Key('palette-${p.id}'),
                onTap: following ? null : () => n.setPalette(p),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: p.id == s.palette.id ? t.selected() : t.plain(),
                  child: Row(
                    children: [
                      _Swatches(p),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              paletteSub(p),
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        p.id == s.palette.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: p.id == s.palette.id ? t.accent : muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (ref.watch(omarchyLocatorProvider) != null)
          SwitchListTile(
            key: const Key('follow-omarchy'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Follow Omarchy theme'),
            subtitle: Text(
              omarchy == null
                  ? 'Omarchy theme not found'
                  : s.followOmarchy
                  ? (omarchy.name ?? 'Omarchy')
                  : 'Linux only · reads your active theme',
            ),
            value: s.followOmarchy && omarchy != null,
            onChanged: omarchy == null && !s.followOmarchy
                ? null
                : n.setFollowOmarchy,
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ShapeCard(
                'Rounded',
                ShapeMode.rounded,
                s.shape == ShapeMode.rounded,
                () => n.setShape(ShapeMode.rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ShapeCard(
                'Box (Omarchy)',
                ShapeMode.box,
                s.shape == ShapeMode.box,
                () => n.setShape(ShapeMode.box),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShapeCard extends StatelessWidget {
  const _ShapeCard(this.label, this.mode, this.selected, this.onTap);
  final String label;
  final ShapeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final box = mode == ShapeMode.box;
    return InkWell(
      key: Key('shape-${mode.name}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: selected ? t.selected() : t.plain(),
        child: Column(
          children: [
            Container(
              height: 40,
              alignment: Alignment.center,
              child: Container(
                width: 64,
                height: 26,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.25),
                  border: Border.all(color: t.accent, width: box ? 2 : 1),
                  borderRadius: BorderRadius.circular(box ? 0 : 13),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? t.accent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
