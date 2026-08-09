-- Pieces.lua — per-set collection progress and per-piece records.
-- The X/N computation is copied from Blizzard's own sets journal
-- (WardrobeSetsDataProviderMixin:GetSetSourceData): count collected PRIMARY
-- appearances, never GetAllSourceIDs (which lists alternate same-look sources
-- and would inflate the denominator).
--
-- Gotcha (verified in Blizzard code): TransmogSetPrimaryAppearanceInfo's
-- `appearanceID` field is actually a sourceID (itemModifiedAppearanceID).

local ADDON, ns = ...
ns.Pieces = ns.Pieces or {}
local Pieces = ns.Pieces

local progress = {}   -- [setID] = { collected = n, total = m }, lazy
local iconCache = {}  -- [setID] = fileID | false, lazy

-- --- synthetic sets (Data/ExtraSets.lua, negative setIDs = -wowheadID) --------

--- The baked extra-set record behind a synthetic setID, nil for journal sets.
function Pieces.ExtraFor(setID)
  local X = EasySetCollectionExtraSets
  return (setID and setID < 0 and X) and X[-setID] or nil
end

--- Appearance-level "collected": any source of the visual is known (what
--- pa.collected means for journal pieces).
local function visualCollected(visualID)
  if not visualID then return false end
  local ok, all = pcall(C_TransmogCollection.GetAllAppearanceSources, visualID)
  if ok and type(all) == "table" then
    for _, sid in ipairs(all) do
      if C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance
        and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sid) then
        return true
      end
    end
  end
  return false
end

--- Piece records of a synthetic set: itemID -> live appearance/source data.
--- C_TransmogCollection.GetItemInfo answers only once the ITEM DATA is
--- loaded (old items start cold): unresolved items get a PLACEHOLDER record
--- (no sourceID, "…" name) and an async load request — the detail pane's
--- ContinueOnItemLoad repaint re-resolves them a moment later. The second
--- return says whether any placeholder remains (callers skip their caches).
local function extraPieces(x)
  local out = {}
  local pending = false
  for _, itemID in ipairs(x.items or {}) do
    local visualID, sourceID = C_TransmogCollection.GetItemInfo
      and C_TransmogCollection.GetItemInfo(itemID)
    local si = sourceID and C_TransmogCollection.GetSourceInfo(sourceID)
    if si then
      -- source info of NON-journal items carries no name/quality: try the
      -- transmog item LINK first (local wardrobe data, instant), then the
      -- item cache; still-cold items get a load request and resolve on the
      -- pane's ContinueOnItemLoad repaint
      local iName, iQuality
      if C_TransmogCollection.GetAppearanceSourceInfo then
        local ok, _, _, _, _, _, link = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
        if ok and type(link) == "string" then
          local n = link:match("%[(.-)%]")
          if n and n ~= "" then iName = n end
        end
      end
      if C_Item and C_Item.GetItemInfo then
        local n, _, q = C_Item.GetItemInfo(si.itemID or itemID)
        iName, iQuality = iName or n, q
      end
      if not iName and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, si.itemID or itemID)
      end
      out[#out + 1] = {
        sourceID = sourceID,
        collected = visualCollected(visualID or si.visualID),
        sourceCollected = si.isCollected,
        itemID = si.itemID or itemID,
        itemModID = si.itemModID,
        invType = si.invType,
        sourceType = (si.sourceType and si.sourceType > 0) and si.sourceType or nil,
        name = (si.name and si.name ~= "") and si.name or iName,
        quality = si.quality or iQuality,
      }
    else
      pending = true
      if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
      end
      out[#out + 1] = {
        sourceID = nil,   -- placeholder: inert row until the item loads
        collected = false,
        sourceCollected = false,
        itemID = itemID,
        invType = C_Item.GetItemInventoryTypeByID
          and C_Item.GetItemInventoryTypeByID(itemID) or nil,
        sourceType = nil,
        name = nil,
        quality = nil,
      }
    end
  end
  return out, pending
end

--- X/N progress of one variant set (cached until the collection changes).
---@return number collected, number total
function Pieces.Progress(setID)
  local p = progress[setID]
  if not p then
    local n, t = 0, 0
    local x = Pieces.ExtraFor(setID)
    if x then
      local recs, pending = extraPieces(x)
      for _, rec in ipairs(recs) do
        t = t + 1
        if rec.collected then n = n + 1 end
      end
      if pending then
        -- some items still cold: report but DON'T cache, the next call
        -- (post item-load repaint) recounts with real data
        return n, t
      end
    else
      local pas = C_TransmogSets.GetSetPrimaryAppearances and
        C_TransmogSets.GetSetPrimaryAppearances(setID)
      if pas then
        for _, pa in ipairs(pas) do
          t = t + 1
          if pa.collected then n = n + 1 end
        end
      end
    end
    p = { collected = n, total = t }
    progress[setID] = p
  end
  return p.collected, p.total
end

--- Progress shown on a group's list row: the best variant's counts, so a
--- Mythic-only collector isn't shown 0/8 (Blizzard GetBaseSetData pattern).
---@return number collected, number total
function Pieces.GroupProgress(group)
  local bestN, bestT, bestRatio = 0, 0, -1
  for _, v in ipairs(group.variants) do
    local n, t = Pieces.Progress(v.setID)
    local r = t > 0 and n / t or 0
    if r > bestRatio or (r == bestRatio and t > bestT) then
      bestRatio, bestN, bestT = r, n, t
    end
  end
  return bestN, bestT
