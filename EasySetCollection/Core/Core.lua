-- Core.lua — initialization, saved variables, slash commands and event wiring.
-- Loads last, so it can wire all other modules together.

local ADDON, ns = ...
local L = ns.L

--- Create the saved-variable tables if missing and seed their default fields.
--- Uses the `if x == nil` idiom so `false` values survive, and back-fills new
--- filter keys on upgrade without wiping the user's choices.
local function initSavedVars()
  ns.firstInstall = (EasySetCollectionDB == nil)
  EasySetCollectionDB = EasySetCollectionDB or {}
  EasySetCollectionCharDB = EasySetCollectionCharDB or {}
  ns.charDB = EasySetCollectionCharDB

  -- profiles: migrate flat v1 saved vars, bind ns.db (this character's active
  -- profile) and ns.gdb (account-wide), then seed the profile's defaults
  ns.Profiles.Init()
  ns.Profiles.SeedDefaults(ns.db)

  ns.gdb.onboard = ns.gdb.onboard or {}   -- tour + wizard state (UI/Onboard|Setup.lua)
  if not ns.firstInstall and ns.gdb.onboard.wizard == nil then
    ns.gdb.onboard.wizard = true   -- existing install: never auto-open the wizard
  end

  ns.charDB.trackedSets = ns.charDB.trackedSets or {}
  if ns.charDB.trackedSetID then   -- migrate the old single-set field
    table.insert(ns.charDB.trackedSets, ns.charDB.trackedSetID)
    ns.charDB.trackedSetID = nil
  end

  -- `/esc lang`: force the addon chrome to English. The locale files already
  -- ran (saved variables load after the Lua files), but translations are plain
  -- entries in ns.L whose metatable falls back to the English keys — wiping
  -- the table restores English. Game data (sets, items, quests, instances)
  -- stays in the client language either way.
  if ns.gdb.forceEnglish == nil then ns.gdb.forceEnglish = false end
  if ns.gdb.forceEnglish then
    wipe(ns.L)
    _G["BINDING_NAME_EASYSETCOLLECTION_TOGGLE"] = ns.L["Open/close the window"]
  end
end

