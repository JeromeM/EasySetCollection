-- Filters.lua — the filter/sort pipeline feeding the set list. One O(#groups)
-- pass over the precomputed catalog per change; the text query is a plain
-- (non-pattern) find over the precomputed lowercase name, so filtering on every
-- keystroke stays instant.

local ADDON, ns = ...
ns.Filters = ns.Filters or {}
local Filters = ns.Filters

Filters.query = ""   -- lowercase search text (deliberately not persisted)

function Filters.SetQuery(q)
  Filters.query = (q or ""):lower()
end

--- The classID to filter on: nil db value = the character's own class,
--- 0 = no class filter, anything else = that explicit class.
local function effectiveClassID()
  local id = ns.db.filters.classID
  if id == nil then return (select(3, UnitClass("player"))) end
  if id == 0 then return nil end
  return id
end

--- Does one group survive the current filters?
function Filters.Pass(g)
  local fl = ns.db.filters
  -- list tab: journal sets and out-of-journal sets live on separate tabs
  if (g.extra or false) ~= (ns.db.listTab == "extra") then return false end
  if g.hidden then return false end
  if g.legacy and not fl.showLegacy then return false end

  local classID = effectiveClassID()
  if classID and bit.band(g.classMask or 0, 2 ^ (classID - 1)) == 0 then return false end

  if not fl.otherFaction and g.requiredFaction then
    local faction = UnitFactionGroup("player")
    if faction and g.requiredFaction ~= faction then return false end
  end

  -- unseen expansion/type keys count as visible (nil ~= false)
  if fl.expansions[g.expansionID] == false then return false end
  if fl.contentTypes[g.bucket or "unknown"] == false then return false end
  if not fl.possession[ns.Pieces.PossessionState(g)] then return false end

  local q = Filters.query
  if q ~= "" and not g.nameLower:find(q, 1, true) then return false end

  -- last: the lockout verdict is the only non-precomputed axis (it resolves
  -- the group's guide targets on first use, then caches)
  if fl.hideCleared and ns.Lockouts and ns.Lockouts.GroupState(g) == "cleared" then
    return false
  end
  return true
end

--- Sort ranks for the "progress" mode: started sets closest to completion
--- first, then untouched sets, complete sets last.
local function progressRank(g)
  local n, t = ns.Pieces.GroupProgress(g)
  if t > 0 and n >= t then return 2, 0 end
  if n == 0 then return 1, 0 end
  return 0, t - n
end

function Filters.Sort(list)
  local mode = ns.db.sort or "expansion"
  if mode == "alpha" then
    table.sort(list, function(a, b) return a.name < b.name end)
  elseif mode == "progress" then
    table.sort(list, function(a, b)
      local ra, ma = progressRank(a)
      local rb, mb = progressRank(b)
      if ra ~= rb then return ra < rb end
      if ma ~= mb then return ma < mb end
      return a.name < b.name
    end)
  else -- "expansion": favorites, then newest content first (Blizzard ordering)
    table.sort(list, function(a, b)
      if (a.favorite or false) ~= (b.favorite or false) then return a.favorite end
      if a.expansionID ~= b.expansionID then return a.expansionID > b.expansionID end
      if a.uiOrder ~= b.uiOrder then return a.uiOrder > b.uiOrder end
      return a.name < b.name
    end)
  end
end

--- Filtered + sorted groups, plus the complete-sets count for the footer.
--- Returns nil while the catalog isn't ready (login).
function Filters.Apply()
  local cat = ns.Sets.EnsureCatalog()
  if not cat then return nil end
  local out, complete = {}, 0
  for _, g in ipairs(cat.order) do
    if Filters.Pass(g) then
      out[#out + 1] = g
      if ns.Pieces.PossessionState(g) == "complete" then complete = complete + 1 end
    end
  end
  Filters.Sort(out)
  return out, complete
end

--- Number of filter axes deviating from their default — shown as the
--- "Filters (N)" badge on the toolbar button.
function Filters.ActiveCount()
  local fl = ns.db.filters
  local n = 0
  for _, k in ipairs({ "complete", "partial", "none" }) do
    if not fl.possession[k] then n = n + 1 end
  end
  for _, k in ipairs(ns.CONTENT_BUCKETS or {}) do
    if fl.contentTypes[k] == false then n = n + 1 end
  end
  for _, v in pairs(fl.expansions) do
    if v == false then n = n + 1 end
  end
  if fl.classID ~= nil then n = n + 1 end
  if fl.otherFaction then n = n + 1 end
  if not fl.showLegacy then n = n + 1 end
  if fl.hideCleared then n = n + 1 end
  return n
end

--- Back to defaults (also clears the search text).
function Filters.Reset()
  local fl = ns.db.filters
  for k in pairs(fl.possession) do fl.possession[k] = true end
  for k in pairs(fl.contentTypes) do fl.contentTypes[k] = true end
  for e in pairs(fl.expansions) do fl.expansions[e] = true end
  fl.classID = nil
  fl.otherFaction = false
  fl.showLegacy = true
  fl.hideCleared = false
  Filters.query = ""
end
