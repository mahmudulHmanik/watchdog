import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/browse_providers.dart';

/// "Category: All v" dropdown button for Home; opens [showCategorySheet].
class CategoryButton extends ConsumerWidget {
  const CategoryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final cat = ref.watch(selectedCategoryProvider);
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final name = cats.where((c) => c.id == cat).firstOrNull?.name;
    final r = t.box ? 0.0 : 999.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          key: const Key('home-category'),
          onTap: () => showCategorySheet(context, ref),
          child: Container(
            height: 40,
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: name != null ? t.selected(r: r) : t.plain(r: r),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Category: ${name ?? 'All'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: name != null
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: name != null ? t.accent : null,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: name != null ? t.accent : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showCategorySheet(BuildContext context, WidgetRef ref) async {
  final cats = [...?ref.read(categoriesProvider).value]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final pick = await showModalBottomSheet<(int?,)>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CategorySheet(
      categories: cats,
      selected: ref.read(selectedCategoryProvider),
    ),
  );
  if (pick != null) ref.read(selectedCategoryProvider.notifier).set(pick.$1);
}

/// Searchable, scrollable list: "All" first, then categories (A-Z) with
/// title counts. Pops `(id,)` (null id = All); dismiss pops null.
class CategorySheet extends StatefulWidget {
  const CategorySheet({
    super.key,
    required this.categories,
    required this.selected,
  });
  final List<Category> categories;
  final int? selected;

  @override
  State<CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<CategorySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final q = _q.trim().toLowerCase();
    final items = [
      if (q.isEmpty || 'all'.contains(q)) null,
      for (final c in widget.categories)
        if (q.isEmpty || c.name.toLowerCase().contains(q)) c,
    ];
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  key: const Key('category-search'),
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(
                    hintText: 'Search categories',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              Flexible(
                child: items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No matching category'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: items.length,
                        itemBuilder: (ctx, i) {
                          final c = items[i];
                          final on = c?.id == widget.selected;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              key: Key('category-${c?.id ?? 'all'}'),
                              onTap: () => Navigator.pop(context, (c?.id,)),
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: on
                                    ? t.selected()
                                    : const BoxDecoration(),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c?.name ?? 'All',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: on
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: on ? t.accent : null,
                                        ),
                                      ),
                                    ),
                                    if (c != null)
                                      Text(
                                        '${c.titleCount}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    if (on) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.check,
                                        size: 18,
                                        color: t.accent,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
