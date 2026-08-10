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
  -- Esc closes the window like any standard panel (user request). The game
  -- calls Hide() directly, so the open-state bookkeeping lives in OnHide.
  tinsert(UISpecialFrames, "EasySetCollectionFrame")
  f:HookScript("OnHide", function()
    if ns.db then ns.db.shown = false end
    if ns.FilterPanel and ns.FilterPanel.Hide then ns.FilterPanel.Hide() end
    if ns.Travel then ns.Travel.Hide() end
  end)
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
  f.sortBtn:SetScript("OnEnter", function(self)
    W.Paint(self, true)
    W.OwnTooltip(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Sort by"])
    if (ns.db.sort or "expansion") == "expansion" and ns.db.favoritesFirst ~= false then
      GameTooltip:AddLine(L["Favorite sets are listed first."], 0.96, 0.72, 0.32, true)
    end
    GameTooltip:Show()
  end)
  f.sortBtn:SetScript("OnLeave", function(self)
    W.Paint(self, false)
    GameTooltip:Hide()
  end)

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
  -- a star in front of the mode says favorites float to the top (the sort
  -- menu holds the toggle) — WoW fonts have no ★ glyph, hence the texture
  local star = (mode == "expansion" and ns.db.favoritesFirst ~= false)
    and "|TInterface\\Common\\FavoritesIcon:12:12:0:0|t" or ""
  f.sortBtn.label:SetText(star .. W.GREY .. (names[mode] or "?") .. "|r")
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

--- Close the window. The bookkeeping lives in the frame's OnHide hook so that
--- Esc (UISpecialFrames calls Hide directly) takes the exact same path.
--- The waypoint + arrow deliberately survive closing the window: they are
--- dismissed from the arrow's right-click menu ("Close") or by guiding elsewhere.
function UI.Hide()
  if UI.frame then
    UI.frame:Hide()
  elseif ns.db then
    ns.db.shown = false
  end
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
  author:SetText(L["Author"] .. ": |cffffffffGrommey|r")

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

  -- every actual setting lives in our own window; this page just leads there
  local open = W.MakeButton(f, "primary", "GameFontNormal")
  open:SetSize(240, 28)
  open:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", -6, -24)
  open.label:SetText(L["Open the options"])
  open:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel.Hide then SettingsPanel:Hide() end
    if ns.Options then ns.Options.Show() end
  end)

  f.OnCommit = function() end
  f.OnDefault = function() end
  f.OnRefresh = function() end

  return f
end

--- Register a single entry in the game's Settings panel (AddOns list). It only
--- holds a button that opens OUR options window: people look for the addon
--- there, but every actual setting lives in UI/Options.lua.
function UI.BuildSettings()
  if UI.settingsCategory then return end
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  UI.settingsCategory = Settings.RegisterCanvasLayoutCategory(UI.BuildAboutPanel(), L["EasySetCollection"])
  Settings.RegisterAddOnCategory(UI.settingsCategory)
end


--- Open the addon's own options window (UI/Options.lua).
function UI.OpenSettings()
  if ns.Options then ns.Options.Show() end
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
    -- right-click dismisses (and surfaces the next queued toast so a loot
    -- burst can be scanned one flick at a time); left-click opens the window
    -- on the set the toast is about
    p:EnableMouse(true)
    p:SetScript("OnMouseUp", function(self, btn)
      if self.timer then self.timer:Cancel() end
      local data = self.data
      self:Hide()
      showNextToast()
      if btn ~= "RightButton" and data and data.baseSetID then
        local g = ns.Sets.GroupFor and ns.Sets.GroupFor(data.baseSetID)
        if g then
          UI.Show()
          ns.SetList.Select(g)
          if ns.SetList.ScrollTo then ns.SetList.ScrollTo(g.baseSetID) end
        end
      end
    end)
    UI.toast = p
  end
  p.data = data

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
function UI.NotifyAssist(title, line, icon, setID)
  local baseID
  if setID then
    if setID < 0 then
      baseID = setID   -- synthetic set: baseSetID == setID
    else
      local i = C_TransmogSets.GetSetInfo and C_TransmogSets.GetSetInfo(setID)
      baseID = i and (i.baseSetID or i.setID) or nil
    end
  end
  enqueueToast({
    title = W.AMBER .. (title or "") .. "|r",
    line = line,
    icon = icon or "Interface\\Icons\\INV_Misc_Map01",
    silent = true,
    baseSetID = baseID,
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
    baseSetID = ns.SetList and ns.SetList.selected or nil,
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
      baseSetID = baseID,   -- left-clicking the toast opens the set
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
