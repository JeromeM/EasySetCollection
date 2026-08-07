# HANDOFF — EasySetCollection architecture notes

Context document for future work sessions. Written 2026-08-07, at v0.1.0
(initial implementation, not yet tested in game).

## What this addon is

A transmog **set** collection browser + farm guide for retail WoW (Interface
120007). House conventions: pure Lua, zero libraries, no XML,
`local ADDON, ns = ...` namespace, `Core/Locale.lua` loads first (metatable
`ns.L`, English keys as fallback), `Core/Core.lua` loads last (wiring), flat
WHITE8x8 design kit, native Settings panel, hand-rolled minimap button,
generated-data + hand-override data layer, custom CI/packaging scripts.

## Module map (load order = .toc order)

- `Core/Locale.lua` — `ns.L` metatable + `ns.Print`.
- `Locales/enUS.lua`, `frFR.lua` — enUS is the reference key list; frFR guarded
  by `GetLocale()`.
- `Data/SetSources.lua` (GENERATED) — `EasySetCollectionSets[setID] = { ct, st,
  j, pieces = { [sourceID] = { j } } }`. IDs only, never strings. Ships empty
  until the first generation; everything still works via live fallbacks.
- `Data/Instances.lua` (GENERATED) — `EasySetCollectionInstances[jid] = { raid,
  tier, map, x, y }` (entrance fallback, 0-100 coords).
- `Data/Overrides.lua` (HAND) — `EasySetCollectionOverrides.sets[baseSetID or
  setID]` (map/x/y/npc/questID nav targets, `ct`/`j` corrections, `legacy`) and
  `.instances[jid]` (`entranceMaps` for moving portals, manual entrance coords).
- `Modules/Sets.lua` — the catalog: `GetAllSets()` grouped by `baseSetID`;
  precomputes name/nameLower/expansionID/classMask/classSummary/hidden/favorite
  + `bucket`/`legacy` via `Sources.ClassifyGroup`. `EnsureCatalog()` returns nil
  until collection data exists; `Invalidate()` on every collection event.
- `Modules/Pieces.lua` — progress (X/N over **GetSetPrimaryAppearances**, the
  Blizzard-canonical computation), per-piece records, slot labels, item links,
  set icon (best head-to-feet piece via `EJ_GetInvTypeSortOrder`), progress
  cache + targeted invalidation.
- `Modules/Sources.lua` — the three-layer source resolution (overrides > baked >
  live `GetAppearanceSourceDrops` + a lazily-built EJ name index), content-type
  classification, `GuideTargets(setID)` / `NavFor(setID)`, `/esc missing` dump.