end

--- Possession bucket of a group for the filter: "complete" when any variant is
--- fully collected, "partial" when any piece is owned, "none" otherwise.
function Pieces.PossessionState(group)
  local anyStarted = false
  for _, v in ipairs(group.variants) do
    local n, t = Pieces.Progress(v.setID)
    if t > 0 and n >= t then return "complete" end
    if n > 0 then anyStarted = true end
  end
  return anyStarted and "partial" or "none"
end

--- Piece records of one variant set, sorted head-to-feet (EJ inventory order).
--- `name`/`quality` may be nil until the item cache warms; the detail pane
--- resolves them asynchronously via Item:ContinueOnItemLoad.
function Pieces.For(setID)
  local out = {}
  local x = Pieces.ExtraFor(setID)
  if x then
    out = extraPieces(x)
  else
    local pas = C_TransmogSets.GetSetPrimaryAppearances and
      C_TransmogSets.GetSetPrimaryAppearances(setID)
    if not pas then return out end
    for _, pa in ipairs(pas) do
      local si = C_TransmogCollection.GetSourceInfo(pa.appearanceID)
      if si then
        out[#out + 1] = {
          sourceID = pa.appearanceID,
          collected = pa.collected,
          sourceCollected = si.isCollected,   -- that exact item known (tooltip detail)
          itemID = si.itemID,
          itemModID = si.itemModID,
          invType = si.invType,
          sourceType = si.sourceType,
          name = si.name,
          quality = si.quality,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    local oa = EJ_GetInvTypeSortOrder and EJ_GetInvTypeSortOrder(a.invType or 0) or a.invType or 99
    local ob = EJ_GetInvTypeSortOrder and EJ_GetInvTypeSortOrder(b.invType or 0) or b.invType or 99
    if oa ~= ob then return oa < ob end
    return (a.itemID or 0) < (b.itemID or 0)
  end)
  return out
end

--- Localized slot label ("Head", "Tête", …) from the item's equip location.
function Pieces.SlotLabel(itemID)
  if not itemID then return "" end
  local equipLoc = select(4, C_Item.GetItemInfoInstant(itemID))
  return (equipLoc and _G[equipLoc]) or ""
end

--- Item link of a source (for chat linking / dress-up); nil-safe. Tries the
--- transmog-aware link first, then the plain item link (cached by the time the
--- detail pane displays the piece).
function Pieces.ItemLink(sourceID, itemID)
  if C_TransmogCollection and C_TransmogCollection.GetAppearanceSourceInfo then
    local ok, _, _, _, _, _, link = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
    if ok and type(link) == "string" and link ~= "" then return link end
  end
  if itemID and C_Item and C_Item.GetItemInfo then
    local link = select(2, C_Item.GetItemInfo(itemID))
    if link then return link end
  end
  return nil
end

--- Icon shown on a group's list row. Sets have no icon of their own, so this
--- replicates TransmogUtil.GetSetIcon: the best head-to-feet piece's item icon
--- (available synchronously via GetItemInfoInstant, no item-cache dance).
function Pieces.SetIcon(setID)
  local icon = iconCache[setID]
  if icon ~= nil then return icon or nil end
  local bestItem, bestOrder
  local x = Pieces.ExtraFor(setID)
  if x then
    -- synthetic: straight over the baked itemIDs (inventory type is synchronous)
    for _, itemID in ipairs(x.items or {}) do
      local invType = C_Item.GetItemInventoryTypeByID and C_Item.GetItemInventoryTypeByID(itemID)
      local order = (EJ_GetInvTypeSortOrder and invType and EJ_GetInvTypeSortOrder(invType)) or 99
      if not bestOrder or order < bestOrder then
        bestOrder, bestItem = order, itemID
      end
    end
  else
    local pas = C_TransmogSets.GetSetPrimaryAppearances and
      C_TransmogSets.GetSetPrimaryAppearances(setID)
    for _, pa in ipairs(pas or {}) do
      local si = C_TransmogCollection.GetSourceInfo(pa.appearanceID)
      if si and si.itemID then
        local order = EJ_GetInvTypeSortOrder and EJ_GetInvTypeSortOrder(si.invType or 0) or 99
        if not bestOrder or order < bestOrder then
          bestOrder, bestItem = order, si.itemID
        end
      end
    end
  end
  icon = bestItem and select(5, C_Item.GetItemInfoInstant(bestItem)) or false
  if icon or not x then
    -- synthetic sets skip negative caching: cold items may resolve later
    iconCache[setID] = icon
  end
  return icon or nil
end

--- Drop every cached progress entry (collection changed globally).
--- `Pieces.stamp` increments on every invalidation so consumers (the preview
--- model) can key their own caches on collection state.
function Pieces.WipeProgressCache()
  wipe(progress)
  Pieces.stamp = (Pieces.stamp or 0) + 1
end

--- Drop the cached progress of every set containing this source (targeted
--- invalidation for TRANSMOG_COLLECTION_SOURCE_ADDED/REMOVED).
function Pieces.InvalidateSource(sourceID)
  if not (sourceID and C_TransmogSets.GetSetsContainingSourceID) then return end
  local setIDs = C_TransmogSets.GetSetsContainingSourceID(sourceID)
  for _, setID in ipairs(setIDs or {}) do
    progress[setID] = nil
  end
  Pieces.stamp = (Pieces.stamp or 0) + 1
end
