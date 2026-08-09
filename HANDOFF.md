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
- `Core/Profiles.lua` — hand-rolled settings profiles (AceDB UX, zero lib):
  `DB.profiles[name]` tables + `DB.profileKeys[char]` + `DB.global` (account
  bits: `onboard`, `forceEnglish` — exposed as `ns.gdb`). `ns.db` IS the
  active profile; the rest of the addon never knows profiles exist. Flat v1
  saved vars migrate into the Default profile on first load. SeedDefaults
  (moved out of Core.lua) seeds any profile; Switch/CopyFrom/Reset/Delete +
  Apply (re-push scale/position/minimap/arrow + refresh). Management UI:
  "Profiles" canvas sub-page (UI.BuildProfilesPanel) with click-generated
  MenuUtil menus.
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
- `Data/Vendors.lua` (GENERATED) — the baked vendor layer (Wowhead import,
  fetch-vendor-sources.mjs): `npcs[npcID] = { name (English, displayed via
  ns.L), map (uiMapID), x, y }`, `sets[setID] = { { n=npcID, s=side? } }`
  (side 1=Alliance 2=Horde, omitted=both; Sources.VendorFor picks by faction,
  located vendors first) and `costs[itemID] = { g=copper, c={{currencyID,qty}},
  i={{itemID,qty}} }`. Powers vendor names in source lines/labels, per-piece
  price display (Sources.PieceCost), the LocationLabel zone fallback, and a
  LAST-RESORT GuideTargets map target flagged `vendor=true` — Suggest skips
  those (farm-only spirit), the Guide button uses them.
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
  Every per-piece function resolves through farmSource(): when the set's own
  item is NOT a boss drop, a boss-drop sibling of the same appearance
  (GetAllAppearanceSources) becomes the piece's farmable face — T11 heroic
  "vendor" pieces are farmed off Maloriak & co. TOKEN pieces (tier sets, no
  sibling) are promoted the same way when their OWN GetAppearanceSourceDrops
  is non-empty (the client encodes the token→boss chain there): T5 "vendor"
  pieces classify, label, lock and guide as Serpentshrine/Tempest Keep drops. Difficulty FACETS (size ×
  tier from difficultyID) power all difficulty comparisons — the client names
  the same difficulty three different ways.
