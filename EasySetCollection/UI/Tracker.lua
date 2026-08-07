-- Tracker.lua — the compact "follow this set" window: a small movable frame,
-- independent from the main window, listing the tracked set's pieces with
-- their collected state. Click a piece to set a waypoint to it; right-click
-- the window for its options (hide collected pieces, auto-guide to the next
-- missing piece, lock). The tracked set persists per character and the window
-- refreshes itself on every collection change.

local ADDON, ns = ...
ns.Tracker = ns.Tracker or {}
local Tracker = ns.Tracker
local L = ns.L
local W = ns.Widgets

local TW, PAD = 260, 10
local ROW_H = 22

local pendingNameRefresh

-- ---------------------------------------------------------------------------
-- frame
-- ---------------------------------------------------------------------------
local function savePosition(f)
  local p, _, rp, x, y = f:GetPoint()
  ns.db.tracker.pos = { p = p, rp = rp, x = x, y = y }
end

function Tracker.Ensure()
  if Tracker.frame then return Tracker.frame end

  local f = CreateFrame("Frame", "EasySetCollectionTracker", UIParent, "BackdropTemplate")
  Tracker.frame = f
  f:SetSize(TW, 120)
  f:SetFrameStrata("MEDIUM")
  f:SetBackdrop(W.BD1)
  f:SetBackdropColor(W.C_BG[1], W.C_BG[2], W.C_BG[3], 0.95)
  f:SetBackdropBorderColor(W.C_BORDER[1], W.C_BORDER[2], W.C_BORDER[3], 1)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", function(self)
    if not ns.db.tracker.locked then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition(self)
  end)
  f:SetScript("OnMouseUp", function(self, btn)
    if btn == "RightButton" then Tracker.OpenMenu(self) end
  end)
  f:SetScript("OnEnter", function(self)
    ns.Widgets.OwnTooltip(self, "ANCHOR_TOPRIGHT")
    GameTooltip:AddLine(L["Tracked set"])
    GameTooltip:AddLine(L["Right-click: options"], 0.35, 0.7, 1.0)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", GameTooltip_Hide)

  local pos = ns.db.tracker.pos
  if pos and pos.p then
    f:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y)
  else
    f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 40)
  end

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", PAD, -9)
  f.title:SetPoint("RIGHT", f, "RIGHT", -70, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)

  f.count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.count:SetPoint("TOPRIGHT", -28, -10)

  f.close = W.MakeButton(f, "nav")
  f.close:SetSize(16, 16)
  f.close:SetPoint("TOPRIGHT", -6, -6)
  f.close.label:SetText("×")
  f.close:SetScript("OnClick", function() Tracker.Untrack() end)

  f.sep = f:CreateTexture(nil, "ARTWORK")
  f.sep:SetColorTexture(W.C_SEP[1], W.C_SEP[2], W.C_SEP[3], 1)
  f.sep:SetHeight(1)
  f.sep:SetPoint("TOPLEFT", PAD, -28)
  f.sep:SetPoint("TOPRIGHT", -PAD, -28)

  f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.empty:SetPoint("TOPLEFT", PAD, -36)
  f.empty:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
  f.empty:SetJustifyH("LEFT")
  f.empty:Hide()

  Tracker.rows = {}
  f:Hide()
  return f
end

local function ensureRow(i)
  local row = Tracker.rows[i]
  if row then return row end

  row = CreateFrame("Button", nil, Tracker.frame)
  row:SetSize(TW - PAD * 2, ROW_H)
  row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)

  row.iconFrame = W.MakePanel(row)
  row.iconFrame:SetSize(18, 18)
  row.iconFrame:SetPoint("LEFT", 0, 0)
  row.iconFrame:SetBackdropColor(0, 0, 0, 0.5)
  row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("TOPLEFT", 1, -1)
  row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.name:SetPoint("LEFT", row.iconFrame, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row:SetScript("OnEnter", function(self)
    local p = self.piece
    if not p then return end
    ns.Widgets.OwnTooltip(self, "ANCHOR_LEFT")
    if p.itemID and GameTooltip.SetItemByID then GameTooltip:SetItemByID(p.itemID) end
    if self.srcFull and self.srcFull ~= "" then
      GameTooltip:AddLine(self.srcFull, 0.96, 0.72, 0.32, true)
    end
    GameTooltip:AddLine(L["Click to set a waypoint to this piece."], 0.35, 0.7, 1.0)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnClick", function(self)
    if self.piece then Tracker.GuidePiece(self.piece) end
  end)

  Tracker.rows[i] = row
  return row
end

-- ---------------------------------------------------------------------------
-- tracking state
-- ---------------------------------------------------------------------------
function Tracker.Toggle(setID)
  if ns.charDB.trackedSetID == setID then
    Tracker.Untrack()
  else
    Tracker.Track(setID)
  end
end

function Tracker.Track(setID)
  ns.charDB.trackedSetID = setID
  Tracker.lastGuidedJid = nil
  Tracker.Refresh()
  if ns.UI and ns.UI.RefreshDetail then ns.UI.RefreshDetail() end
end

function Tracker.Untrack()
  ns.charDB.trackedSetID = nil
  Tracker.lastGuidedJid = nil
  if Tracker.frame then Tracker.frame:Hide() end
  if ns.Nav and ns.Nav.StopFollowing then ns.Nav.StopFollowing() end
  if ns.Travel then ns.Travel.Hide() end
  if ns.Waypoint then ns.Waypoint.Clear() end
  if ns.UI and ns.UI.RefreshDetail then ns.UI.RefreshDetail() end
end

--- Waypoint to one specific piece's instance (or the set's curated target).
function Tracker.GuidePiece(piece)
  local setID = ns.charDB.trackedSetID
  if not (setID and piece) then return end
  local target
  local jid = ns.Sources.PieceInstance(setID, piece)
  if jid then
    target = { jid = jid, title = ns.Sources.InstanceName(jid) }
  else
    target = ns.Sources.NavFor(setID)
  end
  if not target then return end
  local info = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(setID)
  ns.charDB.lastGuidedBaseSetID = info and (info.baseSetID or info.setID) or nil
  if not (ns.Nav and ns.Nav.GuideTo and ns.Nav.GuideTo(target)) then
    if ns.Waypoint then ns.Waypoint.GuideToTarget(target, true) end
  end
  Tracker.lastGuidedJid = target.jid or -1
