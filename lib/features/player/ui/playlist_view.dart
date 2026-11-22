import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/features/series/domain/playlist_labels.dart';

/// Scrollable playlist: season header rows (not tappable) and item rows.
/// [index] is the current item's index in `Playlist.items`; [onPick] gets an
/// item index (never a row index), so headers never shift playback.
class PlaylistView extends StatefulWidget {
  const PlaylistView({
    super.key,
    required this.rows,
    required this.index,
    required this.onPick,
  });
  final List<PlaylistRow> rows;
  final int index;
  final ValueChanged<int> onPick;

  static const itemExtent = 56.0;
  static const headerExtent = 36.0;

  @override
  State<PlaylistView> createState() => _PlaylistViewState();
}

class _PlaylistViewState extends State<PlaylistView> {
  late final ScrollController _ctl;

  double _extent(PlaylistRow r) => r is PlaylistHeaderRow
      ? PlaylistView.headerExtent
      : PlaylistView.itemExtent;

  /// Scroll offset that puts the current item one row below the top; when its
  /// season header directly precedes it, the header sits at the top instead.
  double _offsetFor(int item) {
    var y = 0.0;
    for (var r = 0; r < widget.rows.length; r++) {
      final row = widget.rows[r];
      if (row is PlaylistItemRow && row.index == item) {
        final above = r > 0 && widget.rows[r - 1] is PlaylistHeaderRow
            ? PlaylistView.headerExtent
            : PlaylistView.itemExtent;
        return (y - above).clamp(0.0, double.infinity);
      }
      y += _extent(row);
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _ctl = ScrollController(initialScrollOffset: _offsetFor(widget.index));
  }

  @override
  void didUpdateWidget(PlaylistView old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && _ctl.hasClients) {
      final max = _ctl.position.maxScrollExtent;
      _ctl.animateTo(
        _offsetFor(widget.index).clamp(0.0, max),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView.builder(
      controller: _ctl,
      // No inherited status-bar padding (this list is not at the screen top);
      // keep the last row clear of the gesture bar.
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      itemExtentBuilder: (i, _) => _extent(widget.rows[i]),
      itemCount: widget.rows.length,
      itemBuilder: (_, i) {
        final row = widget.rows[i];
        if (row is PlaylistHeaderRow) {
          return Container(
            key: ValueKey('playlist-header-$i'),
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Text(
              row.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
          );
        }
        row as PlaylistItemRow;
        final cur = row.index == widget.index;
        return InkWell(
          key: ValueKey('playlist-item-${row.index}'),
          onTap: () => widget.onPick(row.index),
          child: Container(
            decoration: cur
                ? BoxDecoration(
                    color: t.hi,
                    border: Border(left: BorderSide(color: t.accent, width: 3)),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: cur
                      ? Icon(Icons.play_arrow, size: 18, color: t.accent)
                      : Text(
                          row.number,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 12),
                        ),
                ),
                Expanded(
                  child: Text(
                    row.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: cur ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
