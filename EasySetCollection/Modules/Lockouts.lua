-- Lockouts.lua — weekly instance lockouts joined to the set catalog.
-- GetSavedInstanceInfo enumerates the character's saved instances (one entry
-- per instance AND difficulty); they are indexed here by localized instance
-- name — the same strings the Encounter Journal uses, so they join Sources'
-- guide targets directly — to answer, per set: is there anything left to farm
-- this week? A variant whose description is a difficulty name ("Heroic",
-- "25 Player") only listens to the lockout of that same difficulty; without a
-- difficulty context the most-progressed lockout speaks for the instance.

local ADDON, ns = ...
ns.Lockouts = ns.Lockouts or {}
local Lockouts = ns.Lockouts

local locks          -- [instance name lower] = { { diffName, total, killed, expires }, … }; nil until the first UPDATE_INSTANCE_INFO
local setCache = {}  -- [setID] = { state, details } | false (verdict: nothing relevant)

--- Ask the server for fresh lockout data (it answers with UPDATE_INSTANCE_INFO).
function Lockouts.Request()
  if RequestRaidInfo then RequestRaidInfo() end
end

--- Rebuild the lockout index from GetSavedInstanceInfo (on UPDATE_INSTANCE_INFO).
function Lockouts.Rebuild()
  locks = {}
  wipe(setCache)
  local now = GetTime()
  for i = 1, (GetNumSavedInstances and GetNumSavedInstances() or 0) do
    local name, _, reset, _, locked, extended, _, _, _, diffName, numEnc, encProgress =
      GetSavedInstanceInfo(i)
    if name and (locked or extended) and reset and reset > 0 then
      local key = name:lower()
      local list = locks[key]
      if not list then list = {}; locks[key] = list end
      list[#list + 1] = {
        diffName = diffName,
        total    = numEnc or 0,
        killed   = encProgress or 0,
        expires  = now + reset,
      }
    end
  end
end

--- Drop the per-set verdicts (collection changed: the missing counts moved).
function Lockouts.InvalidateSets()
  wipe(setCache)
end

-- Variant descriptions are only a difficulty CONTEXT when they actually are a
-- difficulty name (same GetDifficultyInfo space as the lockouts' difficultyName;
-- ID list mirrors Sources' default-variant preference table).
local DIFF_IDS = { 1, 14, 3, 4, 9, 2, 15, 5, 6, 23, 16, 17, 7 }
local diffNames
local function isDifficultyName(desc)
  if not diffNames then
    diffNames = {}
    for _, d in ipairs(DIFF_IDS) do
      local name = GetDifficultyInfo and GetDifficultyInfo(d)
      if name then diffNames[name] = true end
    end
  end
  return diffNames[desc] or false
end

--- The lockout that speaks for an instance: the variant difficulty's own
--- lockout when the variant has one (a foreign difficulty's lockout neither
--- locks nor informs it), otherwise the most-progressed lockout.
local function pickLock(list, desc)
  if desc then
    for _, lk in ipairs(list) do
      if lk.diffName == desc then return lk end
    end
    return nil
  end
  local best, bestP
  for _, lk in ipairs(list) do
    local p = lk.total > 0 and lk.killed / lk.total or 0
    if not bestP or p > bestP then best, bestP = lk, p end
  end
  return best
end

--- Weekly verdict for a variant set.
---@return string? state  "cleared" (every instance holding missing pieces is
---  fully cleared this week) or "partial" (lockout progress exists, pieces
---  still up) — nil when no active lockout touches the set's missing pieces
---@return table? details  { { title, diffName, killed, total, expires, cleared }, … }
function Lockouts.SetState(setID)
  if not (locks and setID) then return nil end
  local cached = setCache[setID]
  if cached ~= nil then
    if cached == false then return nil end
    return cached.state, cached.details
  end

  local info = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(setID)
  local desc = info and info.description
  if desc == "" or (desc and not isDifficultyName(desc)) then desc = nil end

  local details, relevant, cleared = {}, 0, 0
  for _, t in ipairs(ns.Sources.GuideTargets(setID)) do
    if t.jid and (t.missing or 0) > 0 then
      relevant = relevant + 1
      local list = locks[ns.Sources.InstanceName(t.jid):lower()]
      local lk = list and pickLock(list, desc)
      if lk then
        local full = lk.total > 0 and lk.killed >= lk.total
        details[#details + 1] = {
          title = t.title, diffName = lk.diffName,
          killed = lk.killed, total = lk.total,
          expires = lk.expires, cleared = full,
        }
        if full then cleared = cleared + 1 end
      end
    end
  end

  local state
  if relevant > 0 and #details > 0 then
    state = (cleared == relevant) and "cleared" or "partial"
  end
  setCache[setID] = state and { state = state, details = details } or false
  if not state then return nil end
  return state, details
end

--- Verdict for a list-row group: computed on its default variant — the same
--- one the row's location label describes.
function Lockouts.GroupState(g)
  local setID = ns.Sources.DefaultVariant(g) or (g.base and g.base.setID) or g.baseSetID
  return Lockouts.SetState(setID)
end

--- "2 d 4 h" — remaining time before a lockout entry resets.
function Lockouts.ResetText(entry)
  local s = entry.expires - GetTime()
  if s < 0 then s = 0 end
  return SecondsToTime(s, true)
end
