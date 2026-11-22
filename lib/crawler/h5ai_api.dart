// Client for the h5ai JSON API (`POST /_h5ai/public/index.php`).
//
// One call with `what: 2` returns a folder's children AND grandchildren as a
// flat item list (plus the siblings of every ancestor, which we drop). Folders
// carry `fetched`: whether their own children are in the response. We rebuild
// a tree from it. See CLAUDE.md for why `what: 2` must only be used on
// category roots / year or bucket folders, never on many small folders inside
// one huge directory (every response repeats the ancestors' siblings).
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:watchdog/crawler/host_limiter.dart';
import 'package:watchdog/crawler/listing_client.dart';

enum ApiFailure {
  /// Host has no usable JSON API (404/405/501, HTML or non-JSON answer).
  unsupported,

  /// 200 but the body is not the expected shape.
  badResponse,

  /// The requested folder is not in the answer (unknown / hidden path).
  notFound,
  timeout,
  connect,
  http,
}

/// Typed API error. It is a [FetchException], so existing retry / dead-host
/// handling (`retryable`, `noAnswer`) applies unchanged.
class ApiException extends FetchException {
  const ApiException(
    super.url,
    super.kind,
    super.message,
    this.reason, {
    super.status,
  });
  final ApiFailure reason;

  @override
  String toString() => 'ApiException($reason, $url: $message)';
}

/// One entry of an API answer.
class ApiItem {
  const ApiItem({
    required this.name,
    required this.href,
    required this.isFolder,
    this.time,
    this.size,
    this.children,
  });

  /// Decoded last path segment.
  final String name;

  /// Absolute path as served (percent-encoded); folders end with '/'.
  final String href;
  final bool isFolder;

  /// Modification time, exact epoch ms read as UTC.
  final DateTime? time;

  /// Bytes (files only). The HTML listing shows the same as KB = bytes/1000.
  final int? size;

  /// Listed children; null when the answer did not list this folder (or for
  /// files). Empty list = listed and empty.
  final List<ApiItem>? children;

  bool get isListed => children != null;

  /// [time] the way the HTML listing parser would have produced it: the
  /// minute-truncated server wall clock (UTC) read as a *local* DateTime.
  /// Equal to `Entry.modified` for the same folder, so fingerprints from
  /// either source compare equal.
  DateTime? get timeAsListing {
    final t = time;
    return t == null
        ? null
        : DateTime(t.year, t.month, t.day, t.hour, t.minute);
  }

  Iterable<ApiItem> get folders =>
      (children ?? const <ApiItem>[]).where((c) => c.isFolder);
  Iterable<ApiItem> get files =>
      (children ?? const <ApiItem>[]).where((c) => !c.isFolder);

  @override
  String toString() =>
      'ApiItem($href${children == null ? '' : ', ${children!.length} children'})';
}

/// Result of the capability probe for one host.
class ApiProbe {
  const ApiProbe(this.host, this.supported, {this.reason, this.message});
  final String host;
  final bool supported;
  final ApiFailure? reason;
  final String? message;
}

/// Percent-encodes decoded path [segments] like PHP `rawurlencode` per
/// segment: `/a/b c/` from `['a', 'b c']`. Folders get a trailing '/'.
String encodeHref(Iterable<String> segments, {bool folder = true}) {
  final b = StringBuffer('/');
  for (final s in segments) {
    b
      ..write(Uri.encodeComponent(s))
      ..write('/');
  }
  final r = b.toString();
  return folder || r == '/' ? r : r.substring(0, r.length - 1);
}

