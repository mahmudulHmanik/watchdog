import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'release.dart';
import 'release_feed.dart';
import 'update_cleanup.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Cooperative cancel flag for [UpdateService.download].
class CancelToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// File name an update APK is stored under in the update dir.
String apkFileName(ReleaseInfo r) => (r.apkName ?? 'watchdog-${r.version}.apk')
    .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

/// Checks GitHub Releases and downloads the APK of a newer one.
class UpdateService {
  UpdateService({
    http.Client? client,
    this.repo = 'mahmudulHmanik/watchdog',
    this.guard,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// The APK being installed (if any) is never deleted by cleanup.
  final InstallGuard? guard;

  /// `owner/name`.
  final String repo;

  static const _headers = {
    'Accept': 'application/vnd.github+json',
    // GitHub rejects requests without a User-Agent; keep it generic.
    'User-Agent': 'watchdog-updater',
  };

  /// The newest release if it is newer than [currentVersion], else null.
  /// Throws [UpdateException] when GitHub cannot be reached or answers badly.
  ///
  /// Asks the REST API first (full metadata in one request). Its anonymous
  /// limit is 60 requests/hour per IP, which shared and mobile connections
  /// often exhaust, so any API failure falls back to the public release feed
  /// (no such limit). The feed cannot tell pre-releases apart, so the
  /// fallback is only used when pre-releases are wanted.
  Future<ReleaseInfo?> check({
    required String currentVersion,
    bool prerelease = true,
  }) async {
    UpdateException apiError;
    try {
      return await _checkApi(currentVersion, prerelease);
    } on UpdateException catch (e) {
      apiError = e;
    }
    if (!prerelease) throw apiError;
    try {
      return await _checkFeed(currentVersion);
    } on UpdateException catch (feedError) {
      // Keep the most useful message: the rate-limit one explains why.
      throw _rateLimited(apiError) ? apiError : feedError;
    }
  }

  static const _rateLimitMessage = 'GitHub rate limit hit. Try again later.';
  bool _rateLimited(UpdateException e) => e.message == _rateLimitMessage;

  Future<http.Response> _fetch(
    Uri url, {
    String accept = 'application/vnd.github+json',
  }) async {
    try {
      return await _client
          .get(url, headers: {..._headers, 'Accept': accept})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const UpdateException('GitHub did not answer in time');
    } on SocketException {
      throw const UpdateException('Cannot reach GitHub. Check your internet.');
    } on http.ClientException catch (e) {
      throw UpdateException('Cannot reach GitHub: ${e.message}');
    }
  }

  Future<ReleaseInfo?> _checkApi(String currentVersion, bool prerelease) async {
    final res = await _fetch(
      Uri.https('api.github.com', '/repos/$repo/releases', {'per_page': '15'}),
    );
    if (res.statusCode == 403 || res.statusCode == 429) {
      throw const UpdateException(_rateLimitMessage);
    }
    if (res.statusCode != 200) {
      throw UpdateException('GitHub answered ${res.statusCode}');
    }
    final Object? json;
    try {
      json = jsonDecode(res.body);
    } on FormatException {
      throw const UpdateException('Unreadable answer from GitHub');
    }
    final r = pickRelease(json, prerelease: prerelease);
    return r != null && isNewer(r, currentVersion) ? r : null;
  }

  /// Same answer from the public web pages: the releases Atom feed, then the
  /// asset list and checksum file of the newest release only if it is newer.
  Future<ReleaseInfo?> _checkFeed(String currentVersion) async {
    final res = await _fetch(
      Uri.https('github.com', '/$repo/releases.atom'),
      accept: 'application/atom+xml',
    );
    if (res.statusCode != 200) {
      throw UpdateException(
        res.statusCode == 403 || res.statusCode == 429
            ? _rateLimitMessage
            : 'GitHub answered ${res.statusCode}',
      );
    }
    final body = utf8.decode(res.bodyBytes);
    // A real feed (even one with no releases yet) has a <feed> root; anything
    // else is an error page or garbage, not "you are up to date".
    if (!body.contains('<feed')) {
      throw const UpdateException('Unreadable answer from GitHub');
    }
    final entries = [
      for (final e in parseReleasesFeed(body))
        if (parseVersion(e.tag) != null) e,
    ]..sort((a, b) => compareVersions(b.tag, a.tag));
    // Newest first; the first one with an APK attached wins (like the API).
    for (final e in entries.take(3)) {
      if (compareVersions(e.tag, currentVersion) <= 0) return null;
      final tag = Uri.encodeComponent(e.tag);
      final page = await _fetch(
        Uri.https('github.com', '/$repo/releases/expanded_assets/$tag'),
        accept: 'text/html',
      );
      if (page.statusCode != 200) continue;
      final assets = parseExpandedAssets(utf8.decode(page.bodyBytes));
      final apk = pickApk(assets);
      if (apk == null) continue;
      String? sum;
      final sumAsset = pickChecksum(assets, apk);
      if (sumAsset != null) {
        try {
          final f = await _fetch(Uri.parse(sumAsset.url), accept: 'text/plain');
          if (f.statusCode == 200) {
            sum = parseSha256File(utf8.decode(f.bodyBytes));
          }
        } on UpdateException {
          sum = null; // unverified checksum is skipped, like a missing digest
        }
      }
      return ReleaseInfo(
        tag: e.tag,
        version: e.tag.replaceFirst(RegExp(r'^v'), ''),
        notes: e.notes,
        pageUrl: e.pageUrl,
        apkUrl: apk.url,
        apkName: apk.name,
        sha256: sum,
      );
    }
    return null;
  }

  /// Downloads the APK of [r] into [dir] (created if needed) and returns it.
  /// A complete, verified earlier download is reused. The file only gets its
  /// final name after the size / SHA-256 checks pass.
  Future<File> download(
    ReleaseInfo r,
    Directory dir, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final url = r.apkUrl;
    if (url == null) throw const UpdateException('No APK attached to release');
    dir.createSync(recursive: true);
    final name = apkFileName(r);
    // Older update APKs are ~37 MB each; keep only the one we may reuse.
    await cleanBeforeDownload(dir, keepName: name, guard: guard);
    final done = File('${dir.path}/$name');
    if (done.existsSync() && await _ok(done, r)) {
      onProgress?.call(done.lengthSync(), done.lengthSync());
      return done;
    }
    final part = File('${done.path}.part');
    if (part.existsSync()) part.deleteSync();

    final req = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = _headers['User-Agent']!;
    final http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const UpdateException('Download did not start in time');
    } on SocketException {
      throw const UpdateException('Download failed: no connection');
    } on http.ClientException catch (e) {
      throw UpdateException('Download failed: ${e.message}');
    }
    if (res.statusCode != 200) {
      throw UpdateException('Download failed (HTTP ${res.statusCode})');
    }
    final total = res.contentLength ?? r.apkSize ?? -1;
    final sink = part.openWrite();
    final digestOut = _DigestSink();
    final hash = sha256.startChunkedConversion(digestOut);
    var got = 0;
    try {
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (cancel?.cancelled ?? false) {
          throw const UpdateException('Cancelled');
        }
        sink.add(chunk);
        hash.add(chunk);
        got += chunk.length;
        onProgress?.call(got, total);
      }
      await sink.flush();
      await sink.close();
      hash.close();
    } on TimeoutException {
      await _drop(sink, part);
      throw const UpdateException('Download stalled');
    } catch (e) {
      await _drop(sink, part);
      if (e is UpdateException) rethrow;
      throw UpdateException('Download failed: $e');
    }
    final sum = '${digestOut.value}';
    final expectSize = r.apkSize;
    if ((expectSize != null && got != expectSize) ||
        (r.sha256 != null && sum != r.sha256)) {
      part.deleteSync();
      throw const UpdateException(
        'Downloaded file is corrupt (checksum mismatch). Try again.',
      );
    }
    if (done.existsSync()) done.deleteSync();
    return part.renameSync(done.path);
  }

  Future<bool> _ok(File f, ReleaseInfo r) async {
    final size = r.apkSize;
    if (size != null && f.lengthSync() != size) return false;
    final want = r.sha256;
    if (want == null) return size != null;
    return (await sha256.bind(f.openRead()).first).toString() == want;
  }

  Future<void> _drop(IOSink sink, File part) async {
    try {
      await sink.close();
    } catch (_) {}
    try {
      if (part.existsSync()) part.deleteSync();
    } catch (_) {}
  }

  void close() => _client.close();
}
