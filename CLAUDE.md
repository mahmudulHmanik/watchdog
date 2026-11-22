# watchdog

**watchdog** — unofficial cross-platform (Android first, then Linux) client for **DhakaFlix**, a BDIX FTP/HTTP media server in Bangladesh (Sam Online). Browse, search, filter and play movies/series; hand off to external players; download; copy links.

Package/app id: `watchdog` (Flutter project name), display name "watchdog" (lowercase). Icon idea: square-cornered dog head in Everforest green.

## Working rules (owner: mhm)
- **Ask before writing code.** Discuss/plan first, then build on approval.
- Terse, direct answers. No padding.
- Small changes → targeted edits, not full rewrites. Full code → complete, ready-to-use files.
- Prefer paste-ready terminal one-liners; no manual file editing for the user.
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
