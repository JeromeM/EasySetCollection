-- Sources.lua — where does each piece come from, and where do we send the player?
-- Joins three layers, most authoritative first:
--   1. Data/Overrides.lua  — hand-curated targets/corrections (vendor coords, …)
--   2. Data/SetSources.lua — generator-baked IDs (journalInstanceID per piece)
--   3. live resolution     — C_TransmogCollection.GetAppearanceSourceDrops gives
--      localized strings (no IDs); a lazily-built Encounter Journal name index
--      turns them into journalInstanceIDs. This fallback keeps new-patch sets
--      working before the baked data is regenerated.
--
-- Display strings always come from the live APIs (client-localized); baked data
-- is only ever IDs.
--
-- NOTE: AppearanceSourceInfo.sourceType is a luaIndex matching the localized
-- TRANSMOG_SOURCE_<n> globals (1=Boss Drop … 7=Trading Post). It is NOT the
-- Enum.TransmogSource numbering — never compare against that enum.

local ADDON, ns = ...
ns.Sources = ns.Sources or {}
local Sources = ns.Sources
local L = ns.L

ns.SRC = { BOSS = 1, QUEST = 2, VENDOR = 3, WORLD = 4, ACHIEVEMENT = 5, PROFESSION = 6, TRADINGPOST = 7 }

--- Localized label of a sourceType ("Boss Drop", "Quête", …).
function Sources.SourceLabel(sourceType)
  return (sourceType and _G["TRANSMOG_SOURCE_" .. sourceType]) or L["Unknown source"]
end

-- --- overrides ------------------------------------------------------------

--- Hand-authored override for a set: the variant-specific entry wins over the
--- base-set entry.
local function overrideFor(setID)
  local ov = EasySetCollectionOverrides and EasySetCollectionOverrides.sets
  if not ov then return nil end
  if ov[setID] then return ov[setID] end
  local base = C_TransmogSets.GetBaseSetID and C_TransmogSets.GetBaseSetID(setID)
  return base and ov[base] or nil
end

-- --- live drop info (localized strings, cached — the data is static) --------

local dropsCache = {}   -- [sourceID] = TransmogAppearanceJournalEncounterInfo[]

local function dropsFor(sourceID)
  local d = dropsCache[sourceID]
  if d then return d end
  local ok, drops
  if C_TransmogCollection.GetAppearanceSourceDrops then
    ok, drops = pcall(C_TransmogCollection.GetAppearanceSourceDrops, sourceID)
  end
  if ok and type(drops) == "table" and #drops > 0 then
    dropsCache[sourceID] = drops
    return drops
  end
  -- empty results are NOT cached: drop data can arrive late, retry next call
  return nil
end

-- --- Encounter Journal name index (runtime fallback, built once) ------------

local ejIndex   -- [localized instance name] = journalInstanceID
local ejIsRaid  -- [journalInstanceID] = true for raids

local function ensureEJIndex()
  if ejIndex then return ejIndex end
  if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal") end
  end
  if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return nil end

  ejIndex, ejIsRaid = {}, {}
  local prevTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
  for tier = 1, EJ_GetNumTiers() do
    EJ_SelectTier(tier)
    for _, isRaid in ipairs({ false, true }) do
      local i = 1
      while true do
        local jid, name = EJ_GetInstanceByIndex(i, isRaid)
        if not jid then break end
        if name and not ejIndex[name] then ejIndex[name] = jid end
        if isRaid then ejIsRaid[jid] = true end
        i = i + 1
      end
    end
  end
  -- EJ_SelectTier mutates shared Encounter Journal state; put it back
  if prevTier then pcall(EJ_SelectTier, prevTier) end
  return ejIndex
end

--- journalInstanceID for a localized instance name (EJ name index), nil when
--- unknown. Used by the in-instance assistant as a fallback when the map→EJ
--- resolution has no answer.
function Sources.InstanceByName(name)
  if not name then return nil end
  local idx = ensureEJIndex()
  return idx and idx[name] or nil
end

