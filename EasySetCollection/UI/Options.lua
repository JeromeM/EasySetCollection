-- Options.lua — the addon's own options window: a left rail of categories and
-- a content pane, in the same flat kit as the rest of the UI. It replaces the
-- game's Settings pages (which only ever offered stacked checkboxes and a red
-- Blizzard skin); the entry registered in Options -> AddOns is a stub that
-- opens this window, because that is where people look for it.
--
-- Pages are declared as data at the bottom of the file: each row is a check,
-- a slider, a note, a button or a section header, so adding a setting is one
-- line and never a layout problem.

local ADDON, ns = ...
local L = ns.L
local W = ns.Widgets

ns.Options = ns.Options or {}
local Options = ns.Options

local FRAME_W, FRAME_H = 720, 540
local RAIL_W = 176           -- category rail on the left
local PAD = 18
local CONTENT_X = RAIL_W + PAD
local CONTENT_W = FRAME_W - CONTENT_X - PAD

local frame, pages, buttons

-- --- row factories ------------------------------------------------------------------
-- Every factory takes (panel, y) and returns the next y. They register a
-- `refresh` closure so reopening the window always shows live values.

local function addHeader(p, y, text)
  local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", 0, y)
  fs:SetText(text)
  fs:SetTextColor(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3])
  local line = p:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(W.C_SEP[1], W.C_SEP[2], W.C_SEP[3], 1)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", 0, y - 18)
  line:SetPoint("TOPRIGHT", 0, y - 18)
  return y - 30
end

local function addNote(p, y, text)
  local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", 0, y)
  fs:SetWidth(CONTENT_W)
  fs:SetJustifyH("LEFT")
  fs:SetSpacing(2)
  fs:SetTextColor(0.62, 0.62, 0.68)
  fs:SetText(text)
  return y - fs:GetStringHeight() - 10
end

