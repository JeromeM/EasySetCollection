-- Profiles.lua — hand-rolled settings profiles (the AceDB UX without the lib).
-- EasySetCollectionDB.profiles holds named settings tables, profileKeys maps
-- each character to the profile it uses, and `global` keeps the account-wide
-- bits (onboarding state, forced language). ns.db always points at the ACTIVE
-- profile — the rest of the addon never knows profiles exist; ns.gdb is the
-- global table. The management UI is the "Profiles" canvas sub-page in the
-- game's Settings panel (UI/UI.lua).

local ADDON, ns = ...

ns.Profiles = ns.Profiles or {}
local P = ns.Profiles

local DEFAULT = "Default"

function P.CharKey()
  return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

local function deepcopy(src)
  local out = {}
  for k, v in pairs(src) do
    out[k] = (type(v) == "table") and deepcopy(v) or v
  end
  return out
end

--- One-time v1 migration (flat saved vars -> Default profile) and binding of
--- ns.db (this character's profile) + ns.gdb (account-wide) for the session.
function P.Init()
  local DB = EasySetCollectionDB
  if not DB.profiles then
    -- v1 -> v2: every legacy top-level key becomes the Default profile;
    -- account-level state moves to `global` (nobody loses their settings)
    local prof = {}
    for k, v in pairs(DB) do
      prof[k] = v
      DB[k] = nil
    end
    DB.profiles = { [DEFAULT] = prof }
    DB.profileKeys = {}
    DB.global = { onboard = prof.onboard, forceEnglish = prof.forceEnglish }
    prof.onboard, prof.forceEnglish = nil, nil
  end
  DB.global = DB.global or {}
  DB.profileKeys = DB.profileKeys or {}
  DB.profiles[DEFAULT] = DB.profiles[DEFAULT] or {}
  ns.gdb = DB.global

  local name = DB.profileKeys[P.CharKey()]
  if not name or not DB.profiles[name] then name = DEFAULT end
  DB.profileKeys[P.CharKey()] = name
  ns.db = DB.profiles[name]
end

--- Seed every missing field of a profile table (the `if nil` idiom keeps
--- explicit `false` values; back-fills new keys on upgrade).
function P.SeedDefaults(db)
  db.minimap = db.minimap or { angle = 200, hide = false }
  if db.windowScale == nil then db.windowScale = 1 end
  if db.locked == nil then db.locked = false end
  if db.shown == nil then db.shown = false end
  if db.autoGuide == nil then db.autoGuide = true end
  if db.sort == nil then db.sort = "expansion" end
  if db.favoritesFirst == nil then db.favoritesFirst = true end
  if db.listTab == nil then db.listTab = "journal" end   -- "journal" | "extra"
  db.extraFav = db.extraFav or {}          -- favorites of out-of-journal sets

  db.arrow = db.arrow or {}
  if db.arrow.enabled == nil then db.arrow.enabled = true end
  if db.arrow.scale == nil then db.arrow.scale = 1 end
  if db.arrow.textScale == nil then db.arrow.textScale = 1 end

  db.toast = db.toast or {}
  if db.toast.enabled == nil then db.toast.enabled = true end
  if db.toast.sound == nil then db.toast.sound = true end
  if db.toast.onlyComplete == nil then db.toast.onlyComplete = false end
  if db.toast.showPiece == nil then db.toast.showPiece = true end
  if db.toast.showSet == nil then db.toast.showSet = true end
  if db.toast.showProgress == nil then db.toast.showProgress = true end
  if db.toast.showOtherSets == nil then db.toast.showOtherSets = true end
  if db.toast.otherClasses == nil then db.toast.otherClasses = false end
  if db.preview == nil then db.preview = "full" end   -- "full" | "owned"

  db.assist = db.assist or {}
  if db.assist.enabled == nil then db.assist.enabled = true end
  if db.assist.toast == nil then db.assist.toast = true end
  if db.assist.announceExtras == nil then db.assist.announceExtras = false end

  db.tracker = db.tracker or {}
  if db.tracker.hideCollected == nil then db.tracker.hideCollected = false end
  if db.tracker.autoGuide == nil then db.tracker.autoGuide = true end
  if db.tracker.locked == nil then db.tracker.locked = false end

  db.filters = db.filters or {}
  local fl = db.filters
  fl.possession = fl.possession or {}
  for _, k in ipairs({ "complete", "partial", "none" }) do
    if fl.possession[k] == nil then fl.possession[k] = true end
  end
  fl.contentTypes = fl.contentTypes or {}
  for _, k in ipairs(ns.CONTENT_BUCKETS or {}) do
    if fl.contentTypes[k] == nil then fl.contentTypes[k] = true end
  end
  fl.expansions = fl.expansions or {}
  local maxExp = (GetClientDisplayExpansionLevel and GetClientDisplayExpansionLevel())
    or LE_EXPANSION_LEVEL_CURRENT or 11
  for e = 0, maxExp do
    if fl.expansions[e] == nil then fl.expansions[e] = true end
  end
  if fl.otherFaction == nil then fl.otherFaction = false end
  if fl.showLegacy == nil then fl.showLegacy = true end
  if fl.hideCleared == nil then fl.hideCleared = false end
  -- fl.classID stays nil by default: nil = current class, 0 = all classes
end

--- Name of this character's active profile.
function P.Current()
  return EasySetCollectionDB.profileKeys[P.CharKey()] or DEFAULT
end

--- Sorted list of every profile name.
function P.List()
  local names = {}
  for name in pairs(EasySetCollectionDB.profiles) do names[#names + 1] = name end
  table.sort(names)
  return names
end

--- Push the active profile onto the live UI: window scale/position, minimap
--- button, arrow — then repaint everything that renders db state.
function P.Apply()
  local UI = ns.UI
  if UI and UI.frame then
    UI.frame:SetScale(ns.db.windowScale or 1)
    if UI.RestorePosition then UI.RestorePosition() end
  end
  if ns.Minimap and ns.Minimap.button then
    ns.Minimap.button:SetShown(not (ns.db.minimap and ns.db.minimap.hide))
    if ns.Minimap.UpdatePosition then ns.Minimap.UpdatePosition() end
  end
  if ns.Arrow and ns.Arrow.Hide and ns.db.arrow and ns.db.arrow.enabled == false then
    ns.Arrow.Hide()
  end
  if UI and UI.frame and UI.frame:IsShown() and UI.RefreshAll then UI.RefreshAll() end
  if ns.Tracker and ns.Tracker.Refresh then ns.Tracker.Refresh() end
end

--- Switch this character to profile `name` (created and seeded when missing).
function P.Switch(name)
  if not name or name == "" then return end
  local DB = EasySetCollectionDB
  DB.profiles[name] = DB.profiles[name] or {}
  DB.profileKeys[P.CharKey()] = name
  ns.db = DB.profiles[name]
  P.SeedDefaults(ns.db)
  P.Apply()
end

--- Overwrite the ACTIVE profile with a copy of another one's contents.
function P.CopyFrom(src)
  local from = EasySetCollectionDB.profiles[src]
  if not from or from == ns.db then return end
  wipe(ns.db)
  for k, v in pairs(deepcopy(from)) do ns.db[k] = v end
  P.SeedDefaults(ns.db)
  P.Apply()
end

--- Reset the ACTIVE profile to the defaults.
function P.Reset()
  wipe(ns.db)
  P.SeedDefaults(ns.db)
  P.Apply()
end

--- Delete a profile (never Default, never one in use by THIS character);
--- other characters bound to it fall back to Default.
function P.Delete(name)
  local DB = EasySetCollectionDB
  if name == DEFAULT or not DB.profiles[name] or DB.profiles[name] == ns.db then return end
  DB.profiles[name] = nil
  for charKey, prof in pairs(DB.profileKeys) do
    if prof == name then DB.profileKeys[charKey] = DEFAULT end
  end
end
