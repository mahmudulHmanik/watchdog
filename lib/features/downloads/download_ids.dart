import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/platform/platform_api.dart';

/// Stable `MediaFile.id` for a download. The id stored in the task metadata
/// can be dangling (file rows are dropped by the v3 migration and by
/// `Repository.trimFileCache`), so re-resolve it from the url, creating a bare
/// row when needed. Falls back to the stored id when the url is unknown or
/// matches no indexed title. Use this everywhere a download's id is consumed
/// (playing it, resume, watched marks).
Future<int?> resolveDownloadFileId(Repository repo, DownloadProgress d) async {
  final url = d.url;
  if (url != null && url.isNotEmpty) {
    final f = await repo.ensureFileByUrl(url);
    if (f != null) return f.id;
  }
  return d.fileId;
}

/// Title ids of every download in [downloads] (any state), via
/// [Repository.titleIdForUrl]; urls that match no indexed title are skipped.
Future<Set<int>> titleIdsOfDownloads(
  Repository repo,
  Iterable<DownloadProgress> downloads,
) async {
  final ids = <int>{};
  for (final url in {
    for (final d in downloads)
      if (d.url != null && d.url!.isNotEmpty) d.url!,
  }) {
    final id = await repo.titleIdForUrl(url);
    if (id != null) ids.add(id);
  }
  return ids;
}

/// Title ids of all downloads: queued, running, paused, finished and moved to
/// `Movies/watchdog` (`moved_downloads.json` only maps a task id to a new path;
/// the url still lives in the downloader record, which [PlatformApi.downloads]
/// returns). Pass the result as `protectedTitleIds` to `trimFileCache`.
/// Reads the downloader store fresh on every call (one DB read plus one
/// indexed lookup per distinct url); throws if the store cannot be read, in
/// which case skip the trim rather than trim unprotected.
Future<Set<int>> downloadedTitleIds(PlatformApi api, Repository repo) async =>
    titleIdsOfDownloads(repo, await api.downloads());

/// `ref.read(downloadedTitleIdsProvider)()` -> protected title ids.
final downloadedTitleIdsProvider = Provider<Future<Set<int>> Function()>(
  (ref) =>
      () => downloadedTitleIds(
        ref.read(platformApiProvider),
        ref.read(repositoryProvider),
      ),
);
