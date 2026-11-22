import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/ui/title_tile.dart' show Poster;
import 'package:watchdog/features/search/search_providers.dart'
    show tmdbHasDataProvider;
import 'package:watchdog/features/settings/tmdb_ui_providers.dart';
import 'package:watchdog/tmdb/tmdb_images.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart';

import '../tmdb_title_providers.dart';
import 'file_actions_sheet.dart' show showToast;

/// "Fix match" / "Find on TMDB": search TMDB by hand and pick the right entry.
Future<void> showTmdbMatchSheet(BuildContext context, MediaTitle t) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MatchSheet(t),
    );

class _MatchSheet extends ConsumerStatefulWidget {
  const _MatchSheet(this.t);
  final MediaTitle t;

  @override
  ConsumerState<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends ConsumerState<_MatchSheet> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.t.name,
  );
  late TmdbMediaType _type = widget.t.kind == TitleKind.series
      ? TmdbMediaType.tv
      : TmdbMediaType.movie;
  List<TmdbHit>? _hits;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  int _gen = 0; // drops answers of superseded searches

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final sync = ref.read(tmdbSyncProvider);
    final q = _ctl.text.trim();
    if (sync == null || q.isEmpty) return;
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hits = await sync.searchCandidates(q, _type, year: widget.t.year);
      // Empty with a year: the year may be off, look again without it.
      final all = hits.isEmpty && widget.t.year != null
          ? await sync.searchCandidates(q, _type)
          : hits;
      if (!mounted || gen != _gen) return;
      setState(() {
        _hits = all;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _hits = null;
        _loading = false;
        _error = tmdbErrorText(e);
      });
    }
  }

  Future<void> _pick(TmdbHit h) async {
    final sync = ref.read(tmdbSyncProvider);
    if (sync == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await sync.rematch(widget.t.id, h.id, h.mediaType);
    if (!mounted) return;
    if (r.status == TmdbFetchStatus.matched) {
      ref.invalidate(tmdbInfoProvider(widget.t.id));
      ref.invalidate(tmdbHasDataProvider);
      final nav = Navigator.of(context);
      final host = nav.context;
      nav.pop();
      if (host.mounted) showToast(host, 'Matched to ${h.title}');
    } else {
      setState(() {
        _saving = false;
        _error = r.error == null ? 'Could not save.' : tmdbErrorText(r.error!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tk = context.tokens;
    final info = ref.watch(tmdbInfoProvider(widget.t.id)).value;
    final fix = info != null && info.status != TmdbStatus.unmatched;
    final media = MediaQuery.of(context);
    final hits = _hits;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                fix ? 'Fix match' : 'Find on TMDB',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('tmdb-match-query'),
                controller: _ctl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  labelText: 'Search TMDB',
                  suffixIcon: IconButton(
                    key: const Key('tmdb-match-go'),
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (type, label) in [
                    (TmdbMediaType.movie, 'Movie'),
                    (TmdbMediaType.tv, 'TV show'),
                  ])
                    ChoiceChip(
                      key: Key('tmdb-type-${type.name}'),
                      label: Text(label),
                      selected: _type == type,
                      onSelected: (_) {
                        setState(() => _type = type);
                        _search();
                      },
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  _error!,
                  key: const Key('tmdb-match-error'),
                  style: TextStyle(color: tk.palette.error),
                ),
              ),
            const Divider(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : hits == null
                  ? const SizedBox()
                  : hits.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing found. Try another spelling.',
                        key: const Key('tmdb-match-empty'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: hits.length,
                      itemBuilder: (context, i) {
                        final h = hits[i];
                        final sub = [
                          if (h.year != null) '${h.year}',
                          h.mediaType == TmdbMediaType.movie
                              ? 'Movie'
                              : 'TV show',
                        ].join(' · ');
                        final orig =
                            h.originalTitle != null &&
                                h.originalTitle != h.title
                            ? h.originalTitle
                            : null;
                        return ListTile(
                          key: Key('tmdb-hit-${h.id}'),
                          enabled: !_saving,
                          leading: Poster(
                            tmdbImageUrl(h.posterPath, TmdbImageSize.poster),
                            width: 40,
                            height: 60,
                          ),
                          title: Text(h.title),
                          subtitle: Text(orig == null ? sub : '$sub\n$orig'),
                          isThreeLine: orig != null,
                          onTap: () => _pick(h),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