- `Modules/Lockouts.lua` — weekly lockouts (`GetSavedInstanceInfo`, refreshed
  via `RequestRaidInfo` on PEW/BOSS_KILL → `UPDATE_INSTANCE_INFO`), indexed by
  localized instance name (joins the EJ names used by Sources' guide targets).
  `SetState(setID)` → "cleared"/"partial"/nil + per-instance details, cached;
  variant difficulty (set description ∈ GetDifficultyInfo names) selects the
  matching lockout only — and is only ENFORCED when the group has ≥2
  difficulty-named variants (vanilla sets say "Normal", their lockout says
  "40 Player"). Cata/MoP RAIDS (baked inst.tier 4/5) share one lockout across
  every size and difficulty: for them pickLock/BossDead ignore facets — any
  difficulty's lockout locks them all. The lockout↔instance join is NUMERIC
  first —
  GetSavedInstanceInfo's 14th return (instanceMapID) vs EJ_GetInstanceInfo's
  10th — because localized names disagree between the two lists ("Temple
  noir" saved vs "Le Temple noir" in the EJ); normKey'd names (lowercase,
  ’→', punctuation stripped) remain as fallback only. Verdicts invalidated on collection changes (missing
  counts move). NOTE: the hideCleared filter resolves GuideTargets for every
  passing group on first use — if that first toggle hitches with a cold drops
  cache, precompute or restrict to raid/dungeon buckets.
- `Modules/Suggest.lua` — "farm the closest thing": sweeps the catalog (own
  class, obtainable, incomplete, not Lockouts-"cleared", and per-target at
  least one missing piece whose boss is still up — farmableMissing over
  Lockouts.BossDead with the variant's difficulty facets), resolves each
  candidate's primary guide target to continent world space (EntranceForInstance
  → GetWorldPosFromMapPos, cached per session) and ranks same-continent by
  distance, the rest by fewest-missing. Go() selects + scrolls the list
  (SetList.ScrollTo) and guides. Footer button (left/right click) + `/esc
  suggest`.
- `Modules/Assist.lua` — in-instance assistant: on PEW (+3s) / zone change,
  EJ_GetInstanceForMap resolves where we are; MissingHere(jid) sweeps the
  class's incomplete groups through Sources.PieceInstanceSet (multi-drop) and
  PieceEncounterIn, DIFFICULTY-AWARE through Sources' difficulty FACETS
  (size 10/25/40 × tier normal/heroic/mythic/lfr, from difficultyID; names
  compared by facet compatibility because the client is inconsistent —
  instance "25 Player (Heroic)" vs variant "Heroic" vs drop "25 Player"):
  variantFor picks the compatible variant, pieces filter per-drop through
  Sources.PieceMatchesDifficulty (10/25-player sets share one jid — without
  this, both announce everywhere); announces once per visit+difficulty via
  UI.NotifyAssist
  (silent toast, title override) + a boss-by-boss chat list. `db.assist.enabled`
  toggle in Notifications (+ `.toast` for the toast alone). Feeds UI.Show's
  open-on-current-instance selection (BestGroupHere). Boss TOOLTIPS (unit and
  Encounter Journal) were attempted and dropped on 2026-08-07 — unit names are
  secret values in instances (gotcha below) and the EJ boss-button hover hook
  (EncounterJournal_DisplayInstance + EncounterJournalBossButton<i>) never
  fired on 12.x; the EJ frame structure needs in-game inspection first.
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
- `UI/Onboard.lua` — first-open tour: three sequential bubbles (search →
  Suggest → options gear) with a pulsing outline on the spotlighted control;
  state in `db.onboard` (`step` resumes a closed-mid-tour window, `done` ends
  it for good, `hello` = the one-time /esc chat hint printed only on a
  genuinely fresh install — `ns.firstInstall`, set when EasySetCollectionDB
  was nil at ADDON_LOADED). Entry point `Onboard.MaybeStart()` from UI.Show.
- `UI/Setup.lua` — first-install setup WIZARD (installer-style window, 5
  pages: welcome → guidance → notifications → window/minimap → done) binding
  the same db fields as the Settings pages. Auto-opens at login while
  `db.onboard.wizard` is unset — set on any close, and STAMPED for existing
  installs in initSavedVars (upgraders never see it); `/esc setup` reruns it.
  Complements the bubble tour: the wizard configures, the tour shows where
  things are.
- `Tools/Generator.lua` (DEV, stripped by package.sh) — see below.
- `Core/Core.lua` — saved vars defaults, events, slash `/esc`.

## API gotchas (verified against wow-ui-source / wiki during design)

- **12.x SECRET VALUES (verified in game 2026-08-07)**: inside instances, unit
  NAMES reach addons as secret strings by every path (GameTooltip:GetUnit,
  UnitName, C_TooltipInfo lines) — any index/compare in tainted code throws
  "attempt to index … a secret string value". Guard with `issecretvalue()`.
  Consequence: boss unit tooltips cannot be matched by name — any future
  boss-tooltip feature must key on IDs (GUID npcID, if readable) with baked
  npc→encounter data, or decorate our own UI instead.

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
   Wowhead importers (DEV-ONLY, throttled ~1 req/s, resumable, stop cleanly
   when CloudFront starts blocking):
   - `fetch-quest-sources.mjs` fills the old-content quest gaps (XML feed);
     its `--deep` pass re-tries the XML misses through the full item page's
     "Reward from" listview (663→880/1260 matched). The ~380 still-unmatched
     "quest" pieces are mostly client mislabels (really crafted / boss drops /
     world drops — spot-checked); the HTML page does NOT embed the item's own
     sourcemore, so a future classification fix needs an XML re-pass over the
     misses recorded in `data/item-sources.json`.
   - `fetch-vendor-sources.mjs` resolves vendor sets: one representative
     piece per set → "sold by" listview (npc, faction react, zone, price),
     then every discovered npc page → g_mapperData coords. `--costs` is the
     long full-piece price crawl (7k+ items, run overnight). Wowhead zone ids
     are AreaTable ids: hand-map them to uiMapIDs in `data/zone-uimap.json`
     (the build warns, with URLs, about unmapped ones).
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
