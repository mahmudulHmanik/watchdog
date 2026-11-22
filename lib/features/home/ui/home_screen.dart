import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/index/index_service.dart';
import 'package:watchdog/features/index/ui/first_run_view.dart';

import '../home_providers.dart';
import 'bdix_pill.dart';
import 'category_picker.dart';
import 'continue_row.dart';
import 'recent_grid.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await ref.read(indexServiceProvider).reindex();
    ref.read(revisionProvider.notifier).bump();
    ref.invalidate(bdixOnlineProvider);
    if (r.outcome != IndexOutcome.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            r.message ??
                (r.offBdix
                    ? 'Not on BDIX: servers unreachable.'
                    : 'Index ${r.outcome.name}.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(countsProvider);
    final skipped = ref.watch(skipIndexProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'watchdog',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const BdixPill(),
                ],
              ),
            ),
            Expanded(
              child: counts.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (c) => c.titles == 0 && !skipped
                    ? const FirstRunView()
                    : RefreshIndicator(
                        onRefresh: () => _refresh(context, ref),
                        child: const _Browse(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends ConsumerWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: InkWell(
        key: const Key('home-search'),
        onTap: () => ref.read(navIndexProvider.notifier).go(tabSearch),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: t.plain(r: 14, color: Theme.of(context).cardColor),
          child: Row(
            children: [
              Icon(Icons.search, color: muted),
              const SizedBox(width: 10),
              Text('Search titles', style: TextStyle(color: muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Browse extends ConsumerWidget {
  const _Browse();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(selectedCategoryProvider);
    final recent = ref.watch(recentTitlesProvider(cat));
    final repo = ref.watch(repositoryProvider);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: _SearchBar()),
        const SliverToBoxAdapter(child: CategoryButton()),
        const SliverToBoxAdapter(child: ContinueRow()),
        SliverToBoxAdapter(
          child: SectionHeader(
            'Recently added',
            onSeeAll: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AllTitlesScreen(
                  loader: (o, l) => repo.browse(
                    BrowseFilter(
                      categoryId: cat,
                      sort: BrowseSort.recentlyAdded,
                    ),
                    offset: o,
                    limit: l,
                  ),
                ),
              ),
            ),
          ),
        ),
        ...recent.when(
          data: (items) => items.isEmpty
              ? [
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No titles. Pull down to index.'),
                      ),
                    ),
                  ),
                ]
              : [posterGridSliver(items)],
          loading: () => [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
          error: (e, _) => [SliverToBoxAdapter(child: Text('Error: $e'))],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