--- PLAYER_LOGIN handler: build the UI shell, settings pages and minimap button,
--- then restore the window's open/closed state. The set catalog itself is built
--- lazily on first Show (and invalidated by collection events).
local function onLogin()
  ns.UI.Init()
  ns.UI.BuildSettings()
  ns.Minimap.Init()
  if ns.Tooltip then ns.Tooltip.Init() end
  -- brand-new install: say how to open the window, once ever
  if ns.firstInstall and not ns.gdb.onboard.hello then
    ns.gdb.onboard.hello = true
    ns.Print(L["Type /esc or click the minimap button to browse your sets."])
  end
  -- ...and walk through the setup wizard (auto-opens until closed once)
  if not ns.gdb.onboard.wizard and ns.Setup then ns.Setup.Show() end
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
    -- lockout verdicts depend on the missing counts: recompute them too
    if ns.Lockouts then ns.Lockouts.InvalidateSets() end
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
f:RegisterEvent("UPDATE_INSTANCE_INFO")
f:RegisterEvent("BOSS_KILL")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then initSavedVars() end

  elseif event == "PLAYER_LOGIN" then
    onLogin()

  elseif event == "PLAYER_ENTERING_WORLD" then
    -- the client re-syncs the whole collection after every loading screen and can
    -- replay SOURCE_ADDED in bursts; suppress the loot toast for a few seconds.
    ns.toastGraceUntil = GetTime() + 10
    -- fresh lockout data (the server answers with UPDATE_INSTANCE_INFO)
    if ns.Lockouts then ns.Lockouts.Request() end
    -- in-instance assistant: announce once the map/position has settled
    C_Timer.After(3, function()
      if ns.Assist then ns.Assist.Check() end
    end)
    -- the minimap may have been resized/reshaped (Edit Mode, minimap addons)
    if ns.Minimap and ns.Minimap.UpdatePosition then ns.Minimap.UpdatePosition() end
    -- FarstriderLib trail: recompute the next hop once the position settles;
    -- also re-dress the preview model (SetUnit fails during loading screens)
    C_Timer.After(1.5, function()
      if ns.Nav and ns.Nav.lastTarget and ns.Nav.Available() then
        ns.Nav.GuideTo(ns.Nav.lastTarget)
      end
      if ns.Detail then ns.Detail.previewKey = nil end
      if ns.UI and ns.UI.RefreshDetail then ns.UI.RefreshDetail() end
    end)

  elseif event == "ZONE_CHANGED_NEW_AREA" then
    -- entered a new zone without a loading screen: advance the trail
    if ns.Nav and ns.Nav.lastTarget and ns.Nav.Available() then
      ns.Nav.GuideTo(ns.Nav.lastTarget)
    end
    if ns.Assist then ns.Assist.Check() end

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

  elseif event == "UPDATE_INSTANCE_INFO" then
    if ns.Lockouts then
      ns.Lockouts.Rebuild()
      if ns.UI and ns.UI.RefreshAll then ns.UI.RefreshAll() end
    end

  elseif event == "BOSS_KILL" then
    -- a boss just died: re-pull the lockouts so the verdicts follow live
    if ns.Lockouts then ns.Lockouts.Request() end
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

  elseif msg == "suggest" then
    if ns.Suggest and ns.Suggest.Pick then ns.Suggest.Pick() end

  elseif msg == "minimap" then
    ns.db.minimap.hide = not ns.db.minimap.hide
    if ns.Minimap.button then
      ns.Minimap.button:SetShown(not ns.db.minimap.hide)
    end

  elseif msg == "arrow" then
    ns.db.autoGuide = not ns.db.autoGuide
    ns.Print(ns.db.autoGuide and L["Auto waypoint arrow: ON"] or L["Auto waypoint arrow: OFF"])

  elseif msg == "lang" then
    ns.gdb.forceEnglish = not ns.gdb.forceEnglish
    ns.Print(ns.gdb.forceEnglish
      and L["Addon language: English (type /reload to apply)"]
      or L["Addon language: client language (type /reload to apply)"])

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

  elseif msg:match("^findmap%s+(.+)$") then
    -- DEV: find a UiMapID by name without travelling there (covenant sanctums
    -- and the like can't be visited on a whim). Scans the client's map table.
    local needle = msg:match("^findmap%s+(.+)$")
    local KIND = { [1] = "world", [2] = "continent", [3] = "zone", [4] = "dungeon", [5] = "micro" }
    local found = 0
    for id = 1, 3000 do
      local info = C_Map.GetMapInfo(id)
      local name = info and info.name
      if name and name:lower():find(needle, 1, true) then
        found = found + 1
        if found <= 40 then
          -- the parent chain is what tells homonyms apart (which Dalaran?
          -- which Silvermoon?), so walk up to the continent
          local chain, pid, guard = {}, info.parentMapID, 0
          while pid and pid > 0 and guard < 6 do
            local p = C_Map.GetMapInfo(pid)
            if not p then break end
            chain[#chain + 1] = p.name
            pid, guard = p.parentMapID, guard + 1
          end
          print(string.format("  |cffffff00%d|r  %s  (%s)  |cff888888%s|r", id, name,
            KIND[info.mapType or 0] or ("type " .. tostring(info.mapType)),
            table.concat(chain, " < ")))
        end
      end
    end
    ns.Print(string.format("findmap '%s': %d result(s)%s", needle, found,
      found > 40 and " (first 40 shown)" or ""))

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

  elseif msg == "setup" then
    if ns.Setup then ns.Setup.Show() end

  elseif msg == "options" or msg == "config" then
    if ns.Options then ns.Options.Toggle() end

  elseif msg == "help" then
    ns.Print(L["Commands:"])
    print("  " .. L["/esc — open/close the window"])
    print("  " .. L["/esc guide — set a waypoint to the selected set"])
    print("  " .. L["/esc suggest — guide to the closest farmable set"])
    print("  " .. L["/esc minimap — toggle the minimap button"])
    print("  " .. L["/esc arrow — toggle the auto waypoint arrow"])
    print("  " .. L["/esc lang — toggle English addon texts"])
    print("  " .. L["/esc options — open the options"])
    print("  " .. L["/esc setup — rerun the first-time setup"])

  else
    ns.UI.Toggle()
  end
end