- `Modules/Lockouts.lua` — weekly lockouts (`GetSavedInstanceInfo`, refreshed
  via `RequestRaidInfo` on PEW/BOSS_KILL → `UPDATE_INSTANCE_INFO`), indexed by
  localized instance name (joins the EJ names used by Sources' guide targets).
  `SetState(setID)` → "cleared"/"partial"/nil + per-instance details, cached;
  variant difficulty (set description ∈ GetDifficultyInfo names) selects the
  matching lockout only. Verdicts invalidated on collection changes (missing
  counts move). NOTE: the hideCleared filter resolves GuideTargets for every
  passing group on first use — if that first toggle hitches with a cold drops
  cache, precompute or restrict to raid/dungeon buckets.
- `Modules/Filters.lua` — the filter/sort pipeline (single O(#groups) pass).
- `Navigation/*` — the waypoint/arrow/routing stack. `Waypoint.lua`:
  `ns.EntranceForInstance(jid)` (live `GetDungeonEntrancesForMap` over override
  entranceMaps + baked entrance map, then baked/override coords) and
  `Waypoint.GuideToTarget({jid}|{map,x,y})`. `Nav.lua` exposes
  `Nav.GuideTo(target)` (FarstriderLib first hop, optional dep). `Arrow.lua` is
  the sprite-sheet 3D direction arrow (Media/arrow.tga, 8×8 = 64 frames; its
  top line comes from `UI.ArrowText()` = last guided set); `Travel.lua` the
  docked secure travel-action button.
- `UI/Widgets.lua` — the shared design kit
  (BD1/palette/MakeButton/MakePanel/MakeCheckRow/Paint*) + `MakeSearchBox`
  (debounced 150ms) and `MakeProgressBar`.
- `UI/UI.lua` — 760×560 two-pane shell, toolbar (search / class dropdown /
  Filters badge), footer (counts / sort), Settings pages (about canvas +
  Window / Arrow / Notifications sub-pages, `leftAlignCheckbox` hack), and the
  queued loot **toast** (`NotifyNewPiece`).
- `UI/SetList.lua` — the left list: `WowScrollBoxList` + `MinimalScrollBar` +
  `CreateScrollBoxListLinearView` (extent 44), lazily-built Button rows,
  loading/empty states. **If the ScrollBox templates misbehave in game, the
  fallback is a manual 10-row pool — the row painting code is reusable as-is.**
- `UI/Detail.lua` — middle pane: variants as segmented buttons, piece rows
  (item icon = collected state, async item names via `Item:ContinueOnItemLoad`,
  coalesced repaint), action row (Guide / Try on / Journal), Travel dock, and
  the PREVIEW pane (third column): a `DressUpModel` of the player wearing the
  set (`SetUnit("player")` → `Undress()` → `TryOn(sourceID)` per piece, keyed
  on setID+mode+`Pieces.stamp` to avoid re-pose flicker), with a full-set /
  owned-pieces toggle persisted in `db.preview`. Combat-guarded (the layout
  shows/hides the docked secure button).
  Font note: WoW fonts lack ✓ ✗ ▾ ★ glyphs (they render as squares) — use item
  icons, `W.AddDropdownArrow` (rotated ChatFrameExpandArrow texture) and the
  FavoritesIcon texture instead.
- `UI/FilterPanel.lua` — side filter panel + MenuUtil class/sort dropdowns.
- `Tools/Generator.lua` (DEV, stripped by package.sh) — see below.
- `Core/Core.lua` — saved vars defaults, events, slash `/esc`.

## API gotchas (verified against wow-ui-source / wiki during design)

- `TransmogSetPrimaryAppearanceInfo.appearanceID` **is a sourceID**
  (itemModifiedAppearanceID) despite its name — Blizzard's own
  `WardrobeSetsDataProviderMixin` feeds it to `GetSourceInfo`.
- `AppearanceSourceInfo.sourceType` is a **luaIndex 1..7** matching the
  `TRANSMOG_SOURCE_<n>` localized globals (1=Boss Drop, 2=Quest, 3=Vendor,
  4=World, 5=Achievement, 6=Profession, 7=Trading Post). It is NOT
  `Enum.TransmogSource` (different numbering). `ns.SRC` holds our constants.
- Enumerate with `C_TransmogSets.GetAllSets()`, never `GetBaseSets()` — the
  latter is mutated by the client's persistent wardrobe filters.
- `C_TransmogCollection.GetAppearanceSourceDrops(sourceID)` returns **localized
  strings only** (instance/encounter/difficulties, no IDs) — display uses them
  directly; navigation needs the generator's name→ID resolution.
- The sets-journal filters (`SetBaseSetsFilter`, `SetTransmogSetsClassFilter`)
  are persistent client state shared with the Blizzard UI: the generator saves
  and restores all of them around its PvP snapshot.
- Group progress = **best variant's** X/N (Blizzard `GetBaseSetData` pattern);
  a variant is hidden while `hiddenUntilCollected and not collected`.
- Secure travel button: parented to UIParent, anchored to a Frame (never to a
  region), all attribute/visibility changes deferred out of combat.

## Data generation workflow (dev)

1. In game: `/esc gen` (a few seconds, chunked; EJ index → entrance harvest →
   PvP snapshot → per-set sweep with retry rounds for late drop data).
   Then optionally `/esc genquests` (~10-15 min): sweeps every questID's
   rewards (RequestLoadQuestByID + GetQuestLogRewardInfo/ChoiceInfo) and
   matches them against the quest pieces' itemIDs — the client has no
   item→quest API, so the mapping is rebuilt in reverse. Early-exits once
   every quest item is matched.
2. `/reload` to flush `EasySetCollectionGen` to disk.
3. Copy `WTF/Account/<acct>/SavedVariables/EasySetCollection.lua` to
   `data/sets-export.lua`.
4. `npm run build` → rewrites `Data/SetSources.lua` + `Data/Instances.lua`,
   prints unresolved instance names (→ add to `Data/Overrides.lua`) and the
   count of nav-less sets.
5. `scripts/deploy.sh` to test; `/esc missing` for the overrides worklist.

The build compresses aggressively: only per-piece **instance deviations** are
baked (a piece dropping outside the set's dominant instance). Encounter IDs are
collected in the export but deliberately NOT baked (unused at runtime so far).

## Status & next steps (as of v0.1.0)

- All 22 Lua files pass luaparse (5.1); **not yet loaded in the game client.**
- In-game probes to run early (from the plan's risk list):
  - `/dump C_TransmogCollection.GetAppearanceSourceDrops(sourceID)` for an
    uncollected piece AND a piece of another class's set — if cross-class fails,
    the generator needs a per-class EJ loot sweep fallback (`EJ_SetLootFilter`
    + `EJ_LOOT_DATA_RECIEVED`, itemID → instance join).
  - `/dump C_TransmogSets.GetSetPrimaryAppearances(setID)` for another class's
    set — if `collected` is unreliable, use
    `PlayerHasTransmogItemModifiedAppearance` per piece.
  - Check `WowScrollBoxList`/`MinimalScrollBar` render correctly on 12.x.
- No real generated data yet (`Data/*.lua` ship as empty skeletons; the runtime
  EJ-name-index fallback makes the addon usable regardless).
- `Data/Overrides.lua` is empty — quest/vendor/PvP sets have no Guide target
  until authored (`/esc missing` lists them, newest first).
- Repo workflow: day-to-day work lands on `develop`; PRs into `main` only on
  request. There is deliberately NO CurseForge release CI yet — it will be
  added later (triggered by PR merges into `main`), with the repo secrets/vars
  (`CF_API_KEY`, `CF_PROJECT_ID`) once a CurseForge project exists.
- Release gotcha for that future workflow: tag AFTER uploading means a failed
  upload leaves no tag and the next merge re-publishes (CurseForge duplicate).
