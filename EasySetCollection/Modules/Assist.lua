-- Assist.lua — the in-instance assistant: entering a dungeon or raid, announce
-- what you're still missing HERE — which bosses, which pieces — for your own
-- class: a toast with the count, the detailed boss list in the chat frame.
-- Piece → instance joins go through Sources.PieceInstanceSet (multi-drop
-- aware), so WotLK tiers count in Naxxramas AND the Vault of Archavon.

local ADDON, ns = ...
ns.Assist = ns.Assist or {}
local Assist = ns.Assist
local L = ns.L

local lastVisitKey   -- "jid:difficulty" last announced (wing changes / releases must not re-toast, a difficulty change must)

--- The journal instance the player is standing in (nil outdoors / in
--- scenarios): map → EJ resolution first, then the localized instance name
--- (GetInstanceInfo) through the EJ name index.
local function currentJid()
  local inInstance, kind = IsInInstance()
  if not inInstance or (kind ~= "party" and kind ~= "raid") then return nil end
  if not EJ_GetInstanceForMap and C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
  end
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  if map and EJ_GetInstanceForMap then
    local ok, jid = pcall(EJ_GetInstanceForMap, map)
    if ok and jid and jid > 0 then return jid end
  end
  local name = GetInstanceInfo and GetInstanceInfo() or nil
  return name and ns.Sources.InstanceByName(name) or nil
end

--- Public: the journal instance the player is standing in (nil outdoors).
function Assist.CurrentJid()
  return currentJid()
end

--- Facets of the difficulty the player's current instance runs on (nil when
--- unknown — everything then behaves permissively).
local function currentDifficultyFacets()
  local _, _, diffID = GetInstanceInfo()
  return ns.Sources.DifficultyFacets(diffID)
end

--- The variant to inspect for a group: the first one whose difficulty
--- description is COMPATIBLE with the instance's facets ("Heroic" matches a
--- "25 Player (Heroic)" instance), the default variant otherwise.
local function variantFor(g, facets)
  if facets then
    for _, v in ipairs(g.variants) do
      local vf = ns.Sources.FacetsForDifficultyName(v.description)
      if vf and ns.Sources.FacetsCompatible(vf, facets) then return v.setID end
    end
  end
  return ns.Sources.DefaultVariant(g) or g.baseSetID
end

--- Pieces of a group dropping in an instance ON a compatible difficulty.
---@return number here, number missing
local function piecesHere(g, jid, facets)
  local setID = variantFor(g, facets)
  local here, missing = 0, 0
  for _, piece in ipairs(ns.Pieces.For(setID)) do
    if ns.Sources.PieceInstanceSet(setID, piece)[jid]
       and ns.Sources.PieceMatchesDifficulty(setID, piece, jid, facets) then
      here = here + 1
      if not piece.collected then missing = missing + 1 end
    end
  end
  return here, missing
end

--- Does a group drop anything in the CURRENT instance (on its difficulty)?
--- Used to leave the user's selection alone when it already belongs here.
function Assist.GroupDropsIn(g, jid)
  return (piecesHere(g, jid, currentDifficultyFacets())) > 0
end

--- The variant of a group matching the current instance's difficulty (the
--- one the window should open on while standing inside).
function Assist.VariantHere(g)
  return variantFor(g, currentDifficultyFacets())
end

--- The group to bring forward when opening the window inside an instance:
--- the class's set with the most missing pieces HERE (most pieces dropping
--- here as tie-break). Nil when nothing relevant drops here.
function Assist.BestGroupHere(jid)
  local cat = ns.Sets.EnsureCatalog()
  if not cat then return nil end
  local classID = select(3, UnitClass("player"))
  local faction = UnitFactionGroup("player")
  local facets = currentDifficultyFacets()
  local best, bestMissing, bestHere
  for _, g in ipairs(cat.order) do
    if not g.hidden and not g.legacy
      and (not classID or bit.band(g.classMask or 0, 2 ^ (classID - 1)) ~= 0)
      and not (g.requiredFaction and faction and g.requiredFaction ~= faction) then
      local here, missing = piecesHere(g, jid, facets)
      if here > 0 and (not best
          or missing > bestMissing
          or (missing == bestMissing and here > bestHere)) then
        best, bestMissing, bestHere = g, missing, here
      end
    end
  end
  return best
end

