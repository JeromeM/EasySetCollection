-- FilterPanel.lua — the side filter panel (possession / content type /
-- expansion checklists + extras), the class dropdown and the sort menu.
-- The panel sits on the DIALOG strata with edge-aware anchoring; check rows
-- are bound to getter/setter closures.

local ADDON, ns = ...
ns.FilterPanel = ns.FilterPanel or {}
local FP = ns.FilterPanel
local L = ns.L
local W = ns.Widgets

local FW = 230   -- panel width

local function onFilterChanged()
  ns.UI.UpdateToolbar()
  ns.UI.RefreshList()
end

--- Build the filter popup (idempotent).
function FP.Build()
  if FP.panel then return end
  local p = CreateFrame("Frame", "EasySetCollectionFilterPanel", ns.UI.frame, "BackdropTemplate")
  FP.panel = p
  p:SetFrameStrata("DIALOG")
  p:SetWidth(FW)
  p:SetBackdrop(W.BD1)
  p:SetBackdropColor(W.C_BG[1], W.C_BG[2], W.C_BG[3], 0.98)
  p:SetBackdropBorderColor(W.C_BORDER[1], W.C_BORDER[2], W.C_BORDER[3], 1)
  p:SetClampedToScreen(true)
  p:EnableMouse(true)
  p:Hide()

  FP.rows = {}
  local y = -10

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, y)
  title:SetText(W.WHITE .. L["Filters"] .. "|r")
  y = y - 24

  local function sectionHeader(text)
    local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", 10, y)
    h:SetText(text)
    h:SetTextColor(0.55, 0.55, 0.62)
    y = y - 18
  end

  local function addRow(label, get, set)
    local row = W.MakeCheckRow(p, label, FW - 16)
    row:SetPoint("TOPLEFT", 8, y)
    W.PaintCheck(row, get())
    row:SetScript("OnClick", function()
      local v = not get()
      set(v)
      W.PaintCheck(row, v)
      onFilterChanged()
    end)
    FP.rows[#FP.rows + 1] = { row = row, get = get }
    y = y - 20
  end

  local fl = ns.db.filters

  sectionHeader(L["Possession"])
  local POSSESSION = {
    { "complete", L["Complete sets"] },
    { "partial", L["Partially collected"] },
    { "none", L["Not collected"] },
  }
  for _, c in ipairs(POSSESSION) do
    local key = c[1]
    addRow(c[2],
      function() return fl.possession[key] ~= false end,
      function(v) fl.possession[key] = v end)
  end

  y = y - 8
  sectionHeader(L["Content type"])
  local BUCKETS = {
    { "raid", L["Raid"] }, { "dungeon", L["Dungeon"] }, { "pvp", L["PvP"] },
    { "quest", L["Quest"] }, { "vendor", L["Vendor"] }, { "world", L["World"] },
    { "unknown", L["Unknown"] },
  }
  for _, c in ipairs(BUCKETS) do
    local key = c[1]
    addRow(c[2],
      function() return fl.contentTypes[key] ~= false end,
      function(v) fl.contentTypes[key] = v end)
  end

  y = y - 8
  sectionHeader(L["Expansions"])
  local maxExp = (GetClientDisplayExpansionLevel and GetClientDisplayExpansionLevel())
    or LE_EXPANSION_LEVEL_CURRENT or 11
  for e = 0, maxExp do
    if _G["EXPANSION_NAME" .. e] then
      local exp = e
      addRow(ns.ExpansionName(e),
        function() return fl.expansions[exp] ~= false end,
        function(v) fl.expansions[exp] = v end)
    end
  end

  y = y - 8
  sectionHeader(L["Extras"])
  addRow(L["Opposite-faction sets"],
    function() return fl.otherFaction == true end,
    function(v) fl.otherFaction = v end)
  addRow(L["Unobtainable sets"],
    function() return fl.showLegacy ~= false end,
    function(v) fl.showLegacy = v end)
  addRow(L["Hide sets with nothing left to farm this week"],
    function() return fl.hideCleared == true end,
    function(v) fl.hideCleared = v end)

  y = y - 10
  local reset = W.MakeButton(p, "warn")
  reset:SetSize(FW - 20, 22)
  reset:SetPoint("TOPLEFT", 10, y)
  reset.label:SetText(L["Reset the filters"])
  reset:SetScript("OnClick", function()
    ns.Filters.Reset()
    local f = ns.UI.frame
    if f and f.search and f.search.editBox then f.search.editBox:SetText("") end
    FP.RefreshRows()
    onFilterChanged()
  end)
  y = y - 26

  p:SetHeight(-y + 10)
end

--- Repaint every check row from the current saved state.
function FP.RefreshRows()
  for _, r in ipairs(FP.rows or {}) do W.PaintCheck(r.row, r.get()) end
end

--- Anchor the panel to whichever side of the window has room.
function FP.Position()
  local p, f = FP.panel, ns.UI.frame
  if not p or not f then return end
  p:ClearAllPoints()
  local right = f:GetRight()
  local screenW = UIParent:GetWidth()
  if right and screenW and (screenW - right) >= (FW + 10) then
    p:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, 0)
  else
    p:SetPoint("TOPRIGHT", f, "TOPLEFT", -6, 0)
  end
end

function FP.Toggle()
  FP.Build()
  if FP.panel:IsShown() then
    FP.panel:Hide()
  else
    FP.Position()
    FP.RefreshRows()
    FP.panel:Show()
  end
end

function FP.Hide()
  if FP.panel then FP.panel:Hide() end
end

-- ---------------------------------------------------------------------------
-- dropdown menus (modern MenuUtil API)
-- ---------------------------------------------------------------------------
--- Class selector: my class / all classes / each of the 13 classes.
function FP.OpenClassMenu(anchor)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  local fl = ns.db.filters
  local function apply(v)
    fl.classID = v
    onFilterChanged()
  end
  MenuUtil.CreateContextMenu(anchor, function(_, root)
    root:CreateTitle(L["Show sets for"])
    root:CreateRadio(L["My class"],
      function() return fl.classID == nil end, function() apply(nil) end)
    root:CreateRadio(L["All classes"],
      function() return fl.classID == 0 end, function() apply(0) end)
    root:CreateDivider()
    for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
      local info = C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
      if info then
        local name = info.className
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classFile]
        if color and color.WrapTextInColorCode then name = color:WrapTextInColorCode(name) end
        local id = classID
        root:CreateRadio(name,
          function() return fl.classID == id end, function() apply(id) end)
      end
    end
  end)
end

--- Sort selector (footer).
function FP.OpenSortMenu(anchor)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  local function apply(mode)
    ns.db.sort = mode
    onFilterChanged()
  end
  local MODES = {
    { "expansion", L["Expansion"] },
    { "alpha", L["Alphabetical"] },
    { "progress", L["Progress"] },
  }
  MenuUtil.CreateContextMenu(anchor, function(_, root)
    root:CreateTitle(L["Sort by"])
    for _, m in ipairs(MODES) do
      local mode = m[1]
      root:CreateRadio(m[2],
        function() return (ns.db.sort or "expansion") == mode end,
        function() apply(mode) end)
    end
  end)
end
