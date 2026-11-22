# watchdog task board

Owners are project subagents in `.claude/agents/`. Rule: one owner per task, one area per agent, `qa-reviewer` signs off every task before it is marked done. Status: `[x]` done, `[ ]` todo.

> Legend: [x] done in code and tested, [~] partly done, [ ] not done. Device-only checks (playback on Android, notifications, VLC/MX hand-off, content URIs) cannot be verified without a physical device.

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
- [~] **T1.12** (code QA passed on Linux + real BDIX run; device smoke test still open) Phase 1 QA: full test run, real crawl on BDIX into a temp DB, count vs corpus, perf check, device smoke test. Owner: qa-reviewer.

## Phase 2: Player and series
- [x] **T2.1** media_kit setup (Android + Linux), player screen, lifecycle (create on open, dispose on close). Owner: player-engineer.
- [x] **T2.2** Track sheet: audio/subtitle/video selection, preferred audio language, external .srt. Owner: player-engineer. Depends: T2.1.
- [x] **T2.3** Series model: seasons -> episodes list, language variants, specials (season 0), range files (E01-E05). Owner: player-engineer. Depends: T1.2.
- [x] **T2.4** Playlist behavior: play-from-here, autoplay next, resume position, watched at 90%. Owner: player-engineer. Depends: T2.1, T2.3.
- [x] **T2.5** Series screen UI (YouTube-style playlist), episode actions sheet. Owner: ui-builder. Depends: T2.3.
- [~] **T2.6** (read-only review done; needs a physical Android device: long-file seek, AC3/DTS multi-audio, ASS subs, resume after kill) Phase 2 QA: long-file seek, MKV multi-audio (AC3/DTS), ASS subs, resume after kill, memory with player closed. Owner: qa-reviewer.

## Phase 3: Polish
- [x] **T3.1** Theme system: 3 palettes with exact tokens, Rounded/Box shapes, Inter / mono fonts. Owner: ui-builder.
- [x] **T3.2** Settings: theme, shape, external player, preferred audio, servers editor, re-index, clear data. Owner: ui-builder. Depends: T1.3, T3.1.
- [x] **T3.3** Linux: "Follow Omarchy theme" reading `~/.local/state/omarchy/current/theme/colors.toml`. Owner: ui-builder.
- [~] **T3.4** (Linux release build + desktop entry exist; launch verified headless only) Linux build and desktop entry, libmpv dependency notes. Owner: platform-integrator.
- [x] **T3.5** Icon (square-cornered dog head, Everforest green), launcher assets. Owner: release-engineer.
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
- [ ] **T4.7** (v0.2.0 signed with the NEW key is installed on the owner's phone since 2026-11-22, local build, not published; remaining: publish a higher version and update to it from inside the app) Real update install end to end: needs a release signed with the same key as the installed app (release key was lost; see CLAUDE.md).
- [ ] **T4.8** Duplicate subtitle lines on some ASS releases (two identical stacked lines from `sub-text`); dedupe in the Flutter subtitle view.

## Phase 5: TMDB metadata (started 2026-11-22)
Contract (lead): `lib/data/repository.dart` "TMDB metadata" section + `TmdbInfo`/`TmdbProgress` in `lib/data/models.dart`. Details: CLAUDE.md "TMDB metadata".
- [x] **T5.1** Schema v2 + migration (indexes created explicitly), people FTS, tests. Lead.
- [x] **T5.2** TMDB client: v3 key / v4 token, search movie/tv, details+credits, typed errors, mock-HTTP tests. Lead.
- [~] **T5.3** Repository impl (save/replace match, queue, progress, clear), TMDB filters in `BrowseFilter` + SQL, genre/language facets, `searchPeople`/`person`, perf test with TMDB rows. Owner: data-architect (running).
- [~] **T5.4** Matcher, throttled sync service (429/401 handling, pause/resume, fetchNow, manual rematch), secure key storage, providers. Owner: crawler-engineer. Built 2026-11-22 (matcher threshold 0.80, 5 req/s, Keystore on Android, 0600 file on Linux); awaiting qa-reviewer sign-off and Linux build check (libsecret).
- [ ] **T5.5** UI: Settings TMDB section (paste key, test, background toggle, progress, clear), title screen (backdrop, overview, rating, genres, cast row, Fix match), filter sheets for TMDB filters, actor chips in search, poster fallback, About credit + logo. Owner: ui-builder. Depends: T5.3, T5.4.
- [ ] **T5.6** Search integration: actor-name matches alongside title results. Owner: search-engineer. Depends: T5.3.
- [ ] **T5.7** README/NOTICE attribution; owner supplies the approved TMDB logo. Owner: release-engineer.
- [ ] **T5.8** QA on Linux + phone with a real key (match rate on the real library, filters, actor search, rate limits). Owner: qa-reviewer.

## Release checklist (owner builds at home, see CLAUDE.md "Release signing")
- [x] New keystore + `android/key.properties` created 2026-11-22 (old key lost, one reinstall needed). Owner: copy `watchdog-release.jks` + `watchdog-release.credentials.txt` to the drive.
- [ ] Bump `pubspec.yaml` version and `lib/core/app_info.dart` together, then `scripts/release.sh`.
- [ ] Install old release, publish new one, confirm Settings → Check for updates installs it (T4.7).

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
