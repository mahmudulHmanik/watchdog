import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';

import '../search_providers.dart';
import 'facet_sheet.dart';

/// 34px filter chip: active shows a clear (x), inactive a chevron.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClear,
    this.name,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClear;

  /// Stable key suffix (defaults to [label]).
  final String? name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = t.box ? 0.0 : 999.0;
    final k = name ?? label;
    return Container(
      height: 34,
      decoration: active ? t.selected(r: r) : t.plain(r: r),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: Key('pill-$k'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? t.accent : null,
                  ),
                ),
              ),
            ),
          ),
          InkWell(
            key: Key('pill-icon-$k'),
            onTap: active ? onClear : onTap,
            child: Padding(
              padding: const EdgeInsets.only(left: 2, right: 8),
              child: Icon(
                active ? Icons.close : Icons.keyboard_arrow_down,
                size: 16,
                color: active ? t.accent : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selected year buckets of [f] among [presets].
Set<YearBucket> selectedYearBuckets(BrowseFilter f, List<YearBucket> presets) =>
    {
      for (final b in presets)
        if ((b.years.isNotEmpty || b.ranges.isNotEmpty) &&
            f.years.containsAll(b.years) &&
            b.ranges.every(f.yearRanges.contains))
          b,
    };

/// Chip text for the year facet: selected bucket labels, then any years or
/// ranges not covered by a preset bucket; `Year` when unfiltered.
String yearChipLabel(BrowseFilter f, List<YearBucket> presets) {
  if (!f.hasYearFilter) return 'Year';
  final sel = selectedYearBuckets(f, presets);
  final coveredYears = {for (final b in sel) ...b.years};
  final coveredRanges = {for (final b in sel) ...b.ranges};
  final parts = <String>[
    for (final b in sel) b.label,
    for (final y
        in (f.years.difference(coveredYears).toList()..sort((a, b) => b - a)))
      '$y',
    for (final r in f.yearRanges)
      if (!coveredRanges.contains(r))
        r.from == null ? 'Before ${r.to! + 1}' : '${r.from}-${r.to ?? ''}',
  ];
  return parts.length <= 2
      ? parts.join(', ')
      : '${parts.length} ${parts.length == 1 ? 'year' : 'years'}';
}

/// `2024, 2023` or `3 years`.
String summarize(List<String> labels, String noun) =>
    labels.length <= 2 ? labels.join(', ') : '${labels.length} $noun';

/// Kind / Year / Language / Quality (+ Category) chips opening pickers.
class FilterBar extends ConsumerWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(searchFilterProvider);
    final repo = ref.watch(repositoryProvider);
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    void set(BrowseFilter n) => ref.read(searchFilterProvider.notifier).set(n);

    final presets = YearBucket.presets();
    final yearSel = selectedYearBuckets(f, presets);
    final kind = f.kind;

    Future<void> openYear() async {
      final pick = await showFacetSheet<YearBucket>(
        context,
        title: 'Year',
        options: Future.value([
          for (final b in presets) FacetOption(b.label, b),
        ]),
        selected: yearSel,
      );
      if (pick == null) return;
      final m = YearBucket.merge(pick);
      set(f.copyWith(years: m.years, yearRanges: m.ranges));
    }

    Future<void> openLanguage() async {
      final pick = await showFacetSheet<String>(
        context,
        title: 'Language',
        options: repo
            .languages(f)
            .then(
              (l) => [
                for (final v in l)
                  FacetOption(v.value, v.value, count: v.count),
              ],
            ),
        selected: f.languages,
        columns: 2,
      );
      if (pick != null) set(f.copyWith(languages: pick));
    }

    Future<void> openQuality() async {
      final pick = await showFacetSheet<int>(
        context,
        title: 'Quality',
        options: repo
            .qualities(f)
            .then(
              (l) => [
                for (final v in l)
                  FacetOption('${v.value}p', v.value, count: v.count),
              ],
            ),
        selected: f.qualities,
      );
      if (pick != null) set(f.copyWith(qualities: pick));
    }

    Future<void> openCategory() async {
      final pick = await showFacetSheet<int>(
        context,
        title: 'Category',
        options: Future.value([
          for (final c in cats) FacetOption(c.name, c.id, count: c.titleCount),
        ]),
        selected: {?f.categoryId},
        columns: 2,
        multi: false,
      );
      if (pick != null) set(f.copyWith(categoryId: pick.firstOrNull));
    }

    final pills = <Widget>[
      FilterPill(
        name: 'Type',
        label: switch (kind) {
          TitleKind.series => 'Series',
          TitleKind.movie => 'Movie',
          _ => 'Type',
        },
        active: kind != null,
        onTap: () => set(
          f.copyWith(
            kind: switch (kind) {
              null => TitleKind.series,
              TitleKind.series => TitleKind.movie,
              _ => null,
            },
          ),
        ),
        onClear: () => set(f.copyWith(kind: null)),
      ),
      FilterPill(
        name: 'Year',
        label: yearChipLabel(f, presets),
        active: f.hasYearFilter,
        onTap: openYear,
        onClear: () => set(f.copyWith(years: const {}, yearRanges: const [])),
      ),
      FilterPill(
        name: 'Language',
        label: f.languages.isEmpty
            ? 'Language'
            : summarize(f.languages.toList(), 'languages'),
        active: f.languages.isNotEmpty,
        onTap: openLanguage,
        onClear: () => set(f.copyWith(languages: const {})),
      ),
      FilterPill(
        name: 'Quality',
        label: f.qualities.isEmpty
            ? 'Quality'
            : summarize([for (final q in f.qualities) '${q}p'], 'qualities'),
        active: f.qualities.isNotEmpty,
        onTap: openQuality,
        onClear: () => set(f.copyWith(qualities: const {})),
      ),
      FilterPill(
        name: 'Category',
        label:
            cats.where((c) => c.id == f.categoryId).firstOrNull?.name ??
            'Category',
        active: f.categoryId != null,
        onTap: openCategory,
        onClear: () => set(f.copyWith(categoryId: null)),
      ),
    ];
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8).copyWith(left: 16),
        itemCount: pills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => pills[i],
      ),
    );
  }
}