--- Is this instance a raid? Baked flag first, then the EJ index.
function Sources.InstanceIsRaid(jid)
  local inst = EasySetCollectionInstances and EasySetCollectionInstances[jid]
  if inst and inst.raid ~= nil then return inst.raid and true or false end
  ensureEJIndex()
  return (ejIsRaid and ejIsRaid[jid]) and true or false
end

--- Localized instance name for a journalInstanceID (nil-safe).
function Sources.InstanceName(jid)
  if jid and EJ_GetInstanceInfo then
    local name = EJ_GetInstanceInfo(jid)
    if name and name ~= "" then return name end
  end
  return jid and ("#" .. jid) or "?"
end

-- --- quest titles (from hand-authored questID overrides) ----------------------

local questTitleCache = {}   -- [questID] = localized title

--- Localized quest title for a questID; nil while the data loads (the request
--- is issued here, QUEST_DATA_LOAD_RESULT triggers a repaint — see Core.lua).
function Sources.QuestTitle(questID)
  if not questID then return nil end
  local cached = questTitleCache[questID]
  if cached then return cached end
  local title = C_QuestLog and C_QuestLog.GetTitleForQuestID
    and C_QuestLog.GetTitleForQuestID(questID)
  if title and title ~= "" then
    questTitleCache[questID] = title
    return title
  end
  if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
    pcall(C_QuestLog.RequestLoadQuestByID, questID)
  end
  return nil
end

-- --- per-piece resolution ---------------------------------------------------

--- The instance a piece drops in: baked ID first, live name-match fallback.
---@return number? journalInstanceID, string? localized instance name
function Sources.PieceInstance(setID, piece)
  local baked = EasySetCollectionSets and EasySetCollectionSets[setID]
  if baked then
    local p = baked.pieces and baked.pieces[piece.sourceID]
    local jid = p and p.j
    if not jid and (not p or p.j == nil) then
      local st = (p and p.st) or piece.sourceType
      if st == ns.SRC.BOSS then jid = baked.j end
    end
    if jid then return jid, Sources.InstanceName(jid) end
  end
  local drops = dropsFor(piece.sourceID)
  if drops then
    local d = drops[1]
    local idx = ensureEJIndex()
    local jid = idx and d.instance and idx[d.instance] or nil
    return jid, d.instance
  end
  return nil, nil
end

