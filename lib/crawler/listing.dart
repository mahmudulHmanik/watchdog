import 'package:html/parser.dart' as html;

/// One row of an h5ai directory listing.
class Entry {
  const Entry({
    required this.name,
    required this.href,
    required this.isDir,
    this.modified,
    this.sizeKb,
  });

  final String name;

  /// Absolute-path href exactly as served (percent-encoded).
  final String href;
  final bool isDir;
  final DateTime? modified;

  /// h5ai reports sizes in KB (e.g. "682735 KB"); null for folders.
  final int? sizeKb;
}

/// Parses the no-JS fallback table of an h5ai v0.29 index page.
List<Entry> parseListing(String body) {
  final doc = html.parse(body);
  final out = <Entry>[];
  for (final tr in doc.querySelectorAll('#fallback tr')) {
    final a = tr.querySelector('td.fb-n a');
    if (a == null) continue;
    final img = tr.querySelector('td.fb-i img')?.attributes['alt'] ?? '';
    if (img == 'folder-parent') continue;
    final href = a.attributes['href'] ?? '';
    if (href.isEmpty || href == '..') continue;
    out.add(
      Entry(
        name: a.text.trim(),
        href: href,
        isDir: img == 'folder' || href.endsWith('/'),
        modified: parseListingDate(
          tr.querySelector('td.fb-d')?.text.trim() ?? '',
        ),
        sizeKb: parseListingSize(
          tr.querySelector('td.fb-s')?.text.trim() ?? '',
        ),
      ),
    );
  }
  return out;
}

final _dateRe = RegExp(r'^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d)$');
final _sizeRe = RegExp(r'^(\d+)\s*KB$', caseSensitive: false);

/// `YYYY-MM-DD HH:MM` (server wall clock, which is UTC) read as a local
/// DateTime, exactly as it has always been stored.
DateTime? parseListingDate(String s) {
  final m = _dateRe.firstMatch(s);
  if (m == null) return null;
  return DateTime(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
  );
}

/// `682735 KB` -> 682735.
int? parseListingSize(String s) {
  final m = _sizeRe.firstMatch(s);
  return m == null ? null : int.parse(m[1]!);
}
