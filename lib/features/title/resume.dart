import 'package:watchdog/data/models.dart';

/// Display order: numbered seasons first, specials (number 0) last.
List<SeasonEpisodes> displayOrder(List<SeasonEpisodes> seasons) => [
  ...seasons.where((s) => s.season.number != 0),
  ...seasons.where((s) => s.season.number == 0),
];

/// First playable episode that is not watched (in-progress ones included),
/// scanning in display order; falls back to the first playable (rewatch).
MediaFile? pickResume(
  List<SeasonEpisodes> seasons,
  Map<int, WatchState> states,
) {
  MediaFile? first;
  for (final s in displayOrder(seasons)) {
    for (final f in s.files) {
      if (!f.playable) continue;
      first ??= f;
      if (!(states[f.id]?.watched ?? false)) return f;
    }
  }
  return first;
}

String episodeLabel(MediaFile f) {
  String two(int v) => v.toString().padLeft(2, '0');
  final e = f.episode;
  if (e == null) return '';
  final end = f.episodeEnd;
  return end != null && end != e ? 'E${two(e)}-E${two(end)}' : 'E${two(e)}';
}

String seasonLabel(Season s) {
  final base = s.number == 0 ? 'Specials' : s.label;
  return s.language == null ? base : '$base · ${s.language}';
}
