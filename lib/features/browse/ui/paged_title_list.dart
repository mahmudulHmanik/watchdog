import 'package:material_ui/material_ui.dart';
import 'package:watchdog/data/models.dart';

import 'title_tile.dart';

typedef TitleLoader = Future<List<MediaTitle>> Function(int offset, int limit);

/// Lazy, offset/limit paged title list in a CustomScrollView, with optional
/// header slivers. Give it a new [key] to reset when the query changes.
class PagedTitleList extends StatefulWidget {
  const PagedTitleList({
    super.key,
    required this.loader,
    this.headers = const [],
    this.emptyText = 'Nothing here.',
    this.pageSize = 50,
    this.query = '',
    this.onLoaded,
  });
  final String query;

  /// Called after each page with (loaded so far, no more pages).
  final void Function(int count, bool done)? onLoaded;
  final TitleLoader loader;
  final List<Widget> headers;
  final String emptyText;
  final int pageSize;

  @override
  State<PagedTitleList> createState() => _PagedTitleListState();
}

class _PagedTitleListState extends State<PagedTitleList> {
  final _items = <MediaTitle>[];
  bool _loading = false, _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final page = await widget.loader(_items.length, widget.pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _done = page.length < widget.pageSize;
        _error = null;
      });
      widget.onLoaded?.call(_items.length, _done);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _done = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = _items.isEmpty && !_loading;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        ...widget.headers,
        if (empty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(_error != null ? 'Error: $_error' : widget.emptyText),
            ),
          )
        else
          SliverList.builder(
            itemCount: _items.length + (_done ? 0 : 1),
            itemBuilder: (context, i) {
              if (i >= _items.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _more());
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return TitleTile(_items[i], query: widget.query);
            },
          ),
      ],
    );
  }
}
