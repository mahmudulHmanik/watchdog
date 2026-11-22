/// GitHub release parsing and version comparison. Pure Dart.
library;

/// A published release that can be installed.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.apkName,
    this.apkSize,
    this.sha256,
    this.prerelease = false,
  });

  /// Git tag, e.g. `v0.2.0`.
  final String tag;

  /// Tag without the leading `v`, e.g. `0.2.0`.
  final String version;

  /// Release notes (markdown as written on GitHub).
  final String notes;

  /// Web page of the release.
  final String pageUrl;

  /// Direct download of the Android (arm64) APK; null when none attached.
  final String? apkUrl;
  final String? apkName;
  final int? apkSize;

  /// Lower-case hex SHA-256 of the APK when GitHub reports it.
  final String? sha256;
  final bool prerelease;
}

/// `major.minor.patch` from `v0.2.0`, `0.2.0+3`, `0.2.0-rc1`; null if absent.
({int major, int minor, int patch})? parseVersion(String s) {
  final m = RegExp(r'^\s*v?(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(s);
  if (m == null) return null;
  return (
    major: int.parse(m.group(1)!),
    minor: int.parse(m.group(2)!),
    patch: int.parse(m.group(3) ?? '0'),
  );
}

/// Negative / zero / positive like [Comparable]; unparsable counts as 0.0.0.
int compareVersions(String a, String b) {
  final x = parseVersion(a) ?? (major: 0, minor: 0, patch: 0);
  final y = parseVersion(b) ?? (major: 0, minor: 0, patch: 0);
  final c = x.major.compareTo(y.major);
  if (c != 0) return c;
  final d = x.minor.compareTo(y.minor);
  return d != 0 ? d : x.patch.compareTo(y.patch);
}

/// Picks the newest installable release from the GitHub
/// `GET /repos/{owner}/{repo}/releases` array.
///
/// Drafts are skipped; pre-releases only when [prerelease] is true (the
/// `/releases/latest` endpoint ignores them, which would hide v0.x builds).
/// A release needs an `.apk` asset; one whose name mentions [abi] wins over
/// other APKs of the same release.
ReleaseInfo? pickRelease(
  Object? json, {
  bool prerelease = true,
  String abi = 'arm64',
}) {
  if (json is! List) return null;
  ReleaseInfo? best;
  for (final e in json) {
    if (e is! Map) continue;
    if (e['draft'] == true) continue;
    final pre = e['prerelease'] == true;
    if (pre && !prerelease) continue;
    final tag = '${e['tag_name'] ?? ''}';
    if (parseVersion(tag) == null) continue;
    final assets = [
      for (final a in (e['assets'] as List? ?? const []))
        if (a is Map && '${a['name']}'.toLowerCase().endsWith('.apk')) a,
    ];
    if (assets.isEmpty) continue;
    final asset =
        assets
            .where((a) => '${a['name']}'.toLowerCase().contains(abi))
            .firstOrNull ??
        assets.first;
    final digest = '${asset['digest'] ?? ''}';
    final info = ReleaseInfo(
      tag: tag,
      version: tag.replaceFirst(RegExp(r'^v'), ''),
      notes: '${e['body'] ?? ''}'.trim(),
      pageUrl: '${e['html_url'] ?? ''}',
      apkUrl: asset['browser_download_url'] as String?,
      apkName: asset['name'] as String?,
      apkSize: (asset['size'] as num?)?.toInt(),
      sha256: digest.startsWith('sha256:')
          ? digest.substring(7).toLowerCase()
          : null,
      prerelease: pre,
    );
    if (best == null || compareVersions(info.tag, best.tag) > 0) best = info;
  }
  return best;
}

/// True when [r] is newer than the running [current] version (`appVersion`).
bool isNewer(ReleaseInfo r, String current) =>
    compareVersions(r.tag, current) > 0;
