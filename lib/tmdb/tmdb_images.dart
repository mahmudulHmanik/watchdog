/// Builds image URLs from TMDB file paths.
///
/// TMDB's docs say to read the base URL from `/configuration`; it has been
/// `https://image.tmdb.org/t/p/` for years, so it is a constant here and one
/// request per app run is saved.
library;

enum TmdbImageSize {
  /// Small poster for lists.
  poster('w185'),

  /// Poster on the title screen.
  posterLarge('w500'),

  /// Backdrop on the title screen.
  backdrop('w780'),

  /// Actor photo.
  profile('w185');

  const TmdbImageSize(this.path);
  final String path;
}

String? tmdbImageUrl(String? filePath, TmdbImageSize size) {
  if (filePath == null || filePath.isEmpty) return null;
  final p = filePath.startsWith('/') ? filePath : '/$filePath';
  return 'https://image.tmdb.org/t/p/${size.path}$p';
}
