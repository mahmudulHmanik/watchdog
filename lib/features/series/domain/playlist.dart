/// Pure-Dart playback queue model and builders (no Flutter, no media_kit).
library;

import 'package:watchdog/data/models.dart';

/// Immutable ordered queue of playable files with a current index.
///
/// Navigation returns new instances; `null` means "no such item".
class Playlist {
  Playlist(Iterable<MediaFile> items, {this.index = 0})
    : items = List.unmodifiable(items) {
    if (this.items.isEmpty) {
      throw ArgumentError('Playlist needs at least one item');
    }
    RangeError.checkValidIndex(index, this.items, 'index', this.items.length);
  }

  final List<MediaFile> items;
  final int index;

  MediaFile get current => items[index];
  int get length => items.length;
  bool get hasNext => index < items.length - 1;
  bool get hasPrev => index > 0;
  MediaFile? get nextFile => hasNext ? items[index + 1] : null;

  Playlist? next() => hasNext ? Playlist(items, index: index + 1) : null;
  Playlist? prev() => hasPrev ? Playlist(items, index: index - 1) : null;

  /// Same queue positioned at [i]; null when out of range.
  Playlist? jumpTo(int i) =>
      i < 0 || i >= items.length ? null : Playlist(items, index: i);

  /// "Play from here": the queue from [i] onwards (index 0 = that file).
  Playlist? fromIndex(int i) =>
      i < 0 || i >= items.length ? null : Playlist(items.sublist(i));
}

/// Builds [Playlist]s from repository data.
///
/// Rules:
/// - Only `playable` files are queued (.rar/.zip dropped).
/// - A range file (E01-E05) is one item (one [MediaFile]).
/// - Language variants: a season's `language` is its variant; a playlist never
///   crosses variants (same equality rule as `Repository.nextEpisode`).
/// - Season 0 (specials / unparsed) is its own queue: starting inside it
///   plays specials only, and starting in a numbered season never includes
///   specials. (`Repository.nextEpisode` differs: it rolls S0 into S1.)
/// - Order: season number, then the given season order (listing order of
///   language groups), then the repository's file order (episode, name).
abstract final class PlaylistBuilder {
  /// Single file (movie / ad-hoc).
  static Playlist single(MediaFile file) => Playlist([file]);

  /// Movie/event files (`Repository.titleFiles`), starting at [startFileId]
  /// or the first playable file. Null when nothing is playable.
  static Playlist? fromFiles(List<MediaFile> files, {int? startFileId}) {
    final p = [
      for (final f in files)
        if (f.playable) f,
    ];
    if (p.isEmpty) return null;
    final i = startFileId == null
        ? 0
        : p.indexWhere((f) => f.id == startFileId);
    return Playlist(p, index: i < 0 ? 0 : i);
  }

  /// Series queue containing [startFileId], within that file's language
  /// variant (and season-0 / numbered split). Null when the file is not found
  /// among playable episodes.
  static Playlist? forEpisode(List<SeasonEpisodes> seasons, int startFileId) {
    final home = seasons
        .where((s) => s.files.any((f) => f.id == startFileId))
        .firstOrNull;
    if (home == null) return null;
    return _queue(seasons, home.season, startFileId: startFileId);
  }

  /// Series queue for a season row: starts at its first playable episode and
  /// continues into later seasons of the same variant. Null when empty.
  static Playlist? forSeason(List<SeasonEpisodes> seasons, int seasonId) {
    final home = seasons.where((s) => s.season.id == seasonId).firstOrNull;
    if (home == null) return null;
    return _queue(seasons, home.season);
  }

  static Playlist? _queue(
    List<SeasonEpisodes> seasons,
    Season home, {
    int? startFileId,
  }) {
    final special = home.number == 0;
    final ordered = [for (var i = 0; i < seasons.length; i++) (i, seasons[i])]
      ..sort((a, b) {
        final c = a.$2.season.number.compareTo(b.$2.season.number);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final flat = <MediaFile>[
      for (final (_, s) in ordered)
        if (s.season.language == home.language &&
            (s.season.number == 0) == special)
          for (final f in s.files)
            if (f.playable) f,
    ];
    if (flat.isEmpty) return null;
    if (startFileId == null) {
      // Start at the requested season, not at an earlier one in the variant.
      final first = ordered
          .where((e) => e.$2.season.id == home.id)
          .expand((e) => e.$2.files)
          .where((f) => f.playable)
          .firstOrNull;
      final i = first == null ? 0 : flat.indexWhere((f) => f.id == first.id);
      return Playlist(flat, index: i < 0 ? 0 : i);
    }
    final i = flat.indexWhere((f) => f.id == startFileId);
    return i < 0 ? null : Playlist(flat, index: i);
  }
}
