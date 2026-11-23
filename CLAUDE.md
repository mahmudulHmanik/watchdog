# watchdog

**watchdog** — unofficial cross-platform (Android first, then Linux) client for **DhakaFlix**, a BDIX FTP/HTTP media server in Bangladesh (Sam Online). Browse, search, filter and play movies/series; hand off to external players; download; copy links; optional TMDB details.

Repo: https://github.com/mahmudulHmanik/watchdog (public). Flutter project/package name `watchdog`, Android app id `dev.watchdog.watchdog` (debug builds `dev.watchdog.watchdog.debug`), display name "watchdog" (lowercase). Icon: folded-ribbon W (cream front strokes, Everforest green folded strokes, on `#232a2e`); sources in `assets/icon/*.svg`, regenerate Android icons with `dart run flutter_launcher_icons`.

## Status snapshot (2026-11-22)
- **Latest release: v0.3.3, published as the final ("Latest") release**, arm64 APK + `.sha256`, signed with the NEW key (see Release signing). It ships the new folded-ribbon W app icon (branch `icon-ribbon-w`, launcher icons regenerated with `dart run flutter_launcher_icons`) on top of v0.3.2's decoder fallback (phones whose hardware video decoder fails, e.g. the owner's girlfriend's Realme C17 / Android 11 / SD460, showed "Could not open codec" on every video: grace window for decoder errors, one automatic software-decoding retry remembered per phone, Settings -> Playback -> Hardware decoding (Auto/Off), clearer message + "Open in external player"; still NOT verified on that phone). `main` holds the same code. Earlier: v0.3.2 and v0.3.1 (final), v0.3.0 and v0.2.0 (pre-releases); v0.1.0 deleted (signed with a lost key).
- **Shipped**: browse/search/filters, in-app player (media_kit) with gestures and track sheet, season-grouped playlists, downloads to `Movies/watchdog`, in-app updates (API + feed fallback), 9 themes + Box/Rounded shapes, skeleton index via the h5ai JSON API (usable in seconds, ~3.5 min full re-index on the phone), lazy file lists, schema v3 (index DB ~190 MB -> ~22 MB), Storage controls, optional TMDB (details, filters, actor search), Settings reorganised into six groups.
- **Quality bar at release**: `dart analyze` clean, `flutter test` 1,009 passed. Device checks done on the owner's phone: v2->v3 migration on real data, lazy loading of a never-opened series, Storage block, full re-index, Settings pages, in-place upgrade 0.3.0 -> 0.3.1.
- **Open items** (details in TASKS.md): T5.11 TMDB fill is slow for a full library (cache lookups by name+year, raise ~5 req/s default, prioritise opened titles); T4.7 prove the in-app download+install end to end (needs a release newer than the installed one); T4.8 duplicate ASS subtitle lines; unverified: from-empty first run, off-BDIX behaviour, playing an episode of a lazily loaded title, Linux build (needs `cmake` and libsecret headers); cosmetics (cramped "11-12" episode-number column, low "Indexing" total estimate early in a run).
- **Resuming a session**: read this file, then TASKS.md, run `git status` and `git log --oneline -5`. Everything here is the source of truth, not chat history.

## Working rules (owner: mhm)
- **Ask before writing code.** Discuss/plan first, then build on approval. The owner usually answers "go ahead"; give a recommendation, not a menu.
- Terse, direct answers. No padding. Report outcomes faithfully (failures included).
- Small changes → targeted edits, not full rewrites. Full code → complete, ready-to-use files.
- Prefer paste-ready terminal one-liners; no manual file editing for the user.
- **Use the specialist subagents in parallel** for independent lanes (`.claude/agents/`): the lead defines the shared contract first (interfaces/models/provider names), then agents own DISJOINT files, then `qa-reviewer` (read-only) last. Lead owns CLAUDE.md/TASKS.md. Agents never commit or push.
- **Never upload anything to GitHub on your own.** No `git push`, `gh release create`, `scripts/release.sh`, or any publish unless the owner asks in that message. Never stage or commit `*.jks`, `key.properties`, `*credentials*`. Local guards (untracked, in `.git/hooks`): pre-commit blocks secret files; pre-push blocks every push unless `WATCHDOG_ALLOW_PUSH=1 git push`, and still refuses if a key file is in the pushed commits; `scripts/release.sh` needs a typed `publish` (or `RELEASE_CONFIRM=yes`). Re-create the hooks on a fresh clone.
- **Never wipe the owner's data without asking.** "Clear index" also deletes all TMDB matches (cascade) which take hours to refetch; prefer "Full re-index" for timing tests. Their phone has two apps: release `dev.watchdog.watchdog` and debug `.debug` (separate data; the TMDB key lives in the debug app).
- Research API/package syntax before using it — verify current versions on pub.dev, don't guess.
- Privacy: never put the owner's name/email/project details in outside requests; generic User-Agents only (`watchdog`, `watchdog-updater`).

