-- Tracker.lua — the compact "follow these sets" window: a small movable frame,
-- independent from the main window, showing each tracked set as a tree:
-- set > location (clickable: waypoint there) > boss/quest/vendor > pieces.
-- Several sets can be tracked at once (right-click the Track button to add).
-- Right-click the window for its options; state persists per character and the
-- window refreshes itself on every collection change.

local ADDON, ns = ...
ns.Tracker = ns.Tracker or {}
local Tracker = ns.Tracker
local L = ns.L
local W = ns.Widgets

local TW, PAD = 260, 10
local ROW_H = 22

local pendingNameRefresh
local anchorTooltip   -- forward declaration (Ensure's handlers use it)

local function trackedSets()
  return (ns.charDB and ns.charDB.trackedSets) or {}
end

local function isTracked(setID)
  for _, id in ipairs(trackedSets()) do
    if id == setID then return true end
  end
  return false
end

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
    anchorTooltip(self)
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

  Tracker.rows, Tracker.locRows, Tracker.srcRows, Tracker.setRows = {}, {}, {}, {}
  f:Hide()
  return f
end

-- ---------------------------------------------------------------------------
-- row pools
-- ---------------------------------------------------------------------------
local function ensureRow(i)
  local row = Tracker.rows[i]
  if row then return row end

  row = CreateFrame("Button", nil, Tracker.frame)
  row:SetSize(TW - PAD * 2 - 20, ROW_H)
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
    anchorTooltip(self)
    if p.itemID and GameTooltip.SetItemByID then GameTooltip:SetItemByID(p.itemID) end
    if self.srcFull and self.srcFull ~= "" then
      GameTooltip:AddLine(self.srcFull, 0.96, 0.72, 0.32, true)
    end
    GameTooltip:AddLine(L["Click to set a waypoint to this piece."], 0.35, 0.7, 1.0)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnClick", function(self)
    if self.piece then Tracker.GuidePiece(self.trackSetID, self.piece) end
  end)

  Tracker.rows[i] = row
  return row
end

--- Anchor GameTooltip beside the tracker window (never on top of it),
--- flipping to the left edge when the screen runs out on the right.
anchorTooltip = function(owner)
  local f = Tracker.frame
  ns.Widgets.OwnTooltip(owner, "ANCHOR_NONE")
  if f and (f:GetRight() or 0) + 260 < UIParent:GetWidth() then
    GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, 0)
  elseif f then
    GameTooltip:SetPoint("TOPRIGHT", f, "TOPLEFT", -6, 0)
  end
end

--- Collapse/expand a section (persisted per character).
function Tracker.ToggleCollapse(key)
  ns.charDB.trackerCollapsed = ns.charDB.trackerCollapsed or {}
  ns.charDB.trackerCollapsed[key] = (not ns.charDB.trackerCollapsed[key]) or nil
  Tracker.Refresh()
end

-- shared behaviour of the three header levels: left-click = collapse/expand,
-- right-click = guide there, tooltip explains both
local function wireHeader(row)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" then
      if self.piece then Tracker.GuidePiece(self.trackSetID, self.piece) end
    elseif self.collapseKey then
      Tracker.ToggleCollapse(self.collapseKey)
    end
  end)
  row:SetScript("OnEnter", function(self)
    anchorTooltip(self)
    GameTooltip:AddLine(self.text:GetText() or "")
    GameTooltip:AddLine(L["Click: collapse or expand"], 0.35, 0.7, 1.0)
    GameTooltip:AddLine(L["Right-click: set a waypoint"], 0.35, 0.7, 1.0)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
end

-- per-set header row (name + progress + its own untrack button)
local function ensureSetRow(i)
  local row = Tracker.setRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, Tracker.frame)
  row:SetSize(TW - PAD * 2, 20)
  row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.text:SetPoint("LEFT", 0, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -52, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)
  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.count:SetPoint("RIGHT", -20, 0)
  row.remove = W.MakeButton(row, "nav")
  row.remove:SetSize(14, 14)
  row.remove:SetPoint("RIGHT", 0, 0)
  row.remove.label:SetText("×")
  row.remove:SetScript("OnClick", function(self)
    local parent = self:GetParent()
    if parent.trackSetID then Tracker.Remove(parent.trackSetID) end
  end)
  wireHeader(row)
  Tracker.setRows[i] = row
  return row
end

-- location header rows + source rows (both collapsible, right-click to guide)
local function ensureLocRow(i)
  local row = Tracker.locRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, Tracker.frame)
  row:SetSize(TW - PAD * 2 - 8, 18)
  row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.text:SetPoint("LEFT", 0, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -34, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)
  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.count:SetPoint("RIGHT", -2, 0)
  wireHeader(row)
  Tracker.locRows[i] = row
  return row
