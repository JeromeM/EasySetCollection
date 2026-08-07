-- Generator.lua — one-shot data generator (dev tool, stripped from the public
-- build by scripts/package.sh). For every journal transmog set it resolves where
-- each piece drops, as IDs:
--   * an Encounter Journal name index turns the localized strings returned by
--     C_TransmogCollection.GetAppearanceSourceDrops into journalInstanceIDs /
--     journalEncounterIDs — locale-proof because both sides come from the same
--     client. No EJ loot sweep needed.
--   * instance entrances are harvested via GetDungeonEntrancesForMap over
--     every mapID.
--   * PvP sets are identified authoritatively via the client's own PvE/PvP
--     base-sets filter, snapshotted per class (filters saved and restored).
--
-- The result is written to the EasySetCollectionGen saved variable (flushed to
-- disk on /reload), then transformed by scripts/build-sets.mjs into
-- Data/SetSources.lua + Data/Instances.lua.
--
-- Usage in game:  /esc gen   then   /reload   then  npm run build

local ADDON, ns = ...
ns.Gen = ns.Gen or {}
local Gen = ns.Gen

local SETS_PER_STEP = 25       -- sets processed per frame during the sweep
local SRC_BOSS = 1             -- AppearanceSourceInfo.sourceType luaIndex for boss drops

local running
local instByName, encByName, instMeta, entranceLoc
local pvpBase
local outSets, unresolved, emptyBoss
local stats

-- --- phase 1: Encounter Journal name index ----------------------------------

local function buildEJIndex()
  instByName, encByName, instMeta = {}, {}, {}
  local prevTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
  for t = 1, EJ_GetNumTiers() do
    EJ_SelectTier(t)
    for _, isRaid in ipairs({ false, true }) do
      local i = 1
      while true do
        local jid, name = EJ_GetInstanceByIndex(i, isRaid)
        if not jid then break end
        if name and not instByName[name] then instByName[name] = jid end
        instMeta[jid] = { name = name, raid = isRaid or nil, tier = t }
        EJ_SelectInstance(jid)
        local encs = {}
        local j = 1
        while true do
          local encName, _, encounterID = EJ_GetEncounterInfoByIndex(j, jid)
          if not encName then break end
          if encounterID then encs[encName] = encounterID end
          j = j + 1
        end
        encByName[jid] = encs
        i = i + 1
      end
    end
  end
  if prevTier then pcall(EJ_SelectTier, prevTier) end
end

-- --- phase 2: entrance harvest ------------------------------------------------

local function harvestEntrances()
  entranceLoc = {}
  if not (C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap) then return end
  local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
  for mapID = 1, 2700 do
    local ok, ents = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, mapID)
    if ok and type(ents) == "table" then
      local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
      local isZone = info and info.mapType == ZONE
      for _, e in ipairs(ents) do
        local jid = e.journalInstanceID
        -- prefer ZONE-type maps: the first map found can be a continent, whose
        -- normalized coords are far too coarse for a usable waypoint
        local cur = entranceLoc[jid]
        if jid and (not cur or (isZone and not cur.zone)) then
          local x, y = 0, 0
          if e.position and e.position.GetXY then x, y = e.position:GetXY() end
          entranceLoc[jid] = { map = mapID, x = (x or 0) * 100, y = (y or 0) * 100, zone = isZone or nil }
        end
      end
    end
  end
  for _, l in pairs(entranceLoc) do l.zone = nil end   -- internal flag, not exported
end

-- --- phase 3: PvP snapshot via the client's own sets filters -----------------

