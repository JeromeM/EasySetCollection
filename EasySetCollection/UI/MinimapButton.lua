-- MinimapButton.lua — self-contained minimap button (no external libs).
-- Left-click: toggle window. Right-click: open the settings panel.

local ADDON, ns = ...
ns.Minimap = ns.Minimap or {}
local Minimap = ns.Minimap
local L = ns.L

--- Place the button on the minimap EDGE at its saved angle: the radius comes
--- from the minimap's real size (resized minimaps kept the old fixed radius
--- inside the ring), and the GetMinimapShape() convention is honoured so
--- square minimaps put the button on their edge too.
---@param btn table  the minimap Button frame to reposition
local function updatePosition(btn)
  local mm = _G.Minimap
  local angle = math.rad((ns.db.minimap and ns.db.minimap.angle) or 200)
  local cos, sin = math.cos(angle), math.sin(angle)
  local rx = (mm:GetWidth() or 140) / 2 + 5
  local ry = (mm:GetHeight() or 140) / 2 + 5
  local shape = (type(_G.GetMinimapShape) == "function") and _G.GetMinimapShape() or "ROUND"
  if type(shape) == "string" and shape:find("SQUARE") then
    local k = 1 / math.max(math.abs(cos), math.abs(sin), 0.001)
    cos, sin = cos * k, sin * k
  end
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", mm, "CENTER", cos * rx, sin * ry)
end

--- Recompute the position (minimap resized — Edit Mode, minimap addons).
function Minimap.UpdatePosition()
  if Minimap.button then updatePosition(Minimap.button) end
end

--- Create the minimap button once and wire up its icon, click, drag and tooltip
--- handlers; no-op if the button already exists. Starts hidden if so configured.
function Minimap.Init()
  if Minimap.button then return end
  ns.db.minimap = ns.db.minimap or {}

  local btn = CreateFrame("Button", "EasySetCollectionMinimapButton", _G.Minimap)
  Minimap.button = btn
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")

  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  btn:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      ns.UI.OpenSettings()
    else
      ns.UI.Toggle()
    end
  end)

  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = _G.Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = _G.Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
      updatePosition(self)
    end)
  end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  btn:SetScript("OnEnter", function(self)
    ns.Widgets.OwnTooltip(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(L["EasySetCollection"])
    GameTooltip:AddLine(L["Left-click: open/close"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: open settings"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move around the minimap"], 1, 1, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", GameTooltip_Hide)

  updatePosition(btn)
  if ns.db.minimap.hide then btn:Hide() end
end
