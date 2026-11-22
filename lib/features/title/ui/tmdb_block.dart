import 'package:watchdog/features/browse/ui/app_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/search/search_providers.dart';
import 'package:watchdog/features/settings/settings_target.dart';
import 'package:watchdog/features/settings/tmdb_ui_providers.dart';
import 'package:watchdog/tmdb/tmdb_images.dart';
import 'package:watchdog/tmdb/tmdb_models.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart';

import '../tmdb_title_providers.dart';
import 'tmdb_match_sheet.dart';

/// Show the search tab filtered by [f] (genre / actor tap).
void openSearchWith(BuildContext context, WidgetRef ref, BrowseFilter f) {
  // Read everything before popping: this widget is gone afterwards.
  ref.read(searchFilterProvider.notifier).set(f);
  ref.read(navIndexProvider.notifier).go(tabSearch);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

void openSettingsTab(BuildContext context, WidgetRef ref) {
  ref.read(settingsTargetProvider.notifier).open(SettingsPage.tmdb);
  ref.read(navIndexProvider.notifier).go(tabSettings);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

/// ISO 639-1 codes TMDB uses for `original_language`; unknown codes show as is.
const _langNames = {
  'en': 'English',
  'hi': 'Hindi',
  'bn': 'Bengali',
  'ta': 'Tamil',
  'te': 'Telugu',
  'ml': 'Malayalam',
  'kn': 'Kannada',
  'mr': 'Marathi',
  'pa': 'Punjabi',
  'ur': 'Urdu',
  'ko': 'Korean',
  'ja': 'Japanese',
  'zh': 'Chinese',
  'cn': 'Cantonese',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'ar': 'Arabic',
  'tr': 'Turkish',
  'th': 'Thai',
  'id': 'Indonesian',
};

String languageName(String code) => _langNames[code] ?? code.toUpperCase();

String formatRuntime(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Everything TMDB adds below the title header. Shows nothing for events and
/// while the key setting is still loading.
class TmdbBlock extends ConsumerWidget {
  const TmdbBlock(this.t, {super.key});
  final MediaTitle t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(tmdbConfigProvider).value;
    if (cfg == null || t.kind == TitleKind.event) return const SizedBox();
    if (cfg.auth == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: InkWell(
          key: const Key('tmdb-hint'),
          onTap: () => openSettingsTab(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Add a TMDB key in Settings for details',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      );
    }
    final info = ref.watch(tmdbInfoProvider(t.id)).value;
    final fetch = ref.watch(tmdbFetchProvider(t.id));
    final matched = info != null && info.status != TmdbStatus.unmatched;
    if (matched) return TmdbDetailsView(t, info);
    return _StatusRow(
      t,
      loading: fetch.isLoading,
      failed: fetch.value?.status == TmdbFetchStatus.failed
          ? fetch.value!.error
          : null,
    );
  }
}

/// Fixed-height row for the states without details, so the area does not
/// jump between loading, unmatched and failed.
class _StatusRow extends ConsumerWidget {
  const _StatusRow(this.t, {required this.loading, this.failed});
  final MediaTitle t;
  final bool loading;
  final Object? failed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(fontSize: 13, color: muted);
    Widget child;
    if (loading) {
      child = Row(
        key: const Key('tmdb-loading'),
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Looking up on TMDB...', style: style),
        ],
      );
    } else if (failed != null) {
      child = Row(
        key: const Key('tmdb-failed'),
        children: [
          Icon(Icons.cloud_off, size: 16, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tmdbErrorText(failed!),
              style: style,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            key: const Key('tmdb-retry'),
            onPressed: () => ref.invalidate(tmdbFetchProvider(t.id)),
            child: const Text('Retry'),
          ),
        ],
      );
    } else {
      child = Row(
        key: const Key('tmdb-unmatched'),
        children: [
          Expanded(child: Text('No match on TMDB', style: style)),
          TextButton(
            key: const Key('tmdb-find'),
            onPressed: () => showTmdbMatchSheet(context, t),
            child: const Text('Find on TMDB'),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(height: 44, child: child),
    );
  }
}

class TmdbDetailsView extends ConsumerWidget {
  const TmdbDetailsView(this.t, this.info, {super.key});
  final MediaTitle t;
  final TmdbInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final tk = context.tokens;
    final meta = <Widget>[
      if (info.rating != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, size: 16, color: tk.accent),
            const SizedBox(width: 4),
            Text(
              '${info.rating!.toStringAsFixed(1)}/10',
              key: const Key('tmdb-rating'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      if (info.runtime != null)
        Text(formatRuntime(info.runtime!), key: const Key('tmdb-runtime')),
      if (info.originalLanguage != null)
        Text(
          'Original: ${languageName(info.originalLanguage!)}',
          key: const Key('tmdb-lang'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (info.tagline != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              info.tagline!,
              key: const Key('tmdb-tagline'),
              style: TextStyle(fontStyle: FontStyle.italic, color: muted),
            ),
          ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(spacing: 16, runSpacing: 4, children: meta),
          ),
        if (info.genres.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in info.genres)
                  ActionChip(
                    key: Key('genre-${g.id}'),
                    label: Text(g.name),
                    onPressed: () => openSearchWith(
                      context,
                      ref,
                      BrowseFilter(genreIds: {g.id}),
                    ),
                  ),
              ],
            ),
          ),
        if (info.overview != null) _Overview(info.overview!),
        if (info.cast.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Cast', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 132,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: info.cast.length,
              itemBuilder: (context, i) => _CastTile(
                info.cast[i],
                onTap: () => openSearchWith(
                  context,
                  ref,
                  BrowseFilter(personId: info.cast[i].personId),
                ),
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: TextButton.icon(
            key: const Key('tmdb-fix'),
            icon: const Icon(Icons.manage_search, size: 18),
            label: const Text('Fix match'),
            onPressed: () => showTmdbMatchSheet(context, t),
          ),
        ),
      ],
    );
  }
}

class _Overview extends StatefulWidget {
  const _Overview(this.text);
  final String text;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const Key('tmdb-overview'),
    onTap: () => setState(() => _open = !_open),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        widget.text,
        maxLines: _open ? null : 5,
        overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
      ),
    ),
  );
}

class _CastTile extends StatelessWidget {
  const _CastTile(this.c, {required this.onTap});
  final TmdbCastMember c;
  final VoidCallback onTap;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final l = parts.toList();
    if (l.isEmpty) return '?';
    if (l.length == 1) return l.first.characters.first.toUpperCase();
    return (l.first.characters.first + l.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tk = context.tokens;
    final url = tmdbImageUrl(c.profilePath, TmdbImageSize.profile);
    final fallback = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      color: cs.surfaceContainerHigh,
      child: Text(
        initials(c.name),
        style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
      ),
    );
    return InkWell(
      key: Key('cast-${c.personId}'),
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: tk.radius(999),
                child: url == null
                    ? fallback
                    : AppImage(
                        url,
                        width: 64,
                        height: 64,
                        cacheWidth: 128,
                        fallback: fallback,
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                c.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (c.character != null)
                Text(
                  c.character!,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 16:9-ish backdrop that fades into the page background.
class TmdbBackdrop extends StatelessWidget {
  const TmdbBackdrop(this.url, {super.key});
  final String url;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      key: const Key('tmdb-backdrop'),
      height: 180,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppImage(
            url,
            cacheWidth: 1080,
            fallback: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0), bg],
                stops: const [0.5, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
