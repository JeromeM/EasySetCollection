-- Waypoint.lua — guide to a point using the game's native user waypoint (map +
-- minimap pin + supertracked distance) together with our own on-screen direction
-- arrow (ns.Arrow). No external addon dependency. We track what WE set so Clear()
-- only removes ours (never a waypoint the player placed by hand).
-- The entrance resolution works from a journalInstanceID: baked entrance coords
-- plus live moving-portal tracking through the Encounter Journal.

local ADDON, ns = ...
ns.Waypoint = ns.Waypoint or {}
local Waypoint = ns.Waypoint
local L = ns.L

--- Live entrance resolution from the Encounter Journal: the game only lists an
--- instance's portal on the map where it currently is, so scanning the candidate
--- maps auto-tracks moving portals (e.g. Ny'alotha between Uldum and the Vale).
---@param jid number  journalInstanceID to look for
---@param candidateMaps number[]  uiMapIDs to scan
---@return number? mapId, number? x, number? y  (coords 0-100)
local function liveEntrance(jid, candidateMaps)
  if not (C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap) then return end
  for _, mapId in ipairs(candidateMaps) do
    local ok, list = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, mapId)
    if ok and type(list) == "table" then
      for _, e in ipairs(list) do
        if e.journalInstanceID == jid and e.position then
          local px, py
          if e.position.GetXY then px, py = e.position:GetXY() end
          px = px or e.position.x; py = py or e.position.y
          if px and py then return mapId, px * 100, py * 100 end
        end
      end
    end
  end
end

--- Effective entrance coords (0-100) for an instance: live Encounter-Journal
--- resolution first (moving portals), then hand-authored override coords, then
--- the generation-time harvest baked in Data/Instances.lua.
---@param jid number  journalInstanceID
---@return number? mapId, number? x, number? y
function ns.EntranceForInstance(jid)
  if not jid then return end
  local inst = EasySetCollectionInstances and EasySetCollectionInstances[jid]
  local ov = EasySetCollectionOverrides and EasySetCollectionOverrides.instances
    and EasySetCollectionOverrides.instances[jid]

  local candidates = {}
  if ov and ov.entranceMaps then
    for _, m in ipairs(ov.entranceMaps) do candidates[#candidates + 1] = m end
  end
  if inst and inst.map then candidates[#candidates + 1] = inst.map end

  local m, x, y = liveEntrance(jid, candidates)
  if m then return m, x, y end
  if ov and ov.map and ov.x and ov.y then return ov.map, ov.x, ov.y end
  if inst and inst.map and inst.x and inst.y then return inst.map, inst.x, inst.y end
end

--- Remove what WE set (native user waypoint + our arrow), leaving player-placed
--- waypoints intact.
function Waypoint.Clear()
  if Waypoint._blizzard and C_Map and C_Map.ClearUserWaypoint then
    C_Map.ClearUserWaypoint()
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
      C_SuperTrack.SetSuperTrackedUserWaypoint(false)
    end
    Waypoint._blizzard = nil
  end
  if ns.Arrow then ns.Arrow.Hide() end
end

--- Point at an explicit UI map point: set the native user waypoint (map + minimap
--- pin + supertracked distance) best-effort, and always show our own on-screen
--- arrow. Clears our previous one first.
---@param mapID number  uiMapID of the target map
---@param x number  normalized X coordinate (0-1)
---@param y number  normalized Y coordinate (0-1)
---@param title string?  label shown on the waypoint / arrow
function Waypoint.SetTo(mapID, x, y, title)
  if not mapID or not x or not y then return end
  Waypoint.Clear()   -- drop our previous one first

  -- Native user waypoint for the map + minimap pin. Best-effort: some maps
  -- disallow it (CanSetUserWaypointOnMap == false) — the arrow still guides there.
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    if not (C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID)) then
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
      Waypoint._blizzard = true
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
      end
    end
  end

  -- Our own on-screen direction arrow.
  if ns.Arrow then ns.Arrow.Show(mapID, x, y, title) end
end

--- Guide to a navigation target from Sources.GuideTargets/NavFor: either
--- { jid, title } (instance entrance) or { map, x, y, title } (curated point).
---@param target table  the navigation target
---@param silent boolean?  suppress user-facing error messages when true
function Waypoint.GuideToTarget(target, silent)
  if not target then return end
  local map, x, y
  if target.jid then
    map, x, y = ns.EntranceForInstance(target.jid)
  elseif target.map and target.x and target.y then
    map, x, y = target.map, target.x, target.y
  end
  if not map or not x or not y then
    if not silent then
      ns.Print(string.format(L["No coordinates for \"%s\"."], target.title or "?"))
    end
    return
  end
  Waypoint.SetTo(map, x / 100, y / 100, target.title)
end