local function snapshotPvP()
  pvpBase = {}
  if not (C_TransmogSets.SetBaseSetsFilter and C_TransmogSets.GetBaseSetsFilter
      and C_TransmogSets.SetTransmogSetsClassFilter and C_TransmogSets.GetTransmogSetsClassFilter) then
    ns.Print("PvP filter APIs unavailable — sets will be classified without the pvp flag.")
    return
  end

  -- filter indexes: the LE_TRANSMOG_SET_FILTER_* globals were dropped from the
  -- client at some point; their historical values are the fallback.
  local F_COLLECTED   = LE_TRANSMOG_SET_FILTER_COLLECTED or 1
  local F_UNCOLLECTED = LE_TRANSMOG_SET_FILTER_UNCOLLECTED or 2
  local F_PVE         = LE_TRANSMOG_SET_FILTER_PVE or 3
  local F_PVP         = LE_TRANSMOG_SET_FILTER_PVP or 4

  -- these filters are persistent client state shared with the Blizzard wardrobe:
  -- save everything, mutate, snapshot, restore.
  local savedClass = C_TransmogSets.GetTransmogSetsClassFilter()
  local FILTERS = { F_COLLECTED, F_UNCOLLECTED, F_PVE, F_PVP }
  local savedFilters = {}
  for _, fi in ipairs(FILTERS) do savedFilters[fi] = C_TransmogSets.GetBaseSetsFilter(fi) end

  C_TransmogSets.SetBaseSetsFilter(F_COLLECTED, true)
  C_TransmogSets.SetBaseSetsFilter(F_UNCOLLECTED, true)
  C_TransmogSets.SetBaseSetsFilter(F_PVE, false)
  C_TransmogSets.SetBaseSetsFilter(F_PVP, true)
  for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
    C_TransmogSets.SetTransmogSetsClassFilter(classID)
    for _, s in ipairs(C_TransmogSets.GetBaseSets() or {}) do
      pvpBase[s.setID] = true
    end
  end

  for fi, v in pairs(savedFilters) do C_TransmogSets.SetBaseSetsFilter(fi, v) end
  if savedClass then C_TransmogSets.SetTransmogSetsClassFilter(savedClass) end

  local n = 0
  for _ in pairs(pvpBase) do n = n + 1 end
  ns.Print(string.format("PvP snapshot: %d base sets flagged.", n))
end

-- --- phase 4: per-set sweep ---------------------------------------------------

