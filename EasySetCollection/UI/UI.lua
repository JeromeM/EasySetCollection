-- UI.lua — the main two-pane window shell: header, toolbar (search / class /
-- filters), left list pane + right detail pane, footer, the Settings pages and
-- the "new set piece" toast. The panes' contents live in SetList.lua and
-- Detail.lua; the filter side panel in FilterPanel.lua.

local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local L = ns.L
local W = ns.Widgets

-- window geometry (shared with the other UI files via ns.UI)
UI.W, UI.H, UI.PAD = 984, 560, 14
UI.LIST_W = 380                       -- left pane width (rows + scrollbar)
UI.DETAIL_X = UI.PAD + UI.LIST_W + 22 -- left edge of the detail pane
UI.DETAIL_W = 300
UI.MODEL_X = UI.DETAIL_X + UI.DETAIL_W + 24   -- left edge of the preview pane
UI.MODEL_W = UI.W - UI.MODEL_X - UI.PAD

-- ---------------------------------------------------------------------------
-- position persistence
-- ---------------------------------------------------------------------------
function UI.SavePosition()
  local p, _, rp, x, y = UI.frame:GetPoint()
  ns.db.pos = { p = p, rp = rp, x = x, y = y }
end

function UI.RestorePosition()
  UI.frame:ClearAllPoints()
  local pos = ns.db and ns.db.pos
  if pos and pos.p then
    UI.frame:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y)
  else
    UI.frame:SetPoint("CENTER")
  end
end

