import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';

/// One selectable option in a facet sheet.
class FacetOption<T> {
  const FacetOption(this.label, this.value, {this.count});
  final String label;
  final T value;
  final int? count;
}

/// Bottom sheet: title + Reset, grid of 44px option buttons, full-width
/// "Show results". Returns the chosen set (empty = any), or null if
/// dismissed. [multi] false = at most one selected.
Future<Set<T>?> showFacetSheet<T>(
  BuildContext context, {
  required String title,
  required Future<List<FacetOption<T>>> options,
  required Set<T> selected,
  int columns = 4,
  bool multi = true,
}) => showModalBottomSheet<Set<T>>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => _FacetSheet<T>(
    title: title,
    options: options,
    selected: selected,
    columns: columns,
    multi: multi,
  ),
);

class _FacetSheet<T> extends StatefulWidget {
  const _FacetSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.columns,
    required this.multi,
  });
  final String title;
  final Future<List<FacetOption<T>>> options;
  final Set<T> selected;
  final int columns;
  final bool multi;

  @override
  State<_FacetSheet<T>> createState() => _FacetSheetState<T>();
}

class _FacetSheetState<T> extends State<_FacetSheet<T>> {
  late final Set<T> _sel = {...widget.selected};

  void _toggle(T v) => setState(() {
    if (_sel.remove(v)) return;
    if (!widget.multi) _sel.clear();
    _sel.add(v);
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final body = Theme.of(context).textTheme.bodyMedium;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(_sel.clear),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          Flexible(
            child: FutureBuilder<List<FacetOption<T>>>(
              future: widget.options,
              builder: (ctx, snap) {
                if (!snap.hasData) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: snap.hasError
                        ? Text('Error: ${snap.error}')
                        : const CircularProgressIndicator(),
                  );
                }
                final items = snap.data!;
                return GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: widget.columns,
                    mainAxisExtent: 44,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final o = items[i];
                    final on = _sel.contains(o.value);
                    return InkWell(
                      key: Key('facet-${o.label}'),
                      onTap: () => _toggle(o.value),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: on
                            ? t.selected(r: t.box ? 0 : 999)
                            : t.plain(r: t.box ? 0 : 999),
                        child: Text(
                          o.count == null ? o.label : '${o.label} (${o.count})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: body?.copyWith(
                            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                            color: on ? t.accent : null,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, {..._sel}),
                child: const Text('Show results'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
