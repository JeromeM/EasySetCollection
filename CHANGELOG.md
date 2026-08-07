# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