## Network facts (verified 2026-11-22)
- Servers: `.7` (English/Foreign/Kolkata/3D movies), `.14` (Hindi/South/Animation/IMDb/1080p/Korean), `.12` (`TV-WEB-Series`, 2382–2383 shows in 4 A–Z buckets, flatten them), `.10` (Anime, Documentary, WWE, Awards, Tutorial), `.8` (games/software — excluded), `.4` up but unlinked, `.9` times out. Portal `http://<ip>/` is a plain page whose links give the real category URLs. ~39.6k titles in total.
- Servers run nginx + **h5ai v0.29**. Two ways to read a folder: (1) the no-JS fallback table (`#fallback tr`: `td.fb-i img[alt]`, `td.fb-n a`, `td.fb-d`, `td.fb-s` in KB; HTML times are server wall clock = UTC, minute resolution), (2) the JSON API `POST /_h5ai/public/index.php` with `{"action":"get","items":{"href":"<encoded folder>","what":2}}` returning children AND grandchildren per request (`what` capped at 2; times are exact epoch ms UTC). Hrefs are absolute-path, percent-encoded. HTML supports keep-alive + gzip; the JSON is not compressed.
- Reachable only from a BDIX-peered ISP. Not reachable from cloud/CI. This machine IS on BDIX; the phone can reach 172.16.50.x over the same network (ping ~4 ms).
- Layouts: `Category/(Year)/Title/file` · flat `Category/Title/file` · `Show/Season N/files` · `Bucket/Show/Season/files` (Anime) · collections `Collection/Movie/files` · event folders (WWE/Awards) · Documentary mixes movies and `Show/Season N/` folders (kind=series inside a movie category) · Foreign Language Movies is 21 language buckets. Depth varies up to 4 below a category; recurse and classify by contents. Ignore `Sample`/`extra`/`scoped_dir_*`. `.rar/.zip` exist → not playable. Posters are `.jpg` in the title folder.
- Parser coverage on the full crawl (~125k video files): year 98%, season folders 99%, episode# 98.7%. Anime year ranges like `(TV Cartoon 2009–2024)` are parsed since v0.3.0. Re-check with `dart run tool/corpus_check.dart <dir with tv.json,all.json>` (the saved crawl is not on disk now; its replay test skips).
- Warning: each `what=2` response repeats the siblings of every ancestor. Never call it on many small folders inside a huge flat directory (977 Documentary folders = 177 MB); use it on category roots and year/bucket folders, and the HTML season listing for single shows.

## Toolchain (user-space, no sudo)
`mise.toml` pins flutter 3.50.1, java temurin-17, ninja. Android SDK in `~/Android/Sdk` (platform 36). Use `eval "$(mise env)"` + `export ANDROID_HOME=~/Android/Sdk`. `cmake` and libsecret headers are NOT installed here (needed for a Linux desktop build/run; `flutter_secure_storage_linux` is compiled in).
- Checks: `dart analyze` (must be clean), `flutter test` (~4 min, 981 tests). `test/data/perf_test.dart` budgets are load-sensitive: if it fails on a busy machine, rerun it alone (it passes with budgets met: browse ~1 ms, FTS ~30 ms on 35k titles).
- Tests never use the live network. Opt-in live tools: `WATCHDOG_LIVE=1 flutter test tool/skeleton_index_smoke.dart`, `tool/skeleton_smoke.dart`, `tool/measure_parse.dart`.

