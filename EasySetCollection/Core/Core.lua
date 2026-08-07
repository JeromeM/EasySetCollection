-- Core.lua — initialization, saved variables, slash commands and event wiring.
-- Loads last, so it can wire all other modules together.

local ADDON, ns = ...
local L = ns.L

--- Create the saved-variable tables if missing and seed their default fields.
--- Uses the `if x == nil` idiom so `false` values survive, and back-fills new
--- filter keys on upgrade without wiping the user's choices.
local function initSavedVars()
  EasySetCollectionDB = EasySetCollectionDB or {}
  EasySetCollectionCharDB = EasySetCollectionCharDB or {}
  ns.db = EasySetCollectionDB
  ns.charDB = EasySetCollectionCharDB

  ns.db.minimap = ns.db.minimap or { angle = 200, hide = false }
  if ns.db.windowScale == nil then ns.db.windowScale = 1 end
  if ns.db.locked == nil then ns.db.locked = false end
  if ns.db.shown == nil then ns.db.shown = false end
  if ns.db.autoGuide == nil then ns.db.autoGuide = true end
  if ns.db.sort == nil then ns.db.sort = "expansion" end

  ns.db.arrow = ns.db.arrow or {}
  if ns.db.arrow.enabled == nil then ns.db.arrow.enabled = true end
  if ns.db.arrow.scale == nil then ns.db.arrow.scale = 1 end
  if ns.db.arrow.textScale == nil then ns.db.arrow.textScale = 1 end

  ns.db.toast = ns.db.toast or {}
  if ns.db.toast.enabled == nil then ns.db.toast.enabled = true end
  if ns.db.toast.sound == nil then ns.db.toast.sound = true end
  if ns.db.toast.onlyComplete == nil then ns.db.toast.onlyComplete = false end
  if ns.db.toast.showPiece == nil then ns.db.toast.showPiece = true end
  if ns.db.toast.showSet == nil then ns.db.toast.showSet = true end
  if ns.db.toast.showProgress == nil then ns.db.toast.showProgress = true end
  if ns.db.toast.showOtherSets == nil then ns.db.toast.showOtherSets = true end
  if ns.db.preview == nil then ns.db.preview = "full" end   -- "full" | "owned"

  ns.charDB.trackedSets = ns.charDB.trackedSets or {}
  if ns.charDB.trackedSetID then   -- migrate the old single-set field
    table.insert(ns.charDB.trackedSets, ns.charDB.trackedSetID)
    ns.charDB.trackedSetID = nil
  end

  ns.db.tracker = ns.db.tracker or {}
  if ns.db.tracker.hideCollected == nil then ns.db.tracker.hideCollected = false end
  if ns.db.tracker.autoGuide == nil then ns.db.tracker.autoGuide = true end
  if ns.db.tracker.locked == nil then ns.db.tracker.locked = false end

  ns.db.filters = ns.db.filters or {}
  local fl = ns.db.filters
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
  -- fl.classID stays nil by default: nil = current class, 0 = all classes
end

--- PLAYER_LOGIN handler: build the UI shell, settings pages and minimap button,
--- then restore the window's open/closed state. The set catalog itself is built
--- lazily on first Show (and invalidated by collection events).
local function onLogin()
  ns.UI.Init()
  ns.UI.BuildSettings()
  ns.Minimap.Init()
  if ns.db.shown then ns.UI.Show() end
  -- restore the tracked-set window (it refreshes again once collection data
  -- is ready, via the first TRANSMOG_COLLECTION_UPDATED)
  if ns.Tracker and #(ns.charDB.trackedSets or {}) > 0 then ns.Tracker.Refresh() end
end

-- --- events ---------------------------------------------------------------

-- Collection updates arrive in bursts (a single loot can fire several events),
-- so refreshes are coalesced behind a short timer.
local pendingRefresh
local function queueRefresh()
  if pendingRefresh then return end
  pendingRefresh = C_Timer.NewTimer(0.25, function()
    pendingRefresh = nil
    -- collected/hidden flags snapshotted in the catalog go stale too, so both
    -- caches are rebuilt (synchronous DB reads — cheap even for ~4k sets)
    if ns.Sets then ns.Sets.Invalidate() end
    if ns.Pieces then ns.Pieces.WipeProgressCache() end
    if ns.UI and ns.UI.RefreshAll then ns.UI.RefreshAll() end
    -- the tracker lives outside the main window: refresh it even when hidden
    if ns.Tracker and ns.Tracker.Refresh then ns.Tracker.Refresh() end
  end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
f:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
f:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_REMOVED")
f:RegisterEvent("TRANSMOG_SETS_UPDATE_FAVORITE")
f:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
f:RegisterEvent("QUEST_DATA_LOAD_RESULT")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then initSavedVars() end

  elseif event == "PLAYER_LOGIN" then
    onLogin()

  elseif event == "PLAYER_ENTERING_WORLD" then
    -- the client re-syncs the whole collection after every loading screen and can
    -- replay SOURCE_ADDED in bursts; suppress the loot toast for a few seconds.
    ns.toastGraceUntil = GetTime() + 10
    -- FarstriderLib trail: recompute the next hop once the position settles
    C_Timer.After(1.5, function()
      if ns.Nav and ns.Nav.lastTarget and ns.Nav.Available() then
        ns.Nav.GuideTo(ns.Nav.lastTarget)
      end
    end)

  elseif event == "ZONE_CHANGED_NEW_AREA" then
    -- entered a new zone without a loading screen: advance the trail
    if ns.Nav and ns.Nav.lastTarget and ns.Nav.Available() then
      ns.Nav.GuideTo(ns.Nav.lastTarget)
    end

  elseif event == "TRANSMOG_COLLECTION_UPDATED" then
    queueRefresh()

  elseif event == "TRANSMOG_COLLECTION_SOURCE_ADDED" then
    if ns.Pieces then ns.Pieces.InvalidateSource(arg1) end
    if ns.UI and ns.UI.NotifyNewPiece then ns.UI.NotifyNewPiece(arg1) end
    queueRefresh()

  elseif event == "TRANSMOG_COLLECTION_SOURCE_REMOVED" then
    if ns.Pieces then ns.Pieces.InvalidateSource(arg1) end
    queueRefresh()

  elseif event == "TRANSMOG_SETS_UPDATE_FAVORITE" then
    if ns.Sets then ns.Sets.RefreshFavorites() end
    if ns.UI and ns.UI.RefreshList then ns.UI.RefreshList() end

  elseif event == "TRANSMOG_COLLECTION_ITEM_UPDATE" then
    -- item names/qualities became available: repaint the open details panel only
    if ns.UI and ns.UI.RefreshDetail then ns.UI.RefreshDetail() end

  elseif event == "QUEST_DATA_LOAD_RESULT" then
    -- a quest title we requested (override questID) is now available
    if ns.UI then
      if ns.UI.RefreshList then ns.UI.RefreshList() end
      if ns.UI.RefreshDetail then ns.UI.RefreshDetail() end
    end
  end
end)

