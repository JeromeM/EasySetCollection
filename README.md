# EasySetCollection

A World of Warcraft (retail) addon that makes transmog **set** collecting actually
pleasant: a clear two-pane browser of every journal set — owned, partially
collected or missing — with **per-piece sources** (which boss, which instance,
which difficulty) and a **"Guide me"** button that points you straight at the
raid, dungeon or zone that drops it.

Pure Lua, zero libraries, flat modern look, native waypoints + on-screen 3D arrow.

## Features

- **Set browser**: scrollable list of every base set with icon, collection
  progress (X/N + bar), expansion / content-type / class tags, favorites first.
- **Filters & search**: instant text search, possession state (complete /
  partial / none), expansion, content type (raid / dungeon / PvP / quest /
  vendor / world), class selector (my class by default, any class, or all),
  opposite-faction and unobtainable toggles. Three sort modes (expansion,
  alphabetical, closest-to-completion).
- **Detail pane**: variants (Normal / Heroic / Mythic / LFR recolors) as
  segmented buttons, one row per piece with its item icon (green border =
  collected, desaturated = missing), slot, quality-colored name and the exact
  source ("Boss – Instance (Difficulty)"). Ctrl+click previews a piece,
  Shift+click links it in chat, "Try on" opens the dressing room.
- **Preview pane**: your own character wearing the selected set, right in the
  window (drag to rotate, wheel to zoom) — switchable between the full set and
  only the pieces you own.
- **Guide me**: left-click sets a native waypoint + on-screen direction arrow to
  the instance holding the most missing pieces; right-click picks among every
  known source. With [FarstriderLib](https://www.curseforge.com/wow/addons/farstriderlib)
  installed (optional), you get turn-by-turn routing with clickable
  hearthstone/teleport actions.
- **Loot toast**: a small notification whenever you collect a new set piece,
  showing the set's fresh progress — and a green one when a set is completed.
  Optional, with or without sound (Options → EasySetCollection → Notifications).

## Usage

- `/esc` (or `/easyset`) — open/close the window. There's a minimap button too,
  and a bindable key (Options → Keybindings → AddOns → EasySetCollection).
- `/esc guide` — re-set the waypoint to the selected set.
- `/esc minimap`, `/esc arrow`, `/esc help` — the usual toggles.

Everything is resolved live from the game client, so names, bosses, instances
and difficulties are always in your language (frFR fully translated).

## Development

```
EasySetCollection/    the addon (pure Lua, no libs — see HANDOFF.md)
scripts/              dev tooling (Node 20+, `npm install` once)
```

- `npm run check` — Lua 5.1 syntax check of every addon file.
- `scripts/deploy.sh` — copy the addon into your `Interface/AddOns`.
- Data generation (dev only): `/esc gen` in game → `/reload` → copy
  `WTF/.../SavedVariables/EasySetCollection.lua` to `data/sets-export.lua` →
  `npm run build` → regenerated `Data/SetSources.lua` + `Data/Instances.lua`.
  The public zip (`scripts/package.sh`) strips the generator.
- `Data/Overrides.lua` is the hand-authored escape hatch: navigation targets for
  quest/vendor/PvP sets, classification fixes, unobtainable flags. `/esc missing`
  lists the sets that still need one.

## License / credits

By JeromeM. Issues and suggestions: https://github.com/JeromeM/EasySetCollection/issues

My other addons: [EasyMountFarmer](https://github.com/JeromeM/EasyMountFarmer) —
a guided, one-mount-at-a-time farming route planner.
