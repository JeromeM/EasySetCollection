# EasySetCollection

A World of Warcraft (retail) addon that makes transmog **set** collecting actually
pleasant: a clear two-pane browser of every journal set — owned, partially
collected or missing — with **per-piece sources** (which boss, which instance,
which difficulty) and a **"Guide me"** button that points you straight at the
raid, dungeon or zone that drops it.

Pure Lua, zero libraries, flat modern look, native waypoints + on-screen 3D arrow.

## Features

- **Set browser**: scrollable list of every base set with icon, collection
  progress (X/N + bar), expansion / content-type / class tags. Two tabs:
  the game's **Journal** sets, and **1,720 off-journal sets** — dungeon
  recolors, world sets, old PvP off-sets, event gear the sets journal simply
  doesn't list, farmable exactly like the rest.
- **Filters & search**: instant text search, possession state (complete /
  partial / none), expansion, content type (raid / dungeon / PvP / quest /
  vendor / world), class selector (my class by default, any class, or all),
  opposite-faction and unobtainable toggles, "hide what's locked this week".
  Three sort modes (expansion, alphabetical, closest-to-completion) with an
  optional favorites-first switch.
- **Detail pane**: every place the set comes from (all its instances, then
  World, Vendor, …), variants (Normal / Heroic / Mythic / LFR recolors) as
  segmented buttons, one row per piece with its item icon (green border =
  collected, desaturated = missing), slot, quality-colored name and the exact
  source ("Boss – Instance (Difficulty)", quest name, or vendor + price).
  Left-click selects a piece so "Guide me" leads to **that** piece, right-click
  hides it from the preview, Shift+click links it in chat.
- **Preview pane**: your own character wearing the selected set, right in the
  window (drag to rotate, wheel to zoom) — switchable between the full set and
  only the pieces you own.
- **Guide me**: left-click sets a native waypoint + on-screen direction arrow to
  the instance holding the most missing pieces (or to the vendor selling them);
  right-click picks among every known source. With
  [FarstriderLib](https://www.curseforge.com/wow/addons/farstriderlib)
  installed (optional), you get turn-by-turn routing with clickable
  hearthstone/teleport actions.
- **Suggest**: one click picks the closest set you can still farm *this week* —
  real travel distance, weekly lockouts and already-dead bosses taken into
  account — and guides you there.
- **Weekly lockouts**: sets whose bosses you already killed this week are
  flagged (lock icon, "This week" tooltip) and can be filtered out, so you
  never travel for a raid the game won't let you loot.
- **In-instance assistant**: entering a dungeon or raid that still drops pieces
  you miss announces them boss by boss (clickable item links, defeated bosses
  flagged), and the window opens on the right set for the place. Optional.
- **Loot toast**: a small notification whenever you collect a new set piece,
  showing the set's fresh progress — and a green one when a set is completed.
  Right-click dismisses it (and shows the next), left-click opens the set.
- **Settings profiles**: named profiles hold every setting and each character
  picks the one it uses; a first-install wizard walks new users through the
  essentials (`/esc setup` to rerun it).

## Usage

- `/esc` (or `/easyset`) — open/close the window (`Esc` closes it). There's a
  minimap button too, and a bindable key (Options → Keybindings → AddOns →
  EasySetCollection).
- `/esc suggest` — guide me to the closest set I can still farm this week.
- `/esc guide` — re-set the waypoint to the selected set.
- `/esc setup` — rerun the first-install wizard.
- `/esc minimap`, `/esc arrow`, `/esc help` — the usual toggles.

Everything is resolved live from the game client, so names, bosses, instances
and difficulties are always in your language (frFR fully translated). The
off-journal sets are the exception: the game has no name for them, so they
carry their community (English) names.

## Development

```
EasySetCollection/    the addon (pure Lua, no libs — see HANDOFF.md)
scripts/              dev tooling (Node 20+, `npm install` once)
```

- `npm run check` — Lua 5.1 syntax check of every addon file.
- `scripts/deploy.sh` — copy the addon into your `Interface/AddOns`.
- Data generation (dev only): `/esc gen` in game → `/reload` → copy
  `WTF/.../SavedVariables/EasySetCollection.lua` to `data/sets-export.lua` →
  `npm run build` → regenerated `Data/*.lua`. The public zip
  (`scripts/package.sh`) strips the generator.
- The vendor, quest and off-journal data comes from throttled Wowhead imports
  (`scripts/fetch-*.mjs`); the off-journal harvest reruns weekly in CI and
  ships new sets as small `X.Y.Z.N` data releases.
- `Data/Overrides.lua` is the hand-authored escape hatch: navigation targets for
  quest/vendor/PvP sets, classification fixes, unobtainable flags. `/esc missing`
  lists the sets that still need one.

## License / credits

By JeromeM. Issues and suggestions: https://github.com/JeromeM/EasySetCollection/issues

My other addons: [EasyMountFarmer](https://github.com/JeromeM/EasyMountFarmer) —
a guided, one-mount-at-a-time farming route planner.