-- --- key binding ------------------------------------------------------------
-- Bindings.xml declares EASYSETCOLLECTION_TOGGLE, which calls this global.
-- The key itself is assigned by the player in Options -> Keybindings -> AddOns.
BINDING_HEADER_EASYSETCOLLECTION = "EasySetCollection"
_G["BINDING_NAME_EASYSETCOLLECTION_TOGGLE"] = L["Open/close the window"]

function EasySetCollection_Toggle()
  if ns.UI and ns.UI.Toggle then ns.UI.Toggle() end
end

-- --- slash commands -------------------------------------------------------
SLASH_EASYSETCOLLECTION1 = "/easysetcollection"
SLASH_EASYSETCOLLECTION2 = "/easyset"
SLASH_EASYSETCOLLECTION3 = "/esc"
--- Dispatch a /easysetcollection (/easyset, /esc) slash command; with no argument
--- it toggles the main window, otherwise it runs the matching sub-command.
---@param msg string?  raw command text after the slash (trimmed and lower-cased)
SlashCmdList.EASYSETCOLLECTION = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if msg == "guide" then
    if ns.UI and ns.UI.GuideSelected then ns.UI.GuideSelected() end

  elseif msg == "track" then
    if ns.Tracker and ns.Detail and ns.Detail.setID then
      ns.Tracker.Toggle(ns.Detail.setID)
    end

  elseif msg == "minimap" then
    ns.db.minimap.hide = not ns.db.minimap.hide
    if ns.Minimap.button then
      ns.Minimap.button:SetShown(not ns.db.minimap.hide)
    end

  elseif msg == "arrow" then
    ns.db.autoGuide = not ns.db.autoGuide
    ns.Print(ns.db.autoGuide and L["Auto waypoint arrow: ON"] or L["Auto waypoint arrow: OFF"])

  elseif msg == "debug" then
    -- diagnostics: catalog size, baked-data coverage, current selection
    local nGroups, nSets = ns.Sets.Counts()
    local baked = 0
    for _ in pairs(EasySetCollectionSets or {}) do baked = baked + 1 end
    ns.Print(string.format("locale=%s | groups=%d sets=%d | baked=%d",
      GetLocale(), nGroups, nSets, baked))
    local sel = ns.charDB and ns.charDB.selectedSetID
    if sel then
      local info = C_TransmogSets.GetSetInfo(sel)
      ns.Print(string.format("selected setID=%d (%s)", sel, info and info.name or "?"))
      local nav = ns.Sources.NavFor(sel)
      if nav then
        ns.Print(string.format("nav: jid=%s map=%s x=%s y=%s",
          tostring(nav.jid), tostring(nav.map), tostring(nav.x), tostring(nav.y)))
      else
        ns.Print("nav: none")
      end
    end

  elseif msg == "mapid" then
    -- report the current zone's UiMapID + localized name (handy for override coords)
    local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local info = id and C_Map.GetMapInfo(id)
    ns.Print(string.format("UiMapID = |cffffff00%s|r  (%s)", tostring(id), info and info.name or "?"))

  elseif msg == "missing" then
    -- DEV: list visible sets that have no navigation target, newest expansion
    -- first — the authoring worklist for Data/Overrides.lua.
    if ns.Sources and ns.Sources.DumpMissingNav then ns.Sources.DumpMissingNav() end

  elseif msg == "gen" then
    -- DEV-ONLY: Tools/Generator.lua ships only in the author's build (stripped by
    -- scripts/package.sh), so guard the call — it's a silent no-op for end users.
    if ns.Gen and ns.Gen.Generate then ns.Gen.Generate() end

  elseif msg == "genquests" then
    -- DEV-ONLY: quest-reward sweep (item -> quest mapping); run after /esc gen.
    if ns.Gen and ns.Gen.GenerateQuests then ns.Gen.GenerateQuests() end

  elseif msg == "help" then
    ns.Print(L["Commands:"])
    print("  " .. L["/esc — open/close the window"])
    print("  " .. L["/esc guide — set a waypoint to the selected set"])
    print("  " .. L["/esc minimap — toggle the minimap button"])
    print("  " .. L["/esc arrow — toggle the auto waypoint arrow"])

  else
    ns.UI.Toggle()
  end
end
