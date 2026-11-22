# watchdog

**watchdog** — unofficial cross-platform (Android first, then Linux) client for **DhakaFlix**, a BDIX FTP/HTTP media server in Bangladesh (Sam Online). Browse, search, filter and play movies/series; hand off to external players; download; copy links.

Package/app id: `watchdog` (Flutter project name), display name "watchdog" (lowercase). Icon idea: square-cornered dog head in Everforest green.

## Working rules (owner: mhm)
- **Ask before writing code.** Discuss/plan first, then build on approval.
- Terse, direct answers. No padding.
- Small changes → targeted edits, not full rewrites. Full code → complete, ready-to-use files.
- Prefer paste-ready terminal one-liners; no manual file editing for the user.
- **Never upload anything to GitHub on your own.** No `git push`, `gh release create`, `scripts/release.sh`, or any publish unless the owner asks in that message. Never stage or commit `*.jks`, `key.properties`, `*credentials*`. Local guards (untracked, in `.git/hooks`): pre-commit blocks secret files; pre-push blocks every push unless `WATCHDOG_ALLOW_PUSH=1 git push`, and still refuses if a key file is in the pushed commits; `scripts/release.sh` needs a typed `publish` (or `RELEASE_CONFIRM=yes`). Re-create the hooks on a fresh clone.
- Research API/package syntax before using it — verify current versions on pub.dev, don't guess.

## Network facts (verified 2026-11-22)
- Servers: `.7` (English/Foreign/Kolkata/3D movies), `.14` (Hindi/South/Animation/IMDb/1080p/Korean), `.12` (`TV-WEB-Series`, 2383 shows in 4 A–Z buckets, flatten them), `.10` (Anime, Documentary, WWE, Awards, Tutorial), `.8` (games/software — excluded), `.4` up but unlinked, `.9` times out. Portal `http://<ip>/` is a plain page whose links give the real category URLs.
- Listings are **h5ai v0.29**; parse the no-JS fallback table (`#fallback tr`: `td.fb-i img[alt]`, `td.fb-n a`, `td.fb-d`, `td.fb-s` in KB). Hrefs are absolute-path, percent-encoded.
- Reachable only from a BDIX-peered ISP. Not reachable from cloud/CI. This machine IS on BDIX.
- Layouts: `Category/(Year)/Title/file` · flat `Category/Title/file` · `Show/Season N/files` · `Bucket/Show/Season/files` (Anime) · collections `Collection/Movie/files` · event folders (WWE/Awards). Depth varies up to 4 below a category; recurse and classify by contents. Ignore `Sample`/`extra`/`scoped_dir_*`. `.rar/.zip` exist → not playable. Posters are `.jpg` in the title folder.
- Parser coverage on full crawl (~125k video files): year 98%, season folders 99%, episode# 98.7%. Re-check with `dart run tool/corpus_check.dart <dir with tv.json,all.json>`.

## Toolchain (user-space, no sudo)
`mise.toml` pins flutter 3.50.1, java temurin-17, ninja. Android SDK in `~/Android/Sdk` (platform 36). Use `eval "$(mise env)"` + `export ANDROID_HOME=~/Android/Sdk`.

## Decisions already made (don't relitigate)
- **Not a web app.** Browsers can't switch audio tracks in MKV (Chrome/Firefox lack `audioTracks`), block HTTP media on HTTPS pages, and need CORS. A backend/transcoder was rejected (no server to run).
- **Flutter** — one codebase for Android + Linux. Native Kotlin was considered (lighter) but rejected to avoid two codebases.
- In-app player: **media_kit** (libmpv). Handles MKV, AC3/DTS, ASS subs, track selection.

- **License: Apache-2.0** (open source, wants credit). Credit via `NOTICE`, README author line, in-app About screen; author handle `mhm` (no email anywhere). GitHub repo later, not now. Check libmpv GPL/LGPL implications of media_kit builds before any release.
- **Agents**: specialist subagents in `.claude/agents/`, task board in `TASKS.md`. Lead owns CLAUDE.md/TASKS.md.

