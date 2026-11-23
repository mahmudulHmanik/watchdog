# watchdog task board

Owners are project subagents in `.claude/agents/`. Rule: one owner per task, one area per agent, `qa-reviewer` signs off every task before it is marked done. Status: `[x]` done, `[ ]` todo.

> Legend: [x] done in code and tested, [~] partly done, [ ] not done. Device-only checks (playback on Android, notifications, VLC/MX hand-off, content URIs) cannot be verified without a physical device.

## Current status (2026-11-22, v0.3.1 final release)
Shipped: everything in Phases 0-6 below (skeleton index + lazy files + schema v3, TMDB, Storage controls, Settings reorg, season-aware playlists, update fallback). `dart analyze` clean, 981 tests green. Context for a new session: CLAUDE.md "Status snapshot".

**Open items, in rough priority**
1. **T5.11** TMDB fill speed (cache by name+year, raise default rate, prioritise opened titles).
2. **T4.7** prove the in-app update end to end (download + install) with a release newer than the installed one.
3. **QA gaps (T6.8)**: from-empty first run (needs a throw-away install, do NOT clear the owner's index), off-BDIX behaviour, playing an episode of a lazily loaded title, Linux build (install `cmake`, libsecret headers).
4. **T4.8** duplicate ASS subtitle lines; pinch-to-zoom not implemented.
5. Cosmetics: cramped "11-12" episode-number column; early "Indexing" total estimate is low; `skipIndexProvider` in `browse_providers.dart` is unused.
6. Owner decisions pending: none. Decided: no prebuilt snapshot; image cache cap 1,500.

## Contracts (agree first, keeps agents from colliding)
- **C1 Repository interface** (`lib/data/repository.dart`): data-architect writes it; UI, search, player and downloads code only against it. No drift types leave `lib/data`.
- **C2 Models** (`lib/data/models.dart`): `Title`, `Season`, `MediaFile`, `WatchState`, `Category` as plain immutable Dart classes.
- **C3 Platform API** (`lib/platform/platform_api.dart`): `openExternal(List<MediaFile>)`, `copyUrl`, `enqueueDownload`. platform-integrator owns it.

## Phase 0: Foundation
- [x] Toolchain, `flutter create`, deps, CLAUDE.md facts (lead)
- [x] h5ai listing parser + name parsers + 45 tests, corpus check (crawler)
- [x] **T0.1** Write contracts C1/C2/C3 as interfaces + docs. Owner: data-architect (C1, C2), platform-integrator (C3). Accept: compiles, no implementation.
- [x] **T0.2** Replace template `main.dart`; app shell with Riverpod `ProviderScope`, empty routes. Owner: ui-builder.
- [x] **T0.3** Lint config (`analysis_options.yaml`), exclude `tool/` from `avoid_print`. Owner: release-engineer.

## Phase 1: Core (index, search, hand-off)
- [x] **T1.1** drift schema: sources, categories, titles, seasons, files, watch, downloads + FTS5 (`titles_fts`, trigram). build_runner wired. Owner: data-architect. Depends: T0.1. Accept: in-memory DB tests, migrations v1.
- [x] **T1.2** DAOs/repository implementation: browse by category/year/language/quality, series playlist, upsert-by-folder-url, watch progress. Owner: data-architect. Depends: T1.1.
- [x] **T1.3** Crawl config: editable server/category list with defaults (.7 .10 .12 .14; exclude .8, Tutorial), layout kinds. Owner: crawler-engineer. Depends: T0.1.
- [x] **T1.4** Recursive classifier: title / season / collection / event / extras; unparsed season dir => season 0; Anime bucket depth; nested release folders flattened. Owner: crawler-engineer. Depends: T0.1. Accept: replay of the saved crawl via fixtures reproduces corpus counts.
- [x] **T1.5** Crawl engine: bounded concurrency, retry/timeout, progress stream, off-BDIX failure handling, cancel. Owner: crawler-engineer. Depends: T1.3, T1.4.
- [x] **T1.6** Index writer: crawl results -> repository, incremental update by folder mtime, deletes removed items. Owner: crawler-engineer. Depends: T1.2, T1.5.
- [x] **T1.7** Search: FTS5 trigram query + Levenshtein re-rank, combined filters, paging, benchmark under 100 ms on ~35k titles. Owner: search-engineer. Depends: T1.2.
- [x] **T1.8** Platform: openExternal (Android intent chooser; m3u for multiple; Linux `mpv`), copy URL. Owner: platform-integrator. Depends: T0.1.
- [x] **T1.9** Android cleartext HTTP config limited to private ranges; arm64-only build config. Owner: platform-integrator.
- [x] **T1.10** Downloads: background_downloader queue, pause/resume, notification, path. Owner: platform-integrator. Depends: T1.2.
- [x] **T1.11** Minimal UI: Home (categories), title list, Search + filter chips, file actions sheet (play external / copy / download / mark watched), first-run index screen with progress. Owner: ui-builder. Depends: T1.2, T1.7, T1.8, T1.10.
- [x] **T1.12** (code QA passed on Linux + real BDIX run; device smoke test done: full re-index and use on the owner's phone 2026-11-22) Phase 1 QA: full test run, real crawl on BDIX into a temp DB, count vs corpus, perf check, device smoke test. Owner: qa-reviewer.

## Phase 2: Player and series
- [x] **T2.1** media_kit setup (Android + Linux), player screen, lifecycle (create on open, dispose on close). Owner: player-engineer.
- [x] **T2.2** Track sheet: audio/subtitle/video selection, preferred audio language, external .srt. Owner: player-engineer. Depends: T2.1.
- [x] **T2.3** Series model: seasons -> episodes list, language variants, specials (season 0), range files (E01-E05). Owner: player-engineer. Depends: T1.2.
- [x] **T2.4** Playlist behavior: play-from-here, autoplay next, resume position, watched at 90%. Owner: player-engineer. Depends: T2.1, T2.3.
- [x] **T2.5** Series screen UI (YouTube-style playlist), episode actions sheet. Owner: ui-builder. Depends: T2.3.
- [~] **T2.6** (read-only review done; on the owner's phone 2026-11-22: playback, resume and season-grouped playlists work; still open: long-file seek, AC3/DTS multi-audio, ASS subs, resume after kill) Phase 2 QA: long-file seek, MKV multi-audio (AC3/DTS), ASS subs, resume after kill, memory with player closed. Owner: qa-reviewer.

## Phase 3: Polish
- [x] **T3.1** Theme system: 3 palettes with exact tokens, Rounded/Box shapes, Inter / mono fonts. Owner: ui-builder.
- [x] **T3.2** Settings: theme, shape, external player, preferred audio, servers editor, re-index, clear data. Owner: ui-builder. Depends: T1.3, T3.1.
- [x] **T3.3** Linux: "Follow Omarchy theme" reading `~/.local/state/omarchy/current/theme/colors.toml`. Owner: ui-builder.
- [~] **T3.4** (Linux release build + desktop entry exist; launch verified headless only) Linux build and desktop entry, libmpv dependency notes. Owner: platform-integrator.
- [x] **T3.5** Icon: folded-ribbon W (cream + Everforest green on #232a2e; replaced the square-cornered dog head on branch `icon-ribbon-w`, merged 2026-11-22), launcher assets regenerated with `dart run flutter_launcher_icons`. Owner: release-engineer.
- [x] **T3.6** README with unofficial/disclaimer wording, LICENSE (owner chooses), CONTRIBUTING, issue templates. Owner: release-engineer.
- [x] **T3.7** CI: analyze + test only (BDIX unreachable from CI). Owner: release-engineer.
- [x] **T3.8** Release build script, `adb install` helper. Owner: release-engineer.
- [~] **T3.9** (Linux build/launch verified; Android device verification open) Final QA: all features checklist from CLAUDE.md on device and Linux. Owner: qa-reviewer.

## Phase 4: Field fixes (device feedback, 2026-11-22)
- [x] **T4.1** Player stuck on loading: `MediaKit.ensureInitialized()` was never called, so `Player()` threw inside an async `_create` and the screen spun forever. Fixed in `main.dart`; the screen now shows the error; boot calls are bounded by timeouts. Verified on device.
- [x] **T4.2** Download speed + time left in the Downloads tab (`TaskProgressUpdate.networkSpeed/timeRemaining`). Verified on device.
- [x] **T4.3** YouTube-style player: video pinned at the top (16:9) with playlist below, side-by-side on wide windows, fullscreen toggle, back leaves fullscreen first. Verified on device.
- [x] **T4.4** VLC-style gestures (seek, volume, brightness, double-tap, hold 2x). Verified on device. Pinch-zoom not done.
- [x] **T4.5** Downloads were invisible (app-private `Android/data`): finished files are now moved to `Movies/watchdog` (MediaStore); Downloads tap plays in-app; external player gets a FileProvider URI for the shared folder; error toasts include the detail.
- [x] **T4.6** In-app update from GitHub releases (check, download with SHA-256, installer hand-off, Settings entry, daily check on launch), `scripts/release.sh`.
- [x] **T4.9** Volume gesture changed only mpv's internal gain, not the system volume. Now drives Android `STREAM_MUSIC` through `dev.watchdog/audio` (`MainActivity.kt`, `lib/platform/system_volume.dart`); Linux keeps mpv volume. Brightness reset on volume drag did not reproduce with the new path (logcat showed no brightness change during a volume drag). Verified on device.
- [ ] **T4.7** (v0.2.0 and v0.3.0 published on GitHub 2026-11-22, both signed with the new key; v0.1.0 release deleted (tag kept); the owner's phone runs v0.3.0 installed via adb over v0.2.0 (upgrade + schema v3 migration verified); remaining: publish a higher version, e.g. 0.3.1, and update to it from inside the app to prove the in-app updater end to end) Real update install end to end: needs a release signed with the same key as the installed app (release key was lost; see CLAUDE.md).
- [x] **T4.10** Player playlist showed no season (multi-season shows listed "Episode 1..5" repeatedly, Lupin screenshot 2026-11-22). Fixed: season headers in the playlist, "Season 2 · Episode 3 · Title" under the video, autoplay card; Home continue-watching now uses the season folder number (`ResumeItem.seasonNumber`). Unit/widget tests pass; device look not yet verified.
- [x] **T4.11** In-app update said 'GitHub rate limit hit' (anonymous API 60 req/h per IP, shared mobile IPs exhaust it). Fixed in v0.3.1: fall back to the public release feed + asset page + checksum file; verified live against GitHub while the API was limited.
- [x] **T4.12** (built, 1,009 tests green, released as v0.3.2 and carried in v0.3.3; NOT verified on the Realme C17 itself: ask the owner whether it plays after updating, fallback = Settings -> Playback -> Hardware decoding -> Off) Player failed on EVERY video on a Realme C17 (Android 11, SD460) with 'Could not open codec' while a Redmi Note 13 Pro+ plays everything: the app treated any mpv/media_kit error event as fatal and never tried software decoding. Fix: grace window for decoder errors, one automatic software-decoding retry remembered per phone, Settings -> Playback -> Hardware decoding (Auto/Off), clearer message + 'Open in external player', no auto-skip for decoder failures.
- [~] **T4.13** One-line installer `scripts/install.sh` (latest release via the /releases/latest redirect, SHA-256 + signer check, adb / Termux install, refuses tampered or wrongly signed APKs). Tested here against the real v0.3.3 and v0.3.2 releases and with fake adb/termux-open; written 2026-11-22, NOT pushed yet (the raw URL returns 404 until it is on `main`); not run on a real phone.
- [x] **T4.15** Linux app crashed (SIGSEGV) when playing: LuaJIT in system libmpv + Flutter's exported `_Unwind_*`. Fixed in `linux/runner/main.cc` (self re-exec with `LD_PRELOAD=libgcc_s.so.1`), reproduced + verified with `tool/linux/mpv_unwinder_repro.c`; installed locally on the owner's Omarchy; published 2026-11-23 (the Linux tarball on release v0.3.3 was REPLACED with the fixed build, sha256 db2dffba…; the Android assets are unchanged). Desktop playback verified 2026-11-23 on the owner's Omarchy by driving the real app (hyprctl/wtype/grim): VisionQuest S01E01 (1080p x265) opened from Continue watching, subtitles, season-grouped playlist, seek, pause/resume all fine, no coredump, ~354 MB RSS.
- [~] **T4.14** Linux release: `flutter build linux --release` works (cmake 3.31 pinned in mise.toml, user space), bundle 33 MB, loads in a clean env with no Java (libdartjni.so left out: Android-only, links libjvm via a RUNPATH into the build JDK). `scripts/package-linux.sh` builds `watchdog-<tag>-linux-x64.tar.gz` + `.sha256`; `scripts/install-linux.sh` installs run-time deps (pacman/apt/dnf: mpv/libmpv, GTK 3, libsecret) then the app under ~/.local. Tested here with a fake package manager/sudo, upgrade, uninstall, tampered archive. NOT yet pushed/published, never started with a display (window not opened), not run on a clean Omarchy/Debian/Fedora box.
- [ ] **T4.8** Duplicate subtitle lines on some ASS releases (two identical stacked lines from `sub-text`); dedupe in the Flutter subtitle view.

## Phase 5: TMDB metadata (started 2026-11-22)
Contract (lead): `lib/data/repository.dart` "TMDB metadata" section + `TmdbInfo`/`TmdbProgress` in `lib/data/models.dart`. Details: CLAUDE.md "TMDB metadata".
- [x] **T5.1** Schema v2 + migration (indexes created explicitly), people FTS, tests. Lead.
- [x] **T5.2** TMDB client: v3 key / v4 token, search movie/tv, details+credits, typed errors, mock-HTTP tests. Lead.
- [x] **T5.3** Repository impl (save/replace match, queue, progress, clear), TMDB filters in `BrowseFilter` + SQL, genre/language facets, `searchPeople`/`person`, perf test with TMDB rows. Owner: data-architect.
- [x] **T5.4** Matcher, throttled sync service (429/401 handling, pause/resume, fetchNow, manual rematch), secure key storage, providers. Owner: crawler-engineer. Built 2026-11-22 (matcher threshold 0.80, 5 req/s, Keystore on Android, 0600 file on Linux); QA-reviewed and fixed (T5.10); Linux build check (libsecret) still open.
- [x] **T5.5** (built 2026-11-22; widget-tested only, device check pending; TMDB logo still missing) UI: Settings TMDB section (paste key, test, background toggle, progress, clear), title screen (backdrop, overview, rating, genres, cast row, Fix match), filter sheets for TMDB filters, actor chips in search, poster fallback, About credit + logo. Owner: ui-builder. Depends: T5.3, T5.4.
- [x] **T5.6** (built; actor strip + filters, widget-tested) Search integration: actor-name matches alongside title results. Owner: search-engineer. Depends: T5.3.
- [x] **T5.7** README/NOTICE attribution done; approved TMDB logo bundled (`assets/tmdb/`, `flutter_svg`) and shown in About. Owner: release-engineer.
- [x] **T5.10** (done, 666 tests green) Fixes from the independent QA review 2026-11-22: TMDB saves no longer refresh crawl lists (`tmdbChanges`), sync keyset paging + stop/auto-retry rules, secret scrubbing, key-write failures surfaced, throttled progress queries, Clear index warning, resumeMeta season-0 regression (fixed).
- [ ] **T5.11** TMDB fill is slow for a full library: phone check 2026-11-22 showed Matched 735 / Unmatched 38 / Pending 38,710; at 5 req/s and 2 requests per title that is ~4+ h with the app open. Ideas: cache lookups by (normalised name, year, kind) so the ~10k quality-duplicate rows (720p/1080p copies) cost nothing, raise the default to ~15 req/s (TMDB soft limit ~40), prioritise titles the user opens/searches. Owner: crawler-engineer.
- [~] **T5.8** QA on Linux + phone with a real key (match rate on the real library, filters, actor search, rate limits). Owner: qa-reviewer. Phone check 2026-11-22: key saved, sync running, ~95% match rate (735 matched / 38 unmatched), TMDB block, filter bar and Fix match visible; actor search/filter flows and Linux still to verify.

## Release checklist (owner builds at home, see CLAUDE.md "Release signing")
- [x] New keystore + `android/key.properties` created 2026-11-22 (old key lost). The owner keeps copies of `watchdog-release.jks` + `watchdog-release.credentials.txt` on their drive.
- [x] v0.2.0, v0.3.0 (pre-releases) and v0.3.1 (final, Latest) published 2026-11-22; v0.3.1 installed over v0.3.0 on the phone with `adb install -r` (same key, upgrade OK).
- [ ] Next release: bump `pubspec.yaml` + `lib/core/app_info.dart` together, analyze + tests, signed build, verify signer fingerprint, `adb install -r` upgrade test, then (only when the owner asks) push + `gh release create` (CLAUDE.md "How a release is made"). Use it to prove the in-app update end to end (T4.7).

- [x] **T5.9** Settings reorganised into a home with six groups (Appearance, Playback, Library, TMDB, Updates, About), deep link from the title screen to the TMDB page. Device look not yet verified.

## Phase 6: First-run speed (owner report 2026-11-22)
Problem: the first launch crawls the whole library (~125k files / ~35k titles); setup can take a very long time. Goal: usable within minutes on first run, fully indexed in the background.
- [x] **T6.1** Measured + designed (2026-11-22). ~53k HTTP requests today, 99% only fetch file lists; h5ai JSON API (`POST /_h5ai/public/index.php`, `what=2`) returns children+grandchildren per request: ~240 requests / ~22 MB / ~10 s for all movies on desktop; real DB 190.9 MB, 75% is `files` + its unique url index.
  Owner decisions: lazy file lists on open (YES), JSON API with HTML fallback (YES), prebuilt snapshot (NO), image disk cache cap 1,500 (YES). Targets: first search in seconds, whole catalogue in 1-2 min on the phone, DB ~22 MB (~45 MB with full TMDB).
- [x] **T6.2** (done 2026-11-22; real v2 DB copy 182 MB -> 21.4 MB in ~1 s, watch + TMDB + ids kept; 35k skeleton inserts ~23 s on desktop, phone slower) Schema v3: `files(rel)` no name/ext/playable/unique url, `titles.folder_rel/poster_rel/files_loaded_at`, relative season folders, v2->v3 migration keeping watch + TMDB, VACUUM in beforeOpen, skeleton drafts, `upsertTitleFiles`, `trimFileCache`.
- [x] **T6.3** (done; live: English 14,832 titles in 37 requests/2.8 s, TV 2,382 shows in 5 requests, API vs HTML crawl zero diffs; also fixed Anime year parsing `(TV Cartoon 2009-2024)` and Foreign Language Movies layout config) API client + probe, fast regex listing parser (differential-tested), adaptive concurrency + bounded queue, skeleton classification from `what=2` trees, `tool/skeleton_smoke.dart`.
- [x] **T6.4** (built, widget-tested; MediaStore query+delete NOT yet exercised on a device) Settings -> Library -> Storage block (index, image cache, player cache, downloads size + clear/delete), capped image disk cache (1,500), player cache dir.
- [x] **T6.2b** (done) Downloads resolve a stable file id via `ensureFileByUrl`; helper for protected title ids; clean up old update APKs.
- [x] **T6.5** (done; live smoke on desktop: first run 289 requests, 35.8 MB, 14.0 s, first batch at 2.5 s, 39,604 titles, DB 21.8 MB; incremental run 32 requests / 2.9 s; 35k skeleton inserts 18.5 s -> 6.3 s) (crawler-engineer #1) Skeleton index service: wire crawler to the v3 contract, commit per response, usable-while-indexing, resume, incremental check, `addedAt` from folder mtime, `compact()` after runs. Owner: crawler-engineer.
- [x] **T6.6** (built, tests green; not yet run against the real server or a device) (crawler-engineer #2: `TitleFilesLoader`, loading/offline states, player launcher waits for files, trim with protected titles) Lazy file loader + providers for title/series screens, LRU trim protecting watched/downloaded titles, downloads must resolve without dropped file ids. Owner: crawler-engineer + data-architect + platform.
- [x] **T6.7** (built; seen working on the phone: Elite opened with TMDB block + lazy episode load in ~5 s) UI: replace the blocking first-run view with Home + thin indexing banner, file-loading/offline states on title/series screens. Owner: ui-builder.
- [~] **T6.8** (partly done on the phone 2026-11-22: v2->v3 migration, lazy load of a never-opened series, Storage block, full re-index = 39,604 titles in ~3.5 min with the TMDB sync running; still to do: from-empty first run, off-BDIX behaviour, playback of a lazily loaded title, release build) QA: timed first run + v2 -> v3 update on the phone, migration with real watch data, off-BDIX behaviour. Owner: qa-reviewer.
- [x] **T6.8a** Phone check of the interim build 2026-11-22 (schema v3 migration on the owner's real data): DB 190.9 -> 22.6 MB on first launch (~10 s), Home/Search/Settings/Library/TMDB pages OK, Storage block works on device (index 26 MB, image cache 5.1 MB, free space shown). Bugs found + fixed in code (not yet on the phone): 'Last indexed' shown in UTC, blank row in the Index card, episode rows titled 'br720p'.
- [x] **T6.9** Real phone timing (2026-11-22): migration ~10 s on first launch; full re-index of 39,604 titles ~3.5 min with the TMDB sync running; first results appear within seconds. Owner's original 'a day' report was not reproducible.

## Lead decisions on contracts (from T0.1 hand-back)
- `Repository` gets a `search(query, filter, {offset, limit})` method (added in T1.7 by search-engineer; data-architect exposes the FTS table in T1.1).
- Downloads persistence: NO drift table. background_downloader keeps its own task store; each task carries `MediaFile.id` in its metadata (DownloadProgress.fileId). PlatformApi was amended (downloads(), defaultDownloadDirectory(), removeDownload, fileId/directory params, byte counters).
- Android build: `jni` (transitive via path_provider_android) fails AAPT verify on AGP 9.3.1; `verifyReleaseResources` is disabled for that subproject only in android/build.gradle.kts. arm64 release APK builds (18 MB).
- Crawler inputs are id-free drafts keyed by `folderUrl`; `upsertTitle` keeps watch state for files whose url is unchanged.
- ui-builder must import `package:material_ui/material_ui.dart` (Flutter 3.50 deprecates `flutter/material.dart`).

## Parallel lanes (what can run at once)
1. After T0.1: **data-architect** (T1.1-1.2) || **crawler-engineer** (T1.3-1.5) || **platform-integrator** (T1.8-1.9) || **ui-builder** (T0.2, theme T3.1).
2. After T1.2: search-engineer (T1.7), crawler index writer (T1.6), downloads (T1.10), player series model (T2.3).
3. qa-reviewer runs at the end of every lane, never in parallel with its own subject.

## Working agreement
- Agents read CLAUDE.md first; the lead (main session) owns CLAUDE.md, TASKS.md and merging.
- No agent edits outside its area; cross-area needs go back to the lead as a request.
- Every task ends with `dart analyze` + `flutter test` output pasted in the report.
- Open questions for the owner: license choice (T3.6), GitHub repo yes/no (T3.7).
