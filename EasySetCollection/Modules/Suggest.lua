-- Suggest.lua — "what should I farm right now?": the closest incomplete set.
-- Candidates come from the catalog (the player's own class, obtainable,
-- incomplete), their position from the primary guide target's entrance,
-- resolved to continent world space the same way the arrow does. Sets with
-- nothing left to farm this week (Lockouts "cleared") are skipped; candidates
-- on the player's continent outrank the others, then raw distance decides.
-- Off-continent or position-less candidates fall back to fewest-missing order.

local ADDON, ns = ...
ns.Suggest = ns.Suggest or {}
local Suggest = ns.Suggest
local L = ns.L

--- The player's continent + world position (yards), nil in position-less
--- contexts (some instances, loading screens).
local function playerWorldPos()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition
          and C_Map.GetWorldPosFromMapPos) then return end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return end
  local ppos = C_Map.GetPlayerMapPosition(map, "player")
  if not ppos then return end
  local ok, cont, wpos = pcall(C_Map.GetWorldPosFromMapPos, map, ppos)
  if ok and cont and wpos then return cont, wpos end
end

-- entrance world positions are static per session (moving portals excepted —
-- they'd be caught on the next /reload, good enough for a suggestion)
local posCache = {}   -- [jid | "map:x:y"] = { cont, x, y } | false

--- World position of a navigation target (instance entrance or curated point).
local function targetWorldPos(target)
  local key = target.jid or (target.map .. ":" .. target.x .. ":" .. target.y)
  local c = posCache[key]
  if c ~= nil then
    if c == false then return end
    return c.cont, c
  end
  local map, x, y
  if target.jid then
    map, x, y = ns.EntranceForInstance(target.jid)
  else
    map, x, y = target.map, target.x, target.y
  end
  if map and x and y and C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local ok, cont, wpos = pcall(C_Map.GetWorldPosFromMapPos, map,
      CreateVector2D(x / 100, y / 100))
    if ok and cont and wpos then
      c = { cont = cont, x = wpos.x, y = wpos.y }
      posCache[key] = c
      return cont, c
    end
  end
  posCache[key] = false
end

--- Is candidate target a better pick than b? Same-continent wins, then raw
--- distance, then "has a distance at all".
local function betterTarget(a, b)
  if (a.sameCont or false) ~= (b.sameCont or false) then return a.sameCont or false end
  if a.dist and b.dist then return a.dist < b.dist end
  if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
  return false
end

--- The ranked farmable candidates for this character, best first.
---@param wantCount number?  how many to return (default 5)
---@return table[]  { g, setID, nav, missing, dist?, sameCont? }
function Suggest.Candidates(wantCount)
  local cat = ns.Sets.EnsureCatalog()
  if not cat then return {} end
  local classID = select(3, UnitClass("player"))
  local faction = UnitFactionGroup("player")
  local pCont, pPos = playerWorldPos()

  local out = {}
  for _, g in ipairs(cat.order) do
    repeat
      if g.hidden or g.legacy then break end
      if classID and bit.band(g.classMask or 0, 2 ^ (classID - 1)) == 0 then break end
      if g.requiredFaction and faction and g.requiredFaction ~= faction then break end
      local n, t = ns.Pieces.GroupProgress(g)
      if t == 0 or n >= t then break end
      local setID = ns.Sources.DefaultVariant(g) or g.baseSetID
      local state, lockDetails
      if ns.Lockouts then state, lockDetails = ns.Lockouts.SetState(setID) end
      if state == "cleared" then break end
      local clearedBy = {}
      for _, d in ipairs(lockDetails or {}) do
        if d.cleared then clearedBy[d.title] = true end
      end

      -- the NEAREST still-farmable target decides the set's rank AND where the
      -- suggestion sends you: a WotLK tier drops in Naxxramas AND the Vault of
      -- Archavon — standing at Naxxramas, that's the one you want, not the
      -- most-missing one.
      local best
      for _, tg in ipairs(ns.Sources.GuideTargets(setID)) do
        local eligible
        if tg.jid then
          eligible = (tg.missing or 0) > 0 and not clearedBy[tg.title]
        else
          eligible = true   -- curated quest/vendor point
        end
        if eligible then
          local cand = { nav = tg }
          if pCont and pPos then
            local cont, pos = targetWorldPos(tg)
            if cont and pos then
              cand.sameCont = (cont == pCont)
              if cand.sameCont then
                local dx, dy = pos.x - pPos.x, pos.y - pPos.y
                cand.dist = math.sqrt(dx * dx + dy * dy)
              end
            end
          end
          if not best or betterTarget(cand, best) then best = cand end
        end
      end
      if not best then break end

      out[#out + 1] = { g = g, setID = setID, nav = best.nav,
        missing = t - n, dist = best.dist, sameCont = best.sameCont }
    until true
  end

  table.sort(out, function(a, b)
    if (a.sameCont or false) ~= (b.sameCont or false) then return a.sameCont or false end
    if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
    if a.missing ~= b.missing then return a.missing < b.missing end
    return a.g.name < b.g.name
  end)

  local top = {}
  for i = 1, math.min(wantCount or 5, #out) do top[i] = out[i] end
  return top
end

--- Act on a suggestion: select it in the list, scroll to it, guide there.
function Suggest.Go(cand)
  if not cand then return end
  if ns.UI and ns.UI.Show then ns.UI.Show() end
  ns.Detail.setID = cand.setID
  ns.SetList.Select(cand.g)
  if ns.SetList.ScrollTo then ns.SetList.ScrollTo(cand.g.baseSetID) end
  ns.Detail.GuideTo(cand.nav)
end

--- Left-click / `/esc suggest`: go to the best suggestion.
function Suggest.Pick()
  local top = Suggest.Candidates(1)
  if #top == 0 then
    ns.Print(L["No set to suggest right now."])
    return
  end
  Suggest.Go(top[1])
end

--- Right-click: choose among the best suggestions.
function Suggest.OpenMenu(anchor)
  local top = Suggest.Candidates(6)
  if #top == 0 then
    ns.Print(L["No set to suggest right now."])
    return
  end
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    Suggest.Go(top[1])
    return
  end
  local W = ns.Widgets
  MenuUtil.CreateContextMenu(anchor, function(_, root)
    root:CreateTitle(L["Suggestions"])
    for _, cand in ipairs(top) do
      local label = cand.g.name .. "  " .. W.GREY .. (cand.nav.title or "?")
      if cand.dist and ns.Arrow and ns.Arrow.FormatDistance then
        label = label .. " · " .. ns.Arrow.FormatDistance(cand.dist)
      end
      label = label .. " · " .. string.format(L["(%d pieces)"], cand.missing) .. "|r"
      root:CreateButton(label, function() Suggest.Go(cand) end)
    end
  end)
end
