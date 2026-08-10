-- Nav.lua — turn-by-turn navigation using FarstriderLib as the routing engine
-- (its public API FarstriderLib_API.FindTrailTo). We render only the FIRST step
-- of the freshly-computed trail:
--   * action step (item/spell) -> clickable secure button (Travel.lua)
--   * travel step (walk/fly/portal) -> waypoint arrow
-- Falls back cleanly (returns false) when FarstriderLib is absent, so callers
-- can use the plain waypoint instead.

local ADDON, ns = ...
ns.Nav = ns.Nav or {}
local Nav = ns.Nav

--- Whether turn-by-turn navigation is available (FarstriderLib present).
function Nav.Available()
  return (FarstriderLib_API and FarstriderLib_API.FindTrailTo) and true or false
end

local function currentMap()
  return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

-- Zone events alone don't advance a trail: stepping into an indoor area (the
-- Wizard's Sanctum on the way to a portal, an inn, a cave) changes the MAP
-- without firing ZONE_CHANGED_NEW_AREA, and the trail used to sit on "enter
-- the sanctum" forever. This ticker re-routes whenever the player's map
-- differs from the one the current step was computed on — it costs one
-- comparison every two seconds and nothing else.
local ticker

--- Stop following the current trail (guidance dismissed by the player).
function Nav.StopFollowing()
  Nav.lastTarget = nil
  Nav.currentLabel = nil
  Nav.routeMap = nil
  if ticker then ticker:Cancel() ticker = nil end
end

local function watchMap()
  if ticker then return end
  ticker = C_Timer.NewTicker(2, function()
    if not (Nav.lastTarget and Nav.Available()) then return end
    local m = currentMap()
    if m and m ~= Nav.routeMap then Nav.GuideTo(Nav.lastTarget) end
  end)
end

--- Resolve a navigation target ({jid} or {map,x,y}) to map + 0-100 coords.
local function coordsFor(target)
  if target.jid then
    return ns.EntranceForInstance(target.jid)
  elseif target.map and target.x and target.y then
    return target.map, target.x, target.y
  end
end

--- Guide to a target with FarstriderLib: show a clickable action for an action
--- step, or a waypoint arrow toward the first travel hop.
---@param target table  navigation target from Sources.GuideTargets/NavFor
---@return boolean  true if handled; false to fall back to a plain waypoint
function Nav.GuideTo(target)
  if not target or not Nav.Available() then return false end
  local map, x, y = coordsFor(target)
  if not map or not x or not y then return false end
  Nav.lastTarget = target   -- re-routed on zone changes (see Core.lua)
  Nav.routeMap = currentMap()
  watchMap()

  -- FarstriderLib wants UI coords in 0-1; ours are 0-100.
  local ok, op = pcall(FarstriderLib_API.FindTrailTo, map, x / 100, y / 100, 0)
  if not ok or type(op) ~= "table" or #op == 0 then
    -- present but no route (already there / off-map) -> just point at the target
    ns.Travel.Hide()
    ns.Waypoint.SetTo(map, x / 100, y / 100, target.title, true)
    Nav.currentLabel = nil
    return true
  end

  local step = op[1]

  -- action step? (use first usable item/spell option)
  local isAction = false
  if step.actionOptions then
    for _, opt in ipairs(step.actionOptions) do
      if opt.type == "item" and opt.data then
        ns.Travel.ShowAction("item", opt.data); isAction = true; break
      elseif opt.type == "spell" and opt.data then
        ns.Travel.ShowAction("spell", opt.data); isAction = true; break
      end
    end
  end

  if isAction then
    -- something to DO (hearthstone / teleport / toy): show the button, no arrow.
    ns.Waypoint.Clear()
  else
    -- a place to GO: hide the button and point the arrow there. If FarstriderLib
    -- didn't give a usable position for this hop, fall back to the destination so
    -- we always leave a waypoint (never nothing).
    ns.Travel.Hide()
    if step.loc and step.loc.mapId and step.loc.pos then
      ns.Waypoint.SetTo(step.loc.mapId, step.loc.pos.x, step.loc.pos.y, step.loca or target.title, true)
    else
      ns.Waypoint.SetTo(map, x / 100, y / 100, target.title, true)
    end
  end
  Nav.currentLabel = step.loca      -- already-localized instruction for this step
  return true
end
