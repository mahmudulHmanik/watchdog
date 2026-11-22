/// Season-aware labels and row grouping for a [Playlist]. Pure Dart.
library;

import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/series/domain/playlist.dart';
import 'package:watchdog/features/title/episode_title.dart';

/// One visual row of the playlist: a season header or a playable item.
sealed class PlaylistRow {
  const PlaylistRow();
}

class PlaylistHeaderRow extends PlaylistRow {
  const PlaylistHeaderRow(this.text);
  final String text;
}

class PlaylistItemRow extends PlaylistRow {
  const PlaylistItemRow({
    required this.index,
    required this.number,
    required this.label,
  });

  /// Index into `Playlist.items` (what tap-to-play receives).
  final int index;

  /// Episode number within the season when known, else position in it.
  final String number;
  final String label;
}

final _generic = RegExp(r'^(?:Episode|Special)(?: \d+)?$');
final _extRe = RegExp(r'\.[A-Za-z0-9]{2,4}$');

String _cap(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

/// Season names for a [Playlist]'s `seasons` map, kept distinct from each
/// other, plus episode lines / grouped rows built on them.
class PlaylistLabels {
  PlaylistLabels(this.playlist, this.showName)
    : _names = seasonNames(playlist.seasons.values);

  final Playlist playlist;
  final String showName;
  final Map<int, String> _names;

  /// Header text for [seasonId]; null when the season is unknown.
  String? seasonName(int? seasonId) => _names[seasonId];

  /// Rows in display order: a header whenever the season changes, then its
  /// items. Without season data there are only item rows (flat list).
  List<PlaylistRow> rows() {
    final out = <PlaylistRow>[];
    int? cur;
    var inSeason = 0;
    for (var i = 0; i < playlist.length; i++) {
      final f = playlist.items[i];
      final name = seasonName(f.seasonId);
      if (name != null && (out.isEmpty || f.seasonId != cur)) {
        out.add(PlaylistHeaderRow(name));
        inSeason = 0;
      }
      cur = f.seasonId;
      inSeason++;
      out.add(
        PlaylistItemRow(
          index: i,
          number: _number(f, inSeason),
          label: rowLabel(f),
        ),
      );
    }
    return out;
  }

  String _number(MediaFile f, int position) {
    final e = f.episode;
    if (e == null) return '$position';
    final end = f.episodeEnd;
    return end != null && end != e ? '$e-$end' : '$e';
  }

  bool _special(MediaFile f) =>
      playlist.seasons[f.seasonId]?.number == 0 && f.seasonId != null;

  /// Row text: episode title, or `Episode N` / `Special N`; non-episodes
  /// (movie files) keep their file name.
  String rowLabel(MediaFile f) => f.seasonId == null
      ? f.name.replaceFirst(_extRe, '')
      : cleanEpisodeTitle(
          f.name,
          showName,
          episode: f.episode,
          special: _special(f),
        );

  /// Line under the video, e.g. `Season 2 · Episode 3 · The Heist`.
  String line(MediaFile f) {
    final season = seasonName(f.seasonId);
    if (season == null) return rowLabel(f);
    final e = f.episode;
    final end = f.episodeEnd;
    final title = rowLabel(f);
    final real = _generic.hasMatch(title) ? null : title;
    return [
      season,
      if (e != null) end != null && end != e ? 'Episode $e-$end' : 'Episode $e',
      ?real ?? (e == null ? f.name.replaceFirst(_extRe, '') : null),
    ].join(' · ');
  }
}

/// Distinct display names for [seasons], by `Season.id`.
///
/// `Season N` (number > 0); number 0 is `Specials`, or its folder label when
/// that is something specific (e.g. `OVA`). When several seasons would read
/// the same (language variants of one number) the language is appended, then
/// the folder label, then an ordinal as last resort.
Map<int, String> seasonNames(Iterable<Season> seasons) {
  final list = [...seasons]..sort((a, b) => a.id.compareTo(b.id));
  String base(Season s) {
    if (s.number > 0) return 'Season ${s.number}';
    final l = s.label.trim();
    final generic =
        l.isEmpty ||
        RegExp(r'^(?:other|specials?)$', caseSensitive: false).hasMatch(l);
    return generic ? 'Specials' : l;
  }

  final names = {for (final s in list) s.id: base(s)};
  Map<String, List<Season>> groups() {
    final g = <String, List<Season>>{};
    for (final s in list) {
      g.putIfAbsent(names[s.id]!, () => []).add(s);
    }
    return g;
  }

  for (final g in groups().values.where((g) => g.length > 1)) {
    for (final s in g) {
      final lang = s.language;
      if (lang != null && lang.isNotEmpty) {
        names[s.id] = '${names[s.id]} · ${_cap(lang)}';
      }
    }
  }
  for (final g in groups().values.where((g) => g.length > 1)) {
    for (final s in g) {
      final l = s.label.trim();
      if (l.isNotEmpty && !names[s.id]!.contains(l)) {
        names[s.id] = '${names[s.id]} · $l';
      }
    }
  }
  for (final g in groups().values.where((g) => g.length > 1)) {
    for (var k = 0; k < g.length; k++) {
      names[g[k].id] = '${names[g[k].id]} (${k + 1})';
    }
  }
  return names;
}
