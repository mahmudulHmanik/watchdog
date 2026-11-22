import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

enum FetchFailure { timeout, connect, http, other }

class FetchException implements Exception {
  const FetchException(this.url, this.kind, this.message, {this.status});
  final Uri url;
  final FetchFailure kind;
  final String message;
  final int? status;

  /// Worth another attempt: network trouble and 5xx/408/429, not 4xx.
  bool get retryable => switch (kind) {
    FetchFailure.http =>
      status != null && (status! >= 500 || status == 408 || status == 429),
    FetchFailure.other => false,
    _ => true,
  };

  /// The host did not answer at all (no HTTP response).
  bool get noAnswer =>
      kind == FetchFailure.timeout || kind == FetchFailure.connect;

  @override
  String toString() => 'FetchException($kind, $url: $message)';
}

/// Minimal HTTP seam so tests inject a fake. Returns the response body text;
/// throws [FetchException] on failure.
abstract interface class ListingClient {
  Future<String> fetch(Uri url, {required Duration timeout});
  void close();
}

/// Real client on package:http (dart:io). Connection timeout and total
/// request timeout both honour [timeout].
class HttpListingClient implements ListingClient {
  HttpListingClient({
    http.Client? inner,
    Duration connectTimeout = const Duration(seconds: 5),
  }) : _client =
           inner ??
           IOClient(
             io.HttpClient()
               ..connectionTimeout = connectTimeout
               ..userAgent = 'watchdog-crawler',
           );

  final http.Client _client;

  @override
  Future<String> fetch(Uri url, {required Duration timeout}) async {
    try {
      final res = await _client.get(url).timeout(timeout);
      if (res.statusCode != 200) {
        throw FetchException(
          url,
          FetchFailure.http,
          'HTTP ${res.statusCode}',
          status: res.statusCode,
        );
      }
      // Don't trust a missing charset (package:http would assume latin-1).
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } on FetchException {
      rethrow;
    } on TimeoutException {
      throw FetchException(
        url,
        FetchFailure.timeout,
        'timed out after ${timeout.inSeconds}s',
      );
    } on io.SocketException catch (e) {
      throw FetchException(url, FetchFailure.connect, e.message);
    } on http.ClientException catch (e) {
      throw FetchException(url, FetchFailure.connect, e.message);
    } on io.HttpException catch (e) {
      throw FetchException(url, FetchFailure.other, e.message);
    }
  }

  @override
  void close() => _client.close();
}