end

local function ensureSrcRow(i)
  local row = Tracker.srcRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, Tracker.frame)
  row:SetSize(TW - PAD * 2 - 18, 15)
  row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.text:SetAllPoints()
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)
  wireHeader(row)
  Tracker.srcRows[i] = row
  return row
end

-- ---------------------------------------------------------------------------
-- tracking state
-- ---------------------------------------------------------------------------
function Tracker.Track(setID)          -- replace: follow only this set
  ns.charDB.trackedSets = { setID }
  Tracker.lastGuidedJid = nil
  Tracker.Refresh()
  if ns.UI and ns.UI.RefreshDetail then ns.UI.RefreshDetail() end
end

function Tracker.Add(setID)            -- append to the current tracking
  if not isTracked(setID) then
    ns.charDB.trackedSets = trackedSets()
    table.insert(ns.charDB.trackedSets, setID)
  end
  Tracker.Refresh()
  if ns.UI and ns.UI.RefreshDetail then ns.UI.RefreshDetail() end
end

function Tracker.Remove(setID)
  local list = trackedSets()
  for i = #list, 1, -1 do
    if list[i] == setID then table.remove(list, i) end
  end
  if #list == 0 then
    Tracker.Untrack()
  else
    Tracker.Refresh()
    if ns.UI and ns.UI.RefreshDetail then ns.UI.RefreshDetail() end
  end
end

function Tracker.Toggle(setID)
  if isTracked(setID) then Tracker.Remove(setID) else Tracker.Track(setID) end
end

function Tracker.IsTracked(setID)
  return isTracked(setID)
end

function Tracker.Untrack()             -- stop everything
  ns.charDB.trackedSets = {}
  Tracker.lastGuidedJid = nil
  if Tracker.frame then Tracker.frame:Hide() end
  if ns.Nav and ns.Nav.StopFollowing then ns.Nav.StopFollowing() end
  if ns.Travel then ns.Travel.Hide() end
  if ns.Waypoint then ns.Waypoint.Clear() end
  if ns.UI and ns.UI.RefreshDetail then ns.UI.RefreshDetail() end
end

--- Waypoint to one specific piece's instance (or its set's curated target).
function Tracker.GuidePiece(setID, piece)
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
  ns.charDB.lastGuidedBaseSetID = info and (info.baseSetID or info.setID)
    or (setID and setID < 0 and setID) or nil   -- synthetic: baseSetID == setID
  if not (ns.Nav and ns.Nav.GuideTo and ns.Nav.GuideTo(target)) then
    if ns.Waypoint then ns.Waypoint.GuideToTarget(target, true) end
  end
  Tracker.lastGuidedJid = target.jid or -1
end