--- Missing set pieces (own class, obtainable sets) dropping in an instance,
--- sorted by boss.
---@return table[]?  { boss, pieceName, setName, setID } — nil while the catalog loads
function Assist.MissingHere(jid)
  local cat = ns.Sets.EnsureCatalog()
  if not cat then return nil end
  local classID = select(3, UnitClass("player"))
  local faction = UnitFactionGroup("player")
  local facets = currentDifficultyFacets()
  local out = {}
  for _, g in ipairs(cat.order) do
    repeat
      if g.hidden or g.legacy then break end
      if g.extra and not ns.db.assist.announceExtras then break end
      if classID and bit.band(g.classMask or 0, 2 ^ (classID - 1)) == 0 then break end
      if g.requiredFaction and faction and g.requiredFaction ~= faction then break end
      -- inspect the variant matching the instance's difficulty, and judge
      -- completeness on IT (the 10-player recolor being done must not silence
      -- the 25-player one, and vice versa)
      local setID = variantFor(g, facets)
      local n, t = ns.Pieces.Progress(setID)
      if t == 0 or n >= t then break end
      for _, piece in ipairs(ns.Pieces.For(setID)) do
        if not piece.collected
           and ns.Sources.PieceInstanceSet(setID, piece)[jid]
           and ns.Sources.PieceMatchesDifficulty(setID, piece, jid, facets) then
          out[#out + 1] = {
            boss = ns.Sources.PieceEncounterIn(setID, piece, jid),
            pieceName = piece.name,   -- nil until the item loads (async)
            itemID = piece.itemID,
            sourceID = piece.sourceID,
            setName = g.name,
            setID = setID,
          }
        end
      end
    until true
  end
  table.sort(out, function(a, b)
    if (a.boss or "") ~= (b.boss or "") then return (a.boss or "") < (b.boss or "") end
    return (a.setName or "") < (b.setName or "")
  end)
  return out
end

--- Entering-world / zone-change hook: announce once per instance visit.
function Assist.Check()
  if not (ns.db and ns.db.assist and ns.db.assist.enabled) then return end
  local jid = currentJid()
  if not jid then
    lastVisitKey = nil
    return
  end
  local _, _, diffID = GetInstanceInfo()
  local visitKey = jid .. ":" .. (diffID or 0)
  if visitKey == lastVisitKey then return end
  local list = Assist.MissingHere(jid)
  if not list then
    -- collection still loading (login inside an instance): try again shortly
    C_Timer.After(5, Assist.Check)
    return
  end
  lastVisitKey = visitKey
  if #list == 0 then return end

  local instName = ns.Sources.InstanceName(jid)

  local announced = false
  local function announce()
    if announced then return end
    announced = true
    local line = (#list == 1) and L["A set piece you're missing drops here!"]
      or string.format(L["%d set pieces you're missing drop here!"], #list)
    if ns.db.assist.toast ~= false and ns.UI and ns.UI.NotifyAssist then
      ns.UI.NotifyAssist(instName, line, ns.Pieces.SetIcon(list[1].setID))
    end
    ns.Print(instName .. " — " .. line)
    local facets = currentDifficultyFacets()
    local shown = math.min(#list, 12)
    for i = 1, shown do
      local e = list[i]
      -- a real, clickable item link whenever the item cache allows it
      local pieceText = ns.Pieces.ItemLink(e.sourceID, e.itemID)
        or e.pieceName or ns.Pieces.SlotLabel(e.itemID) or "?"
      local bossText = e.boss or L["Unknown source"]
      if e.boss and ns.Lockouts and ns.Lockouts.BossDead
         and ns.Lockouts.BossDead(jid, facets, e.boss) then
        bossText = bossText .. " |cfff25a4d(" .. L["Defeated"] .. ")|r"
      end
      ns.Print(string.format("|cffe9e9ec%s|r — %s |cff8a8a8a(%s)|r",
        bossText, pieceText, e.setName or "?"))
    end
    if #list > shown then
      ns.Print(string.format(L["(+%d more pieces)"], #list - shown))
    end
  end

  -- item names resolve asynchronously: wait for the stragglers (bounded to
  -- 2s, slot-label fallback) so the lines name the pieces, not their slots
  local waiters = {}
  if Item then
    for _, e in ipairs(list) do
      if not e.pieceName and e.itemID then waiters[#waiters + 1] = e end
    end
  end
  local pending = #waiters
  for _, e in ipairs(waiters) do
    local item = Item:CreateFromItemID(e.itemID)
    item:ContinueOnItemLoad(function()
      e.pieceName = item:GetItemName() or e.pieceName
      pending = pending - 1
      if pending == 0 then announce() end
    end)
  end
  if pending == 0 then
    announce()
  else
    C_Timer.After(2, announce)
  end
end
