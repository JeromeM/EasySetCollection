-- Tooltip.lua — set membership on ITEM tooltips: hovering any piece of a set,
-- anywhere in the game (bags, loot, chat links, the auction house), adds
-- "Set: <name>  5/8" with your live progress.
--
-- Uses the modern TooltipDataProcessor hook (10.0+), which hands us the item id
-- directly. 12.x SECRET VALUES: unit names come through as secret strings in
-- instances and blow up on any comparison — item ids are numbers and behave,
-- but the guard below keeps us honest if that ever changes (see HANDOFF).
--
-- Lookups are cached per itemID and dropped whenever the collection moves
-- (Pieces.stamp), because tooltips fire on every bag hover.

local ADDON, ns = ...
local L = ns.L
local W = ns.Widgets

ns.Tooltip = ns.Tooltip or {}
local T = ns.Tooltip

local MAX_LINES = 2      -- an item can belong to many sets; name the best ones

local lineCache = {}     -- [itemID] = { lines }, invalidated on collection change
local cacheStamp = -1
local extraIndex         -- [itemID] = { wowheadID, ... }, built once

--- itemID -> out-of-journal sets containing it (Data/ExtraSets.lua has no
--- reverse index of its own).
local function ensureExtraIndex()
  if extraIndex then return extraIndex end
  extraIndex = {}
  local X = EasySetCollectionExtraSets
  if X then
    for wid, x in pairs(X) do
      for _, itemID in ipairs(x.items or {}) do
        local list = extraIndex[itemID]
        if not list then
          list = {}
          extraIndex[itemID] = list
        end
        list[#list + 1] = wid
      end
    end
  end
  return extraIndex
end

--- One tooltip line per set the item belongs to: name, progress, and the class
--- when the set isn't for yours. Own-class sets come first, then the ones you
--- have already started.
local function buildLines(itemID)
  local cat = ns.Sets.EnsureCatalog()
  if not cat then return nil end

  local seen, entries = {}, {}
  local function add(baseSetID)
    if seen[baseSetID] then return end
    seen[baseSetID] = true
    local g = ns.Sets.GroupFor(baseSetID)
    if not g or g.hidden then return end
    if g.extra and ns.db.tooltip.extras == false then return end
    local n, t = ns.Pieces.GroupProgress(g)
    if t == 0 then return end
    local classBit = 2 ^ (select(3, UnitClass("player")) - 1)
    entries[#entries + 1] = {
      g = g, n = n, t = t,
      mine = bit.band(g.classMask or 0, classBit) ~= 0,
    }
  end

  -- journal sets: the client knows them by sourceID
  local _, sourceID
  if C_TransmogCollection.GetItemInfo then
    _, sourceID = C_TransmogCollection.GetItemInfo(itemID)
  end
  if sourceID and C_TransmogSets.GetSetsContainingSourceID then
    for _, setID in ipairs(C_TransmogSets.GetSetsContainingSourceID(sourceID) or {}) do
      local info = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(setID)
      add(info and (info.baseSetID or info.setID) or setID)
    end
  end
  -- out-of-journal sets: our own baked index
  for _, wid in ipairs(ensureExtraIndex()[itemID] or {}) do add(-wid) end

  if #entries == 0 then return {} end
  table.sort(entries, function(a, b)
    if a.mine ~= b.mine then return a.mine end
    local sa = (a.t > 0 and a.n >= a.t) and 2 or (a.n > 0 and 0 or 1)
    local sb = (b.t > 0 and b.n >= b.t) and 2 or (b.n > 0 and 0 or 1)
    if sa ~= sb then return sa < sb end
    return a.g.name < b.g.name
  end)

  local lines = {}
  for i = 1, math.min(MAX_LINES, #entries) do
    local e = entries[i]
    local done = e.n >= e.t
    local name = e.g.name
    if not e.mine and e.g.className then name = name .. " (" .. e.g.className .. ")" end
    lines[#lines + 1] = {
      left = string.format(L["%s: %s"], L["Set"], name),
      right = e.n .. "/" .. e.t,
      done = done,
    }
  end
  if #entries > MAX_LINES then
    lines[#lines + 1] = { left = string.format(L["(+%d other sets)"], #entries - MAX_LINES) }
  end
  return lines
end

local function linesFor(itemID)
  if cacheStamp ~= (ns.Pieces.stamp or 0) then
    wipe(lineCache)
    cacheStamp = ns.Pieces.stamp or 0
  end
  local cached = lineCache[itemID]
  if cached == nil then
    cached = buildLines(itemID)
    if cached then lineCache[itemID] = cached end   -- nil = catalog not ready, retry later
  end
  return cached
end

--- Append our lines to an item tooltip (TooltipDataProcessor post-call).
local function onItemTooltip(tooltip, data)
  if not (ns.db and ns.db.tooltip and ns.db.tooltip.enabled) then return end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  local itemID = data and data.id
  if type(itemID) ~= "number" then return end
  if issecretvalue and issecretvalue(itemID) then return end

  local lines = linesFor(itemID)
  if not lines or #lines == 0 then return end
  for _, line in ipairs(lines) do
    if line.right then
      tooltip:AddDoubleLine(line.left, line.right,
        0.96, 0.72, 0.32,
        line.done and 0.38 or 0.96, line.done and 0.82 or 0.72, line.done and 0.43 or 0.32)
    else
      tooltip:AddLine(line.left, 0.55, 0.55, 0.60)
    end
  end
end

--- Install the hook (called once from Core's login handler).
function T.Init()
  if T.hooked then return end
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType) then
    return   -- pre-10.0 tooltip stack: feature simply stays off
  end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
  T.hooked = true
end