--- Resolve a boss-drop piece to IDs from its localized drop strings. Pieces
--- whose drop data isn't loaded yet are queued in `emptyBoss` and re-queried by
--- the retry rounds (the call itself triggers the client to load the data).
---@param p table  piece record (sid/itemID/st), mutated with j/e on success
local function resolveDrops(p)
  local ok, drops = pcall(C_TransmogCollection.GetAppearanceSourceDrops, p.sid)
  if not ok or type(drops) ~= "table" or #drops == 0 then
    emptyBoss[#emptyBoss + 1] = p
    return
  end
  for _, d in ipairs(drops) do
    local jid = d.instance and instByName[d.instance]
    if jid then
      p.j = jid
      p.e = d.encounter and encByName[jid] and encByName[jid][d.encounter] or nil
      stats.resolved = stats.resolved + 1
      return
    end
  end
  -- drops exist but none of the instance names matched the EJ index
  unresolved[#unresolved + 1] = {
    sid = p.sid, itemID = p.itemID,
    instance = drops[1].instance, encounter = drops[1].encounter,
  }
end

local function processSet(set)
  local rec = {
    setID = set.setID,
    base = set.baseSetID,
    pvp = pvpBase[set.baseSetID or set.setID] and true or nil,
    pieces = {},
  }
  local pas = C_TransmogSets.GetSetPrimaryAppearances(set.setID)
  for _, pa in ipairs(pas or {}) do
    local si = C_TransmogCollection.GetSourceInfo(pa.appearanceID)
    if si then
      local p = { sid = pa.appearanceID, itemID = si.itemID, st = si.sourceType }
      stats.pieces = stats.pieces + 1
      if si.sourceType == SRC_BOSS then
        stats.boss = stats.boss + 1
        resolveDrops(p)
      end
      rec.pieces[#rec.pieces + 1] = p
    end
  end
  outSets[#outSets + 1] = rec
end

-- --- phase 5: finalize ----------------------------------------------------------

local function finalize()
  -- export only the instances actually referenced by a piece (plus their entrance)
  local used = {}
  for _, rec in ipairs(outSets) do
    for _, p in ipairs(rec.pieces) do
      if p.j then used[p.j] = true end
    end
  end
  local instances = {}
  for jid in pairs(used) do
    local meta = instMeta[jid] or {}
    local loc = entranceLoc[jid]
    instances[jid] = {
      name = meta.name, raid = meta.raid, tier = meta.tier,
      map = loc and loc.map, x = loc and loc.x, y = loc and loc.y,
    }
  end

  EasySetCollectionGen = {
    built = true,
    when = date("%Y-%m-%d %H:%M"),
    locale = GetLocale(),
    sets = outSets,
    instances = instances,
    unresolved = unresolved,
  }
  running = false
  ns.Print(string.format(
    "Scan done: |cffffff00%d|r sets, %d pieces (%d boss drops, %d resolved to an instance, %d unresolved).",
    #outSets, stats.pieces, stats.boss, stats.resolved, #unresolved))
  ns.Print("Now type |cffffff00/reload|r to save it to disk, then run |cffffff00npm run build|r.")
end

-- Drop data loads asynchronously and 26k pieces take a while to stream in, so
-- keep re-querying the still-empty pieces in rounds until nothing improves.
local RETRY_ROUNDS, RETRY_DELAY = 12, 2

local function retryEmptyThenFinalize(round)
  round = round or 1
  if #emptyBoss == 0 or round > RETRY_ROUNDS then
    for _, p in ipairs(emptyBoss) do
      unresolved[#unresolved + 1] = { sid = p.sid, itemID = p.itemID, reason = "no drops" }
    end
    emptyBoss = {}
    finalize()
    return
  end
  ns.Print(string.format("%d boss pieces still without drop data — retry %d/%d…",
    #emptyBoss, round, RETRY_ROUNDS))
  C_Timer.After(RETRY_DELAY, function()
    local list = emptyBoss
    emptyBoss = {}
    local before = #list
    for _, p in ipairs(list) do resolveDrops(p) end
    if #emptyBoss == before and round > 2 then
      -- two grace rounds, then bail early once nothing improves anymore
      retryEmptyThenFinalize(RETRY_ROUNDS + 1)
    else
      retryEmptyThenFinalize(round + 1)
    end
  end)
end

-- --- quest-reward sweep (/esc genquests) --------------------------------------
-- The client has no item->quest API, but it has the reverse: after
-- C_QuestLog.RequestLoadQuestByID, GetQuestLogRewardInfo/GetQuestLogChoiceInfo
-- expose a quest's reward itemIDs. Sweeping every questID and matching the
-- rewards against our quest pieces' itemIDs rebuilds the mapping automatically.
-- Run AFTER /esc gen (it reads the quest pieces from EasySetCollectionGen).

-- Two async stages per quest (both server round-trips):
--   1. C_QuestLog.RequestLoadQuestByID -> QUEST_DATA_LOAD_RESULT (quest data)
--   2. C_TaskQuest.RequestPreloadRewardData -> HaveQuestRewardData (rewards)
-- Reading rewards right after stage 1 returns nothing — stage 2 is polled.

local QSCAN_MAX = 95000                       -- highest questID probed
local QSCAN_BATCH, QSCAN_INTERVAL = 10, 0.1   -- ~100 quest-data requests/s
local QREWARD_INTERVAL = 0.5                  -- reward-readiness poll cadence
local QREWARD_ATTEMPTS = 10                   -- polls before giving up on a quest

local qscanFrame
local qscanTargets, qscanFound
local qscanNext, qscanRunning, qscanTicker, qscanRewardTicker
local qscanMatched, qscanTotal
local qscanPending                            -- { {q = questID, a = attempts}, ... }

local function qscanReadRewards(questID)
  local function check(itemID)
    if itemID and qscanTargets[itemID] and not qscanFound[itemID] then
      qscanFound[itemID] = questID
      qscanMatched = qscanMatched + 1
    end
  end
  local ok, n = pcall(GetNumQuestLogRewards, questID)
  for i = 1, (ok and n or 0) do
    local ok2, _, _, _, _, _, itemID = pcall(GetQuestLogRewardInfo, i, questID)
    if ok2 then check(itemID) end
  end
  local okc, c = pcall(GetNumQuestLogChoices, questID, false)
  for i = 1, (okc and c or 0) do
    local ok2, _, _, _, _, _, itemID = pcall(GetQuestLogChoiceInfo, i, questID)
    if ok2 then check(itemID) end
  end
end

local function qscanFinish()
  if qscanTicker then qscanTicker:Cancel() end
  if qscanRewardTicker then qscanRewardTicker:Cancel() end
  qscanRunning = false
  if qscanFrame then qscanFrame:UnregisterAllEvents() end
  EasySetCollectionGen = EasySetCollectionGen or {}
  EasySetCollectionGen.questRewards = qscanFound
  ns.Print(string.format("Quest scan done: |cffffff00%d/%d|r quest items matched to a quest.",
    qscanMatched, qscanTotal))
  ns.Print("Now type |cffffff00/reload|r (also clears the quest cache the scan piled up), copy the SavedVariables file, then |cffffff00npm run build|r.")
end

--- `/esc genquests`: sweep every quest's rewards and match them against the
--- quest pieces of the last `/esc gen` export (~15-20 min, early exit when
--- everything is matched).
function Gen.GenerateQuests()
  if qscanRunning then ns.Print("Quest scan already running…") return end
  local genSets = EasySetCollectionGen and EasySetCollectionGen.sets
  if not genSets then
    ns.Print("Run |cffffff00/esc gen|r first — the quest scan reads its export.")
    return
  end
  if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID and GetQuestLogRewardInfo) then
    ns.Print("Quest reward APIs unavailable.")
    return
  end

  qscanTargets, qscanFound, qscanTotal = {}, {}, 0
  for _, rec in ipairs(genSets) do
    for _, p in ipairs(rec.pieces or {}) do
      if p.st == 2 and p.itemID and not qscanTargets[p.itemID] then
        qscanTargets[p.itemID] = true
        qscanTotal = qscanTotal + 1
      end
    end
  end
  if qscanTotal == 0 then
    ns.Print("No quest pieces in the export — nothing to scan.")
    return
  end

  qscanRunning, qscanNext, qscanMatched = true, 1, 0
  qscanPending = {}

  -- stage 1 result: quest data loaded -> ask for its reward data and queue it
  qscanFrame = qscanFrame or CreateFrame("Frame")
  qscanFrame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
  qscanFrame:SetScript("OnEvent", function(_, _, questID, success)
    if not (qscanRunning and success and questID) then return end
    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
      pcall(C_TaskQuest.RequestPreloadRewardData, questID)
    end
    qscanPending[#qscanPending + 1] = { q = questID, a = 0 }
  end)

  -- stage 2: poll the queued quests until their reward data is available
  qscanRewardTicker = C_Timer.NewTicker(QREWARD_INTERVAL, function()
    local remaining = {}
    for _, e in ipairs(qscanPending) do
      if not HaveQuestRewardData or HaveQuestRewardData(e.q) then
        qscanReadRewards(e.q)
      else
        e.a = e.a + 1
        if e.a < QREWARD_ATTEMPTS then remaining[#remaining + 1] = e end
      end
    end
    qscanPending = remaining
    if qscanRunning and (qscanMatched >= qscanTotal
        or (qscanNext > QSCAN_MAX and #qscanPending == 0)) then
      qscanFinish()
    end
  end)

  ns.Print(string.format(
    "Scanning quests 1..%d for %d quest-reward items (~15-20 min, stay logged in)…",
    QSCAN_MAX, qscanTotal))
  qscanTicker = C_Timer.NewTicker(QSCAN_INTERVAL, function()
    for _ = 1, QSCAN_BATCH do
      if qscanNext > QSCAN_MAX then break end
      pcall(C_QuestLog.RequestLoadQuestByID, qscanNext)
      qscanNext = qscanNext + 1
    end
    if qscanNext % 10000 <= QSCAN_BATCH then
      ns.Print(string.format("… quest %d/%d — %d/%d items matched (%d awaiting reward data)",
        math.min(qscanNext, QSCAN_MAX), QSCAN_MAX, qscanMatched, qscanTotal, #qscanPending))
    end
    if qscanNext > QSCAN_MAX and qscanTicker then
      qscanTicker:Cancel()   -- stage 2 keeps draining and finishes the scan
    end
  end)
end

-- --- entry point ------------------------------------------------------------------

--- `/esc gen`: run the whole generation (a few seconds, chunked per frame).
function Gen.Generate()
  if running then ns.Print("Already scanning…") return end
  if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal") end
  if not (EJ_GetNumTiers and EJ_GetInstanceByIndex and C_TransmogSets and C_TransmogSets.GetAllSets
      and C_TransmogCollection and C_TransmogCollection.GetAppearanceSourceDrops) then
    ns.Print("Required APIs unavailable (Encounter Journal / transmog sets).")
    return
  end

  running = true
  outSets, unresolved, emptyBoss = {}, {}, {}
  stats = { pieces = 0, boss = 0, resolved = 0 }

  ns.Print("Indexing the Encounter Journal…")
  buildEJIndex()
  ns.Print("Harvesting instance entrances…")
  harvestEntrances()
  ns.Print("Snapshotting PvP sets…")
  snapshotPvP()

  local all = C_TransmogSets.GetAllSets() or {}
  ns.Print(string.format("Sweeping %d sets…", #all))
  local idx = 0
  local function stepFn()
    local n = 0
    while idx < #all and n < SETS_PER_STEP do
      idx = idx + 1
      processSet(all[idx])
      n = n + 1
    end
    if idx < #all then
      if idx % 1000 < SETS_PER_STEP then
        ns.Print(string.format("… %d/%d sets", idx, #all))
      end
      C_Timer.After(0, stepFn)
    else
      retryEmptyThenFinalize()
    end
  end
  stepFn()
end
