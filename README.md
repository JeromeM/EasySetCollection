# EasySetCollection

A World of Warcraft (retail) addon for transmog **set** collectors. It lists
every set, shows what you are missing, tells you where each piece drops, and
then takes you there.

Pure Lua, no libraries, native waypoints and an on-screen 3D arrow.

## Features

- **Set list**: every set with its icon, your progress (X/N), expansion and
  content type. Two tabs: the sets from the game's journal, and 1,720 sets the
  journal doesn't list (dungeon recolors, world sets, old PvP sets, event
  gear). Both work the same way.
- **Filters and search**: text search, what you own, expansion, content type,
  class, faction, unobtainable sets, and an option to hide what is already
  locked for the week. Sort by expansion, name or progress.
- **Piece list**: each piece shows its icon, slot, name and where it comes
  from: boss and instance with the difficulty, quest name, or vendor and
  price. Click a piece to make "Guide me" take you to that one.
- **Preview**: your character wearing the set, in the window. You can show the
  full set or only the pieces you own.
- **Guide me**: sets a waypoint and shows a 3D arrow to the right instance (or
  to the vendor). Right-click to choose another source. If you also use
  [FarstriderLib](https://www.curseforge.com/wow/addons/farstriderlib), you get
  step-by-step routing with hearthstone and teleport buttons.
- **Suggest**: finds the closest set you can still farm this week and takes you
  there. It skips what is locked and the bosses already killed.
- **Weekly lockouts**: sets you can no longer loot this week are marked, with
  the details in the tooltip.
- **In-instance helper**: when you enter a dungeon or a raid that still drops
  pieces you need, it tells you which boss has what. Can be turned off.
- **Loot notification**: a small popup when you collect a piece, with the new
  progress. Right-click closes it, left-click opens the set.
- **Profiles**: your settings can live in named profiles, one per character if
  you want. New users get a short setup window (`/esc setup` to see it again).

## Usage

- `/esc` (or `/easyset`) — open/close the window (`Esc` closes it). There's a
  minimap button too, and a bindable key (Options → Keybindings → AddOns →
  EasySetCollection).
- `/esc suggest` — guide me to the closest set I can still farm this week.
- `/esc guide` — re-set the waypoint to the selected set.
- `/esc setup` — rerun the first-install wizard.
- `/esc minimap`, `/esc arrow`, `/esc help` — the usual toggles.

Names, bosses, instances and difficulties are read live from the game client, so
they always show up in your language. The addon's own text is in English and
French for now: **if you would like it in your language, I am looking for
translators**, open an issue and say hello. (Off-journal sets are the exception:
the game has no name for them, so they keep their community English names.)

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

By Grommey. Issues and suggestions: https://github.com/JeromeM/EasySetCollection/issues

My other addons: [EasyMountFarmer](https://github.com/JeromeM/EasyMountFarmer) —
a guided, one-mount-at-a-time farming route planner.
