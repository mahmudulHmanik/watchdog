import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/palettes.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/core/theme/theme_store.dart';

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

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.tileKey,
    required this.p,
    required this.title,
    required this.selected,
    required this.onTap,
  });
  final Key tileKey;
  final AppPalette p;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      key: tileKey,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: selected ? t.selected() : t.plain(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Swatches(p),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? t.accent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeSection extends ConsumerWidget {
  const ThemeSection({super.key});

  Widget _group(
    BuildContext context,
    WidgetRef ref,
    String label,
    List<AppPalette> items,
    ThemeSettings s,
  ) {
    final n = ref.read(themeSettingsProvider.notifier);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            label,
            key: Key('palette-group-$label'),
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
        for (var i = 0; i < items.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 66,
              child: Row(
                children: [
                  for (var k = i; k < i + 2; k++) ...[
                    if (k > i) const SizedBox(width: 8),
                    Expanded(
                      child: k < items.length
                          ? _PaletteTile(
                              tileKey: Key('palette-${items[k].id}'),
                              p: items[k],
                              title: items[k].name,
                              selected:
                                  !s.followSystem &&
                                  items[k].id == s.palette.id,
                              onTap: () => n.setPalette(items[k]),
                            )
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final s = ref.watch(themeSettingsProvider);
    final n = ref.read(themeSettingsProvider.notifier);
    final auto = ref.watch(autoThemeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('palette-follow'),
          onTap: n.setFollowSystem,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: s.followSystem ? t.selected() : t.plain(),
            child: Row(
              children: [
                _Swatches(auto.palette),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Follow system',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: s.followSystem ? t.accent : null,
                        ),
                      ),
                      Text(
                        auto.label,
                        key: const Key('follow-sub'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _group(context, ref, 'Dark', [
          for (final p in allPalettes)
            if (p.dark) p,
        ], s),
        _group(context, ref, 'Light', [
          for (final p in allPalettes)
            if (!p.dark) p,
        ], s),
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
