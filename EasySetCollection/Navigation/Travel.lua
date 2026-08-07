-- Travel.lua — the clickable action for the current travel step (use hearthstone
-- / cast a teleport / use a toy). The secure button is DOCKED inside the window:
-- it is parented to UIParent (so the window itself has no protected child and can
-- freely move/resize in combat) but ANCHORED to the window's action panel, so it
-- sits visually inside it. Anchoring to a Frame (not a region) out of combat is
-- allowed. Attribute + show/hide changes are deferred until out of combat.

local ADDON, ns = ...
ns.Travel = ns.Travel or {}
local Travel = ns.Travel
local L = ns.L

Travel.active = false     -- is there an action to show right now?
Travel.label = nil        -- "Use <name>" (localized), for the panel label

local pending             -- attributes to apply out of combat: { kind, id }
local pendingShow         -- show state to apply out of combat (true/false/nil)

-- --- localized name / icon resolution -------------------------------------
local function itemName(id)
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return C_Item and C_Item.GetItemInfo and (C_Item.GetItemInfo(id))
end
local function spellName(id)
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
  return info and info.name
end
local function itemIcon(id)
  return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
end
local function spellIcon(id)
  return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
end

--- Build the secure action button once, docked (anchored) inside the given panel
--- frame. Returns the already-built button on subsequent calls.
---@param anchorTo table  frame the button anchors its LEFT edge to
---@return table  the secure Button frame
function Travel.Ensure(anchorTo)
  if Travel.button then return Travel.button end
  local btn = CreateFrame("Button", "EasySetCollectionActionButton", UIParent,
    "SecureActionButtonTemplate,BackdropTemplate")
  Travel.button = btn
  btn:SetSize(30, 30)
  btn:SetFrameStrata("HIGH")
  btn:SetPoint("LEFT", anchorTo, "LEFT", 6, 0)   -- anchored to a Frame (allowed)
  btn:RegisterForClicks("AnyUp", "AnyDown")

  btn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
  })
  btn:SetBackdropColor(0, 0, 0, 0.5)
  btn:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)

  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetPoint("TOPLEFT", 2, -2)
  btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

  btn:SetScript("OnEnter", function(self)
    if not self.actionId then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.actionKind == "spell" then
      GameTooltip:SetSpellByID(self.actionId)
    else
      GameTooltip:SetItemByID(self.actionId)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", GameTooltip_Hide)

  btn:Hide()
  return btn
end

--- Apply the secure-cast attributes to the button for the given action.
local function applyAttributes(kind, id)
  local btn = Travel.button
  if not btn then return end
  if kind == "spell" then
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", spellName(id) or id)
  else -- item / toy
    btn:SetAttribute("type", "item")
    btn:SetAttribute("item", "item:" .. id)
  end
  btn.actionKind, btn.actionId = kind, id
end

--- Show a clickable action button for the current travel step. Defers attribute
--- and visibility changes until out of combat when in a combat lockdown.
---@param kind string  "item", "toy", or "spell"
---@param id number  spell ID (for "spell") or item ID (for "item"/"toy")
---@param labelOverride string?  replaces the default "Use <name>" panel label
function Travel.ShowAction(kind, id, labelOverride)
  Travel.active = true
  if labelOverride then
    Travel.label = labelOverride
  else
    local nm = (kind == "spell") and spellName(id) or itemName(id)
    Travel.label = string.format(L["Use %s"], nm or "?")
  end
  if Travel.button then
    local ic = (kind == "spell") and spellIcon(id) or itemIcon(id)
    Travel.button.icon:SetTexture(ic or "Interface\\Icons\\INV_Misc_QuestionMark")
  end
  if InCombatLockdown() then         -- attributes / visibility can't change in combat
    pending = { kind = kind, id = id }
    pendingShow = true
    return
  end
  pending, pendingShow = nil, nil
  applyAttributes(kind, id)
  if Travel.button then Travel.button:Show() end
end

--- Hide the action button, deferring the change until out of combat if needed.
function Travel.Hide()
  Travel.active = false
  if not Travel.button then return end
  if InCombatLockdown() then
    pending, pendingShow = nil, false
  else
    Travel.button:Hide()
    pendingShow = nil
  end
end

-- Apply deferred changes + refresh once we leave combat.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
  if pending then applyAttributes(pending.kind, pending.id); pending = nil end
  if pendingShow ~= nil and Travel.button then
    Travel.button:SetShown(pendingShow)
    pendingShow = nil
  end
  if ns.UI and ns.UI.RefreshDetail then ns.UI.RefreshDetail() end
end)
