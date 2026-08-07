-- Detail.lua — the right pane: everything about the selected set. Name, label,
-- progress bar, variant selector (Normal/Heroic/Mythic recolors as segmented
-- buttons), one row per piece (slot, item, collected mark, source line) and the
-- action row: Guide (left-click = best instance, right-click = choose), Try on
-- (full-set dressing room) and Journal (Blizzard sets tab deep-link).

local ADDON, ns = ...
ns.Detail = ns.Detail or {}
local Detail = ns.Detail
local L = ns.L
local W = ns.Widgets

local PIECE_H = 30

Detail.group = nil          -- selected catalog group
Detail.setID = nil          -- selected variant setID
Detail.hiddenPieces = {}    -- [sourceID] = true: excluded from the preview model
Detail.hiddenForSet = nil   -- setID the exclusions belong to (wiped on change)

-- ---------------------------------------------------------------------------
-- build
-- ---------------------------------------------------------------------------
--- Build the detail pane inside the main window (called by UI.Init).
function Detail.Build(f)
  local UI = ns.UI
  local X, DW = UI.DETAIL_X, UI.DETAIL_W

  Detail.placeholder = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  Detail.placeholder:SetPoint("CENTER", f, "TOPLEFT", X + DW / 2, -(UI.H / 2))
  Detail.placeholder:SetWidth(DW - 20)
  Detail.placeholder:SetText(W.GREY .. L["Select a set on the left to see its pieces."] .. "|r")

  Detail.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  Detail.name:SetPoint("TOPLEFT", X, -56)
  Detail.name:SetWidth(DW)
  Detail.name:SetJustifyH("LEFT")
  Detail.name:SetWordWrap(true)
  Detail.name:SetMaxLines(2)

  Detail.sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  Detail.sub:SetWidth(DW)
  Detail.sub:SetJustifyH("LEFT")
  Detail.sub:SetWordWrap(false)

  Detail.bar = W.MakeProgressBar(f, DW, 16)

  Detail.variantBtns = {}
  Detail.pieceRows = {}
  Detail.overflow = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  Detail.overflow:SetWidth(DW)
  Detail.overflow:SetJustifyH("LEFT")

  -- docked travel-action panel (secure button lives in it — see Navigation/Travel.lua)
  Detail.actionPanel = W.MakePanel(f)
  Detail.actionPanel:SetBackdropColor(0.17, 0.13, 0.05, 0.9)
  Detail.actionPanel:SetBackdropBorderColor(W.C_GOLD_BRD[1], W.C_GOLD_BRD[2], W.C_GOLD_BRD[3], 1)
  Detail.actionPanel:SetSize(DW, 42)
  Detail.actionPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", X, UI.PAD + 34)
  Detail.actionLabel = Detail.actionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  Detail.actionLabel:SetPoint("LEFT", Detail.actionPanel, "LEFT", 46, 0)
  Detail.actionLabel:SetPoint("RIGHT", Detail.actionPanel, "RIGHT", -8, 0)
  Detail.actionLabel:SetJustifyH("LEFT")
  Detail.actionLabel:SetWordWrap(false)
  Detail.actionLabel:SetTextColor(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3])
  if ns.Travel and ns.Travel.Ensure then
    ns.Travel.Ensure(Detail.actionPanel)   -- builds + docks the secure button
  end
  Detail.actionPanel:Hide()

  -- bottom action row
  Detail.guideBtn = W.MakeButton(f, "primary")
  Detail.guideBtn:SetSize(122, 26)
  Detail.guideBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", X, UI.PAD)
  W.AddDropdownArrow(Detail.guideBtn)
  Detail.guideBtn.arrow:SetVertexColor(1, 0.82, 0.4)
  Detail.guideBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  Detail.guideBtn:SetMotionScriptsWhileDisabled(true)
  Detail.guideBtn:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      Detail.OpenGuideMenu()
    else
      Detail.GuideSelected()
    end
  end)
  Detail.guideBtn:SetScript("OnEnter", function(self)
    W.Paint(self, true)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if self:IsEnabled() then
      GameTooltip:AddLine(L["Set a waypoint to the place holding the most missing pieces."], 1, 1, 1, true)
      GameTooltip:AddLine(L["Right-click to choose the destination."], 0.35, 0.7, 1.0)
    else
      GameTooltip:AddLine(L["No known destination for this set (quest/vendor/PvP sets need manual data)."], 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  Detail.guideBtn:SetScript("OnLeave", function(self)
    W.Paint(self, false)
    GameTooltip:Hide()
  end)

  Detail.tryBtn = W.MakeButton(f, "nav")
  Detail.tryBtn:SetSize(88, 26)
  Detail.tryBtn:SetPoint("LEFT", Detail.guideBtn, "RIGHT", 6, 0)
  Detail.tryBtn.label:SetText(L["Try on"])
  Detail.tryBtn:SetScript("OnClick", function() Detail.TryOn() end)

  Detail.journalBtn = W.MakeButton(f, "nav")
  Detail.journalBtn:SetSize(88, 26)
  Detail.journalBtn:SetPoint("LEFT", Detail.tryBtn, "RIGHT", 6, 0)
  Detail.journalBtn.label:SetText(L["Journal"])
  Detail.journalBtn:SetScript("OnClick", function() Detail.OpenJournal() end)

  Detail.BuildPreview(f)
  Detail.HideWidgets()
end

-- ---------------------------------------------------------------------------
-- preview pane: the player's own character wearing the set (DressUpModel),
-- with a full-set / owned-pieces-only toggle
-- ---------------------------------------------------------------------------
function Detail.BuildPreview(f)
  local UI = ns.UI
  local X, MW = UI.MODEL_X, UI.MODEL_W

  local bg = W.MakePanel(f)
  Detail.modelBG = bg
  bg:SetPoint("TOPLEFT", X, -56)
  bg:SetSize(MW, UI.H - 56 - UI.PAD - 34)   -- the toggle row sits below
  bg:SetBackdropColor(0.05, 0.055, 0.07, 1)
  bg:SetBackdropBorderColor(W.C_PANEL_BRD[1], W.C_PANEL_BRD[2], W.C_PANEL_BRD[3], 1)

  local m = CreateFrame("DressUpModel", nil, f)
  Detail.model = m
  m:SetPoint("TOPLEFT", bg, "TOPLEFT", 2, -2)
  m:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -2, 2)
  m:SetFrameLevel(bg:GetFrameLevel() + 1)
  m:EnableMouse(true)
  m:EnableMouseWheel(true)

  -- drag to rotate, wheel to zoom
  m:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" then
      self._dragging = true
      self._dragX = GetCursorPosition()
    end
  end)
  m:SetScript("OnMouseUp", function(self) self._dragging = false end)
  m:SetScript("OnUpdate", function(self)
    if not self._dragging then return end
    local x = GetCursorPosition()
    self._rot = (self._rot or 0) + (x - (self._dragX or x)) * 0.012
    self._dragX = x
    self:SetRotation(self._rot)
  end)
  m:SetScript("OnMouseWheel", function(self, delta)
    self._zoom = math.max(0.4, math.min(2.5, (self._zoom or 1) - delta * 0.15))
    if self.SetCamDistanceScale then self:SetCamDistanceScale(self._zoom) end
  end)
  m:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:AddLine(L["Drag to rotate, mouse wheel to zoom."], 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  m:SetScript("OnLeave", GameTooltip_Hide)
  -- the model loses its contents when hidden: force a re-dress on next refresh
  m:SetScript("OnShow", function() Detail.previewKey = nil end)

  -- toggle row: full set / owned pieces only
  Detail.previewBtns = {}
  local MODES = { { "full", L["Full set"] }, { "owned", L["Owned pieces"] } }
  local bw = math.floor((MW - 4) / 2)
  for i, mode in ipairs(MODES) do
    local b = W.MakeButton(f, "nav")
    b:SetSize(bw, 26)
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", X + (i - 1) * (bw + 4), UI.PAD)
    b.label:SetText(mode[2])
    b._mode = mode[1]
    b:SetScript("OnClick", function()
      ns.db.preview = mode[1]
      Detail.PaintPreviewButtons()
      Detail.UpdatePreview(true)
    end)
    Detail.previewBtns[i] = b
  end
end

--- Repaint the toggle segments from the saved mode.
function Detail.PaintPreviewButtons()
  local cur = ns.db.preview or "full"
  for _, b in ipairs(Detail.previewBtns or {}) do
    b._kind = (b._mode == cur) and "primary" or "nav"
    W.Paint(b, false)
  end
end

--- Re-dress the model for the current selection and mode. Keyed on
--- setID + mode + collection stamp so refreshes don't re-pose the model
--- needlessly (SetUnit resets the camera).
function Detail.UpdatePreview(force)
  local m = Detail.model
  if not m then return end
  local setID = Detail.setID
  local mode = ns.db.preview or "full"
  local key = tostring(setID) .. ":" .. mode .. ":" .. (ns.Pieces.stamp or 0)
  if not force and Detail.previewKey == key then return end
  Detail.previewKey = key

  m:SetUnit("player")
  m:SetRotation(m._rot or 0)
  if m.SetCamDistanceScale then m:SetCamDistanceScale(m._zoom or 1) end
  pcall(m.Undress, m)
  for _, piece in ipairs(ns.Pieces.For(setID)) do
    if (mode == "full" or piece.collected) and not Detail.hiddenPieces[piece.sourceID] then
      local ok = pcall(m.TryOn, m, piece.sourceID)
      if not ok then
        local link = ns.Pieces.ItemLink(piece.sourceID, piece.itemID)
        if link then pcall(m.TryOn, m, link) end
      end
    end
  end
end

function Detail.HideWidgets()
  Detail.name:Hide()
  Detail.sub:Hide()
  Detail.bar:Hide()
  Detail.overflow:Hide()
  Detail.actionPanel:Hide()
  for _, b in ipairs(Detail.variantBtns) do b:Hide() end
  for _, r in ipairs(Detail.pieceRows) do r:Hide() end
  Detail.guideBtn:Hide()
  Detail.tryBtn:Hide()
  Detail.journalBtn:Hide()
  if Detail.modelBG then Detail.modelBG:Hide() end
  if Detail.model then Detail.model:Hide() end
  for _, b in ipairs(Detail.previewBtns or {}) do b:Hide() end
  Detail.previewKey = nil
  Detail.placeholder:Show()
end

-- ---------------------------------------------------------------------------
-- selection
-- ---------------------------------------------------------------------------
--- The variant of a group to show by default: the one with the best progress
--- (matches the progress displayed on the group's list row).
local function pickVariant(g)
  local best, bestRatio, bestT = nil, -1, 0
  for _, v in ipairs(g.variants) do
    local n, t = ns.Pieces.Progress(v.setID)
    local r = t > 0 and n / t or 0
    if r > bestRatio or (r == bestRatio and t > bestT) then
      best, bestRatio, bestT = v.setID, r, t
    end
  end
  return best or (g.variants[1] and g.variants[1].setID)
end

--- Show a group (from a list click): keep the current variant when it belongs
--- to the same group, otherwise pick the best one.
function Detail.ShowGroup(g)
  Detail.group = g
  local keep = false
  for _, v in ipairs(g.variants) do
    if v.setID == Detail.setID then keep = true break end
  end
  if not keep then Detail.setID = pickVariant(g) end
  ns.charDB.selectedSetID = Detail.setID
  Detail.Refresh()
end

--- Restore the last session's selection (charDB) once the catalog exists.
local function restoreSelection()
  local saved = ns.charDB and ns.charDB.selectedSetID
  if not saved then return end
  local info = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(saved)
  if not info then return end
  local g = ns.Sets.GroupFor(info.baseSetID or info.setID)
  if not g then return end
  Detail.group = g
  Detail.setID = saved
  ns.SetList.selected = g.baseSetID
end

-- ---------------------------------------------------------------------------
-- piece rows
-- ---------------------------------------------------------------------------
local pendingNameRefresh
local paintPieceRow   -- forward declaration: the row click handler repaints

local function ensurePieceRow(i, f)
  local row = Detail.pieceRows[i]
  if row then return row end

  row = CreateFrame("Button", nil, f)
  row:SetSize(ns.UI.DETAIL_W, PIECE_H)

  -- row background: transparent normally, red-tinted when the piece is hidden
  -- from the preview; plus a subtle hover highlight (the row is clickable)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0)
  row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)

  -- item icon; its border/desaturation carries the collected state
  row.iconFrame = W.MakePanel(row)
  row.iconFrame:SetSize(26, 26)
  row.iconFrame:SetPoint("LEFT", 0, 0)
  row.iconFrame:SetBackdropColor(0, 0, 0, 0.5)
  row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("TOPLEFT", 1, -1)
  row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.name:SetPoint("TOPLEFT", 32, -2)
  row.name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row.src = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.src:SetPoint("BOTTOMLEFT", 32, 3)
  row.src:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  row.src:SetJustifyH("LEFT")
  row.src:SetWordWrap(false)

  row:SetScript("OnEnter", function(self)
    local p = self.piece
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if p.itemID and GameTooltip.SetItemByID then
      GameTooltip:SetItemByID(p.itemID)
    elseif p.name then
      GameTooltip:SetText(p.name)
    end
    if p.collected then
      GameTooltip:AddLine(L["Appearance collected"], 0.38, 0.82, 0.43)
    else
      GameTooltip:AddLine(L["Appearance not collected"], 1, 0.4, 0.4)
    end
    if p.collected and not p.sourceCollected then
      GameTooltip:AddLine(L["Appearance collected from another item."], 0.7, 0.7, 0.7, true)
    end
    if Detail.hiddenPieces[p.sourceID] then
      GameTooltip:AddLine(L["Hidden in the preview — click to show it."], 1, 0.55, 0.35)
    else
      GameTooltip:AddLine(L["Click to hide this piece in the preview."], 0.35, 0.7, 1.0)
    end
    GameTooltip:AddLine(L["Shift + click to link in chat"], 0.35, 0.7, 1.0)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnMouseUp", function(self)
    local p = self.piece
    if not p then return end
    if IsShiftKeyDown() then
      -- link the piece in chat; open the chat input pre-filled when it's closed
      local link = ns.Pieces.ItemLink(p.sourceID, p.itemID)
      if link then
        if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) then
          if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
        end
      end
      return
    end
    -- plain click: toggle this piece in the preview model
    Detail.hiddenPieces[p.sourceID] = (not Detail.hiddenPieces[p.sourceID]) or nil
    paintPieceRow(self, p, self.setID)
    Detail.UpdatePreview(true)
    if GameTooltip:GetOwner() == self then self:GetScript("OnEnter")(self) end
  end)

  Detail.pieceRows[i] = row
  return row