## Decisions already made (don't relitigate)
- **Not a web app.** Browsers can't switch audio tracks in MKV (Chrome/Firefox lack `audioTracks`), block HTTP media on HTTPS pages, and need CORS. A backend/transcoder was rejected (no server to run).
- **Flutter** — one codebase for Android + Linux. Native Kotlin was considered (lighter) but rejected to avoid two codebases.
- In-app player: **media_kit** (libmpv). Handles MKV, AC3/DTS, ASS subs, track selection.
- **License: Apache-2.0** (open source, wants credit). Credit via `NOTICE`, README author line, in-app About screen; author handle `mhm` (no email anywhere). The repo is public. The Android build bundles LGPL libmpv/FFmpeg: analysis and the pending decision are in `docs/LICENSE-ANALYSIS.md`.
- **Index = skeleton + lazy files** (owner decisions 2026-11-22): file lists are fetched when a title is opened, the first crawl uses the h5ai JSON API with automatic HTML fallback, NO prebuilt index snapshot is published (it would publish a third-party catalogue), poster disk cache capped at 1,500 files.
- **Downloads** land in app-private storage first (resumable), then are moved to `Movies/watchdog` through MediaStore (no permission). Records keep the new path in `moved_downloads.json`. Files saved by an install signed with a different key are invisible to the app (delete them in a file manager).
- **In-app updates (Android)**: Settings → Updates → Check for updates, plus a daily check on launch. It asks GitHub's REST API first, then FALLS BACK to the public `releases.atom` feed + `releases/expanded_assets/<tag>` page + the `<apk>.sha256` file (`lib/features/update/release_feed.dart`) because the anonymous API allows only 60 requests/hour per IP and shared/mobile IPs exhaust it (users saw "rate limit hit"). It picks the asset whose name contains `arm64`, downloads it (SHA-256 verified), hands it to the system installer (user allows "Install unknown apps" once), and deletes old update APKs. Release assets must be named `watchdog-<tag>-arm64.apk` and `<same>.sha256`. Linux only shows the release page. Android installs an update over an existing app ONLY if signed with the SAME key.
- **Release signing**: the original keystore was lost on 2026-11-22, so a NEW key was created that day: `watchdog-release.jks` in the repo root (alias `watchdog`, PKCS12), passwords in `watchdog-release.credentials.txt`, SHA-256 cert fingerprint `11:E4:7D:A4:D9:A8:94:82:A9:47:25:66:2B:D1:51:38:7B:90:23:04:45:7F:C4:E0:6D:E1:89:6F:A4:63:34:4C`. The jks, the credentials file and `android/key.properties` are git-ignored; the owner keeps copies on their drive. `android/key.properties` (`storeFile=../../watchdog-release.jks` is relative to `android/app`, `storePassword`, `keyAlias`, `keyPassword`); on another machine copy the jks to the repo root and recreate it. Without it Gradle silently falls back to the debug key and `scripts/release.sh` refuses to run. NEVER swap or lose the key again.
- **How a release is made** (owner asks first): bump `version:` in `pubspec.yaml` AND `appVersion` in `lib/core/app_info.dart` (build number must increase) → `dart analyze` + `flutter test` → `flutter build apk --release --split-per-abi --target-platform android-arm64` → verify the signer with `apksigner verify --print-certs` (must show the fingerprint above, not "Android Debug") → copy to `build/watchdog-<tag>-arm64.apk` + `sha256sum` file → commit, push (`WATCHDOG_ALLOW_PUSH=1`), `gh release create <tag> <apk> <sha> --target <sha>` (add `--prerelease` for a pre-release; `gh release edit <tag> --prerelease=false --latest` promotes). `scripts/release.sh` does the same in one go (asks to type `publish`). Test the upgrade on the phone with `adb install -r` before publishing.
- **Linux release (since 2026-11-22)**: `scripts/package-linux.sh [--build]` -> `build/watchdog-<tag>-linux-x64.tar.gz` + `.sha256` (uploaded with `gh release upload <tag> ...`), installed by `scripts/install-linux.sh` (one-liner in README; installs mpv/gtk3/libsecret with pacman/apt/dnf then the bundle under `~/.local`). The package must NOT contain `libdartjni.so`. `mise.toml` pins cmake 3.31 + ninja so no sudo is needed to build. A Linux release asset is optional per release; the Android updater ignores it.
- **Linux crash on playback (fixed 2026-11-23)**: the first Linux release segfaulted when a video was opened (thread `lua/stats`, `libluajit` -> `_Unwind_RaiseException` in `libflutter_linux_gtk.so`). Cause: Flutter's engine exports its own incompatible `_Unwind_*`; the system libmpv uses LuaJIT, whose Lua errors bind to the engine's copy. Fix: `linux/runner/main.cc` re-executes the app once with `LD_PRELOAD=libgcc_s.so.1` (then restores the caller's LD_PRELOAD). Reproduced/verified with `tool/linux/mpv_unwinder_repro.c` (3/5 crashes without the preload, 0/26 with). Android is unaffected (its libmpv has no LuaJIT). Keep the runner workaround unless the engine stops exporting `_Unwind_*`.
- **Debug builds** use app id suffix `.debug` (own data, installs beside release); pass `--dart-define=FILE_PROVIDER_AUTH=dev.watchdog.watchdog.debug.fileprovider`.
- `MediaKit.ensureInitialized()` must run in `main()` before any `Player()`.
- drift: `createTable` does NOT create `@TableIndex` indexes (migrations must call `createIndex`), and `VACUUM` cannot run inside `onUpgrade` (run it from `beforeOpen` when upgraded).

## TMDB metadata (shipped in v0.3.0)
- **Each user brings their own TMDB key** (v3 key or v4 read-access token), pasted in Settings → TMDB. Nothing bundled; no key = app behaves exactly as before. Stored in the Android Keystore (`flutter_secure_storage`; a 0600 file on Linux), never logged, scrubbed from error messages, never in the repo.
- Features: genre / min-rating / original-language / runtime / actor filters, search by actor name (local cast index, top ~15 billed cast per title), title screen with backdrop/overview/rating/genres/cast, poster fallback, manual "Fix match".
- Matching: parsed name + year → `/search/movie` or `/search/tv`; accept only at confidence ≥ 0.80, else "unmatched" (never guess). Collections and events are not looked up.
- Fetching: on-open (always) + opt-in throttled background fill (~5 req/s, 2 requests per title; soft API limit ~40 req/s), respects 429/Retry-After, stops on 401, auto-retries network/429 stops (60 s, 120 s, 300 s), stops after 10 failures in a row. Phone check: 735 matched / 38 unmatched / 38,710 pending (~95% match rate); a full fill takes hours with the app open (T5.11).
- Data (schema v3): `tmdb_meta`, `tmdb_genres`, `title_genres`, `tmdb_people`, `title_cast`, FTS `people_fts`. TMDB writes emit `repository.tmdbChanges` (throttled in the UI), never the global `changes`.
- Licence: free for non-commercial use with credit. The notice "This product uses the TMDB API but is not endorsed or certified by TMDB." is in About, README and NOTICE; the approved short logo is bundled at `assets/tmdb/tmdb_logo_short.svg` (from themoviedb.org/about/logos-attribution; only edit: its CSS fill is inlined so `flutter_svg` renders the gradient) and shown small in Settings → About. Never recolour or stretch it; keep it less prominent than the app's own name.
- Code: `lib/tmdb/` (client, models, images, matcher, sync, settings, secrets scrubbing), `lib/data/` (tables, filters, people search), `lib/features/{settings,title,search}` (UI).

## Index, lazy files and storage (schema v3)
- **Skeleton crawl**: the first run indexes titles, seasons, posters, file counts and folder times only, per host in parallel (4 hosts, 2 categories each), movies first, then series, flat, events; batches commit at 400 titles or 250 ms. Desktop live numbers: ~289 requests, ~36 MB, ~14 s for 39.6k titles, first batch at ~2.5 s; unchanged refresh ~32 requests / ~3 s. On the phone a full re-index took ~3.5 min (with the TMDB sync running). Per-category fallback to the HTML crawler if the API is missing/bad. Incremental runs compare per-group hashes and folder mtimes; `removeMissing` only after a fully complete category (guards: empty listing, >50% shrink).
- **Lazy files**: file/episode lists are fetched when a title is opened (`TitleFilesLoader`, one HTML listing; series = season folders in parallel) and cached (`files_loaded_at`). LRU `trimFileCache(20000 rows)` never evicts titles with watch rows or downloads. Playback needs BDIX anyway. Downloads resolve their file via `ensureFileByUrl` (a stored `fileId` can dangle).
- **Schema v3**: `files(rel, …)` relative to the title folder (name/ext/playable derived), `titles.folder_rel` (relative to the category) + `poster_rel` + `files_loaded_at`, no big unique URL indexes. Real DB 190.9 MB → ~22 MB; the v2→v3 migration keeps title/season ids, watch rows and TMDB data; VACUUM in `beforeOpen` after upgrade; `compact()` after crawls. `counts().files` is a stored sum and no longer meaningful (the UI shows titles only).
- **Usable while indexing**: no blocking first-run screen. Home shows a setup state until the first batch, then a slim "Indexing N / ~M titles" banner with a per-category sheet and Cancel; off-BDIX shows a calm card with Retry. `isFirstRun` stays true after a partial run so indexing resumes next launch. Recently-added uses real folder mtimes.
- **Storage controls**: Settings → Library → Storage (index DB, image cache, player cache, downloads, free space) with clear actions; image disk cache capped at 1,500 files (in-house LRU); the player writes nothing to disk beyond RAM buffers.

## Stack
| Layer | Package |
|---|---|
| UI | Flutter, Material 3 (`material_ui`), `flutter_svg` |
| Player | `media_kit`, `media_kit_video`, `media_kit_libs_video`, `screen_brightness` |
| DB + search | `drift` (SQLite) + FTS5; fuzzy pass (trigram/Levenshtein) on top |
| HTTP/crawler | `http` + `html` parser, h5ai JSON API client |
| Downloads | `background_downloader` |
| External player | Android: `android_intent_plus` (ACTION_VIEW, `video/*` → VLC/MX chooser) · Linux: `Process.start('mpv', urls)` |
| Secrets / hashing | `flutter_secure_storage`, `crypto` |
| Files | `file_picker`, `path_provider` |
| State | Riverpod 3 |

Lightweight targets: arm64-only, `--split-per-abi` (release APK ~38 MB); index on disk not RAM; lazy lists; create the player only when opened. Linux uses system libmpv (`pacman -S mpv`).

## Architecture
```
lib/
├── core/        config (crawl_config v2), theme tokens, app_info (version)
├── crawler/     h5ai_api, skeleton*, fast_listing, host_limiter, bounded_queue, title_files,
│                HTML listing/classifier/parsing (kept as fallback + per-title loader)
├── data/        drift DB (schema v3), FTS5, filters (incl. TMDB), repository contract, watch progress
├── tmdb/        client, matcher, sync service, settings/secret storage, providers
├── features/
│   ├── browse/  home grids, image cache (AppImage/ImageStore), formatters
│   ├── home/    home screen, BDIX pill, continue row, category picker
│   ├── search/  fuzzy search, filter bar (incl. TMDB), actor strip
│   ├── series/  playlist model + labels (season headers), autoplay next, resume
│   ├── player/  media_kit player, gestures (seek/brightness/system volume), track sheet, playlist view
│   ├── title/   title screen, TMDB block, Fix match sheet, file loading states, file actions
│   ├── downloads/ downloader backend, download id resolution
│   ├── index/   index service (skeleton + fallback), meta, banner/sheet UI
│   ├── update/  GitHub release check (API + feed fallback), installer hand-off, cleanup
│   ├── settings/ six pages: Appearance, Playback, Library (+Storage), TMDB, Updates, About
│   └── demo/    demo mode for screenshots (WATCHDOG_DEMO=…)
└── platform/    external player, storage stats/deletion, system volume, installer channel
android/…/MainActivity.kt   channels: dev.watchdog/installer, /audio (system volume), /storage (MediaStore)
```
- Crawler runs in-app when on BDIX; the index is cached locally → search works offline/anywhere. Playback and opening a never-opened title need BDIX.
- Language filter comes from DhakaFlix category folder names (server language); TMDB adds an "Original language" filter.

## Features
Filters: category, year, language, quality, TMDB genre/rating/original language/runtime/actor · fuzzy search + actor-name search · audio/video/subtitle track switching · series as YouTube-style playlist with season headers (auto-next, resume, "play from here") · VLC-style gestures · download · open in external player · copy URL · mark watched · optional TMDB details · in-app updates · storage controls.

## UI
Original mockups (6 screens): https://claude.ai/artifact/5GXokiYz6TgqRafKEZDyPD (design intent; the implemented UI differs in Settings (six groups), title screens (TMDB block), search (TMDB filters + actor strip) and Home (indexing banner)).

### Themes (Omarchy palettes)
| Token | Tokyo Night | Everforest | Catppuccin Latte |
|---|---|---|---|
| bg | #1a1b26 | #2d353b | #eff1f5 |
| bar | #16161e | #232a2e | #e6e9ef |
| card | #24283b | #343f44 | #e6e9ef |
| highlight | #292e42 | #3d484d | #dce0e8 |
| border | #414868 | #56635f | #bcc0cc |
| text | #c0caf5 | #d3c6aa | #4c4f69 |
| muted | #9aa5ce | #a6b0a0 | #5c5f77 |
| accent | #7aa2f7 | #a7c080 | #1e66f5 |
| onAccent | #16161e | #232a2e | #eff1f5 |
| ok | #9ece6a | #a7c080 | #40a02b |

Six more Omarchy palettes exist in the app (9 total) plus "Follow system / Omarchy theme" (Linux reads `~/.local/state/omarchy/current/theme/colors.toml`).

**Defaults: Everforest theme + Box (Omarchy) shape.**

### Shape modes
- **Rounded**: pills (999) for chips/toggles, 12–14 px cards/inputs/buttons, 22 px top-rounded sheets with grab handle, Inter.
- **Box (Omarchy)**: radius 0 everywhere; selected/focused = transparent fill + 2px accent border (Hyprland active-window look); sheets get 2px accent top border, no handle; monospace font (JetBrains Mono bundled; Omarchy default Caskaydia Mono Nerd Font).

## Build & delivery
- Local build: `flutter build apk --release --split-per-abi --target-platform android-arm64` → `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`; install with `adb install -r`. Helper scripts: `scripts/build-android.sh`, `scripts/install-android.sh`, `scripts/build-linux.sh`, `scripts/release.sh`.
- CI (GitHub Actions) runs analyze + test only (BDIX data is unreachable from CI).
- **Debug on the owner's phone (wireless adb)**: `adb devices` shows the exact serial (e.g. `adb-GMPNF6OJAQBIQSG6-qMHuHz._adb-tls-connect._tcp`; the same phone can appear under a second name with " (2)" — use the one that says `device`, pass it with `-s`). The screen must be awake and unlocked (`adb shell input keyevent KEYCODE_WAKEUP`; never try to bypass the lock). Screenshots: `adb -s S exec-out screencap -p > shot.png` (1220×2712 px); taps: `adb -s S shell input tap X Y` in physical pixels (bottom nav icons at y≈2620; y>2650 hits the gesture strip and does nothing); back: `input keyevent 4`. Debug app data is readable via `adb -s S shell "run-as dev.watchdog.watchdog.debug ls -l files/"` (`watchdog.db`, `index_meta.json`, `theme.json`); the release app's data is not. Logs: `adb -s S logcat -d -s flutter:V`.

## Phases (all done unless noted)
1. **Core** — crawler, index, fuzzy search, filters, external player, copy URL, download.
2. **Player** — media_kit player, track switching, series playlist, auto-next, resume.
3. **Polish** — themes, shapes, settings, Linux build + Follow Omarchy.
4. **Field fixes** — player init, gestures, downloads to `Movies/watchdog`, in-app updates, season labels, system volume.
5. **TMDB** — client, matcher, sync, filters, actor search, UI, attribution (shipped v0.3.0).
6. **First-run speed + storage** — skeleton crawl, lazy files, schema v3, Storage controls (shipped v0.3.0); update fallback (v0.3.1).
Next: see "Open items" above and TASKS.md.
