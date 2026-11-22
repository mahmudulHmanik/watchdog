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
