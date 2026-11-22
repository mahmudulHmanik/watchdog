import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/data/models.dart';

import '../title_providers.dart';
import 'file_tile.dart';
import 'series_view.dart';
import 'title_header.dart';

class TitleScreen extends ConsumerWidget {
  const TitleScreen({super.key, required this.titleId});
  final int titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(titleDetailProvider(titleId));
    // Keep showing the previous data while a refresh is in flight.
    final data = d.value;
    return Scaffold(
      appBar: AppBar(title: Text(data?.title.name ?? '')),
      body: data != null
          ? _Body(data)
          : d.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => const Center(child: Text('Title not found.')),
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.d);
  final TitleDetail d;

  @override
  Widget build(BuildContext context) {
    if (d.title.kind == TitleKind.series) return SeriesView(d);
    return ListView.builder(
      itemCount: d.files.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return TitleHeader(d.title);
        final f = d.files[i - 1];
        return FileTile(
          key: ValueKey('file-${f.id}'),
          title: d.title,
          file: f,
          state: d.states[f.id],
        );
      },
    );
  }
}
