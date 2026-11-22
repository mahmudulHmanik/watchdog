import 'package:watchdog/data/models.dart';

String formatSizeKb(int? kb) {
  if (kb == null) return '';
  if (kb >= 1024 * 1024) return '${(kb / 1024 / 1024).toStringAsFixed(1)} GB';
  if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(0)} MB';
  return '$kb KB';
}

final _qualityRe = RegExp(
  r'(?<!\d)(2160|1440|1080|720|576|480)p',
  caseSensitive: false,
);

/// Vertical resolution parsed from a file name, e.g. 1080.
int? qualityOfName(String name) {
  final m = _qualityRe.firstMatch(name);
  return m == null ? null : int.parse(m.group(1)!);
}

String titleSubtitle(MediaTitle t) {
  final parts = <String>[
    if (t.year != null)
      t.yearEnd != null && t.yearEnd != t.year
          ? '${t.year}-${t.yearEnd}'
          : '${t.year}',
    if (t.quality != null) '${t.quality}p',
    if (t.language != null) t.language!,
    if (t.kind == TitleKind.series && t.seasonCount > 0)
      '${t.seasonCount} season${t.seasonCount == 1 ? '' : 's'}',
  ];
  return parts.join(' · ');
}

/// Local wall-clock time (stored timestamps may be UTC).
String formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final l = t.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// `24 min left`, `1h 12m left`.
String timeLeft(int positionMs, int durationMs) {
  final m = ((durationMs - positionMs) / 60000).ceil().clamp(0, 100000);
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m left' : '$m min left';
}

/// `45:21` / `1:02:03`.
String clock(int ms) {
  final s = ms ~/ 1000;
  String two(int v) => v.toString().padLeft(2, '0');
  final h = s ~/ 3600;
  return h > 0
      ? '$h:${two(s % 3600 ~/ 60)}:${two(s % 60)}'
      : '${s ~/ 60}:${two(s % 60)}';
}

final _seasonRe = RegExp(r'[Ss](\d{1,2})[ ._-]*[Ee]\d');

/// Continue-watching meta: `S02 · E05 · 24 min left` or `Movie · 1h 12m left`.
String resumeMeta(ResumeItem it) {
  final left = it.state.durationMs > 0
      ? timeLeft(it.state.positionMs, it.state.durationMs)
      : null;
  final f = it.file;
  if (f.seasonId != null || f.episode != null) {
    String two(int v) => v.toString().padLeft(2, '0');
    // Season 0 is "specials / unparsed", so a season in the file name wins
    // over it; a real folder number wins over the file name.
    final m = _seasonRe.firstMatch(f.name);
    final fromName = m != null ? int.parse(m.group(1)!) : null;
    final folder = it.seasonNumber;
    final season = (folder != null && folder != 0)
        ? folder
        : (fromName ?? folder);
    return [
      if (season == 0) 'Specials' else if (season != null) 'S${two(season)}',
      if (f.episode != null) 'E${two(f.episode!)}',
      ?left,
    ].join(' · ');
  }
  return ['Movie', ?left].join(' · ');
}

/// Human-readable byte count: `0 B`, `412 KB`, `23 MB`, `1.8 GB`.
String formatBytes(int b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
  if (b >= 1 << 20) {
    final v = b / (1 << 20);
    return '${v.toStringAsFixed(v < 10 ? 1 : 0)} MB';
  }
  if (b >= 1 << 10) return '${(b / (1 << 10)).round()} KB';
  return '$b B';
}
