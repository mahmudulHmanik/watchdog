import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/browse/ui/paged_title_list.dart';

import '../search_providers.dart';
import 'filter_bar.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const debounce = Duration(milliseconds: 250);
  final _ctl = TextEditingController();
  Timer? _timer;
  String _query = '';
  int _count = 0;
  bool _done = true;

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {}); // clear button visibility
    _timer?.cancel();
    _timer = Timer(debounce, () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(searchFilterProvider);
    final rev = ref.watch(revisionProvider);
    final repo = ref.watch(repositoryProvider);
    final q = _query;
    return Scaffold(
      key: const Key('search-screen'),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () =>
                        ref.read(navIndexProvider.notifier).go(tabHome),
                  ),
                  Expanded(
                    child: TextField(
                      key: const Key('search-field'),
                      controller: _ctl,
                      onChanged: _onChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search',
                        suffixIcon: _ctl.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _ctl.clear();
                                  _onChanged('');
                                },
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const FilterBar(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    children: [
                      TextSpan(
                        text: q.isEmpty
                            ? 'Showing all'
                            : 'Showing results for ',
                      ),
                      if (q.isNotEmpty)
                        TextSpan(
                          text: q,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      TextSpan(text: ' · $_count${_done ? '' : '+'} matches'),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: PagedTitleList(
                key: ValueKey((q, filter, rev)),
                query: q,
                emptyText: 'No matches.',
                onLoaded: (n, done) => setState(() {
                  _count = n;
                  _done = done;
                }),
                loader: (o, l) => q.isEmpty
                    ? repo.browse(filter, offset: o, limit: l)
                    : repo.search(q, filter: filter, offset: o, limit: l),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
