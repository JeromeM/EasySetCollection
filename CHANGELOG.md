# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