end

-- ---------------------------------------------------------------------------
-- refresh
-- ---------------------------------------------------------------------------
function Tracker.Refresh()
  local setID = ns.charDB and ns.charDB.trackedSetID
  if not setID then
    if Tracker.frame then Tracker.frame:Hide() end
    return
  end
  local info = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(setID)
  if not info then return end   -- collection not ready: the next event retries

  local f = Tracker.Ensure()
  local opts = ns.db.tracker

  f.title:SetText(W.AMBER .. (info.name or "?") .. "|r")
  local n, t = ns.Pieces.Progress(setID)
  local done = t > 0 and n >= t
  f.count:SetText((done and W.GREEN or W.AMBER) .. n .. "/" .. t .. "|r")

  local pieces = ns.Pieces.For(setID)
  local y = -34
  local shown = 0
  local firstMissing

  for _, piece in ipairs(pieces) do
    if not piece.collected and not firstMissing then firstMissing = piece end
    if not (opts.hideCollected and piece.collected) then
      shown = shown + 1
      local row = ensureRow(shown)
      row.piece = piece
      row.srcFull = ns.Sources.PieceSourceText(setID, piece) or ""

      local icon = piece.itemID and C_Item.GetItemIconByID and C_Item.GetItemIconByID(piece.itemID)
      row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.icon:SetDesaturated(not piece.collected)
      row.iconFrame:SetBackdropBorderColor(
        piece.collected and W.C_GREEN[1] or 0.45,
        piece.collected and W.C_GREEN[2] or 0.45,
        piece.collected and W.C_GREEN[3] or 0.5, 0.9)

      local name = piece.name
      if not name or name == "" then
        name = "…"
        if piece.itemID and Item then
          Item:CreateFromItemID(piece.itemID):ContinueOnItemLoad(function()
            if pendingNameRefresh then return end
            pendingNameRefresh = C_Timer.NewTimer(0.1, function()
              pendingNameRefresh = nil
              Tracker.Refresh()
            end)
          end)
        end
      end
      if piece.collected then
        row.name:SetText(W.GREEN .. name .. "|r")
      else
        row.name:SetText(W.WHITE .. name .. "|r")
      end

      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", PAD, y)
      row:Show()
      y = y - ROW_H
    end
  end
  for i = shown + 1, #Tracker.rows do Tracker.rows[i]:Hide() end

  if shown == 0 then
    f.empty:SetText(done and (W.GREEN .. L["Set complete!"] .. "|r")
      or (W.GREY .. L["Loading the collection..."] .. "|r"))
    f.empty:Show()
    y = y - 20
  else
    f.empty:Hide()
  end

  f:SetHeight(-y + PAD)
  f:Show()

  -- auto-guide: point at the next missing piece whenever the target changes
  if opts.autoGuide then
    if firstMissing then
      local jid = ns.Sources.PieceInstance(setID, firstMissing)
      if jid and jid ~= Tracker.lastGuidedJid then
        Tracker.GuidePiece(firstMissing)
      end
    elseif done and Tracker.lastGuidedJid then
      Tracker.lastGuidedJid = nil
      if ns.Waypoint then ns.Waypoint.Clear() end
    end
  end
end

-- ---------------------------------------------------------------------------
-- options menu (right-click)
-- ---------------------------------------------------------------------------
function Tracker.OpenMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(L["Tracked set"])
    root:CreateCheckbox(L["Hide collected pieces"],
      function() return ns.db.tracker.hideCollected == true end,
      function()
        ns.db.tracker.hideCollected = not ns.db.tracker.hideCollected
        Tracker.Refresh()
        return MenuResponse and MenuResponse.Refresh
      end)
    root:CreateCheckbox(L["Auto-guide to the next missing piece"],
      function() return ns.db.tracker.autoGuide ~= false end,
      function()
        ns.db.tracker.autoGuide = not ns.db.tracker.autoGuide
        Tracker.lastGuidedJid = nil
        Tracker.Refresh()
        return MenuResponse and MenuResponse.Refresh
      end)
    root:CreateCheckbox(L["Lock the window position"],
      function() return ns.db.tracker.locked == true end,
      function()
        ns.db.tracker.locked = not ns.db.tracker.locked
        return MenuResponse and MenuResponse.Refresh
      end)
    root:CreateDivider()
    root:CreateButton(L["Stop tracking"], function() Tracker.Untrack() end)
  end)
end
