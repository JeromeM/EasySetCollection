# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **In-instance assistant**: entering a dungeon or raid where set pieces you
  miss still drop shows a toast with the count and prints the detail — boss,
  piece, set — in the chat frame, once per visit. Toggle in Options →
  Notifications (the toast independently of the announcement). Opening the
  window inside an instance selects the place's most relevant set, and boss
  tooltips list the missing pieces that boss still holds. The Track button's
  tooltip now mentions its right-click.
- **Suggest**: a button in the window header (and `/esc suggest`) that picks
  the closest incomplete set you can still farm this week — instance entrances
  are ranked by real distance on your continent, sets whose sources are fully
  cleared this week are skipped — selects it and guides you there. Right-click
  offers the best suggestions with distance and missing-piece counts.
- **Weekly lockouts in the browser**: sets whose source instances carry an
  active lockout show a lock icon in the list (amber = partial progress this
  week, red = nothing left to farm), with the per-instance detail — difficulty,
  bosses done, time to reset — in the row tooltip and under the detail pane's
  progress bar. The "Guide me to..." menu flags cleared destinations, and a
  new filter (Extras) hides sets with nothing left to farm this week. Variant
  difficulties are honoured: a Heroic recolor only listens to the Heroic
  lockout.

### Changed
- Chat output uses a compact "ESC:" prefix, on every line.

### Fixed
- The loot toast no longer names another class's set when a looted appearance
  only belongs to one (legacy raids drop every armor type) — it now sticks to
  your class's sets, with a Notifications option to include the others (the
  toast then names the class the set belongs to).

## [1.0.0] - 2026-08-07

First full release.

### Added
- **Set tracker**: a compact, movable window independent from the browser
  (the "Track" button replaces "Try on" — the preview pane covers it). It
  shows each tracked set as a collapsible tree — location > boss/quest/vendor
  > pieces — with per-level progress counters. Track several sets at once
  (right-click the Track button → "Add to the current tracking", per-set ×
  to remove). Click a header to collapse it, right-click to set a waypoint
  there, click a piece to waypoint to it. Options on right-click: hide
  collected pieces, auto-guide to the next missing piece (re-points as you
  loot), lock position. State persists per character; the window refreshes on
  every collection change even with the main window closed. `/esc track`.
- `/esc lang`: force the addon texts to English (game data stays in the
  client language).

### Changed
- Guidance overhaul: every instance a set drops in is a guide target (pieces
  dropping in several places — WotLK tiers in Naxxramas AND Vault of
  Archavon — count everywhere); left-click goes to the most-missing one,
  right-click lists them all. The waypoint and arrow now survive closing the
  main window (the arrow's right-click menu gains a Close entry). With
  FarstriderLib, trails re-route automatically on zone changes and no longer
  place the Blizzard map pin (arrow only).
- The preview model loads the character bare (no more equipped weapon/shield
  bleeding into the preview) and reliably dresses at login.

### Fixed
- The list scrolls to the restored selection after a reload.
- Tracker tooltips anchor beside the window instead of covering it; the
  empty-state text no longer overlaps collapsed headers.
- The generator's entrance harvest prefers zone maps (continent coordinates
  were too coarse for waypoints).

## [0.2.0] - 2026-08-07

### Added
- Quest sets now show the actual quest name (localized), in the list rows and
  on each piece's source line. The item→quest mapping is rebuilt automatically:
  an in-game quest-reward sweep (`/esc genquests`, dev-only) merged at build
  time with a Wowhead import — 663 of 1260 quest pieces covered; manual
  `questID` overrides still take precedence and can fill the gaps.
- Piece tooltips include the full, untruncated source line (long boss/instance
  names truncate in the row).

### Changed
- The default variant of a set is now deterministic: dungeon variants first
  (mixed dungeon/vendor groups), then Normal difficulty (10-player before
  25-player, Mythic and LFR last), then the base set — instead of
  best-progress.
- The list's location label and the detail pane's piece rows use the same
  per-piece resolution on the same default variant — they can no longer
  disagree (e.g. "Karazhan" in the list vs "Gruul's Lair" on the pieces).

### Fixed
- Tooltips no longer inherit the window's scale (they rendered bigger or
  smaller than the rest of the UI depending on the window-size setting).
- Hint-only tooltips (Guide me, preview) start with a proper title line
  instead of an oversized first sentence.

## [0.1.0] - 2026-08-07

### Added
- Initial release: two-pane set browser (list + detail) over every journal
  transmog set, with live collection progress.
- Filters: possession state, expansion, content type, class selector,
  opposite-faction / unobtainable toggles; instant text search; three sort modes.
- Detail pane: variant selector, per-piece rows with item icon (collected state
  as border/desaturation), slot, quality-colored name and
  boss/instance/difficulty source lines; piece preview (Ctrl+click), chat link
  (Shift+click), full-set "Try on", journal deep-link.
- Preview pane: the player's character wearing the selected set (rotate/zoom),
  toggleable between the full set and only the owned pieces.
- "Guide me": native waypoint + on-screen 3D direction arrow to the instance
  with the most missing pieces (right-click to choose); optional FarstriderLib
  turn-by-turn routing with clickable travel actions.
- "New set piece" toast with fresh set progress, plus a distinct "set complete"
  toast; configurable in the native Settings panel (with sub-pages Window /
  Arrow / Notifications and an about page).
- Minimap button, `/esc` slash commands, enUS + frFR localization.
- Dev tooling: in-game generator (`/esc gen`) + `build-sets.mjs` data pipeline,
  Lua syntax check, packaging and deploy scripts, GitHub Actions validate +
  release (CurseForge) workflows.