-- ---------------------------------------------------------------------------
-- build the window
-- ---------------------------------------------------------------------------
--- Build the main window and both panes (idempotent: no-op if already built).
function UI.Init()
  if UI.frame then return end

  local f = CreateFrame("Frame", "EasySetCollectionFrame", UIParent, "BackdropTemplate")
  UI.frame = f
  f:SetSize(UI.W, UI.H)
  f:SetScale((ns.db and ns.db.windowScale) or 1)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetBackdrop(W.BD1)
  f:SetBackdropColor(W.C_BG[1], W.C_BG[2], W.C_BG[3], 0.97)
  f:SetBackdropBorderColor(W.C_BORDER[1], W.C_BORDER[2], W.C_BORDER[3], 1)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if not (ns.db and ns.db.locked) then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); UI.SavePosition() end)
  f:SetClampedToScreen(true)
  f:Hide()

  -- header: icon (left) + centered title + gear + close (right)
  f.icon = W.MakePanel(f)
  f.icon:SetSize(22, 22)
  f.icon:SetPoint("TOPLEFT", UI.PAD, -12)
  f.icon:SetBackdropColor(0.10, 0.08, 0.14, 1)
  f.icon:SetBackdropBorderColor(W.C_EPIC[1], W.C_EPIC[2], W.C_EPIC[3], 0.9)
  f.iconTex = f.icon:CreateTexture(nil, "ARTWORK")
  f.iconTex:SetPoint("TOPLEFT", 2, -2)
  f.iconTex:SetPoint("BOTTOMRIGHT", -2, 2)
  f.iconTex:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
  f.iconTex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
  f.icon:EnableMouse(true)
  f.icon:SetScript("OnMouseUp", function()
    if not InCombatLockdown() and ToggleCollectionsJournal then
      pcall(ToggleCollectionsJournal, 5)   -- open Collections -> Appearances tab
    end
  end)

  -- "Suggest" — the flagship action, right next to the wardrobe icon
  f.suggestBtn = W.MakeButton(f, "primary")
  f.suggestBtn:SetSize(84, 22)
  f.suggestBtn:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
  f.suggestBtn.label:SetText(L["Suggest"])
  f.suggestBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f.suggestBtn:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" then
      ns.Suggest.OpenMenu(self)
    else
      ns.Suggest.Pick()
    end
  end)
  f.suggestBtn:SetScript("OnEnter", function(self)
    W.Paint(self, true)
    W.OwnTooltip(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Suggest"])
    GameTooltip:AddLine(L["Pick the closest set you can still farm this week and guide there."], 1, 1, 1, true)
    GameTooltip:AddLine(L["Right-click: more suggestions"], 0.35, 0.7, 1.0)
    GameTooltip:Show()
  end)
  f.suggestBtn:SetScript("OnLeave", function(self)
    W.Paint(self, false)
    GameTooltip:Hide()
  end)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOP", f, "TOP", 0, -15)
  f.title:SetText(W.WHITE .. L["EasySetCollection"] .. "|r")

  f.close = W.MakeButton(f, "nav", "GameFontNormalLarge")
  f.close:SetSize(22, 22)
  f.close:SetPoint("TOPRIGHT", -10, -11)
  f.close.label:SetText("×")
  f.close:SetScript("OnClick", function() UI.Hide() end)

  f.gear = W.MakeButton(f, "nav")
  f.gear:SetSize(22, 22)
  f.gear:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
  f.gear.label:Hide()
  f.gearTex = f.gear:CreateTexture(nil, "OVERLAY")
  f.gearTex:SetSize(14, 14)
  f.gearTex:SetPoint("CENTER")
  f.gearTex:SetTexture("Interface\\AddOns\\EasySetCollection\\Media\\settings.tga")
  f.gearTex:SetVertexColor(0.86, 0.86, 0.90)
  f.gear:SetScript("OnClick", function() UI.OpenSettings() end)
  f.gear:SetScript("OnEnter", function(self)
    W.Paint(self, true)
    W.OwnTooltip(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Open the options"])
    GameTooltip:Show()
  end)
  f.gear:SetScript("OnLeave", function(self)
    W.Paint(self, false)
    GameTooltip:Hide()
  end)

  -- wand — rerun the first-time setup wizard
  f.setupBtn = W.MakeButton(f, "nav")
  f.setupBtn:SetSize(22, 22)
  f.setupBtn:SetPoint("RIGHT", f.gear, "LEFT", -4, 0)
  f.setupBtn.label:Hide()
  f.setupTex = f.setupBtn:CreateTexture(nil, "OVERLAY")
  f.setupTex:SetSize(14, 14)
  f.setupTex:SetPoint("CENTER")
  f.setupTex:SetTexture("Interface\\AddOns\\EasySetCollection\\Media\\setup.tga")
  f.setupTex:SetVertexColor(0.86, 0.86, 0.90)
  f.setupBtn:SetScript("OnClick", function()
    if ns.Setup then ns.Setup.Show() end
  end)
  f.setupBtn:SetScript("OnEnter", function(self)
    W.Paint(self, true)
    W.OwnTooltip(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Rerun the first-time setup"])
    GameTooltip:Show()
  end)
  f.setupBtn:SetScript("OnLeave", function(self)
    W.Paint(self, false)
    GameTooltip:Hide()
  end)

  -- header separator
  f.sep = f:CreateTexture(nil, "ARTWORK")
  f.sep:SetColorTexture(W.C_SEP[1], W.C_SEP[2], W.C_SEP[3], 1)
  f.sep:SetHeight(1)
  f.sep:SetPoint("TOPLEFT", UI.PAD, -44)
  f.sep:SetPoint("TOPRIGHT", -UI.PAD, -44)

  -- vertical separators between the three panes (list | detail | preview)
  f.vsep = f:CreateTexture(nil, "ARTWORK")
  f.vsep:SetColorTexture(W.C_SEP[1], W.C_SEP[2], W.C_SEP[3], 1)
  f.vsep:SetWidth(1)
  f.vsep:SetPoint("TOPLEFT", UI.PAD + UI.LIST_W + 10, -52)
  f.vsep:SetPoint("BOTTOMLEFT", UI.PAD + UI.LIST_W + 10, UI.PAD)

  f.vsep2 = f:CreateTexture(nil, "ARTWORK")
  f.vsep2:SetColorTexture(W.C_SEP[1], W.C_SEP[2], W.C_SEP[3], 1)
  f.vsep2:SetWidth(1)
  f.vsep2:SetPoint("TOPLEFT", UI.DETAIL_X + UI.DETAIL_W + 12, -52)
  f.vsep2:SetPoint("BOTTOMLEFT", UI.DETAIL_X + UI.DETAIL_W + 12, UI.PAD)

  -- toolbar (over the left pane): search box + class dropdown + Filters button
  f.search = W.MakeSearchBox(f, 200, L["Search..."], function(txt)
    ns.Filters.SetQuery(txt)
    UI.RefreshList()
  end)
  f.search:SetPoint("TOPLEFT", UI.PAD, -52)

  f.classBtn = W.MakeButton(f, "nav")
  f.classBtn:SetSize(100, 24)
  f.classBtn:SetPoint("LEFT", f.search, "RIGHT", 6, 0)
  f.classBtn.label:SetWordWrap(false)
  f.classBtn.label:ClearAllPoints()
  f.classBtn.label:SetPoint("LEFT", 6, 0)
  f.classBtn.label:SetPoint("RIGHT", -14, 0)
  W.AddDropdownArrow(f.classBtn)
  f.classBtn:SetScript("OnClick", function(self) ns.FilterPanel.OpenClassMenu(self) end)

  f.filterBtn = W.MakeButton(f, "nav")
  f.filterBtn:SetSize(68, 24)
  f.filterBtn:SetPoint("TOPLEFT", UI.PAD + UI.LIST_W - 68, -52)
  f.filterBtn.label:SetText(L["Filters"])
  f.filterBtn:SetScript("OnClick", function() ns.FilterPanel.Toggle() end)

  -- footer (under the left pane): result counts + sort menu
  f.counts = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.counts:SetPoint("BOTTOMLEFT", UI.PAD, UI.PAD)
  f.counts:SetJustifyH("LEFT")

  f.sortBtn = W.MakeButton(f, "nav")
  f.sortBtn:SetSize(90, 20)
  f.sortBtn:SetPoint("BOTTOMLEFT", UI.PAD + UI.LIST_W - 90, UI.PAD - 2)
  f.sortBtn.label:ClearAllPoints()
  f.sortBtn.label:SetPoint("LEFT", 6, 0)
  f.sortBtn.label:SetPoint("RIGHT", -14, 0)
  W.AddDropdownArrow(f.sortBtn)
  f.sortBtn:SetScript("OnClick", function(self) ns.FilterPanel.OpenSortMenu(self) end)

  ns.SetList.Build(f)
  ns.Detail.Build(f)

  UI.UpdateToolbar()
  UI.RestorePosition()
end

--- Repaint the toolbar's stateful labels: the class button shows the active
--- class filter, the Filters button gains an amber "(N)" badge when non-default.
function UI.UpdateToolbar()
  local f = UI.frame
  if not f then return end

  local classID = ns.db.filters.classID
  local label
  if classID == nil then
    label = L["My class"]
  elseif classID == 0 then
    label = L["All classes"]
  else
    local info = C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
    label = info and info.className or ("#" .. classID)
  end
  f.classBtn.label:SetText(label)

  local n = ns.Filters.ActiveCount()
  if n > 0 then
    f.filterBtn.label:SetText(W.AMBER .. L["Filters"] .. " (" .. n .. ")|r")
  else
    f.filterBtn.label:SetText(L["Filters"])
  end

  local mode = ns.db.sort or "expansion"
  local names = {
    expansion = L["Expansion"], alpha = L["Alphabetical"], progress = L["Progress"],
  }
  f.sortBtn.label:SetText(W.GREY .. (names[mode] or "?") .. "|r")
end

-- ---------------------------------------------------------------------------
-- refresh dispatchers
-- ---------------------------------------------------------------------------
--- Refresh everything (collection changed / filters changed).
function UI.RefreshAll()
  if not (UI.frame and UI.frame:IsShown()) then return end
  UI.UpdateToolbar()
  -- detail first: it restores the saved selection, which the list needs to
  -- highlight the row and scroll to it on the first paint of the session
  ns.Detail.Refresh()
  ns.SetList.Refresh()
end

function UI.RefreshList()
  if not (UI.frame and UI.frame:IsShown()) then return end
  ns.SetList.Refresh()
end

function UI.RefreshDetail()
  if not (UI.frame and UI.frame:IsShown()) then return end
  ns.Detail.Refresh()
end

--- `/esc guide`: guide to the currently selected set.
function UI.GuideSelected()
  if ns.Detail and ns.Detail.GuideSelected then ns.Detail.GuideSelected() end
end

--- The direction arrow's top line: the name of the set being guided to, amber
--- like the detail pane headline (nil when nothing was guided yet).
function UI.ArrowText()
  local baseID = ns.charDB and ns.charDB.lastGuidedBaseSetID
  local g = baseID and ns.Sets.GroupFor(baseID)
  if g and g.name then return W.AMBER .. g.name .. "|r" end
end

-- ---------------------------------------------------------------------------
-- show / hide
-- ---------------------------------------------------------------------------
function UI.Show()
  if not UI.frame then UI.Init() end
  if ns.db then ns.db.shown = true end
  UI.frame:Show()
  UI.RefreshAll()

  -- opened inside a dungeon/raid: bring the place's most relevant set forward
  -- — and in every case open it on the variant of the CURRENT difficulty
  if ns.Assist and ns.Assist.CurrentJid then
    local jid = ns.Assist.CurrentJid()
    if jid then
      local cur = ns.SetList.selected and ns.Sets.GroupFor
        and ns.Sets.GroupFor(ns.SetList.selected) or nil
      if cur and ns.Assist.GroupDropsIn(cur, jid) then
        -- already on a set of this place: just align its variant
        local v = ns.Assist.VariantHere and ns.Assist.VariantHere(cur)
        if v and v ~= ns.Detail.setID then
          ns.Detail.setID = v
          ns.charDB.selectedSetID = v
          ns.Detail.Refresh()
        end
      else
        local g = ns.Assist.BestGroupHere(jid)
        if g then
          if ns.Assist.VariantHere then
            ns.Detail.setID = ns.Assist.VariantHere(g)
          end
          ns.SetList.Select(g)
          if ns.SetList.ScrollTo then ns.SetList.ScrollTo(g.baseSetID) end
        end
      end
    end
  end

  if ns.Onboard then ns.Onboard.MaybeStart() end
end

function UI.Hide()
  if ns.db then ns.db.shown = false end
  if UI.frame then UI.frame:Hide() end
  if ns.FilterPanel and ns.FilterPanel.Hide then ns.FilterPanel.Hide() end
  -- the secure travel button is parented to UIParent (combat rules) and would
  -- float alone once its dock hides with the window
  if ns.Travel then ns.Travel.Hide() end
  -- the waypoint + arrow deliberately survive closing the window: they are
  -- dismissed from the arrow's right-click menu ("Close") or by guiding elsewhere
end

function UI.Toggle()
  if not UI.frame then UI.Init() end
  if UI.frame:IsShown() then UI.Hide() else UI.Show() end
end

-- ---------------------------------------------------------------------------
-- options: registered in the game's Settings panel (AddOns category)
-- ---------------------------------------------------------------------------
--- Build the "about" landing frame shown on the parent Settings page.
function UI.BuildAboutPanel()
  if UI.aboutPanel then return UI.aboutPanel end
  local f = CreateFrame("Frame", "EasySetCollectionAboutPanel", UIParent)
  UI.aboutPanel = f

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", 10, -16)
  title:SetText(L["EasySetCollection"])

  local div = f:CreateTexture(nil, "ARTWORK")
  div:SetAtlas("Options_HorizontalDivider", true)
  div:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

  local desc = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  desc:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 2, -12)
  desc:SetWidth(560)
  desc:SetJustifyH("LEFT")
  desc:SetSpacing(3)
  desc:SetText(L["Browse every transmog set with per-piece sources, see what you still miss, and let the addon point you to the raid, dungeon or zone that drops it."])

  local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
           or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"
  local version = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  version:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
  version:SetText(L["Version"] .. ": |cffffffff" .. ver .. "|r")

  local author = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  author:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -4)
  author:SetText(L["Author"] .. ": |cffffffffJeromeM|r")

  local reportLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  reportLabel:SetPoint("TOPLEFT", author, "BOTTOMLEFT", 0, -16)
  reportLabel:SetText(L["Report a problem"] .. ":")

  -- Read-only, auto-selecting box so the URL can be copied (WoW can't open a browser).
  local url = "https://github.com/JeromeM/EasySetCollection/issues"
  local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  eb:SetPoint("TOPLEFT", reportLabel, "BOTTOMLEFT", 6, -6)
  eb:SetSize(400, 20)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetText(url)
  eb:SetCursorPosition(0)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  eb:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); self:SetCursorPosition(0) end)
  eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  eb:SetScript("OnChar", function(self) self:SetText(url); self:HighlightText() end)   -- keep read-only

  f.OnCommit = function() end
  f.OnDefault = function() end
  f.OnRefresh = function() end

  return f
