-- Sets.lua — the in-memory set catalog: enumerates every journal transmog set via
-- C_TransmogSets.GetAllSets(), groups variants (Normal/Heroic/Mythic/LFR recolors)
-- under their base set, and precomputes the static fields the filter pipeline and
-- list rows need. Rebuilt from scratch whenever the collection changes (cheap:
-- synchronous DB reads).

local ADDON, ns = ...
ns.Sets = ns.Sets or {}
local Sets = ns.Sets

-- content-type buckets shown in the filter UI, in display order
ns.CONTENT_BUCKETS = { "raid", "dungeon", "pvp", "quest", "vendor", "world", "unknown" }

-- fine-grained baked content type -> UI filter bucket
ns.CT_BUCKET = {
  raid = "raid", dungeon = "dungeon", pvp = "pvp", quest = "quest",
  vendor = "vendor", tradingpost = "vendor",
  world = "world", achievement = "world", profession = "world",
  unknown = "unknown",
}

--- Localized expansion name. Expansion 0 is special-cased to "Classic": the
--- frFR client translates EXPANSION_NAME0 as the confusing "World of Warcraft".
function ns.ExpansionName(id)
  if id == 0 then return ns.L["Classic"] end
  return _G["EXPANSION_NAME" .. (id or 0)] or ("Exp " .. tostring(id))
end

--- Localized class name for a classID (nil-safe).
local function classNameFor(classID)
  local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
  return info and info.className
end

--- Compute the classes bit of a group: how many classes can wear it and, when
--- there is exactly one, its localized name (shown in the row tag).
local function classSummary(classMask)
  local count, single = 0, nil
  local numClasses = GetNumClasses and GetNumClasses() or 13
  for classID = 1, numClasses do
    if bit.band(classMask or 0, 2 ^ (classID - 1)) ~= 0 then
      count = count + 1
      single = (count == 1) and classID or nil
    end
  end
  return count, single and classNameFor(single) or nil
end

--- Build (or return) the catalog. Returns nil while C_TransmogSets has no data
--- yet (right after login) — callers retry on the next collection event.
function Sets.EnsureCatalog()
  if Sets.catalog then return Sets.catalog end
  if not (C_TransmogSets and C_TransmogSets.GetAllSets) then return nil end

  local all = C_TransmogSets.GetAllSets()
  if not all or #all == 0 then return nil end

  local groups, order = {}, {}
  for _, info in ipairs(all) do
    local baseID = info.baseSetID or info.setID
    local g = groups[baseID]
    if not g then
      g = { baseSetID = baseID, variants = {} }
      groups[baseID] = g
      order[#order + 1] = g
    end
    if info.setID == baseID then g.base = info end
    g.variants[#g.variants + 1] = info
  end

  for _, g in ipairs(order) do
    -- defensive: a variant can show up without its base row in GetAllSets
    g.base = g.base or g.variants[1]
    -- Blizzard displays variants by descending uiOrder (highest difficulty first)
    table.sort(g.variants, function(a, b) return (a.uiOrder or 0) > (b.uiOrder or 0) end)

    local b = g.base
    g.name = b.name or ""
    g.nameLower = g.name:lower()
    g.expansionID = b.expansionID or 0
    g.classMask = b.classMask or 0
    g.uiOrder = b.uiOrder or 0
    g.requiredFaction = b.requiredFaction
    g.limitedTimeSet = b.limitedTimeSet
    g.classCount, g.className = classSummary(g.classMask)

    -- a group is hidden while every variant is a hidden-until-collected set the
    -- player hasn't collected (mirrors the Blizzard sets journal)
    local allHidden = true
    local fav = false
    for _, v in ipairs(g.variants) do
      if not (v.hiddenUntilCollected and not v.collected) then allHidden = false end
      if v.favorite then fav = true end
    end
    g.hidden = allHidden
    g.favorite = fav

    g.bucket, g.legacy = ns.Sources.ClassifyGroup(g)
  end

  Sets.catalog = { groups = groups, order = order }
  return Sets.catalog
end

--- Throw the catalog away; the next EnsureCatalog() call rebuilds it.
function Sets.Invalidate()
  Sets.catalog = nil
end

--- Re-read the favorite flag of every group (TRANSMOG_SETS_UPDATE_FAVORITE).
function Sets.RefreshFavorites()
  local cat = Sets.catalog
  if not cat then return end
  for _, g in ipairs(cat.order) do
    local fav = false
    for _, v in ipairs(g.variants) do
      if C_TransmogSets.GetIsFavorite and C_TransmogSets.GetIsFavorite(v.setID) then
        fav = true
        break
      end
    end
    g.favorite = fav
  end
end

--- Group record for a base setID (nil while the collection data isn't ready).
function Sets.GroupFor(baseSetID)
  local cat = Sets.EnsureCatalog()
  return cat and cat.groups[baseSetID] or nil
end

--- Catalog sizes for `/esc debug`: number of groups, number of variant sets.
function Sets.Counts()
  local cat = Sets.EnsureCatalog()
  if not cat then return 0, 0 end
  local nSets = 0
  for _, g in ipairs(cat.order) do nSets = nSets + #g.variants end
  return #cat.order, nSets
end