-- ---------------------------------------------------------------------------
-- refresh
-- ---------------------------------------------------------------------------
function Tracker.Refresh()
  local list = trackedSets()
  if #list == 0 then
    if Tracker.frame then Tracker.frame:Hide() end
    return
  end

  local f = Tracker.Ensure()
  local opts = ns.db.tracker
  local multi = #list > 1

  local y = -34
  local shown, li, si, hi = 0, 0, 0, 0
  local firstMissing        -- { setID = ..., piece = ... }
  local allDone = true
  local titleInfo

  for _, setID in ipairs(list) do
    local info = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(setID)
    if not info and setID < 0 then
      -- synthetic set: shim the journal record from the catalog group
      local g = ns.Sets.GroupFor(setID)
      if g then info = { setID = setID, baseSetID = setID, name = g.name } end
    end
    if info then
      titleInfo = titleInfo or info
      local n, t = ns.Pieces.Progress(setID)
      local done = t > 0 and n >= t
      if not done then allDone = false end

      local pieces = ns.Pieces.For(setID)
      local collapsed = ns.charDB.trackerCollapsed or {}
      local setKey = "s" .. setID

      if multi then
        hi = hi + 1
        local sr = ensureSetRow(hi)
        sr.trackSetID = setID
        sr.collapseKey = setKey
        sr.piece = pieces[1]
        sr.text:SetText(W.AMBER .. (collapsed[setKey] and "+ " or "- ")
          .. (info.name or "?") .. "|r")
        sr.count:SetText((done and W.GREEN or W.AMBER) .. n .. "/" .. t .. "|r")
        sr:ClearAllPoints()
        sr:SetPoint("TOPLEFT", PAD, y)
        sr:Show()
        y = y - 21
      end

      -- hierarchy: location -> source (boss / quest / vendor) -> pieces.
      -- Counts cover ALL pieces; hide-collected only prunes item rows.
      local groups, byLoc = {}, {}
      for _, piece in ipairs(pieces) do
        if not piece.collected and not firstMissing then
          firstMissing = { setID = setID, piece = piece }
        end
        local loc, src = ns.Sources.PieceSourceParts(setID, piece)
        loc = loc or "?"
        local g = byLoc[loc]
        if not g then
          g = { title = loc, sources = {}, bySrc = {}, have = 0, total = 0, first = piece }
          byLoc[loc] = g
          groups[#groups + 1] = g
        end
        g.total = g.total + 1
        if piece.collected then g.have = g.have + 1 end
        if not (opts.hideCollected and piece.collected) then
          local skey = src or ""
          local s = g.bySrc[skey]
          if not s then
            s = { title = src, pieces = {} }
            g.bySrc[skey] = s
            g.sources[#g.sources + 1] = s
          end
          s.pieces[#s.pieces + 1] = piece
        end
      end

      local indent = multi and 8 or 0
      for _, g in ipairs(groups) do
        if #g.sources > 0 and not (multi and collapsed[setKey]) then
          local locKey = setID .. "|" .. g.title
          li = li + 1
          local lr = ensureLocRow(li)
          lr.piece = g.first
          lr.trackSetID = setID
          lr.collapseKey = locKey
          lr.text:SetText(W.AMBER .. (collapsed[locKey] and "+ " or "- ") .. g.title .. "|r")
          lr.count:SetText((g.have >= g.total and W.GREEN or W.GREY) .. g.have .. "/" .. g.total .. "|r")
          lr:ClearAllPoints()
          lr:SetPoint("TOPLEFT", PAD + indent, y)
          lr:Show()
          y = y - 18

          for _, s in ipairs(g.sources) do
            local srcCollapsed = false
            if s.title and s.title ~= "" and not collapsed[locKey] then
              local srcKey = locKey .. "|" .. s.title
              srcCollapsed = collapsed[srcKey] or false
              si = si + 1
              local sr2 = ensureSrcRow(si)
              sr2.trackSetID = setID
              sr2.collapseKey = srcKey
              sr2.piece = s.pieces[1]
              sr2.text:SetText(W.GREY .. (srcCollapsed and "+ " or "- ") .. s.title .. "|r")
              sr2:ClearAllPoints()
              sr2:SetPoint("TOPLEFT", PAD + indent + 10, y)
              sr2:Show()
              y = y - 15
            end
            for _, piece in ipairs((collapsed[locKey] or srcCollapsed) and {} or s.pieces) do
              shown = shown + 1
              local row = ensureRow(shown)
              row.piece = piece
              row.trackSetID = setID
              row.srcFull = ns.Sources.PieceSourceText(setID, piece) or ""
              row:SetWidth(TW - PAD * 2 - 20 - indent)

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
              row.name:SetText((piece.collected and W.GREEN or W.WHITE) .. name .. "|r")

              row:ClearAllPoints()
              row:SetPoint("TOPLEFT", PAD + 20 + indent, y)
              row:Show()
              y = y - ROW_H
            end
          end
          y = y - 4   -- breathing room between locations
        end
      end
      if multi then y = y - 4 end
    end
  end
  for i = shown + 1, #Tracker.rows do Tracker.rows[i]:Hide() end
  for i = li + 1, #Tracker.locRows do Tracker.locRows[i]:Hide() end
  for i = si + 1, #Tracker.srcRows do Tracker.srcRows[i]:Hide() end
  for i = hi + 1, #Tracker.setRows do Tracker.setRows[i]:Hide() end

  -- window title: the set's name, or a generic label when tracking several
  if multi then
    f.title:SetText(W.WHITE .. L["Tracked sets"] .. "|r")
    f.count:SetText(W.GREY .. #list .. "|r")
  elseif titleInfo then
    f.title:SetText(W.AMBER .. (titleInfo.name or "?") .. "|r")
    local n, t = ns.Pieces.Progress(list[1])
    f.count:SetText(((t > 0 and n >= t) and W.GREEN or W.AMBER) .. n .. "/" .. t .. "|r")
  else
    f.title:SetText("")
    f.count:SetText("")
  end

  -- truly empty only when NOTHING rendered — collapsed sections still show
  -- their headers, which used to get overlapped by this text
  if shown == 0 and li == 0 and hi == 0 then
    f.empty:SetText(allDone and (W.GREEN .. L["Set complete!"] .. "|r")
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
      local jid = ns.Sources.PieceInstance(firstMissing.setID, firstMissing.piece)
      if jid and jid ~= Tracker.lastGuidedJid then
        Tracker.GuidePiece(firstMissing.setID, firstMissing.piece)
      end
    elseif allDone and Tracker.lastGuidedJid then
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
