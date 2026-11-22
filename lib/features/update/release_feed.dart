/// Release discovery without the GitHub REST API.
///
/// The anonymous API allows 60 requests per hour per IP address, and many
/// mobile / shared connections exhaust that. The public `releases.atom` feed
/// and the `expanded_assets` fragment are plain web pages without that limit,
/// so the updater falls back to them. Pure Dart, no I/O.
library;

/// One `<entry>` of `https://github.com/<repo>/releases.atom`.
class FeedEntry {
  const FeedEntry({
    required this.tag,
    required this.title,
    required this.pageUrl,
    required this.notes,
  });

  /// Git tag, e.g. `v0.3.0` (percent-decoded).
  final String tag;
  final String title;
  final String pageUrl;

  /// Release notes as plain text (the feed carries escaped HTML).
  final String notes;
}

/// An asset link of a release page (`/releases/download/<tag>/<name>`).
class FeedAsset {
  const FeedAsset({required this.name, required this.url});
  final String name;

  /// Absolute https URL.
  final String url;
}

final _entryRe = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
final _linkRe = RegExp(r'<link\b[^>]*>', dotAll: true);
final _titleRe = RegExp(r'<title>(.*?)</title>', dotAll: true);
final _contentRe = RegExp(r'<content\b[^>]*>(.*?)</content>', dotAll: true);
final _tagInHrefRe = RegExp(r'/releases/tag/([^"?#/]+)');
final _hrefRe = RegExp(r'href="([^"]+)"');
final _relAltRe = RegExp(r'rel="alternate"');

/// Entries of a GitHub releases Atom feed, newest first as served.
/// Entries without a tag link are skipped.
List<FeedEntry> parseReleasesFeed(String xml) {
  final out = <FeedEntry>[];
  for (final m in _entryRe.allMatches(xml)) {
    final body = m.group(1)!;
    String? href;
    for (final l in _linkRe.allMatches(body)) {
      final tag = l.group(0)!;
      if (_relAltRe.hasMatch(tag)) {
        href = _hrefRe.firstMatch(tag)?.group(1);
        break;
      }
    }
    if (href == null) continue;
    final tagMatch = _tagInHrefRe.firstMatch(href);
    if (tagMatch == null) continue;
    final title = _titleRe.firstMatch(body)?.group(1) ?? '';
    final content = _contentRe.firstMatch(body)?.group(1) ?? '';
    out.add(
      FeedEntry(
        tag: Uri.decodeComponent(tagMatch.group(1)!),
        title: _xmlUnescape(title).trim(),
        pageUrl: _xmlUnescape(href),
        notes: htmlToText(_xmlUnescape(content)),
      ),
    );
  }
  return out;
}

/// Download links of a release (`.../releases/expanded_assets/<tag>` HTML),
/// source archives excluded.
List<FeedAsset> parseExpandedAssets(String html) {
  final out = <FeedAsset>[];
  final seen = <String>{};
  for (final m in _hrefRe.allMatches(html)) {
    final href = _xmlUnescape(m.group(1)!);
    if (!href.contains('/releases/download/')) continue;
    final url = href.startsWith('http') ? href : 'https://github.com$href';
    if (!seen.add(url)) continue;
    final last = Uri.parse(url).pathSegments.last;
    out.add(FeedAsset(name: Uri.decodeComponent(last), url: url));
  }
  return out;
}

/// The APK to install: one whose name mentions [abi], else the first `.apk`.
FeedAsset? pickApk(List<FeedAsset> assets, {String abi = 'arm64'}) {
  final apks = [
    for (final a in assets)
      if (a.name.toLowerCase().endsWith('.apk')) a,
  ];
  if (apks.isEmpty) return null;
  return apks
          .where((a) => a.name.toLowerCase().contains(abi.toLowerCase()))
          .firstOrNull ??
      apks.first;
}

/// The checksum file that belongs to [apk] (`<apk name>.sha256`), if attached.
FeedAsset? pickChecksum(List<FeedAsset> assets, FeedAsset apk) {
  final want = '${apk.name}.sha256'.toLowerCase();
  return assets.where((a) => a.name.toLowerCase() == want).firstOrNull;
}

final _hex64 = RegExp(r'\b([0-9a-fA-F]{64})\b');

/// Lower-case SHA-256 from the contents of a `sha256sum` style file.
String? parseSha256File(String text) =>
    _hex64.firstMatch(text)?.group(1)?.toLowerCase();

String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Rough HTML -> text for release notes (lists, headings, paragraphs).
String htmlToText(String html) {
  var t = html
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '\n- ')
      .replaceAll(
        RegExp(r'</\s*(p|h[1-6]|ul|ol|div)\s*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]+>'), '');
  t = _xmlUnescape(t);
  return t
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