local function addCheck(p, y, label, get, set, indent)
  local row = W.MakeCheckRow(p, label, CONTENT_W - (indent or 0))
  row:SetPoint("TOPLEFT", (indent or 0), y)
  row.refresh = function() W.PaintCheck(row, get()) end
  row:SetScript("OnClick", function()
    set(not get())
    Options.Refresh()
  end)
  p.rows[#p.rows + 1] = row
  return y - 24
end

local function addSlider(p, y, label, min, max, step, get, set, fmt)
  local s = W.MakeSlider(p, CONTENT_W, min, max, step, label, fmt)
  s:SetPoint("TOPLEFT", 0, y)
  s.onChanged = set
  s.refresh = function() s:SetValueSilently(get()) end
  p.rows[#p.rows + 1] = s
  return y - 42
end

local function addButton(p, y, label, onClick, kind)
  local b = W.MakeButton(p, kind or "nav", "GameFontNormal")
  b:SetSize(220, 26)
  b:SetPoint("TOPLEFT", 0, y)
  b.label:SetText(label)
  b:SetScript("OnClick", onClick)
  return y - 34, b
end

-- --- the window ---------------------------------------------------------------------

local function selectPage(i)
  for k, p in ipairs(pages) do p.frame:SetShown(k == i) end
  for k, b in ipairs(buttons) do
    b._kind = (k == i) and "primary" or "nav"
    W.Paint(b, false)
  end
  Options.current = i
  Options.Refresh()
end

local function ensureFrame()
  if frame then return end

  frame = CreateFrame("Frame", "EasySetCollectionOptions", UIParent, "BackdropTemplate")
  frame:SetSize(FRAME_W, FRAME_H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetBackdrop(W.BD1)
  frame:SetBackdropColor(W.C_BG[1], W.C_BG[2], W.C_BG[3], 0.98)
  frame:SetBackdropBorderColor(W.C_GOLD_BRD[1], W.C_GOLD_BRD[2], W.C_GOLD_BRD[3], 1)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "EasySetCollectionOptions")   -- Esc closes it…
  W.EscPriority(frame)                                   -- …and only it

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", PAD, -16)
  frame.title:SetText(W.AMBER .. L["EasySetCollection"] .. "|r")

  frame.version = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.version:SetPoint("LEFT", frame.title, "RIGHT", 8, -1)
  local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "?"
  frame.version:SetText(W.GREY .. "v" .. ver .. "|r")

  frame.close = W.MakeButton(frame, "nav", "GameFontNormalLarge")
  frame.close:SetSize(22, 22)
  frame.close:SetPoint("TOPRIGHT", -10, -11)
  frame.close.label:SetText("×")
  frame.close:SetScript("OnClick", function() frame:Hide() end)

  local sep = frame:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(W.C_SEP[1], W.C_SEP[2], W.C_SEP[3], 1)
  sep:SetPoint("TOPLEFT", 1, -46)
  sep:SetPoint("TOPRIGHT", -1, -46)
  sep:SetHeight(1)

  -- the rail gets a panel background so the two zones read as separate
  local rail = W.MakePanel(frame)
  rail:SetPoint("TOPLEFT", 1, -47)
  rail:SetPoint("BOTTOMLEFT", 1, 1)
  rail:SetWidth(RAIL_W)
  rail:SetBackdropColor(0.11, 0.11, 0.14, 1)
  rail:SetBackdropBorderColor(0, 0, 0, 0)

  local vsep = frame:CreateTexture(nil, "ARTWORK")
  vsep:SetColorTexture(W.C_SEP[1], W.C_SEP[2], W.C_SEP[3], 1)
  vsep:SetWidth(1)
  vsep:SetPoint("TOPLEFT", RAIL_W + 1, -47)
  vsep:SetPoint("BOTTOMLEFT", RAIL_W + 1, 1)

  pages, buttons = {}, {}
  local y = -58
  for i, def in ipairs(Options.PAGES) do
    local b = W.MakeButton(frame, "nav", "GameFontNormal")
    b:SetSize(RAIL_W - 16, 30)
    b:SetPoint("TOPLEFT", 8, y)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetText(def.title)
    b:SetScript("OnClick", function() selectPage(i) end)
    buttons[i] = b
    y = y - 34

    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", CONTENT_X, -60)
    p:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    p.rows = {}
    def.build(p)
    p:Hide()
    pages[i] = { frame = p, def = def }
  end
end

--- Repaint every row of the visible page from the current profile.
function Options.Refresh()
  if not (frame and frame:IsShown() and Options.current) then return end
  for _, row in ipairs(pages[Options.current].frame.rows) do
    if row.refresh then row.refresh() end
  end
end

--- Open the options window (on the last page you were looking at).
function Options.Show()
  ensureFrame()
  frame:Show()
  selectPage(Options.current or 1)
end

function Options.Toggle()
  ensureFrame()
  if frame:IsShown() then frame:Hide() else Options.Show() end
end

-- --- pages ---------------------------------------------------------------------------

Options.PAGES = {
  {
    title = L["Window"],
    build = function(p)
      local y = addHeader(p, 0, L["Window"])
      y = addSlider(p, y, L["Window size"], 0.6, 1.6, 0.05,
        function() return ns.db.windowScale or 1 end,
        function(v)
          ns.db.windowScale = v
          if ns.UI.frame then ns.UI.frame:SetScale(v) end
        end)
      y = addCheck(p, y, L["Lock the window position"],
        function() return ns.db.locked == true end,
        function(v) ns.db.locked = v end)
      y = addCheck(p, y, L["Show the minimap button"],
        function() return not (ns.db.minimap and ns.db.minimap.hide) end,
        function(v)
          ns.db.minimap = ns.db.minimap or {}
          ns.db.minimap.hide = not v
          if ns.Minimap then
            if not ns.Minimap.button and ns.Minimap.Init then ns.Minimap.Init() end
            if ns.Minimap.button then ns.Minimap.button:SetShown(v) end
          end
        end)

      y = y - 8
      y = addHeader(p, y, L["Item tooltips"])
      y = addNote(p, y, L["Hovering a set piece anywhere in the game tells you which set it belongs to, and how far along you are."])
      y = addCheck(p, y, L["Show set membership on item tooltips"],
        function() return ns.db.tooltip.enabled ~= false end,
        function(v) ns.db.tooltip.enabled = v end)
      y = addCheck(p, y, L["Include out-of-journal sets"],
        function() return ns.db.tooltip.extras ~= false end,
        function(v) ns.db.tooltip.extras = v end, 20)
    end,
  },
  {
    title = L["Guidance"],
    build = function(p)
      local y = addHeader(p, 0, L["Guidance"])
      y = addCheck(p, y, L["Auto-guide (waypoint / action)"],
        function() return ns.db.autoGuide ~= false end,
        function(v) ns.db.autoGuide = v end)
      y = addCheck(p, y, L["Show the direction arrow"],
        function() return not (ns.db.arrow and ns.db.arrow.enabled == false) end,
        function(v)
          ns.db.arrow = ns.db.arrow or {}
          ns.db.arrow.enabled = v
          if not v and ns.Arrow then ns.Arrow.Hide() end
        end)
      y = addCheck(p, y, L["Lock the arrow position"],
        function() return ns.db.arrow and ns.db.arrow.locked == true end,
        function(v)
          ns.db.arrow = ns.db.arrow or {}
          ns.db.arrow.locked = v
          if ns.Arrow and ns.Arrow.frame then ns.Arrow.frame:EnableMouse(not v) end
        end)
      y = addCheck(p, y, L["Use metric distance (m / km)"],
        function() return ns.db.arrow and ns.db.arrow.metric == true end,
        function(v)
          ns.db.arrow = ns.db.arrow or {}
          ns.db.arrow.metric = v
        end)

      y = y - 8
      y = addHeader(p, y, L["Arrow"])
      y = addSlider(p, y, L["Arrow size"], 0.5, 2.5, 0.1,
        function() return (ns.db.arrow and ns.db.arrow.scale) or 1 end,
        function(v)
          ns.db.arrow = ns.db.arrow or {}
          ns.db.arrow.scale = v
          if ns.Arrow and ns.Arrow.ApplyScale then ns.Arrow.ApplyScale() end
        end)
      y = addSlider(p, y, L["Text size"], 0.5, 2.5, 0.1,
        function() return (ns.db.arrow and ns.db.arrow.textScale) or 1 end,
        function(v)
          ns.db.arrow = ns.db.arrow or {}
          ns.db.arrow.textScale = v
          if ns.Arrow and ns.Arrow.ApplyScale then ns.Arrow.ApplyScale() end
        end)
    end,
  },
  {
    title = L["Notifications"],
    build = function(p)
      local y = addHeader(p, 0, L["When you loot a set piece"])
      y = addCheck(p, y, L["Show a notification when you collect a set piece"],
        function() return ns.db.toast.enabled ~= false end,
        function(v) ns.db.toast.enabled = v end)
      y = addCheck(p, y, L["Play a sound with the notification"],
        function() return ns.db.toast.sound ~= false end,
        function(v) ns.db.toast.sound = v end, 20)
      y = addCheck(p, y, L["Only notify when a set becomes complete"],
        function() return ns.db.toast.onlyComplete == true end,
        function(v) ns.db.toast.onlyComplete = v end, 20)
      y = addCheck(p, y, L["Also notify for other classes' sets"],
        function() return ns.db.toast.otherClasses == true end,
        function(v) ns.db.toast.otherClasses = v end, 20)

      y = y - 8
      y = addHeader(p, y, L["What the notification says"])
      y = addCheck(p, y, L["Show the piece name"],
        function() return ns.db.toast.showPiece ~= false end,
        function(v) ns.db.toast.showPiece = v end)
      y = addCheck(p, y, L["Show the set name"],
        function() return ns.db.toast.showSet ~= false end,
        function(v) ns.db.toast.showSet = v end)
      y = addCheck(p, y, L["Show the set progress"],
        function() return ns.db.toast.showProgress ~= false end,
        function(v) ns.db.toast.showProgress = v end)
      y = addCheck(p, y, L["Mention other sets containing the piece"],
        function() return ns.db.toast.showOtherSets ~= false end,
        function(v) ns.db.toast.showOtherSets = v end)
      y = addButton(p, y + 2, L["Test"], function() ns.UI.TestToast() end)

      y = y - 8
      y = addHeader(p, y, L["In-instance assistant"])
      y = addCheck(p, y, L["Announce missing set pieces when entering an instance"],
        function() return ns.db.assist.enabled ~= false end,
        function(v) ns.db.assist.enabled = v end)
      y = addCheck(p, y, L["Show the announcement as a toast (chat is always used)"],
        function() return ns.db.assist.toast ~= false end,
        function(v) ns.db.assist.toast = v end, 20)
      y = addCheck(p, y, L["Also announce out-of-journal sets"],
        function() return ns.db.assist.announceExtras == true end,
        function(v) ns.db.assist.announceExtras = v end, 20)
    end,
  },
  {
    title = L["Profiles"],
    build = function(p)
      local y = addHeader(p, 0, L["Profiles"])
      y = addNote(p, y, L["Profiles hold every setting of the addon; each character picks the one it uses. Tracked sets stay per-character."])

      local P = ns.Profiles
      local curBtn
      y, curBtn = addButton(p, y, "", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
          root:CreateTitle(L["Current profile"])
          for _, name in ipairs(P.List()) do
            root:CreateRadio(name,
              function() return name == P.Current() end,
              function() P.Switch(name) Options.Refresh() end)
          end
        end)
      end, "primary")
      W.AddDropdownArrow(curBtn)
      curBtn.label:ClearAllPoints()
      curBtn.label:SetPoint("LEFT", 8, 0)
      curBtn.label:SetPoint("RIGHT", -16, 0)
      curBtn.label:SetJustifyH("LEFT")
      p.rows[#p.rows + 1] = { refresh = function() curBtn.label:SetText(P.Current()) end }

      -- new profile: name box + create
      local nameLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      nameLabel:SetPoint("TOPLEFT", 0, y - 4)
      nameLabel:SetText(L["New profile"])
      y = y - 22

      local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
      eb:SetPoint("TOPLEFT", 6, y)
      eb:SetSize(214, 24)
      eb:SetAutoFocus(false)
      eb:SetMaxLetters(40)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

      local createBtn = W.MakeButton(p, "primary", "GameFontNormal")
      createBtn:SetSize(110, 26)
      createBtn:SetPoint("LEFT", eb, "RIGHT", 10, 0)
      createBtn.label:SetText(L["Create"])
      local function create()
        local name = (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return end
        P.Switch(name)
        eb:SetText("")
        eb:ClearFocus()
        Options.Refresh()
      end
      createBtn:SetScript("OnClick", create)
      eb:SetScript("OnEnterPressed", create)
      y = y - 38

      local copyBtn
      y, copyBtn = addButton(p, y, L["Copy from"], function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
          root:CreateTitle(L["Copy from"])
          for _, name in ipairs(P.List()) do
            if name ~= P.Current() then
              root:CreateButton(name, function() P.CopyFrom(name) Options.Refresh() end)
            end
          end
        end)
      end)
      W.AddDropdownArrow(copyBtn)

      local resetBtn
      y, resetBtn = addButton(p, y, L["Reset profile"], function()
        P.Reset()
        Options.Refresh()
      end, "warn")

      local delBtn
      y, delBtn = addButton(p, y, L["Delete a profile"], function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
          root:CreateTitle(L["Delete a profile"])
          for _, name in ipairs(P.List()) do
            if name ~= "Default" and name ~= P.Current() then
              root:CreateButton(name, function() P.Delete(name) Options.Refresh() end)
            end
          end
        end)
      end, "warn")
      W.AddDropdownArrow(delBtn)
    end,
  },
  {
    title = L["About"],
    build = function(p)
      local y = addHeader(p, 0, L["About"])
      y = addNote(p, y, L["Browse every transmog set with per-piece sources, see what you still miss, and let the addon point you to the raid, dungeon or zone that drops it."])

      local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "?"
      local info = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      info:SetPoint("TOPLEFT", 0, y)
      info:SetJustifyH("LEFT")
      info:SetSpacing(4)
      info:SetText(L["Version"] .. ": " .. W.WHITE .. ver .. "|r\n"
        .. L["Author"] .. ": " .. W.WHITE .. "Grommey|r")
      y = y - 44

      local reportLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      reportLabel:SetPoint("TOPLEFT", 0, y)
      reportLabel:SetText(L["Report a problem"] .. ":")
      reportLabel:SetTextColor(0.62, 0.62, 0.68)
      y = y - 20

      -- read-only, auto-selecting box: WoW cannot open a browser
      local url = "https://github.com/JeromeM/EasySetCollection/issues"
      local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
      eb:SetPoint("TOPLEFT", 6, y)
      eb:SetSize(CONTENT_W - 12, 22)
      eb:SetAutoFocus(false)
      eb:SetFontObject(ChatFontNormal)
      eb:SetText(url)
      eb:SetCursorPosition(0)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
      eb:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); self:SetCursorPosition(0) end)
      eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
      eb:SetScript("OnChar", function(self) self:SetText(url); self:HighlightText() end)
      y = y - 40

      y = addButton(p, y, L["Rerun the first-time setup"], function()
        if ns.Setup then ns.Setup.Show() end
      end)
    end,
  },
}