- **Downloads** land in app-private storage first (resumable), then are moved to `Movies/watchdog` through MediaStore (no permission). Records keep the new path in `moved_downloads.json`.
- **In-app updates (shipped, Android)**: Settings → Check for updates, plus a daily check on launch. It reads GitHub Releases of `mahmudulHmanik/watchdog` (pre-releases included), picks the asset whose name contains `arm64`, downloads it (SHA-256 verified), and hands it to the system installer (user allows "Install unknown apps" once). Code: `lib/features/update/`. Linux only shows the release page. The check asks GitHub's REST API first, then FALLS BACK to the public `releases.atom` feed + `releases/expanded_assets/<tag>` page + the `<apk>.sha256` file (`lib/features/update/release_feed.dart`) because the anonymous API allows only 60 requests/hour per IP and shared/mobile IPs exhaust it (users saw "rate limit hit"). Release assets must keep the names `watchdog-<tag>-arm64.apk` and `<same>.sha256`. Android installs an update over an existing app ONLY if it is signed with the SAME key as the installed one.
- **Release signing / how releases are made**: the original keystore was lost on 2026-11-22, so a NEW key was created that day (`watchdog-release.jks` in the repo root, alias `watchdog`, passwords in `watchdog-release.credentials.txt`; SHA-256 cert fingerprint `11:E4:7D:A4:D9:A8:94:82:A9:47:25:66:2B:D1:51:38:7B:90:23:04:45:7F:C4:E0:6D:E1:89:6F:A4:63:34:4C`). The jks, the credentials file and `android/key.properties` are git-ignored; the owner keeps copies on their drive. Only the owner had the old build installed, so the move needs ONE reinstall (uninstall old, install new); after that in-app updates work. `android/key.properties` points at the keystore (`storeFile=../../watchdog-release.jks` is relative to `android/app`); on another machine copy the jks to the repo root and recreate `key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). Without it Gradle silently falls back to the debug key and `scripts/release.sh` refuses to run. Release = bump `version:` in `pubspec.yaml` AND `appVersion` in `lib/core/app_info.dart` (build number must increase) -> `NOTES="..." scripts/release.sh` (needs `gh auth login`; `--final` for a non-pre-release). Never swap or lose the key again.
- **Debug builds** use app id suffix `.debug` (own data, installs beside release); pass `--dart-define=FILE_PROVIDER_AUTH=dev.watchdog.watchdog.debug.fileprovider`.
- `MediaKit.ensureInitialized()` must run in `main()` before any `Player()`.

## TMDB metadata (in progress, started 2026-11-22)
- **Each user brings their own TMDB key** (v3 key or v4 read-access token), pasted in Settings. Nothing bundled; no key = app behaves exactly as before. Stored in the secure keystore, never logged, never in the repo.
- Features: TMDB filters (genre, min rating, original language, runtime, actor), search by actor name (local cast index, top ~15 billed cast per title), title screen with backdrop/overview/rating/genres/cast, poster fallback, manual "Fix match".
- Matching: parsed name + year → `/search/movie` or `/search/tv`; accept only on high confidence, else "unmatched" (never guess). Collections and events are not looked up.
- Fetching: on-open (always) + opt-in throttled background fill; soft limit ~40 req/s, respect 429; stop on 401.
- Data: schema v2 (`tmdb_meta`, `tmdb_genres`, `title_genres`, `tmdb_people`, `title_cast`, FTS `people_fts`). Note: drift `createTable` does NOT create `@TableIndex` indexes; migrations must call `createIndex`.
- Licence: free for non-commercial use with credit. Needs the approved TMDB logo + the notice "This product uses the TMDB API but is not endorsed or certified by TMDB." in About/Credits and README/NOTICE. The approved short logo is bundled at `assets/tmdb/tmdb_logo_short.svg` (from themoviedb.org/about/logos-attribution; the only edit is inlining its CSS fill so `flutter_svg` renders the gradient) and shown small in Settings → About via `flutter_svg`. Never recolour or stretch it; keep it less prominent than the app's own name.
- Code: `lib/tmdb/` (client, models, images, matcher, sync, settings), `lib/data/` (tables, filters, people search). Task board: TASKS.md Phase 5.

## Index, lazy files and storage (2026-11-22, schema v3)
- **Skeleton crawl**: first run indexes titles, seasons, posters, file counts and folder times only, using h5ai's JSON API (`POST /_h5ai/public/index.php`, body `{"action":"get","items":{"href":..., "what":2}}`: children + grandchildren per request; `what` is capped at 2). Per-category fallback to the HTML crawler if the API is missing/bad. Desktop numbers: ~289 requests, ~36 MB, ~14 s for ~39.6k titles; first batch committed after ~2.5 s; unchanged refresh ~32 requests. Warning: each `what=2` repeats the siblings of every ancestor, so never call it on many small folders inside a huge flat directory (use it on category roots and year/bucket folders; use the HTML season listing for single shows).
- **Lazy files**: file/episode lists are fetched when a title is opened (`TitleFilesLoader`, one HTML listing; series = season folders in parallel) and cached (`files_loaded_at`). LRU `trimFileCache(20000 rows)` never evicts titles with watch rows or downloads. Playback needs BDIX anyway. Downloads resolve their file via `ensureFileByUrl` (stored `fileId` can dangle).
- **Schema v3**: `files(rel, ...)` relative to the title folder (name/ext/playable derived), `titles.folder_rel` (relative to the category) + `poster_rel` + `files_loaded_at`, no big unique URL indexes. Real DB 190.9 MB -> ~22 MB; migration keeps title/season ids, watch, TMDB. VACUUM runs in `beforeOpen` after the upgrade (cannot run inside drift's transaction); `compact()` after crawls.
- **Usable while indexing**: no blocking first-run screen; Home shows a setup state until the first batch, then a slim "Indexing N / ~M titles" banner with a per-category sheet. `isFirstRun` stays true after a partial run so indexing resumes next launch.
- **Storage controls**: Settings -> Library -> Storage (index, image cache, player cache, downloads, free space) with clear actions; image disk cache capped at 1,500 files (in-house LRU); downloaded update APKs are cleaned up. Files saved by an install signed with a different key are invisible to the app's MediaStore queries (delete them in a file manager).
- **TMDB**: saves emit `repository.tmdbChanges` (throttled in the UI), never the global `changes`, so a background sync does not reset lists.

## Stack
| Layer | Package |
|---|---|
| UI | Flutter, Material 3 |
| Player | `media_kit`, `media_kit_video`, `media_kit_libs_video` |
| DB + search | `drift` (SQLite) + FTS5; fuzzy pass (trigram/Levenshtein) on top |
| HTTP/crawler | `http` + `html` parser |
| Downloads | `background_downloader` |
| External player | Android: `android_intent_plus` (ACTION_VIEW, `video/*` → VLC/MX chooser) · Linux: `Process.start('mpv', urls)` |
| Clipboard | Flutter `Clipboard` |
| State | Riverpod |

Lightweight targets: arm64-only, `--split-per-abi`; index on disk not RAM; lazy lists; create player only when opened. Linux uses system libmpv (`pacman -S mpv`).

## Architecture
```
lib/
├── core/        config, theme tokens, server list
├── crawler/     fetch listings → parse category/title/year/S/E/quality → upsert
├── data/        drift DB, FTS5, filters, watch progress, downloads
├── features/
│   ├── browse/  home, category chips, filters (category/year/language/quality)
│   ├── search/  fuzzy search + filter chips + bottom-sheet pickers
│   ├── series/  seasons → episodes playlist, autoplay next, resume
│   ├── player/  media_kit, audio/subtitle/video track sheet, external .srt
│   ├── downloads/
│   └── settings/ theme, shape, external player, preferred audio, re-index
└── platform/    external player launch (intent / Process)
```
- Crawler runs in-app when on BDIX; index cached locally → search works offline/anywhere. Playback needs BDIX.
- Language filter comes from DhakaFlix category folder names, not from probing audio tracks.

## Features (required)
Filters: category, year, language · fuzzy search · audio/video/subtitle track switching · series as YouTube-style playlist (auto-next, resume, "play from here") · download · open in external player · copy URL · mark watched.

## UI
Mockups (6 screens: Home, Search+filters, Series playlist, Track sheet, Episode actions, Settings): https://claude.ai/artifact/5GXokiYz6TgqRafKEZDyPD

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

Linux extra: "Follow Omarchy theme" — read `~/.local/state/omarchy/current/theme/colors.toml` (see `flutter_omarchy` package).

**Defaults: Everforest theme + Box (Omarchy) shape.**

### Shape modes
- **Rounded**: pills (999) for chips/toggles, 12–14 px cards/inputs/buttons, 22 px top-rounded sheets with grab handle, Inter.
- **Box (Omarchy)**: radius 0 everywhere; selected/focused = transparent fill + 2px accent border (Hyprland active-window look); sheets get 2px accent top border, no handle; monospace font (Omarchy default Caskaydia Mono Nerd Font; JetBrains Mono fallback).

## Build & delivery
- Build locally on this machine (`flutter build apk --split-per-abi --target-platform android-arm64`), install via `adb install`.
- Optional: GitHub repo + Actions to build APK on push.

## Phases
1. **Core** — crawler, index, fuzzy search, filters, external player, copy URL, download.
2. **Player** — media_kit player, track switching, series playlist, auto-next, resume.
3. **Polish** — themes, shapes, settings, Linux build + Follow Omarchy.

## First steps
1. Check toolchain: `flutter doctor`, Android SDK, `adb devices`. Install what's missing (ask first).
2. Fetch real listings: `curl -s http://172.16.50.7/` and one series folder down to episode files. Confirm servers, layout, naming.
3. Propose DB schema + parser rules from the real data → get approval → start Phase 1.