end

--- Build the "Profiles" canvas frame: switch / create / copy / reset / delete
--- settings profiles (Core/Profiles.lua). Menus are generated on click, so
--- they always list the current profile set.
function UI.BuildProfilesPanel()
  if UI.profilesPanel then return UI.profilesPanel end
  local f = CreateFrame("Frame", "EasySetCollectionProfilesPanel", UIParent)
  UI.profilesPanel = f
  local P = ns.Profiles

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", 10, -16)
  title:SetText(L["Profiles"])

  local div = f:CreateTexture(nil, "ARTWORK")
  div:SetAtlas("Options_HorizontalDivider", true)
  div:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

  local desc = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  desc:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 2, -12)
  desc:SetWidth(560)
  desc:SetJustifyH("LEFT")
  desc:SetSpacing(3)
  desc:SetText(L["Profiles hold every setting of the addon; each character picks the one it uses. Tracked sets stay per-character."])

  local refresh   -- repaints the stateful labels (declared below)

  -- current profile: a menu button listing every profile
  local curLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  curLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -22)
  curLabel:SetText(L["Current profile"])

  local curBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  curBtn:SetSize(200, 24)
  curBtn:SetPoint("TOPLEFT", curLabel, "BOTTOMLEFT", 0, -6)
  curBtn:SetScript("OnClick", function(self)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(self, function(_, root)
      root:CreateTitle(L["Current profile"])
      for _, name in ipairs(P.List()) do
        root:CreateRadio(name,
          function() return name == P.Current() end,
          function() P.Switch(name) refresh() end)
      end
    end)
  end)

  -- new profile: name box + create-and-switch
  local newLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  newLabel:SetPoint("TOPLEFT", curBtn, "BOTTOMLEFT", 0, -18)
  newLabel:SetText(L["New profile"])

  local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  eb:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 6, -6)
  eb:SetSize(194, 22)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(40)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local createBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  createBtn:SetSize(100, 24)
  createBtn:SetPoint("LEFT", eb, "RIGHT", 8, 0)
  createBtn:SetText(L["Create"])
  local function createProfile()
    local name = (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    P.Switch(name)
    eb:SetText("")
    eb:ClearFocus()
    refresh()
  end
  createBtn:SetScript("OnClick", createProfile)
  eb:SetScript("OnEnterPressed", createProfile)

  -- copy from / reset / delete
  local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  copyBtn:SetSize(200, 24)
  copyBtn:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", -6, -18)
  copyBtn:SetText(L["Copy from"])
  copyBtn:SetScript("OnClick", function(self)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(self, function(_, root)
      root:CreateTitle(L["Copy from"])
      for _, name in ipairs(P.List()) do
        if name ~= P.Current() then
          root:CreateButton(name, function() P.CopyFrom(name) refresh() end)
        end
      end
    end)
  end)

  local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  resetBtn:SetSize(200, 24)
  resetBtn:SetPoint("LEFT", copyBtn, "RIGHT", 8, 0)
  resetBtn:SetText(L["Reset profile"])
  resetBtn:SetScript("OnClick", function() P.Reset() refresh() end)

  local deleteBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  deleteBtn:SetSize(200, 24)
  deleteBtn:SetPoint("TOPLEFT", copyBtn, "BOTTOMLEFT", 0, -12)
  deleteBtn:SetText(L["Delete a profile"])
  deleteBtn:SetScript("OnClick", function(self)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(self, function(_, root)
      root:CreateTitle(L["Delete a profile"])
      for _, name in ipairs(P.List()) do
        if name ~= "Default" and name ~= P.Current() then
          root:CreateButton(name, function() P.Delete(name) refresh() end)
        end
      end
    end)
  end)

  refresh = function()
    curBtn:SetText(P.Current())
  end
  f:SetScript("OnShow", refresh)

  f.OnCommit = function() end
  f.OnDefault = function() end
  f.OnRefresh = function() end

  return f
end

--- Register the addon's options in the game's Settings panel (idempotent).
function UI.BuildSettings()
  if UI.settingsCategory then return end
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then return end

  local category
  if Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(UI.BuildAboutPanel(), L["EasySetCollection"])
  else
    category = Settings.RegisterVerticalLayoutCategory(L["EasySetCollection"])
  end
  UI.settingsCategory = category

  local pct = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

  -- Move a Settings checkbox's box to the LEFT and let the label fill the rest of
  -- the row. The default layout puts the box on the right, truncating long labels.
  local function leftAlignCheckbox(frame)
    if not (frame and frame.Checkbox and frame.Text) then return end
    local base = ((frame.GetIndent and frame:GetIndent()) or 0) + 37
    frame.Checkbox:ClearAllPoints()
    frame.Checkbox:SetPoint("LEFT", frame, "LEFT", base, 0)
    frame.Text:ClearAllPoints()
    frame.Text:SetPoint("LEFT", frame.Checkbox, "RIGHT", 8, 0)
    frame.Text:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    frame.Text:SetJustifyH("LEFT")
  end

  local function boolean(cat, variable, name, getter, setter)
    local setting = Settings.RegisterProxySetting(cat, "EasySetCollection_" .. variable,
      Settings.VarType.Boolean, name, true, getter, setter)
    local init = Settings.CreateCheckbox(cat, setting)
    if init and init.InitFrame then
      local orig = init.InitFrame
      init.InitFrame = function(self, frame)
        orig(self, frame)
        pcall(leftAlignCheckbox, frame)
      end
    end
  end

  local function scaleSlider(cat, variable, name, getter, setter)
    if not (Settings.CreateSlider and Settings.CreateSliderOptions) then return end
    local setting = Settings.RegisterProxySetting(cat, "EasySetCollection_" .. variable,
      Settings.VarType.Number, name, 1, getter, setter)
    local options = Settings.CreateSliderOptions(0.5, 2.5, 0.1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, pct)
    Settings.CreateSlider(cat, setting, options, nil)
  end

  local function subPage(name)
    if Settings.RegisterVerticalLayoutSubcategory then
      return (Settings.RegisterVerticalLayoutSubcategory(category, name))
    end
    return category
  end

  -- ── Window (sub-page); the parent page is the about landing ────────────────
  local winCat = subPage(L["Window"])

  scaleSlider(winCat, "windowScale", L["Window size"],
    function() return ns.db.windowScale or 1 end,
    function(v)
      ns.db.windowScale = v
      if UI.frame then UI.frame:SetScale(v) end
    end)

  boolean(winCat, "locked", L["Lock the window position"],
    function() return ns.db.locked == true end,
    function(v) ns.db.locked = v end)

  boolean(winCat, "showMinimap", L["Show the minimap button"],
    function() return not (ns.db.minimap and ns.db.minimap.hide) end,
    function(v)
      ns.db.minimap = ns.db.minimap or {}
      ns.db.minimap.hide = not v
      if ns.Minimap then
        if not ns.Minimap.button and ns.Minimap.Init then ns.Minimap.Init() end
        if ns.Minimap.button then ns.Minimap.button:SetShown(v) end
      end
    end)

  -- ── Arrow (sub-page) ────────────────────────────────────────────────────────
  local arrowCat = subPage(L["Arrow"])

  boolean(arrowCat, "autoGuide", L["Auto-guide (waypoint / action)"],
    function() return ns.db.autoGuide ~= false end,
    function(v) ns.db.autoGuide = v end)

  boolean(arrowCat, "arrowEnabled", L["Show the direction arrow"],
    function() return not (ns.db.arrow and ns.db.arrow.enabled == false) end,
    function(v)
      ns.db.arrow = ns.db.arrow or {}
      ns.db.arrow.enabled = v
      if not v and ns.Arrow then ns.Arrow.Hide() end
    end)

  boolean(arrowCat, "arrowMetric", L["Use metric distance (m / km)"],
    function() return ns.db.arrow and ns.db.arrow.metric == true end,
    function(v)
      ns.db.arrow = ns.db.arrow or {}
      ns.db.arrow.metric = v
    end)

  scaleSlider(arrowCat, "arrowScale", L["Arrow size"],
    function() return (ns.db.arrow and ns.db.arrow.scale) or 1 end,
    function(v)
      ns.db.arrow = ns.db.arrow or {}
      ns.db.arrow.scale = v
      if ns.Arrow and ns.Arrow.ApplyScale then ns.Arrow.ApplyScale() end
    end)

  scaleSlider(arrowCat, "textScale", L["Text size"],
    function() return (ns.db.arrow and ns.db.arrow.textScale) or 1 end,
    function(v)
      ns.db.arrow = ns.db.arrow or {}
      ns.db.arrow.textScale = v
      if ns.Arrow and ns.Arrow.ApplyScale then ns.Arrow.ApplyScale() end
    end)

  boolean(arrowCat, "arrowLocked", L["Lock the arrow position"],
    function() return ns.db.arrow and ns.db.arrow.locked == true end,
    function(v)
      ns.db.arrow = ns.db.arrow or {}
      ns.db.arrow.locked = v
      if ns.Arrow and ns.Arrow.frame then ns.Arrow.frame:EnableMouse(not v) end
    end)

  -- ── Notifications (sub-page) ────────────────────────────────────────────────
  local notifCat = subPage(L["Notifications"])

  boolean(notifCat, "toastEnabled", L["Show a notification when you collect a set piece"],
    function() return ns.db.toast and ns.db.toast.enabled ~= false end,
    function(v)
      ns.db.toast = ns.db.toast or {}
      ns.db.toast.enabled = v
    end)

  boolean(notifCat, "toastSound", L["Play a sound with the notification"],
    function() return ns.db.toast and ns.db.toast.sound ~= false end,
    function(v)
      ns.db.toast = ns.db.toast or {}
      ns.db.toast.sound = v
    end)

  boolean(notifCat, "toastOnlyComplete", L["Only notify when a set becomes complete"],
    function() return ns.db.toast and ns.db.toast.onlyComplete == true end,
    function(v) ns.db.toast.onlyComplete = v end)

  -- what goes into the notification body
  boolean(notifCat, "toastShowPiece", L["Show the piece name"],
    function() return ns.db.toast and ns.db.toast.showPiece ~= false end,
    function(v) ns.db.toast.showPiece = v end)

  boolean(notifCat, "toastShowSet", L["Show the set name"],
    function() return ns.db.toast and ns.db.toast.showSet ~= false end,
    function(v) ns.db.toast.showSet = v end)

  boolean(notifCat, "toastShowProgress", L["Show the set progress"],
    function() return ns.db.toast and ns.db.toast.showProgress ~= false end,
    function(v) ns.db.toast.showProgress = v end)

  boolean(notifCat, "toastShowOtherSets", L["Mention other sets containing the piece"],
    function() return ns.db.toast and ns.db.toast.showOtherSets ~= false end,
    function(v) ns.db.toast.showOtherSets = v end)

  boolean(notifCat, "toastOtherClasses", L["Also notify for other classes' sets"],
    function() return ns.db.toast and ns.db.toast.otherClasses == true end,
    function(v) ns.db.toast.otherClasses = v end)

  boolean(notifCat, "assistEnabled", L["Announce missing set pieces when entering an instance"],
    function() return ns.db.assist and ns.db.assist.enabled ~= false end,
    function(v)
      ns.db.assist = ns.db.assist or {}
      ns.db.assist.enabled = v
    end)

  boolean(notifCat, "assistExtras", L["Also announce out-of-journal sets"],
    function() return ns.db.assist and ns.db.assist.extras ~= false end,
    function(v)
      ns.db.assist = ns.db.assist or {}
      ns.db.assist.extras = v
    end)

  boolean(notifCat, "assistToast", L["Show the announcement as a toast (chat is always used)"],
    function() return ns.db.assist and ns.db.assist.toast ~= false end,
    function(v)
      ns.db.assist = ns.db.assist or {}
      ns.db.assist.toast = v
    end)

  -- "Test" button: preview the notification with the current settings
  if CreateSettingsButtonInitializer and SettingsPanel and SettingsPanel.GetLayout then
    local initializer = CreateSettingsButtonInitializer(
      L["Notification preview"], L["Test"],
      function() UI.TestToast() end,
      L["Show a sample notification (alternates piece / set complete)."], true)
    local layout = SettingsPanel:GetLayout(notifCat)
    if layout and layout.AddInitializer then layout:AddInitializer(initializer) end
  end

  -- ── Profiles (canvas sub-page): settings profiles management ───────────────
  if Settings.RegisterCanvasLayoutSubcategory then
    Settings.RegisterCanvasLayoutSubcategory(category, UI.BuildProfilesPanel(), L["Profiles"])
  end

  Settings.RegisterAddOnCategory(category)
end

--- Build the settings if needed and open the game's Settings panel to this category.
function UI.OpenSettings()
  UI.BuildSettings()
  if UI.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(UI.settingsCategory:GetID())
  end
end

-- ---------------------------------------------------------------------------
-- "new set piece" toast (queued, one at a time)
-- ---------------------------------------------------------------------------
local toastQueue = {}
local toastActive = false
local showNextToast   -- forward declaration (the timer callback re-enters it)

showNextToast = function()
  local data = table.remove(toastQueue, 1)
  if not data then
    toastActive = false
    return
  end
  toastActive = true

  local p = UI.toast
  if not p then
    p = CreateFrame("Frame", "EasySetCollectionToast", UIParent, "BackdropTemplate")
    p:SetSize(340, 74)
    p:SetPoint("TOP", 0, -200)
    p:SetFrameStrata("DIALOG")
    p:SetBackdrop(W.BD1)
    p:SetBackdropColor(W.C_BG[1], W.C_BG[2], W.C_BG[3], 0.98)
    p.iconFrame = W.MakePanel(p)
    p.iconFrame:SetSize(46, 46)
    p.iconFrame:SetPoint("LEFT", 14, 0)
    p.iconFrame:SetBackdropColor(0, 0, 0, 0.5)
    p.iconFrame:SetBackdropBorderColor(W.C_EPIC[1], W.C_EPIC[2], W.C_EPIC[3], 0.9)
    p.icon = p.iconFrame:CreateTexture(nil, "ARTWORK")
    p.icon:SetPoint("TOPLEFT", 2, -2)
    p.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.text:SetPoint("LEFT", p.iconFrame, "RIGHT", 12, 0)
    p.text:SetPoint("RIGHT", -12, 0)
    p.text:SetJustifyH("LEFT")
    UI.toast = p
  end

  local brd = data.complete and W.C_GREEN or W.C_GOLD_BRD
  p:SetBackdropBorderColor(brd[1], brd[2], brd[3], 1)
  p.icon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  local title = data.title
    or (data.complete and (W.GREEN .. L["Set complete!"] .. "|r")
    or (W.AMBER .. L["New set piece!"] .. "|r"))
  p.text:SetText(title .. "\n" .. W.WHITE .. (data.line or "") .. "|r")
  p:Show()

  if ns.db.toast.sound and not data.silent and PlaySound and SOUNDKIT then
    pcall(PlaySound, data.complete and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.UI_EPICLOOT_TOAST)
  end
  if p.timer then p.timer:Cancel() end
  p.timer = C_Timer.NewTimer(6, function()
    p:Hide()
    showNextToast()
  end)
end

local function enqueueToast(data)
  toastQueue[#toastQueue + 1] = data
  if not toastActive then showNextToast() end
end

--- Assemble the toast body from the "what to show" settings.
local function buildToastLine(pieceName, setName, n, t, extraSets)
  local opts = ns.db.toast
  local bits = {}
  if opts.showPiece ~= false and pieceName then bits[#bits + 1] = pieceName end
  local setLine
  if opts.showSet ~= false and setName then setLine = setName end
  if opts.showProgress ~= false and t and t > 0 then
    setLine = (setLine and (setLine .. " ") or "") .. "(" .. n .. "/" .. t .. ")"
  end
  if setLine then bits[#bits + 1] = setLine end
  local line = table.concat(bits, "\n")
  if opts.showOtherSets ~= false and extraSets and extraSets > 0 then
    line = line .. " " .. W.GREY .. string.format(L["(+%d other sets)"], extraSets) .. "|r"
  end
  return line
end

--- In-instance assistant toast (Modules/Assist.lua): instance name as the
--- title, missing count as the body. Silent — it's an FYI, not loot.
function UI.NotifyAssist(title, line, icon)
  enqueueToast({
    title = W.AMBER .. (title or "") .. "|r",
    line = line,
    icon = icon or "Interface\\Icons\\INV_Misc_Map01",
    silent = true,
  })
end

--- Settings "Test" button: show a sample notification with the current content
--- settings, alternating between a piece toast and a set-complete toast. Uses
--- the selected set's real data when available.
function UI.TestToast()
  local icon, pieceName, setName, n, t
  local setID = ns.charDB and ns.charDB.selectedSetID
  if setID then
    local pieces = ns.Pieces.For(setID)
    local piece = pieces and pieces[1]
    if piece then
      icon = piece.itemID and C_Item.GetItemIconByID(piece.itemID)
      pieceName = piece.name or ns.Pieces.SlotLabel(piece.itemID)
      local info = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(setID)
      local baseInfo = info and info.baseSetID and C_TransmogSets.GetSetInfo(info.baseSetID) or info
      setName = baseInfo and baseInfo.name
      n, t = ns.Pieces.Progress(setID)
    end
  end
  icon = icon or "Interface\\Icons\\INV_Chest_Cloth_17"
  pieceName = pieceName or L["Example piece"]
  setName = setName or L["Example set"]
  if not t or t == 0 then n, t = 5, 8 end

  UI._testComplete = not UI._testComplete
  local complete = UI._testComplete
  if complete then n = t end
  enqueueToast({
    icon = icon,
    line = buildToastLine(pieceName, setName, n, t, complete and 0 or 1),
    complete = complete,
  })
end

--- TRANSMOG_COLLECTION_SOURCE_ADDED handler: if the new appearance belongs to a
--- journal set, toast the piece + set + fresh progress. Suppressed for a few
--- seconds after loading screens (the client replays the event in bursts) and
--- entirely when disabled in the settings.
function UI.NotifyNewPiece(sourceID)
  if not (ns.db and ns.db.toast and ns.db.toast.enabled) then return end
  if ns.toastGraceUntil and GetTime() < ns.toastGraceUntil then return end
  if not (sourceID and C_TransmogSets.GetSetsContainingSourceID) then return end

  local setIDs = C_TransmogSets.GetSetsContainingSourceID(sourceID)
  if not setIDs or #setIDs == 0 then return end

  -- the player's own class's sets are the ones worth naming: in legacy raids
  -- you loot every armor type, and a cloth bracer belongs to another class's
  -- set. A piece belonging ONLY to other classes' sets stays silent unless
  -- the option says otherwise — and then the toast says whose set it is.
  local classBit = 2 ^ (select(3, UnitClass("player")) - 1)
  local totalSets = #setIDs
  local mine, foreign = {}, {}
  for _, id in ipairs(setIDs) do
    local i = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(id)
    if i and bit.band(i.classMask or 0, classBit) ~= 0 then
      mine[#mine + 1] = id
    else
      foreign[#foreign + 1] = id
    end
  end
  local isForeign = false
  if #mine > 0 then
    setIDs = mine
  elseif ns.db.toast.otherClasses and #foreign > 0 then
    setIDs = foreign
    isForeign = true
  else
    return
  end
  local setID = setIDs[1]
  local info = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(setID)
  if not info then return end

  local baseID = info.baseSetID or info.setID
  local baseInfo = (baseID ~= setID) and C_TransmogSets.GetSetInfo(baseID) or info
  local setName = (baseInfo and baseInfo.name) or info.name or "?"

  -- another class's set: say whose it is
  if isForeign then
    local g = ns.Sets.GroupFor and ns.Sets.GroupFor(baseID)
    if g and g.className then
      setName = setName .. " — " .. g.className
    elseif g and g.classCount and g.classCount > 1 then
      setName = setName .. " — " .. string.format(L["%d classes"], g.classCount)
    end
  end

  local si = C_TransmogCollection.GetSourceInfo(sourceID)
  local itemID = si and si.itemID
  local icon = itemID and select(5, C_Item.GetItemInfoInstant(itemID)) or nil

  -- progress is fresh here: Core invalidates the containing sets first
  local n, t = ns.Pieces.Progress(setID)
  local complete = t > 0 and n >= t
  if ns.db.toast.onlyComplete and not complete then return end

  local function push(pieceName)
    enqueueToast({
      icon = icon,
      line = buildToastLine(pieceName or "?", setName, n, t, totalSets - 1),
      complete = complete,
    })
  end

  if si and si.name and si.name ~= "" then
    push(si.name)
  elseif itemID and Item then
    -- name not cached yet: resolve it asynchronously, then toast
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function() push(item:GetItemName()) end)
  else
    push(nil)
  end
end
