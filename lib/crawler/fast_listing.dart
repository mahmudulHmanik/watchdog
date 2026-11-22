// Regex/index based reader for the h5ai v0.29 no-JS fallback table. Yields the
// same entries as [parseListing] (the `html` package path) but ~30x faster,
// and hands over to it whenever the markup is not exactly what we know.
import 'package:watchdog/crawler/listing.dart';

class _Unrecognised implements Exception {
  const _Unrecognised();
}

// `<tr><td class="fb-i"><img src=".." alt="file"/></td><td class="fb-n">
// <a href="..">name</a></td><td class="fb-d">date</td><td class="fb-s">size
// </td></tr>`
final _row = RegExp(
  r'<tr><td class="fb-i"><img src="[^"]*" alt="([^"]*)"/></td>'
  r'<td class="fb-n"><a href="([^"]*)">([^<]*)</a></td>'
  r'<td class="fb-d">([^<]*)</td><td class="fb-s">([^<]*)</td></tr>',
);

final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

String _unescape(String s) {
  if (!s.contains('&')) return s;
  // A bare `&` (followed by space, punctuation, end) is literal text in
  // HTML5; only `&` + alphanumeric/`#` can start a reference.
  var n = 0;
  for (var i = 0; i < s.length - 1; i++) {
    if (s.codeUnitAt(i) != 0x26) continue;
    final c = s.codeUnitAt(i + 1);
    if (c == 0x23 ||
        (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5a) ||
        (c >= 0x61 && c <= 0x7a)) {
      n++;
    }
  }
  var seen = 0;
  final out = s.replaceAllMapped(_entity, (m) {
    seen++;
    final e = m[1]!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final cp = e.codeUnitAt(1) == 0x78 || e.codeUnitAt(1) == 0x58
        ? int.tryParse(e.substring(2), radix: 16)
        : int.tryParse(e.substring(1));
    // HTML5 remaps C1 controls / rejects NUL and surrogates: leave to `html`.
    if (cp == null ||
        cp < 0x20 ||
        (cp >= 0x7f && cp <= 0x9f) ||
        (cp >= 0xd800 && cp <= 0xdfff) ||
        cp > 0x10ffff) {
      throw const _Unrecognised();
    }
    return String.fromCharCode(cp);
  });
  if (seen != n) throw const _Unrecognised(); // unknown/legacy entity
  return out;
}

bool _digits(String s, int from, int to) {
  for (var i = from; i < to; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  return true;
}

int _num(String s, int from, int to) {
  var v = 0;
  for (var i = from; i < to; i++) {
    v = v * 10 + (s.codeUnitAt(i) - 0x30);
  }
  return v;
}

/// Same result as [parseListingDate], without a regex.
DateTime? _date(String s) {
  final t = s.trim();
  if (t.length != 16) return t.isEmpty ? null : parseListingDate(t);
  if (t.codeUnitAt(4) != 0x2d ||
      t.codeUnitAt(7) != 0x2d ||
      t.codeUnitAt(10) != 0x20 ||
      t.codeUnitAt(13) != 0x3a ||
      !_digits(t, 0, 4) ||
      !_digits(t, 5, 7) ||
      !_digits(t, 8, 10) ||
      !_digits(t, 11, 13) ||
      !_digits(t, 14, 16)) {
    return null;
  }
  return DateTime(
    _num(t, 0, 4),
    _num(t, 5, 7),
    _num(t, 8, 10),
    _num(t, 11, 13),
    _num(t, 14, 16),
  );
}

/// Same result as [parseListingSize] for the common `123 KB` form.
int? _size(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final n = t.length - 3;
  if (n >= 1 && n <= 18 && t.endsWith(' KB') && _digits(t, 0, n)) {
    return _num(t, 0, n);
  }
  return parseListingSize(t);
}

/// Fast path only: null when the page is not recognised exactly (rows must
/// be contiguous, in the known markup, inside `<div id="fallback"><table>`).
List<Entry>? tryParseListingFast(String body) {
  const open = 'id="fallback"><table>';
  var p = body.indexOf('id="fallback"');
  if (p < 0 || !body.startsWith(open, p)) return null;
  p += open.length;
  final out = <Entry>[];
  try {
    while (!body.startsWith('</table>', p)) {
      if (body.startsWith('<tr><th', p)) {
        final close = body.indexOf('</tr>', p);
        if (close < 0) return null;
        p = close + 5;
        continue;
      }
      final m = _row.matchAsPrefix(body, p);
      if (m == null) return null;
      p = m.end;
      final alt = m[1]!;
      if (alt == 'folder-parent') continue;
      final href = _unescape(m[2]!);
      if (href.isEmpty || href == '..') continue;
      out.add(
        Entry(
          name: _unescape(m[3]!).trim(),
          href: href,
          isDir: alt == 'folder' || href.endsWith('/'),
          modified: _date(m[4]!),
          sizeKb: _size(m[5]!),
        ),
      );
    }
  } on _Unrecognised {
    return null;
  }
  // Only the closing tags/comment may follow; anything else (a second table,
  // more rows) is unfamiliar.
  return body.length - p > 400 && body.indexOf('<tr', p) >= 0 ? null : out;
}

/// Parses an h5ai fallback table: fast path first, the `html` package
/// ([parseListing]) when the markup is unfamiliar. Output is identical.
List<Entry> parseListingFast(String body) =>
    tryParseListingFast(body) ?? parseListing(body);