end

--- Repaint one piece row from its record.
paintPieceRow = function(row, piece, setID)
  row.piece = piece
  row.setID = setID

  local icon = piece.itemID and C_Item.GetItemIconByID and C_Item.GetItemIconByID(piece.itemID)
  row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  local hidden = Detail.hiddenPieces[piece.sourceID]
  if hidden then
    row.bg:SetColorTexture(0.5, 0.15, 0.10, 0.22)
    row.icon:SetDesaturated(true)
    row.icon:SetVertexColor(0.45, 0.45, 0.45)
    row.iconFrame:SetBackdropBorderColor(0.65, 0.28, 0.2, 0.9)
  elseif piece.collected then
    row.bg:SetColorTexture(1, 1, 1, 0)
    row.icon:SetDesaturated(false)
    row.icon:SetVertexColor(1, 1, 1)
    row.iconFrame:SetBackdropBorderColor(W.C_GREEN[1], W.C_GREEN[2], W.C_GREEN[3], 0.9)
  else
    row.bg:SetColorTexture(1, 1, 1, 0)
    row.icon:SetDesaturated(true)
    row.icon:SetVertexColor(1, 1, 1)
    row.iconFrame:SetBackdropBorderColor(0.45, 0.45, 0.5, 0.9)
  end

  local name = piece.name
  if not name or name == "" then
    name = "…"
    -- resolve asynchronously, then repaint the pane once (coalesced)
    if piece.itemID and Item then
      Item:CreateFromItemID(piece.itemID):ContinueOnItemLoad(function()
        if Detail.setID ~= setID or pendingNameRefresh then return end
        pendingNameRefresh = C_Timer.NewTimer(0.1, function()
          pendingNameRefresh = nil
          Detail.Refresh()
        end)
      end)
    end
  end
  local q = ITEM_QUALITY_COLORS and piece.quality and ITEM_QUALITY_COLORS[piece.quality]
  if q then
    row.name:SetTextColor(q.r, q.g, q.b)
  else
    row.name:SetTextColor(0.9, 0.9, 0.92)
  end
  row.name:SetText(name)

  local slot = ns.Pieces.SlotLabel(piece.itemID)
  local srcText = ns.Sources.PieceSourceText(setID, piece)
  local bits = {}
  if slot ~= "" then bits[#bits + 1] = slot end
  if srcText and srcText ~= "" then bits[#bits + 1] = srcText end
  row.src:SetText(W.GREY .. table.concat(bits, " · ") .. "|r")
  row:SetAlpha(hidden and 0.65 or (piece.collected and 1 or 0.8))
end

-- ---------------------------------------------------------------------------
-- refresh
-- ---------------------------------------------------------------------------
--- Rebuild the pane for the current selection. Skipped in combat: the layout
--- shows/hides the docked secure travel button (Travel.lua re-runs it on
--- PLAYER_REGEN_ENABLED).
function Detail.Refresh()
  local f = ns.UI.frame
  if not f then return end
  if InCombatLockdown() then return end

  if not Detail.group then restoreSelection() end
  local g = Detail.group
  if g then
    -- re-resolve against the current catalog (group tables are replaced on rebuild)
    g = ns.Sets.GroupFor(g.baseSetID)
    Detail.group = g
  end
  if not g then
    Detail.HideWidgets()
    return
  end

  local setID = Detail.setID or pickVariant(g)
  Detail.setID = setID
  -- preview exclusions are per-variant: wipe them when the selection changes
  if Detail.hiddenForSet ~= setID then
    Detail.hiddenForSet = setID
    wipe(Detail.hiddenPieces)
  end
  local info = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(setID)

  Detail.placeholder:Hide()
  local X, DW = ns.UI.DETAIL_X, ns.UI.DETAIL_W
  local y = -56

  -- name
  Detail.name:SetText(W.AMBER .. g.name .. "|r")
  Detail.name:Show()
  y = y - math.max(20, Detail.name:GetStringHeight()) - 4

  -- sub line: label · variant description · class (+ limited-time warning)
  local bits = {}
  if info and info.label and info.label ~= "" then bits[#bits + 1] = info.label end
  if info and info.description and info.description ~= "" then bits[#bits + 1] = info.description end
  if g.className then bits[#bits + 1] = g.className end
  local sub = W.GREY .. table.concat(bits, " · ") .. "|r"
  if g.limitedTimeSet then
    sub = sub .. "  |cffff4040" .. L["Limited availability"] .. "|r"
  end
  Detail.sub:ClearAllPoints()
  Detail.sub:SetPoint("TOPLEFT", X, y)
  Detail.sub:SetText(sub)
  Detail.sub:Show()
  y = y - 18

  -- progress bar
  local n, t = ns.Pieces.Progress(setID)
  local done = t > 0 and n >= t
  Detail.bar:ClearAllPoints()
  Detail.bar:SetPoint("TOPLEFT", X, y)
  Detail.bar:SetProgress(n, t, done and W.C_GREEN or W.C_AMBER_TX)
  Detail.bar.text:SetText(string.format(L["%d/%d appearances"], n, t))
  Detail.bar:Show()
  y = y - 24

  -- variant selector (segmented), hidden when the set has a single variant.
  -- Labels are clamped inside their segment (old sets carry sentence-long
  -- variant descriptions) — the full text + progress live in the tooltip.
  local nv = #g.variants
  for _, b in ipairs(Detail.variantBtns) do b:Hide() end
  if nv > 1 then
    local gap = 4
    local bw = math.floor((DW - gap * (nv - 1)) / nv)
    for i, v in ipairs(g.variants) do
      local b = Detail.variantBtns[i]
      if not b then
        b = W.MakeButton(f, "nav")
        b:SetHeight(22)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 4, 0)
        b.label:SetPoint("RIGHT", -4, 0)
        b.label:SetWordWrap(false)
        Detail.variantBtns[i] = b
      end
      b._kind = (v.setID == setID) and "primary" or "nav"
      W.Paint(b, false)
      local label = v.description or v.label
      if not label or label == "" then label = tostring(i) end
      local vn, vt = ns.Pieces.Progress(v.setID)
      b.label:SetText(label)
      b:SetWidth(bw)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", X + (i - 1) * (bw + gap), y)
      b:SetScript("OnEnter", function(s)
        W.Paint(s, true)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:AddLine(label, 1, 1, 1, true)
        local done = vt > 0 and vn >= vt
        GameTooltip:AddLine(vn .. "/" .. vt,
          done and 0.38 or 0.96, done and 0.82 or 0.72, done and 0.43 or 0.32)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function(s)
        W.Paint(s, false)
        GameTooltip:Hide()
      end)
      b:SetScript("OnClick", function()
        Detail.setID = v.setID
        ns.charDB.selectedSetID = v.setID
        Detail.Refresh()
      end)
      b:Show()
    end
    y = y - 28
  end

  -- piece rows (with a "+N more" overflow line if space runs out)
  local pieces = ns.Pieces.For(setID)
  local bottomLimit = -(ns.UI.H - ns.UI.PAD - 34 - 46)   -- above the travel dock
  local shown = 0
  for i, piece in ipairs(pieces) do
    if y - PIECE_H < bottomLimit then break end
    local row = ensurePieceRow(i, f)
    paintPieceRow(row, piece, setID)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", X, y)
    row:Show()
    y = y - PIECE_H - 2
    shown = i
  end
  for i = shown + 1, #Detail.pieceRows do Detail.pieceRows[i]:Hide() end
  if shown < #pieces then
    Detail.overflow:ClearAllPoints()
    Detail.overflow:SetPoint("TOPLEFT", X, y)
    Detail.overflow:SetText(W.GREY .. string.format(L["(+%d more pieces)"], #pieces - shown) .. "|r")
    Detail.overflow:Show()
  else
    Detail.overflow:Hide()
  end

  -- travel dock (only when a travel action is active — set by Nav/Travel)
  if ns.Travel and ns.Travel.active then
    Detail.actionLabel:SetText(ns.Travel.label or "")
    Detail.actionPanel:Show()
  else
    Detail.actionPanel:Hide()
  end

  -- action row
  local targets = ns.Sources.GuideTargets(setID)
  Detail.guideBtn.label:SetText(L["Guide me"])
  Detail.guideBtn.arrow:SetShown(#targets > 1)
  W.SetBtn(Detail.guideBtn, #targets > 0)
  Detail.guideBtn:Show()
  Detail.tryBtn:Show()
  Detail.journalBtn:Show()

  -- preview pane
  Detail.modelBG:Show()
  Detail.model:Show()
  for _, b in ipairs(Detail.previewBtns) do b:Show() end
  Detail.PaintPreviewButtons()
  Detail.UpdatePreview()
end

-- ---------------------------------------------------------------------------
-- actions
-- ---------------------------------------------------------------------------
--- Send the player to a target: FarstriderLib routing when available, otherwise
--- a native waypoint + arrow to the destination.
function Detail.GuideTo(target)
  if not target then return end
  ns.charDB.lastGuidedBaseSetID = Detail.group and Detail.group.baseSetID or nil
  if ns.Nav and ns.Nav.GuideTo and ns.Nav.GuideTo(target) then
    Detail.Refresh()   -- the travel dock may have appeared
    return
  end
  if ns.Waypoint and ns.Waypoint.GuideToTarget then
    ns.Waypoint.GuideToTarget(target)
  end
end

--- Left-click "Guide me": the instance holding the most missing pieces.
function Detail.GuideSelected()
  if not Detail.setID then return end
  Detail.GuideTo(ns.Sources.NavFor(Detail.setID))
end

--- Right-click "Guide me": pick the destination from every known one.
function Detail.OpenGuideMenu()
  if not (Detail.setID and MenuUtil and MenuUtil.CreateContextMenu) then
    Detail.GuideSelected()
    return
  end
  local targets = ns.Sources.GuideTargets(Detail.setID)
  if #targets == 0 then return end
  MenuUtil.CreateContextMenu(Detail.guideBtn, function(_, root)
    root:CreateTitle(L["Guide me to..."])
    for _, target in ipairs(targets) do
      local label = target.title or "?"
      if target.missing and target.missing > 0 then
        label = label .. "  " .. W.GREY .. string.format(L["(%d pieces)"], target.missing) .. "|r"
      end
      root:CreateButton(label, function() Detail.GuideTo(target) end)
    end
  end)
end

--- "Try on": the whole selected variant in the dressing room — the exact call
--- Blizzard's sets journal makes.
function Detail.TryOn()
  if not Detail.setID then return end
  local sources = C_TransmogSets.GetAllSourceIDs and C_TransmogSets.GetAllSourceIDs(Detail.setID)
  if sources and #sources > 0 and DressUpTransmogSet then
    pcall(DressUpTransmogSet, sources)
  end
end

--- "Journal": open the Blizzard Appearances > Sets tab on this set (best effort;
--- the deep-link into the wardrobe is an undocumented mixin call).
function Detail.OpenJournal()
  if InCombatLockdown() or not ToggleCollectionsJournal then return end
  local setID = Detail.setID
  pcall(ToggleCollectionsJournal, 5)
  C_Timer.After(0.3, function()
    pcall(function()
      if WardrobeCollectionFrame and WardrobeCollectionFrame.SetTab then
        WardrobeCollectionFrame:SetTab(2)   -- 2 = sets, within the Appearances journal
      end
      if setID and WardrobeCollectionFrame and WardrobeCollectionFrame.SetsCollectionFrame
          and WardrobeCollectionFrame.SetsCollectionFrame.SelectSet then
        WardrobeCollectionFrame.SetsCollectionFrame:SelectSet(setID)
      end
    end)
  end)
end