String _decode(String s) {
  if (!s.contains('%')) return s;
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

String _nameOf(String href) {
  var e = href.length;
  if (e > 1 && href.codeUnitAt(e - 1) == 0x2f) e--;
  final i = href.lastIndexOf('/', e - 1);
  return _decode(href.substring(i + 1, e));
}

/// Canonical key (decoded, folders with trailing '/') used for parent lookup.
String _key(String href) => _decode(href);

String _parentKey(String key) {
  var e = key.length;
  if (e > 1 && key.codeUnitAt(e - 1) == 0x2f) e--;
  final i = key.lastIndexOf('/', e - 1);
  return i < 0 ? '/' : key.substring(0, i + 1);
}

/// Builds the tree below [requestedHref] from an API body. Pure; runs in an
/// isolate for big bodies. Throws [FormatException] on a wrong shape and
/// [StateError] when the folder is absent from the answer.
ApiItem parseApiTree(Uint8List body, String requestedHref) {
  final dynamic j = jsonDecode(utf8.decode(body, allowMalformed: true));
  if (j is! Map || j['items'] is! List) {
    throw const FormatException('no items list');
  }
  final root = _key(
    requestedHref.endsWith('/') ? requestedHref : '$requestedHref/',
  );
  final byParent = <String, List<Map>>{};
  Map? rootRaw;
  for (final raw in (j['items'] as List).cast<Map>()) {
    final href = raw['href'];
    if (href is! String) throw const FormatException('item without href');
    final k = _key(href);
    if (k == root) {
      rootRaw = raw;
      continue;
    }
    (byParent[_parentKey(k)] ??= []).add(raw);
  }
  if (rootRaw == null) throw StateError('folder not in answer');

  ApiItem build(Map raw) {
    final href = raw['href'] as String;
    final isFolder = href.endsWith('/');
    final t = raw['time'];
    final s = raw['size'];
    List<ApiItem>? kids;
    if (isFolder && raw['fetched'] == true) {
      kids = [for (final c in byParent[_key(href)] ?? const <Map>[]) build(c)];
    }
    return ApiItem(
      name: _nameOf(href),
      href: href,
      isFolder: isFolder,
      time: t is num
          ? DateTime.fromMillisecondsSinceEpoch(t.toInt(), isUtc: true)
          : null,
      size: s is num ? s.toInt() : null,
      children: kids,
    );
  }

  // The requested folder is listed by definition (what >= 1); for what=0 it
  // simply has no children in the answer.
  final built = build(rootRaw);
  return ApiItem(
    name: built.name,
    href: built.href,
    isFolder: true,
    time: built.time,
    size: built.size,
    children:
        built.children ??
        [for (final c in byParent[root] ?? const <Map>[]) build(c)],
  );
}

Future<ApiItem> _parseOffIsolate(Uint8List body, String href) =>
    Isolate.run(() => parseApiTree(body, href));

class H5aiApiClient {
  H5aiApiClient({
    http.Client? client,
    this.limiters,
    this.timeout = const Duration(seconds: 30),
    this.probeTimeout = const Duration(seconds: 5),
    this.retries = 2,
    this.backoffBase = const Duration(milliseconds: 400),
    this.decodeOffloadBytes = 64 * 1024,
    this.endpointPath = '/_h5ai/public/index.php',
  }) : _client =
           client ??
           IOClient(
             io.HttpClient()
               ..connectionTimeout = const Duration(seconds: 5)
               ..userAgent = 'watchdog-crawler',
           );

  final http.Client _client;

  /// Optional shared per-host concurrency/latency control.
  final HostLimiters? limiters;
  final Duration timeout, probeTimeout, backoffBase;

  /// Retries after the first attempt, for network trouble / 5xx / 429.
  final int retries;

  /// Bodies larger than this are decoded in a short-lived isolate.
  final int decodeOffloadBytes;
  final String endpointPath;

  final _probes = <String, Future<ApiProbe>>{};

  int requests = 0, bytes = 0;

  Uri _endpoint(String host) => Uri.parse('http://$host$endpointPath');

  /// Probes [host] once per client lifetime (`what = 0`). Never throws.
  Future<ApiProbe> probe(String host, {String href = '/'}) =>
      _probes[host] ??= _probe(host, href);

  /// Whether the JSON API works on [host]; cached for the life of this
  /// client ("per run"). False also when the host does not answer: the
  /// caller then uses the HTML crawler, which reports the real network error.
  Future<bool> supportsApi(String host, {String href = '/'}) async =>
      (await probe(host, href: href)).supported;

  /// Drops the cached probe (all hosts, or one).
  void forgetProbe([String? host]) =>
      host == null ? _probes.clear() : _probes.remove(host);

  /// Marks a host unusable for the rest of the run (e.g. repeated
  /// [ApiFailure.badResponse]); later [supportsApi] answers false.
  void markUnsupported(String host, [String? why]) =>
      _probes[host] = Future.value(
        ApiProbe(host, false, reason: ApiFailure.unsupported, message: why),
      );

  Future<ApiProbe> _probe(String host, String href) async {
    try {
      final r = await _post(host, href, 0, probeTimeout, null);
      final dynamic j = jsonDecode(utf8.decode(r, allowMalformed: true));
      if (j is Map && j['items'] is List) return ApiProbe(host, true);
      return ApiProbe(
        host,
        false,
        reason: ApiFailure.unsupported,
        message: 'no items list',
      );
    } on ApiException catch (e) {
      return ApiProbe(host, false, reason: e.reason, message: e.message);
    } on FormatException catch (e) {
      return ApiProbe(
        host,
        false,
        reason: ApiFailure.unsupported,
        message: 'not JSON: ${e.message}',
      );
    }
  }

  /// Folder at [url] (absolute `http://host/path/`, percent-encoded as in
  /// the crawl config) with children and, for [what] = 2, grandchildren.
  /// [what] is capped at 2 by the server. Throws [ApiException].
  Future<ApiItem> getFolder(Uri url, {int what = 2}) async {
    final href = url.path.endsWith('/') ? url.path : '${url.path}/';
    final host = url.hasPort ? '${url.host}:${url.port}' : url.host;
    final body = await _post(
      host,
      href,
      what.clamp(0, 2),
      timeout,
      _endpoint(host),
      retry: true,
    );
    try {
      return body.length > decodeOffloadBytes
          ? await _parseOffIsolate(body, href)
          : parseApiTree(body, href);
    } on StateError {
      throw ApiException(
        url,
        FetchFailure.other,
        'folder not in answer (empty or forbidden)',
        ApiFailure.notFound,
      );
    } on FormatException catch (e) {
      throw ApiException(
        url,
        FetchFailure.other,
        'bad API answer: ${e.message}',
        ApiFailure.badResponse,
      );
    } on TypeError catch (e) {
      throw ApiException(
        url,
        FetchFailure.other,
        'bad API answer: $e',
        ApiFailure.badResponse,
      );
    }
  }

  Future<Uint8List> _post(
    String host,
    String href,
    int what,
    Duration timeout,
    Uri? endpoint, {
    bool retry = false,
  }) async {
    final url = endpoint ?? _endpoint(host);
    final payload = utf8.encode(
      jsonEncode({
        'action': 'get',
        'items': {'href': href, 'what': what},
      }),
    );
    var attempt = 0;
    while (true) {
      try {
        final lim = limiters?.forHost(host);
        Future<Uint8List> go() => _once(url, payload, timeout);
        return await (lim == null ? go() : lim.run(go));
      } on ApiException catch (e) {
        if (!retry || !e.retryable || attempt >= retries) rethrow;
        attempt++;
        await Future<void>.delayed(backoffBase * (1 << (attempt - 1)));
      }
    }
  }

  Future<Uint8List> _once(Uri url, List<int> payload, Duration timeout) async {
    requests++;
    try {
      final res = await _client
          .post(
            url,
            headers: const {'content-type': 'application/json'},
            body: payload,
          )
          .timeout(timeout);
      bytes += res.bodyBytes.length;
      if (res.statusCode != 200) {
        final unsupported = const {404, 405, 501}.contains(res.statusCode);
        throw ApiException(
          url,
          FetchFailure.http,
          'HTTP ${res.statusCode}',
          unsupported ? ApiFailure.unsupported : ApiFailure.http,
          status: res.statusCode,
        );
      }
      return res.bodyBytes;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        url,
        FetchFailure.timeout,
        'timed out after ${timeout.inSeconds}s',
        ApiFailure.timeout,
      );
    } on io.SocketException catch (e) {
      throw ApiException(
        url,
        FetchFailure.connect,
        e.message,
        ApiFailure.connect,
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        url,
        FetchFailure.connect,
        e.message,
        ApiFailure.connect,
      );
    } on io.HttpException catch (e) {
      throw ApiException(url, FetchFailure.other, e.message, ApiFailure.http);
    }
  }

  void close() => _client.close();
}
