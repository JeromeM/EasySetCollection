-- SetList.lua — the left pane: a recycling scroll list of set groups
-- (WowScrollBoxList + MinimalScrollBar + linear view), with per-row icon, name,
-- tag line, X/N counter and a slim progress bar, following the modern retail
-- ScrollBox pattern.

local ADDON, ns = ...
ns.SetList = ns.SetList or {}
local SetList = ns.SetList
local L = ns.L
local W = ns.Widgets

local ROW_H = 44

SetList.selected = nil   -- baseSetID of the selected group

--- The dim one-line tag under a row's name: "Expansion – Location". The class
--- is only appended when browsing ALL classes (otherwise it just repeats the
--- toolbar's class selector).
local function tagText(g)
  local bits = {}
  bits[#bits + 1] = ns.ExpansionName(g.expansionID or 0)
  -- generic bucket tag (Raid / Dungeon / Vendor / …) — the actual place names
  -- live in the detail pane's location list
  local loc = ns.Sources.BucketLabel(g.bucket)
  if loc then bits[#bits + 1] = loc end
  if ns.db.filters.classID == 0 then
    if g.className then
      bits[#bits + 1] = g.className
    elseif g.classCount and g.classCount > 1 and g.classCount < 13 then
      bits[#bits + 1] = string.format(L["%d classes"], g.classCount)
    end
  end
  if g.legacy then bits[#bits + 1] = L["No longer obtainable"] end
  return table.concat(bits, " – ")
end

-- ---------------------------------------------------------------------------
-- row rendering
-- ---------------------------------------------------------------------------
local function ensureRowWidgets(row)
  if row.icon then return end

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()

  row.iconFrame = W.MakePanel(row)
  row.iconFrame:SetSize(36, 36)
  row.iconFrame:SetPoint("LEFT", 2, 0)
  row.iconFrame:SetBackdropColor(0, 0, 0, 0.5)
  row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("TOPLEFT", 2, -2)
  row.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 10, -4)
  row.name:SetPoint("RIGHT", row, "RIGHT", -66, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.tag:SetPoint("BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", 10, 4)
  row.tag:SetPoint("RIGHT", row, "RIGHT", -66, 0)
  row.tag:SetJustifyH("LEFT")
  row.tag:SetWordWrap(false)

  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.count:SetPoint("TOPRIGHT", -8, -8)
  row.count:SetJustifyH("RIGHT")

  row.barBG = row:CreateTexture(nil, "ARTWORK")
  row.barBG:SetColorTexture(W.C_SEP[1], W.C_SEP[2], W.C_SEP[3], 1)
  row.barBG:SetSize(52, 3)
  row.barBG:SetPoint("BOTTOMRIGHT", -8, 10)
  row.barFill = row:CreateTexture(nil, "OVERLAY")
  row.barFill:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)
  row.barFill:SetSize(0.01, 3)

  row.star = row:CreateTexture(nil, "OVERLAY")
  row.star:SetTexture("Interface\\Common\\FavoritesIcon")
  row.star:SetSize(16, 16)
  row.star:SetPoint("TOPLEFT", 0, 0)

  -- weekly-lockout indicator, left of the X/N counter, tinted like the row's
  -- progress (red when nothing is left to farm this week). Ignores the row's
  -- dimming so it stays readable on untouched (0/N) sets.
  row.lock = row:CreateTexture(nil, "OVERLAY")
  if ns.Lockouts then ns.Lockouts.ApplyIcon(row.lock) end
  row.lock:SetSize(16, 16)
  row.lock:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
  row.lock:SetIgnoreParentAlpha(true)
  row.lock:Hide()

  row:SetScript("OnClick", function(self)
    if self.entry then SetList.Select(self.entry) end
  end)
  row:SetScript("OnEnter", function(self)
    local g = self.entry
    if not g then return end
    ns.Widgets.OwnTooltip(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(g.name)
    for _, v in ipairs(g.variants) do
      local n, t = ns.Pieces.Progress(v.setID)
      local label = v.description or v.label
      if not label or label == "" then label = L["Set"] end
      local done = t > 0 and n >= t
      GameTooltip:AddDoubleLine(label, n .. "/" .. t,
        0.85, 0.85, 0.9,
        done and 0.38 or 0.96, done and 0.82 or 0.72, done and 0.43 or 0.32)
    end
    if ns.Lockouts then
      local _, details = ns.Lockouts.GroupState(g)
      if details then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["This week"], 0.55, 0.55, 0.62)
        for _, d in ipairs(details) do
          local left = d.title
          if d.diffName and d.diffName ~= "" then left = left .. " — " .. d.diffName end
          local right = d.killed .. "/" .. d.total .. " · " .. ns.Lockouts.ResetText(d)
          GameTooltip:AddDoubleLine(left, right, 0.9, 0.9, 0.93,
            d.cleared and 0.95 or 0.96, d.cleared and 0.35 or 0.72, d.cleared and 0.30 or 0.32)
        end
      end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click for details"], 0.35, 0.7, 1.0)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
end

--- Paint one row from its group entry (also used for selection repaints).
local function paintRow(row)
  local g = row.entry
  if not g then return end

  row.icon:SetTexture(ns.Pieces.SetIcon(g.variants[1] and g.variants[1].setID)
    or "Interface\\Icons\\INV_Misc_QuestionMark")
  row.name:SetText(g.name)
  row.tag:SetText(W.GREY .. tagText(g) .. "|r")
  row.star:SetShown(g.favorite or false)


  local n, t = ns.Pieces.GroupProgress(g)
  local sel = (g.baseSetID == SetList.selected)
  if sel then
    row.bg:SetColorTexture(0.24, 0.17, 0.05, 0.9)
  else
    row.bg:SetColorTexture(0.12, 0.12, 0.15, g._zebra and 0.35 or 0.15)
  end

  if t > 0 and n >= t then
    row:SetAlpha(1)
    row.name:SetTextColor(W.C_GREEN[1], W.C_GREEN[2], W.C_GREEN[3])
    row.count:SetText(W.GREEN .. n .. "/" .. t .. "|r")
    row.barFill:SetColorTexture(W.C_GREEN[1], W.C_GREEN[2], W.C_GREEN[3], 1)
  elseif n > 0 then
    row:SetAlpha(1)
    row.name:SetTextColor(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3])
    row.count:SetText(W.AMBER .. n .. "/" .. t .. "|r")
    row.barFill:SetColorTexture(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3], 1)
  else
    row:SetAlpha(0.55)
    row.name:SetTextColor(0.85, 0.85, 0.9)
    row.count:SetText(W.GREY .. n .. "/" .. t .. "|r")
    row.barFill:SetColorTexture(0, 0, 0, 0)
  end
  row.barFill:SetWidth(math.max(0.01, 52 * (t > 0 and n / t or 0)))

  -- lockout indicator: red when nothing is left to farm this week, otherwise
  -- the same color as the row's progress (amber started / light grey untouched)
  local lockState = ns.Lockouts and ns.Lockouts.GroupState(g) or nil
  row.lock:SetShown(lockState ~= nil)
  if lockState == "cleared" then
    row.lock:SetVertexColor(0.95, 0.35, 0.30)
  elseif n > 0 then
    row.lock:SetVertexColor(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3])
  else
    row.lock:SetVertexColor(0.85, 0.85, 0.9)
  end
end

local function initRow(row, entry)
  ensureRowWidgets(row)
  row.entry = entry
  paintRow(row)
end

-- ---------------------------------------------------------------------------
-- build / refresh
-- ---------------------------------------------------------------------------
--- Build the scroll list inside the main window's left pane (called by UI.Init).
function SetList.Build(f)
  local UI = ns.UI

  -- centered status text (loading / empty) + a reset button for the empty state
  SetList.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  SetList.status:SetPoint("CENTER", f, "TOPLEFT", UI.PAD + UI.LIST_W / 2, -(UI.H / 2))
  SetList.status:SetWidth(UI.LIST_W - 40)
  SetList.status:Hide()

  SetList.resetBtn = W.MakeButton(f, "warn")
  SetList.resetBtn:SetSize(180, 24)
  SetList.resetBtn:SetPoint("TOP", SetList.status, "BOTTOM", 0, -12)
  SetList.resetBtn.label:SetText(L["Reset the filters"])
  SetList.resetBtn:SetScript("OnClick", function()
    ns.Filters.Reset()
    if f.search and f.search.editBox then f.search.editBox:SetText("") end
    ns.UI.UpdateToolbar()
    ns.UI.RefreshAll()
    if ns.FilterPanel and ns.FilterPanel.RefreshRows then ns.FilterPanel.RefreshRows() end
  end)
  SetList.resetBtn:Hide()

  if not (CreateScrollBoxListLinearView and ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar
      and CreateDataProvider) then
    -- ScrollBox API missing (should not happen on retail 12.x): degrade visibly
    SetList.status:SetText(W.GREY .. "ScrollBox API unavailable" .. "|r")
    SetList.status:Show()
    return
  end

  local box = CreateFrame("Frame", nil, f, "WowScrollBoxList")
  SetList.box = box
  box:SetPoint("TOPLEFT", UI.PAD, -84)
  box:SetSize(UI.LIST_W - 14, UI.H - 84 - 34)

  local bar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
  SetList.bar = bar
  bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_H)
  view:SetElementInitializer("Button", initRow)
  view:SetElementResetter(function(row) row.entry = nil end)
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
end

--- Repaint the visible rows in place (selection change — no data change).
function SetList.RepaintRows()
  if SetList.box and SetList.box.ForEachFrame then
    SetList.box:ForEachFrame(function(row)
      if row.entry then paintRow(row) end
    end)
  end
end

--- Select a group: remember it, hand it to the detail pane, repaint highlights.
function SetList.Select(g)
  SetList.selected = g.baseSetID
  ns.Detail.ShowGroup(g)
  SetList.RepaintRows()
end

--- Bring a group's row into view (programmatic selection — e.g. Suggest).
--- No-op when the group is filtered out of the current list.
function SetList.ScrollTo(baseSetID)
  if not (SetList.box and SetList.box.ScrollToElementDataIndex) then return end
  for i, g in ipairs(SetList.current or {}) do
    if g.baseSetID == baseSetID then
      pcall(SetList.box.ScrollToElementDataIndex, SetList.box, i,
        ScrollBoxConstants and ScrollBoxConstants.AlignCenter or nil)
      return
    end
  end
end

--- Re-apply the filters and feed the scroll list; drives the loading/empty
--- states and the footer counts.
function SetList.Refresh()
  local f = ns.UI.frame
  if not f then return end

  local list, complete = ns.Filters.Apply()
  SetList.current = list

  if not list then
    -- collection data not ready yet (login): show a message and retry shortly;
    -- the TRANSMOG_COLLECTION_UPDATED event also triggers a rebuild.
    if SetList.box then SetList.box:Hide() end
    if SetList.bar then SetList.bar:Hide() end
    SetList.resetBtn:Hide()
    SetList.status:SetText(W.GREY .. L["Loading the collection..."] .. "|r")
    SetList.status:Show()
    f.counts:SetText("")
    if not SetList.retryTimer then
      SetList.retryTimer = C_Timer.NewTimer(1, function()
        SetList.retryTimer = nil
        ns.UI.RefreshAll()
      end)
    end
    return
  end

  if not SetList.box then return end

  if #list == 0 then
    SetList.box:Hide()
    SetList.bar:Hide()
    SetList.status:SetText(W.WHITE .. L["No set matches the filters."] .. "|r")
    SetList.status:Show()
    SetList.resetBtn:Show()
  else
    SetList.status:Hide()
    SetList.resetBtn:Hide()
    SetList.box:Show()
    SetList.bar:Show()
    for i, g in ipairs(list) do g._zebra = (i % 2 == 0) end
    SetList.box:SetDataProvider(CreateDataProvider(list),
      ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil)

    -- once per session: bring the restored selection into view
    if SetList.selected and not SetList.didInitialScroll then
      for i, g in ipairs(list) do
        if g.baseSetID == SetList.selected then
          SetList.didInitialScroll = true
          if SetList.box.ScrollToElementDataIndex then
            pcall(SetList.box.ScrollToElementDataIndex, SetList.box, i,
              ScrollBoxConstants and ScrollBoxConstants.AlignCenter or nil)
          end
          break
        end
      end
    end
  end

  f.counts:SetText(W.GREY .. string.format(L["%d sets · %d complete"], #list, complete or 0) .. "|r")
end
