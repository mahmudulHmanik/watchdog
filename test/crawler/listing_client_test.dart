import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchdog/crawler/listing_client.dart';

Future<FetchException?> _err(HttpListingClient c, Uri url, Duration t) async {
  try {
    await c.fetch(url, timeout: t);
  } on FetchException catch (e) {
    return e;
  }
  return null;
}

void main() {
  final url = Uri.parse('http://172.16.50.7/x/');

  test('decodes UTF-8 even without a charset header', () async {
    final c = HttpListingClient(
      inner: MockClient(
        (r) async => http.Response.bytes(utf8.encode('Café ★'), 200),
      ),
    );
    expect(await c.fetch(url, timeout: const Duration(seconds: 1)), 'Café ★');
  });

  test('non-200 -> http FetchException with retryable by status', () async {
    final c404 = HttpListingClient(
      inner: MockClient((r) async => http.Response('', 404)),
    );
    final c503 = HttpListingClient(
      inner: MockClient((r) async => http.Response('', 503)),
    );
    final e404 = await _err(c404, url, const Duration(seconds: 1));
    final e503 = await _err(c503, url, const Duration(seconds: 1));
    expect(e404!.retryable, isFalse);
    expect(e404.noAnswer, isFalse);
    expect(e503!.retryable, isTrue);
  });

  test('slow server -> timeout FetchException', () async {
    final c = HttpListingClient(
      inner: MockClient(
        (r) => Future.delayed(
          const Duration(seconds: 5),
          () => http.Response('', 200),
        ),
      ),
    );
    final e = await _err(c, url, const Duration(milliseconds: 30));
    expect(e!.kind, FetchFailure.timeout);
    expect(e.noAnswer, isTrue);
    expect(e.retryable, isTrue);
  });

  test('client errors -> connect FetchException', () async {
    final c = HttpListingClient(
      inner: MockClient((r) async => throw http.ClientException('no route')),
    );
    final e = await _err(c, url, const Duration(seconds: 1));
    expect(e!.kind, FetchFailure.connect);
  });
}
