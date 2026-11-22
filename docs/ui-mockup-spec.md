# UI mockup spec (derived from the 6-screen design canvas)

Status (v0.3.1): the mockups below are the original design intent and were not redrawn. The shipped app differs in these places: Settings is a list of six groups, each opening its own page (Appearance, Playback, Library, TMDB, Updates, About) instead of one long screen; title screens gained a TMDB block (rating, genres, cast, a match sheet for unmatched titles); Search gained TMDB filters (genre, minimum rating) and an actor strip for queries that match a person; Home gained an indexing banner (progress while the index builds). Where this spec and the code disagree, the code is current.

Source: the mockup artifact linked in CLAUDE.md (390x844 phone frames, Everforest + Box by default).
Note: the mockup's wordmark says "DhakaFlix". The app is **watchdog** and unofficial; use the app name, never the DhakaFlix logo/branding.

## Shared rules
- Tokens, palettes and shape rules: CLAUDE.md (Themes, Shape modes). Box: radius 0 everywhere, selected = transparent fill + 2px accent border, sheets have a 2px accent TOP border and no grab handle, monospace font. Rounded: chips/toggles 999, cards 12, inputs 14, thumbs 10, buttons 12-14, sheets 22 top, grab handle 40x4.
- Unselected chip/button border: 1px `border`. Card border in Box: 1px `border`; in Rounded: transparent.
- Poster tiles are placeholders in the mockup; real app uses posterUrl with a tonal fallback tile.
- Touch targets >= 44px. Badge = small label on posters: bg `badge` (bar colour at 90%), text `text`, 10px/600.
- Bottom nav height 72: **4 tabs: Home, Search, Downloads, Settings**. Selected = accent colour + 600 weight; others `muted`. Top border 1px `border`, bg `bar`.

## 1 Home
- Header row: app name (22/700, accent on second half is just styling) + "BDIX online" pill (ok colour on okBg, 8px dot): reflects host probe (IndexService/Crawler.probeHost); show "Offline" state otherwise.
- Search bar (48px, card bg, tap opens Search), category chips row (All, then categories; 36px high; scrollable).
- "Continue watching": horizontal cards 220 wide, 124 high thumbnail with centered play glyph and a 4px progress bar along the bottom (accent on `border`), title 14/600, meta 12 muted: `S02 · E05 · 24 min left` or `Movie · 1h 12m left`. "See all" link on the right in accent.
- "Recently added": 3-column grid of 2:3 posters with a badge bottom-left (`1080p`, `4K`, `Series`), title 13/500 one line ellipsis, meta 11 muted `2025 · English`. "See all" link. Sorted by BrowseSort.recentlyAdded.

## 2 Search + filters
- Top: 44px back button + search field with focus border (2px accent in Box, 1px accent in Rounded), clear (x) button.
- Filter chips (34px): Series/Movie kind, Year, Language, Quality. Active chip shows an x icon (clears), inactive shows a chevron-down. Active = Box: transparent + 2px accent.
- Line: `Showing results for <b>query</b> · N matches`.
- Result rows: 64x96 poster, title 15/600 with the matched fragment highlighted in accent, meta lines 12 muted (`TV Series · 2024 · English`, `3 seasons · 24 episodes` / `1080p · 2.4 GB`). First/selected row: card bg and (Box) 2px accent border.
- Year bottom sheet: title "Year", Reset text button, 4-column grid of 44px buttons (2025 ... 2020, `2010s`, `Older`), multi-select, primary full-width "Show results" button (50px, accent bg, onAccent text). Same sheet pattern for Language and Quality.
- Typo tolerance is shown (query "nortbond" finds "Northbound"): covered by search engine.

## 3 Series playlist (YouTube-style)
- Top: 220px video area with centered prev / pause / next controls, bottom row `18:42 / 42:10` left and `1080p · EN · Sub: EN` right, 4px progress bar (accent). Box: 2px accent bottom border. (Mockup embeds the player on this screen. Our player is a separate full-screen route; acceptable to keep it that way, but the header below must match.)
- Header: title 19/700, subtitle `S02 · E05 — The Long Bridge`, a 44px square button opening the track sheet. Season chips (`Season 1`, `Season 2`...). Row: `5 / 8 · Autoplay next` + toggle (40x24).
- Episode rows: left number (16px wide; `>` glyph for the current one), 112x63 thumbnail with duration badge bottom-right and a 3px progress bar, title 14/600 one line, meta 11 muted (`Watched`, `Now playing · 1080p · 1.2 GB`, `1080p · 1.3 GB`), 44px three-dot button opening Episode actions. Current row: `hi` background, 3px accent left edge, accent title and number.

## 4 Track sheet (player-engineer's file: lib/features/player/ui/track_sheet.dart)
- Scrim over the video; bottom sheet with groups AUDIO / SUBTITLES / VIDEO (12px, 600, uppercase, letter-spacing 0.06em, muted).
- Rows 48px: radio (20px; square in Box, round in Rounded), name 15/500, meta right 12 muted (`AC3 5.1`, `SRT`, `HEVC 10-bit`). Subtitles list starts with `Off`. Selected row: `hi` background + (Box) 3px accent left edge, accent radio.
- Bottom buttons: `Load .srt file`, `Subtitle style` (48px, 1px border).

## 5 Episode actions sheet
- Header: 96x54 thumb + `E06 · Undertow` 15/600 + `45:21 · 1080p · 1.3 GB · MKV` 12 muted; divider.
- 56px action rows with 24px icon + label 15/500 + sublabel 12 muted: **Play** (In-app player, accent icon), **Play from here** (`E06 -> E08 as a playlist`), **Open in external player** (VLC, MX Player...), **Download** (target folder), **Copy link** (Direct BDIX URL), **Mark as watched**.
- Confirmation toast: `Link copied` with ok-coloured check; Box border 2px `ok`, Rounded 1px `border`.

## 6 Settings
- Back + "Settings". Sections:
  - **Theme**: one row per palette with 4 colour swatches (bg, card, text, accent), name, sublabel (`Dark · blue accent`, `Dark · green accent`, `Light · blue accent`), radio. Selected: `hi` bg + 2px accent border. Below: `Follow Omarchy theme` toggle, sublabel `Linux only · reads your active theme`.
  - **Shape**: two cards side by side (`Rounded`, `Box (Omarchy)`) with a tiny preview of the shape.
  - **Playback**: `External player` (value `Ask every time`), `Preferred audio` (value `English`), `Re-index` (action `Run now`).

## Not in the mockup but required
- **Downloads tab** (list with progress, pause/resume/cancel, remove with optional file delete, open file in external player). Design it with the same tokens.
- First-run index screen, off-BDIX message, series with language-variant seasons, archives marked not playable (already built).