--- Display line for a piece row in the detail pane:
--- boss drops → "Encounter – Instance (Difficulty, …)", otherwise the localized
--- source-type label ("Quête", "Vendeur", …).
function Sources.PieceSourceText(setID, piece)
  if piece.sourceType == ns.SRC.BOSS then
    local drops = dropsFor(piece.sourceID)
    if drops then
      -- show the drop entry consistent with the resolved (baked-aware)
      -- instance, so the detail rows agree with the list label
      local d = drops[1]
      if #drops > 1 then
        local jid = Sources.PieceInstance(setID, piece)
        if jid then
          local want = Sources.InstanceName(jid)
          for _, cand in ipairs(drops) do
            if cand.instance == want then d = cand break end
          end
        end
      end
      local txt = (d.encounter and d.encounter ~= "") and (d.encounter .. " – ") or ""
      txt = txt .. (d.instance or "")
      if d.difficulties and #d.difficulties > 0 then
        txt = txt .. " (" .. table.concat(d.difficulties, ", ") .. ")"
      end
      if #drops > 1 then
        txt = txt .. " " .. string.format(L["(+%d other sources)"], #drops - 1)
      end
      if txt ~= "" then return txt end
    end
    local jid = Sources.PieceInstance(setID, piece)
    if jid then return Sources.InstanceName(jid) end
  end
  if piece.sourceType == ns.SRC.QUEST then
    -- quest title: the override questID wins, then the baked quest mapping
    -- (from the /esc genquests sweep)
    local ov = overrideFor(setID)
    local qid = ov and ov.questID
    if not qid and EasySetCollectionSets then
      local baked = EasySetCollectionSets[setID]
      if baked then
        local p = baked.pieces and baked.pieces[piece.sourceID]
        qid = (p and p.q) or baked.q
      end
    end
    if qid then
      local title = Sources.QuestTitle(qid)
      if title then
        return string.format(L["%s: %s"], Sources.SourceLabel(piece.sourceType), title)
      end
    end
  elseif piece.sourceType == ns.SRC.VENDOR then
    local ov = overrideFor(setID)
    if ov and ov.npc then
      return string.format(L["%s: %s"], Sources.SourceLabel(piece.sourceType), L[ov.npc])
    end
  end
  return Sources.SourceLabel(piece.sourceType)
end

--- EVERY instance a piece can drop in: the resolved primary plus the live
--- multi-drop locations (WotLK tiers fall in Naxxramas AND the Vault of
--- Archavon — both count).
---@return table  set of journalInstanceID = true
function Sources.PieceInstanceSet(setID, piece)
  local jids = {}
  local primary = Sources.PieceInstance(setID, piece)
  if primary then jids[primary] = true end
  if piece.sourceType == ns.SRC.BOSS then
    local drops = dropsFor(piece.sourceID)
    if drops then
      local idx = ensureEJIndex()
      for _, d in ipairs(drops) do
        local j2 = idx and d.instance and idx[d.instance]
        if j2 then jids[j2] = true end
      end
    end
  end
  return jids
end

--- The encounter dropping a piece inside a SPECIFIC instance (localized) —
--- the resolved-first drop entry can belong to another instance.
function Sources.PieceEncounterIn(setID, piece, jid)
  if piece.sourceType ~= ns.SRC.BOSS then return nil end
  local drops = dropsFor(piece.sourceID)
  if not drops then return nil end
  local want = Sources.InstanceName(jid)
  for _, d in ipairs(drops) do
    if d.instance == want then return d.encounter end
  end
  return drops[1] and drops[1].encounter
end

--- Hierarchy parts of a piece for the tracker tree: the LOCATION (instance
--- name, or the source kind for non-instance pieces) and the SOURCE inside it
--- (boss encounter / quest title / vendor name — nil when unknown).
function Sources.PieceSourceParts(setID, piece)
  if piece.sourceType == ns.SRC.BOSS then
    local jid = Sources.PieceInstance(setID, piece)
    local drops = dropsFor(piece.sourceID)
    local d
    if drops then
      d = drops[1]
      if jid and #drops > 1 then
        local want = Sources.InstanceName(jid)
        for _, cand in ipairs(drops) do
          if cand.instance == want then d = cand break end
        end
      end
    end
    local loc = (jid and Sources.InstanceName(jid)) or (d and d.instance)
    if loc then return loc, d and d.encounter or nil end
    return Sources.SourceLabel(piece.sourceType), nil
  elseif piece.sourceType == ns.SRC.QUEST then
    local ov = overrideFor(setID)
    local qid = ov and ov.questID
    if not qid and EasySetCollectionSets then
      local baked = EasySetCollectionSets[setID]
      if baked then
        local p = baked.pieces and baked.pieces[piece.sourceID]
        qid = (p and p.q) or baked.q
      end
    end
    return Sources.SourceLabel(piece.sourceType), qid and Sources.QuestTitle(qid) or nil
  elseif piece.sourceType == ns.SRC.VENDOR then
    local ov = overrideFor(setID)
    return Sources.SourceLabel(piece.sourceType), (ov and ov.npc and L[ov.npc]) or nil
  end
  return Sources.SourceLabel(piece.sourceType), nil
end

-- --- group classification (used at catalog build) ----------------------------

local CT_PRIORITY = { "raid", "dungeon", "quest", "vendor", "world", "achievement", "profession", "tradingpost" }
local ST_CT = { [2] = "quest", [3] = "vendor", [4] = "world", [5] = "achievement", [6] = "profession", [7] = "tradingpost" }
local liveCt = {}   -- [baseSetID] = ct, kept across catalog rebuilds

--- Runtime fallback classification (fresh install / new-patch sets with no
--- baked data): majority sourceType over the base variant's pieces, boss drops
--- split raid/dungeon through the Encounter Journal name index. Only complete
--- answers are cached — drop data can still be loading.
local function classifyLive(g)
  local cached = liveCt[g.baseSetID]
  if cached then return cached end
  local setID = (g.base and g.base.setID) or g.baseSetID
  local pas = C_TransmogSets.GetSetPrimaryAppearances and
    C_TransmogSets.GetSetPrimaryAppearances(setID)
  if not pas or #pas == 0 then return nil end

  local tally, incomplete = {}, false
  for _, pa in ipairs(pas) do
    local si = C_TransmogCollection.GetSourceInfo(pa.appearanceID)
    local st = si and si.sourceType
    local ct
    if st == ns.SRC.BOSS then
      local drops = dropsFor(pa.appearanceID)
      local idx = ensureEJIndex()
      local jid = drops and drops[1] and drops[1].instance and idx and idx[drops[1].instance]
      if jid then
        ct = Sources.InstanceIsRaid(jid) and "raid" or "dungeon"
      else
        incomplete = true
      end
    else
      ct = ST_CT[st]
    end
    if ct then tally[ct] = (tally[ct] or 0) + 1 end
  end

  local best, bestN = nil, 0
  for _, ct in ipairs(CT_PRIORITY) do
    local n = tally[ct] or 0
    if n > bestN then best, bestN = ct, n end
  end
  if best and not incomplete then liveCt[g.baseSetID] = best end
  return best
end

-- --- default variant --------------------------------------------------------

-- difficultyIDs in DEFAULT-SELECTION preference order: Normal first (dungeon,
-- raid, then 10-player before 25-player and 40), Heroic, Mythic, LFR last.
local DIFF_PREF_IDS = { 1, 14, 3, 4, 9, 2, 15, 5, 6, 23, 16, 17, 7 }
local prefRanks   -- [localized difficulty name] = rank (built once)

local function difficultyRank(desc)
  if not desc or desc == "" then return nil end
  if not prefRanks then
    prefRanks = {}
    for i, d in ipairs(DIFF_PREF_IDS) do
      local name = GetDifficultyInfo and GetDifficultyInfo(d)
      if name and not prefRanks[name] then prefRanks[name] = i end
    end
  end
  return prefRanks[desc]
end

--- The variant a group should open on (and the one its list label describes):
--- dungeon variants first (mixed dungeon/vendor groups), then by difficulty
--- preference (Normal, 10-player, 25-player, Heroic…, Mythic, LFR), then the
--- base set itself.
function Sources.DefaultVariant(g)
  local best, bestScore
  for _, v in ipairs(g.variants) do
    local score = 1000
    local rank = difficultyRank(v.description)
    if rank then score = rank * 10 end
    local baked = EasySetCollectionSets and EasySetCollectionSets[v.setID]
    if baked and baked.ct == "dungeon" then score = score - 500 end
    if v.setID == g.baseSetID then score = score - 1 end
    if not bestScore or score < bestScore then best, bestScore = v.setID, score end
  end
  return best
end

local locCache = {}   -- [baseSetID] = location label (static, resolved once)

--- Label for a SET of journalInstanceIDs: the instance's name when there is
--- one, a plural kind ("Dungeons"/"Raids") when the pieces span several.
local function instancesLabel(jids)
  local total, raids, only = 0, 0, nil
  for jid in pairs(jids) do
    total = total + 1
    only = jid
    if Sources.InstanceIsRaid(jid) then raids = raids + 1 end
  end
  if total == 0 then return nil end
  if total == 1 then return Sources.InstanceName(only) end
  if raids == total then return L["Raids"] end
  if raids == 0 then return L["Dungeons"] end
  return L["Dungeons & raids"]
end

--- Human location of a group for its list row: curated override (zone/NPC/
--- instance) > baked instances > live drop info > dominant source kind
--- (Quest, Vendor, …). Multi-instance sets get a plural label instead of a
--- misleading single instance name.
function Sources.LocationLabel(g)
  local cached = locCache[g.baseSetID]
  if cached then return cached end
  local label
  local nocache = false

  local ov = EasySetCollectionOverrides and EasySetCollectionOverrides.sets
    and EasySetCollectionOverrides.sets[g.baseSetID]
  if ov then
    if ov.j then
      label = Sources.InstanceName(ov.j)
    else
      if ov.questID then
        local title = Sources.QuestTitle(ov.questID)
        if title then
          label = title
        else
          nocache = true   -- fall back below, upgrade once the title loads
        end
      end
      if not label and ov.npc then label = L[ov.npc] end
      if not label and ov.map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(ov.map)
        label = info and info.name
      end
    end
  end

  if not label then
    -- Same per-piece resolution as the detail pane (PieceInstance: overrides >
    -- baked > live), computed on the DEFAULT variant — the one the detail pane
    -- opens on — so the list label and the piece rows always agree.
    local setID = Sources.DefaultVariant(g) or (g.base and g.base.setID) or g.baseSetID
    local pieces = ns.Pieces.For(setID)
    if #pieces == 0 then nocache = true end

    local tally, counts, total, missingDrops = {}, {}, 0, false
    for _, piece in ipairs(pieces) do
      local st = piece.sourceType
      if st == ns.SRC.BOSS then
        local jid, instName = Sources.PieceInstance(setID, piece)
        local name = (jid and Sources.InstanceName(jid)) or instName
        if name then
          counts[name] = (counts[name] or 0) + 1
          total = total + 1
        else
          missingDrops = true
        end
      end
      if st then tally[st] = (tally[st] or 0) + 1 end
    end

    local bestName, bestCount, nNames = nil, 0, 0
    for name, c in pairs(counts) do
      nNames = nNames + 1
      if c > bestCount then bestName, bestCount = name, c end
    end
    if nNames == 1 then
      label = bestName
    elseif nNames > 1 then
      if total - bestCount <= 2 then
        -- at most 2 pieces drop elsewhere: the dominant instance says it best
        -- (e.g. Judgement: 7 pieces in Blackwing Lair, 1 on Ragnaros)
        label = bestName
      else
        local jids, unmatched = {}, 0
        local idx = ensureEJIndex()
        for name in pairs(counts) do
          local jid = idx and idx[name]
          if jid then jids[jid] = true else unmatched = unmatched + 1 end
        end
        label = (unmatched == 0) and instancesLabel(jids) or L["Multiple locations"]
      end
    end
    if label and missingDrops then
      -- some pieces' drop data is still loading: the answer may be incomplete,
      -- return it uncached so the next repaint can do better
      return label
    end

    if not label then
      -- quest set with a baked dominant quest -> its localized title
      local baked = EasySetCollectionSets and EasySetCollectionSets[setID]
      if baked and baked.q then
        local title = Sources.QuestTitle(baked.q)
        if title then label = title else nocache = true end
      end
    end

    if not label then
      if g.bucket == "pvp" then
        label = L["PvP"]
      else
        local best, bestN
        for st, n in pairs(tally) do
          if not bestN or n > bestN then best, bestN = st, n end
        end
        if best then
          label = Sources.SourceLabel(best)
          if best == ns.SRC.BOSS then
            return label   -- uncached: the instance names may still be loading
          end
        end
      end
    end
  end

  if label and not nocache then locCache[g.baseSetID] = label end
  return label
end

--- Filter bucket + legacy flag for a group: override > baked > live fallback.
--- (PvP can only come from the baked data or an override — the live fallback
--- classifies current PvP sets as "vendor".)
function Sources.ClassifyGroup(g)
  local ov = EasySetCollectionOverrides and EasySetCollectionOverrides.sets
    and EasySetCollectionOverrides.sets[g.baseSetID] or nil
  local legacy = (ov and ov.legacy) or false
  local ct = ov and ov.ct
  if not ct then
    local baked = EasySetCollectionSets and EasySetCollectionSets[g.baseSetID]
    if not baked and EasySetCollectionSets then
      for _, v in ipairs(g.variants) do
        baked = EasySetCollectionSets[v.setID]
        if baked then break end
      end
    end
    ct = baked and baked.ct
  end
  if not ct or ct == "unknown" then
    ct = classifyLive(g) or ct
  end
  return ns.CT_BUCKET[ct or "unknown"] or "unknown", legacy
end

-- --- navigation targets -------------------------------------------------------

--- Every place worth guiding to for a variant set, best first. Each target is
--- either { jid, title, missing } (instance holding `missing` uncollected
--- pieces) or { map, x, y, title } (curated override for quest/vendor sets).
function Sources.GuideTargets(setID)
  local out, byJid = {}, {}

  local ov = overrideFor(setID)
  if ov then
    if ov.legacy then return out end
    if ov.map and ov.x and ov.y then
      local info = C_Map.GetMapInfo and C_Map.GetMapInfo(ov.map)
      out[#out + 1] = {
        map = ov.map, x = ov.x, y = ov.y, questID = ov.questID,
        title = (ov.questID and Sources.QuestTitle(ov.questID))
          or (ov.npc and L[ov.npc]) or (info and info.name) or "?",
      }
    elseif ov.j then
      out[#out + 1] = { jid = ov.j, title = Sources.InstanceName(ov.j), missing = 0, pieces = 0 }
      byJid[ov.j] = out[#out]
    end
  end

  -- every instance the set drops in is a target (raid/dungeon entrance), even
  -- when nothing is missing there — missing pieces only drive the priority.
  -- A piece can drop in SEVERAL instances (WotLK tiers: Naxxramas AND Vault of
  -- Archavon), so every drop location counts, not just the resolved-first one.
  local instTargets = {}
  for _, piece in ipairs(ns.Pieces.For(setID)) do
    local jids = Sources.PieceInstanceSet(setID, piece)
    for jid in pairs(jids) do
      local t = byJid[jid]
      if not t then
        t = { jid = jid, title = Sources.InstanceName(jid), missing = 0, pieces = 0 }
        byJid[jid] = t
        instTargets[#instTargets + 1] = t
      end
      t.pieces = t.pieces + 1
      if not piece.collected then t.missing = t.missing + 1 end
    end
  end
  table.sort(instTargets, function(a, b)
    if a.missing ~= b.missing then return a.missing > b.missing end
    if (a.pieces or 0) ~= (b.pieces or 0) then return (a.pieces or 0) > (b.pieces or 0) end
    return a.title < b.title
  end)
  for _, t in ipairs(instTargets) do out[#out + 1] = t end

  return out
end

--- Best single navigation target for a set (nil when there is none).
function Sources.NavFor(setID)
  return Sources.GuideTargets(setID)[1]
end

--- DEV (`/esc missing`): list visible groups with no navigation target, newest
--- expansion first — the authoring worklist for Data/Overrides.lua.
function Sources.DumpMissingNav()
  local cat = ns.Sets.EnsureCatalog()
  if not cat then ns.Print("catalog not ready.") return end
  local missing = {}
  for _, g in ipairs(cat.order) do
    if not g.hidden and not g.legacy then
      local found = false
      for _, v in ipairs(g.variants) do
        if Sources.GuideTargets(v.setID)[1] then found = true break end
      end
      if not found then missing[#missing + 1] = g end
    end
  end
  table.sort(missing, function(a, b)
    if a.expansionID ~= b.expansionID then return a.expansionID > b.expansionID end
    return a.name < b.name
  end)
  ns.Print(string.format("%d set groups without a navigation target:", #missing))
  local shown = math.min(#missing, 40)
  for i = 1, shown do
    local g = missing[i]
    print(string.format("  [%d] %s  (exp=%d, bucket=%s)",
      g.baseSetID, g.name, g.expansionID, g.bucket or "?"))
  end
  if #missing > shown then
    print(string.format("  … and %d more (raise the limit in Sources.DumpMissingNav).", #missing - shown))
  end
end
