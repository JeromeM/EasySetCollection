-- Assist.lua — the in-instance assistant: entering a dungeon or raid, announce
-- what you're still missing HERE — which bosses, which pieces — for your own
-- class: a toast with the count, the detailed boss list in the chat frame.
-- Piece → instance joins go through Sources.PieceInstanceSet (multi-drop
-- aware), so WotLK tiers count in Naxxramas AND the Vault of Archavon.

local ADDON, ns = ...
ns.Assist = ns.Assist or {}
local Assist = ns.Assist
local L = ns.L

local lastJid   -- last announced instance (wing changes / releases must not re-toast)

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

--- Missing set pieces (own class, obtainable sets) dropping in an instance,
--- sorted by boss.
---@return table[]?  { boss, pieceName, setName, setID } — nil while the catalog loads
function Assist.MissingHere(jid)
  local cat = ns.Sets.EnsureCatalog()
  if not cat then return nil end
  local classID = select(3, UnitClass("player"))
  local faction = UnitFactionGroup("player")
  local out = {}
  for _, g in ipairs(cat.order) do
    repeat
      if g.hidden or g.legacy then break end
      if classID and bit.band(g.classMask or 0, 2 ^ (classID - 1)) == 0 then break end
      if g.requiredFaction and faction and g.requiredFaction ~= faction then break end
      local n, t = ns.Pieces.GroupProgress(g)
      if t == 0 or n >= t then break end
      local setID = ns.Sources.DefaultVariant(g) or g.baseSetID
      for _, piece in ipairs(ns.Pieces.For(setID)) do
        if not piece.collected and ns.Sources.PieceInstanceSet(setID, piece)[jid] then
          out[#out + 1] = {
            boss = ns.Sources.PieceEncounterIn(setID, piece, jid),
            pieceName = piece.name or ns.Pieces.SlotLabel(piece.itemID),
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
    lastJid = nil
    return
  end
  if jid == lastJid then return end
  local list = Assist.MissingHere(jid)
  if not list then
    -- collection still loading (login inside an instance): try again shortly
    C_Timer.After(5, Assist.Check)
    return
  end
  lastJid = jid
  if #list == 0 then return end

  local instName = ns.Sources.InstanceName(jid)
  local line = string.format(L["%d set pieces you're missing drop here!"], #list)
  if ns.db.assist.toast ~= false and ns.UI and ns.UI.NotifyAssist then
    ns.UI.NotifyAssist(instName, line, ns.Pieces.SetIcon(list[1].setID))
  end

  ns.Print(instName .. " — " .. line)
  local shown = math.min(#list, 12)
  for i = 1, shown do
    local e = list[i]
    print(string.format("  |cffe9e9ec%s|r — %s |cff8a8a8a(%s)|r",
      e.boss or L["Unknown source"], e.pieceName or "?", e.setName or "?"))
  end
  if #list > shown then
    print("  " .. string.format(L["(+%d more pieces)"], #list - shown))
  end
end
