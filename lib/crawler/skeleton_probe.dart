// Cheap "did anything change?" probe for incremental runs, plus size
// estimates for progress. One `what = 2` request on the category root lists
// its children AND grandchildren (names + mtimes, no files): enough to hash
// every top-level group (year bucket, language folder, promotion, ...) and to
// count titles. A group whose signature equals the stored one is skipped; only
// changed groups are re-read (see SkeletonCrawler `only`).
import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/classifier.dart'
    show FolderNode, NodeFile, looksLikeShow;
import 'package:watchdog/crawler/h5ai_api.dart';
import 'package:watchdog/crawler/parsing.dart' show isExtrasFolder;

/// Layouts whose groups are tracked with signatures. Series and flat
/// categories are re-read in full (a handful of requests) and compared per
/// title instead: a show's change fingerprint needs its season folders, which
/// the bucket level answer already lists.
bool usesGroupSignatures(CategoryConfig cat) =>
    cat.layout == LayoutKind.yearBuckets || cat.layout == LayoutKind.events;

class CategoryProbe {
  const CategoryProbe({
    required this.signatures,
    required this.estimatedTitles,
    required this.folders,
  });

  /// Child folder href (as served) -> signature of its listing.
  final Map<String, int> signatures;

  /// Rough number of titles in the category (progress estimate only).
  final int estimatedTitles;

  /// Child folders found under the root (non-extras).
  final int folders;
}

const _mask = 0xFFFFFFFFFFFFF; // 52 bits: exact in JSON / JS doubles
const _prime = 1099511628211;

int _mix(int h, String s) {
  for (var i = 0; i < s.length; i++) {
    h = ((h ^ s.codeUnitAt(i)) * _prime) & _mask;
  }
  return ((h ^ 0x7c) * _prime) & _mask;
}

int _mixInt(int h, int? v) => _mix(h, v == null ? '-' : '$v');

/// Signature of a listed folder: its own time and every entry's href + time
/// (+ size for files). Order independent of the server's sorting.
int groupSignature(ApiItem g) {
  final parts = <String>[
    for (final c in g.children ?? const <ApiItem>[])
      if (!(c.isFolder && isExtrasFolder(c.name)))
        '${c.href}|${c.time?.millisecondsSinceEpoch}|${c.isFolder ? '' : c.size}',
  ]..sort();
  var h = 0xcbf29ce484222 & _mask;
  h = _mixInt(h, g.time?.millisecondsSinceEpoch);
  for (final p in parts) {
    h = _mix(h, p);
  }
  return h;
}

FolderNode _shallow(ApiItem n) => FolderNode(
  name: n.name,
  url: n.href,
  mtime: n.time,
  files: [
    for (final f in n.files) NodeFile(name: f.name, url: f.href, mtime: f.time),
  ],
  folders: [for (final f in n.folders) FolderNode(name: f.name, url: f.href)],
);

/// Estimated title count from a `what = 2` root answer. For year-bucket
/// roots fetched with `what = 1` the answer says nothing about titles: use
/// [probeCategory] instead.
int estimateTitles(ApiItem root, CategoryConfig cat) {
  var n = 0;
  for (final c in root.folders) {
    if (isExtrasFolder(c.name)) continue;
    if (!c.isListed) {
      n++;
      continue;
    }
    switch (cat.layout) {
      case LayoutKind.flat:
        n++;
      case LayoutKind.series:
        n += looksLikeShow(_shallow(c))
            ? 1
            : c.folders.where((f) => !isExtrasFolder(f.name)).length;
      case LayoutKind.yearBuckets || LayoutKind.events:
        final kids = c.folders.where((f) => !isExtrasFolder(f.name)).length;
        // A title folder directly under the root (has files) counts itself.
        n += kids > 0 ? kids : (c.files.isNotEmpty ? 1 : 0);
    }
  }
  return n;
}

/// Pure: signatures + estimate from the root answer (`what = 2`).
CategoryProbe probeFromRoot(ApiItem root, CategoryConfig cat) => CategoryProbe(
  signatures: {
    for (final c in root.folders)
      if (!isExtrasFolder(c.name) && c.isListed) c.href: groupSignature(c),
  },
  estimatedTitles: estimateTitles(root, cat),
  folders: root.folders.where((c) => !isExtrasFolder(c.name)).length,
);

/// One `what = 2` request on [cat]'s root. Throws [ApiException].
Future<CategoryProbe> probeCategory(
  H5aiApiClient api,
  CategoryConfig cat,
) async {
  final url = Uri.parse(cat.url.endsWith('/') ? cat.url : '${cat.url}/');
  return probeFromRoot(await api.getFolder(url, what: 2), cat);
}
