# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **1,720 out-of-journal sets** — dungeon recolors, world sets, old PvP
  off-sets, event gear: everything the game's sets journal doesn't list, on
  a new "Off-journal" tab. They behave like any other set: per-piece sources,
  farm guidance, weekly lockouts, the in-instance assistant (opt-in) and the
  dressing-room preview all work; Suggest deliberately sticks to journal
  sets. (Set names for these come from the community and exist in English
  only.) New sets ship automatically every week as small X.Y.Z.N data
  updates, with the additions listed in the release notes.

### Added
- **Vendor sets know their vendor**: pieces sold by a NPC now name it and show
  its price (gold, currencies, tokens), the set list shows the vendor's zone,
  and the Guide button walks you to the seller. Suggest deliberately keeps
  ignoring them — it suggests farms, not shopping trips.
- **First-install setup**: a small setup window walks new installs through
  the day-one options (guidance, notifications, window size, minimap button)
  — rerun it anytime with `/esc setup` or the "?" button next to the window's
  gear icon. Existing installs never see it uninvited. Its first page can
  adopt an existing settings profile directly (skipping the setup), or
  create a new one to configure.
- **Settings profiles**: named profiles hold every setting, each character
  picks the one it uses (like the big addon suites) — switch, create, copy,
  reset and delete them from Options → Profiles. Existing settings become
  the "Default" profile, shared by all characters until told otherwise;
  tracked sets stay per-character.
- **First-open tour**: three short bubbles introduce the search, the Suggest
  button and the options the first time the window opens (skippable, shown
  once). A brand new install also gets a one-time chat hint about `/esc`.

### Changed
- The expansion sort says what it does: a star on the sort button (and a
  tooltip) shows that favorites float to the top — and the sort menu now has
  a "Favorites first" switch to turn that off.
- The window closes with `Esc`, like any other panel.
- Notifications answer the mouse: right-click dismisses one and brings up the
  next queued one (handy to scan a burst of loot), left-click opens the window
  on the set it is about.
- The set list tags rows with their category (Raid, Dungeon, Vendor, …); the
  full story moved to the detail pane, which now lists EVERY place the set
  comes from — all its instances, then World, Vendor and the like. No more
  "the list says Serpentshrine but this piece says Tempest Keep".
- Piece rows: left-click selects a piece and the Guide button walks you to
  THAT piece (its instance — or its vendor); right-click toggles the piece
  in the preview (shift-click still links it in chat).
- Many more quest sets name their quest (and can be guided to): the source
  import now recovers quest IDs the previous pass missed on old content.

### Fixed
- Tier sets bought with boss tokens (T4/T5/T6…) no longer read "Vendor": the
  pieces classify, label and guide as drops of the instance their token falls
  in, the set list names that instance, and the in-instance assistant and
  lockouts treat them like any other boss farm.

### Changed
- Suggest judges "farmable" per boss: an instance where every boss holding
  your missing pieces is already dead this week is skipped, even when its
  lockout isn't fully cleared.

### Fixed
- The minimap button sits on the minimap's actual edge (resized minimaps kept
  it inside the ring), honours square-minimap addons (GetMinimapShape), and
  its tooltip now mentions it can be dragged around.
- Our tooltips' scale correction no longer lingers on the shared GameTooltip
  (with a resized window, every other tooltip in the game inherited it).
- Cataclysm and Mists raids share one lockout across every size and
  difficulty (a 25-heroic clear blocks 10/25 normal too): their lockouts now
  lock all variants of a set — no more suggesting a normal-mode farm the
  game won't let you enter. An active lockout also binds the week's ENTRY to
  its difficulty, so pieces of the other difficulty stop counting as
  farmable even when their bosses are still alive.

## [1.1.1] - 2026-08-08

### Changed
- The assistant's chat lines link the actual items (clickable) and flag the
  bosses already defeated this week in red.

### Fixed
- Pieces whose appearance can also be looted from a boss now lead with that
  boss source instead of "Vendor" (the T11 heroic vendor pieces share their
  looks with Blackwing Descent / Bastion of Twilight drops): the source line
  names the boss, and guidance, the in-instance assistant and the lockouts
  all treat the piece as farmable there.
- The in-instance assistant honours the difficulty you entered on: it inspects
  the variant matching the instance's difficulty and only announces pieces
  that actually drop on it — no more 10-player pieces listed in a 25-player
  raid. Difficulties are compared by their size/tier facets, so a "Heroic"
  recolor correctly matches a "25 Player (Heroic)" instance; lockout matching
  uses the same rule. The open-on-current-instance selection (and the variant
  it opens on) follows too.
- Lockouts join their instance by numeric id instead of localized name — some
  instances are named differently in the saved-instances list and in the
  Encounter Journal ("Temple noir" vs "Le Temple noir" in French), which left
  their sets without lock state.

## [1.1.0] - 2026-08-08

### Added
- **In-instance assistant**: entering a dungeon or raid where set pieces you
  miss still drop shows a toast with the count and prints the detail — boss,
  piece, set — in the chat frame, once per visit. Toggle in Options →
  Notifications (the toast independently of the announcement). Opening the
  window inside an instance selects the place's most relevant set. The Track
  button's tooltip now mentions its right-click.
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
