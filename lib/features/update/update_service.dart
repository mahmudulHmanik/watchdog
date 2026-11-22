import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'release.dart';

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

/// Checks GitHub Releases and downloads the APK of a newer one.
class UpdateService {
  UpdateService({http.Client? client, this.repo = 'mahmudulHmanik/watchdog'})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// `owner/name`.
  final String repo;

  static const _headers = {
    'Accept': 'application/vnd.github+json',
    // GitHub rejects requests without a User-Agent; keep it generic.
    'User-Agent': 'watchdog-updater',
  };

  /// The newest release if it is newer than [currentVersion], else null.
  /// Throws [UpdateException] when GitHub cannot be reached or answers badly.
  Future<ReleaseInfo?> check({
    required String currentVersion,
    bool prerelease = true,
  }) async {
    final http.Response res;
    try {
      res = await _client
          .get(
            Uri.https('api.github.com', '/repos/$repo/releases', {
              'per_page': '15',
            }),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const UpdateException('GitHub did not answer in time');
    } on SocketException {
      throw const UpdateException('Cannot reach GitHub. Check your internet.');
    } on http.ClientException catch (e) {
      throw UpdateException('Cannot reach GitHub: ${e.message}');
    }
    if (res.statusCode == 403 || res.statusCode == 429) {
      throw const UpdateException('GitHub rate limit hit. Try again later.');
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
    final name = (r.apkName ?? 'watchdog-${r.version}.apk').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
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
