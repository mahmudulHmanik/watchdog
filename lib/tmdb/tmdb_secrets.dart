/// Keeps the TMDB credential out of any text that can reach the UI or a log.
library;

final _apiKeyParam = RegExp(r'api_key=[^&\s"<>]*', caseSensitive: false);
final _bearer = RegExp(r'Bearer\s+[^\s"<>,;]+', caseSensitive: false);
final _jwtLike = RegExp(r'[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}');
final _hex32 = RegExp(r'\b[0-9a-fA-F]{32}\b');

/// [text] with every credential-looking part masked: `api_key=...`, bearer
/// tokens, JWT-shaped and 32-hex strings, and each of [secrets] verbatim
/// (also percent-encoded).
String scrubSecrets(String text, {Iterable<String> secrets = const []}) {
  var s = text;
  for (final v in secrets) {
    if (v.length < 8) continue;
    s = s.replaceAll(v, '***').replaceAll(Uri.encodeComponent(v), '***');
  }
  return s
      .replaceAll(_apiKeyParam, 'api_key=***')
      .replaceAll(_bearer, 'Bearer ***')
      .replaceAll(_jwtLike, '***')
      .replaceAll(_hex32, '***');
}
