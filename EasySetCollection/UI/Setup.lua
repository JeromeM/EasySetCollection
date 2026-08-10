-- Setup.lua — first-install setup wizard: a small standalone window walking
-- through the settings that matter on day one (guidance, notifications,
-- window & minimap), installer-style: Previous / Continue, a step counter,
-- and a "keep the defaults" shortcut. Opens once on a brand new install
-- (ns.firstInstall); `/esc setup` reruns it anytime. Every option it touches
-- also lives in the regular Settings pages — it binds the same db fields.

local ADDON, ns = ...
local L = ns.L
local W = ns.Widgets

ns.Setup = ns.Setup or {}
local Setup = ns.Setup

local FRAME_W, FRAME_H = 460, 380
local PAD = 18

local frame, pageFrames, currentPage

-- --- row factories --------------------------------------------------------------

local function makeCheck(parent, y, label, get, set)
  local row = W.MakeCheckRow(parent, label, FRAME_W - PAD * 2)
  row:SetPoint("TOPLEFT", PAD - 4, y)
  row.refresh = function() W.PaintCheck(row, get()) end
  row:SetScript("OnClick", function()
    set(not get())
    row.refresh()
  end)
  parent.rows[#parent.rows + 1] = row
  return y - 26
end

local function makeNote(parent, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", PAD, y)
  fs:SetWidth(FRAME_W - PAD * 2)
  fs:SetJustifyH("LEFT")
  fs:SetSpacing(2)
  fs:SetTextColor(0.62, 0.62, 0.68)
  fs:SetText(text)
  return y - fs:GetStringHeight() - 14, fs
end

local function makeBody(parent, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", PAD, y)
  fs:SetWidth(FRAME_W - PAD * 2)
  fs:SetJustifyH("LEFT")
  fs:SetSpacing(3)
  fs:SetText(text)
  return y - fs:GetStringHeight() - 14, fs
end

-- label left, [-] value [+] right — the flat stepper used for the window scale
local function makeStepper(parent, y, label, get, set, fmt)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", PAD, y - 5)
  fs:SetText(label)

  local plus = W.MakeButton(parent, "nav")
  plus:SetSize(22, 22)
  plus:SetPoint("TOPRIGHT", -PAD, y)
  plus.label:SetText("+")

  local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  value:SetPoint("RIGHT", plus, "LEFT", -8, 0)
  value:SetTextColor(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3])

  local minus = W.MakeButton(parent, "nav")
  minus:SetSize(22, 22)
  minus:SetPoint("RIGHT", value, "LEFT", -8, 0)
  minus.label:SetText("-")

  local function paint() value:SetText(fmt(get())) end
  minus:SetScript("OnClick", function() set(-1) paint() end)
  plus:SetScript("OnClick", function() set(1) paint() end)
  parent.rows[#parent.rows + 1] = { refresh = paint }
  return y - 30
end

-- --- the pages --------------------------------------------------------------------

local PAGES = {
  {
    title = L["Welcome!"],
    build = function(p)
      local y = -8
      y = makeBody(p, y, L["EasySetCollection browses every transmog set, shows where each piece comes from, and guides you to the farm."])
      y = makeBody(p, y, L["This quick setup covers the essentials. Everything can be changed later in the options — the gear icon in the window, or a right-click on the minimap button."])

      -- path 1: adopt an existing profile — applies it and skips the setup
      y = makeNote(p, y, L["Use an existing profile (this skips the setup):"])
      local pick = W.MakeButton(p, "nav")
      pick:SetSize(200, 22)
      pick:SetPoint("TOPLEFT", PAD, y)
      pick.label:SetText(L["Choose a profile"])
      pick:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu and ns.Profiles) then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
          root:CreateTitle(L["Current profile"])
          for _, name in ipairs(ns.Profiles.List()) do
            root:CreateRadio(name,
              function() return name == ns.Profiles.Current() end,
              function()
                ns.Profiles.Switch(name)
                Setup.Finish()
              end)
          end
        end)
      end)
      y = y - 32

      -- path 2: walk the setup for the named profile (a new name creates it)
      y = makeNote(p, y, L["Or continue to set up this profile (type a new name to create one):"])
      local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
      eb:SetPoint("TOPLEFT", PAD + 6, y)
      eb:SetSize(194, 22)
      eb:SetAutoFocus(false)
      eb:SetMaxLetters(40)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      frame.profileBox = eb
      p.rows[#p.rows + 1] = { refresh = function()
        eb:SetText(ns.Profiles and ns.Profiles.Current() or "")
      end }
    end,
  },
  {
    title = L["Guidance"],
    build = function(p)
      local y = -8
      y = makeNote(p, y, L["When you pick a set to farm, the addon can set a waypoint and point the way."])
      y = makeCheck(p, y, L["Auto-guide (waypoint / action)"],
        function() return ns.db.autoGuide ~= false end,
        function(v) ns.db.autoGuide = v end)
      y = makeCheck(p, y, L["Show the direction arrow"],
        function() return not (ns.db.arrow and ns.db.arrow.enabled == false) end,
        function(v)
          ns.db.arrow = ns.db.arrow or {}
          ns.db.arrow.enabled = v
          if not v and ns.Arrow then ns.Arrow.Hide() end
        end)
    end,
  },
  {
    title = L["Notifications"],
    build = function(p)
      local y = -8
      y = makeNote(p, y, L["Pick what the addon tells you about — when you loot, and when you enter an instance."])
      y = makeCheck(p, y, L["Show a notification when you collect a set piece"],
        function() return ns.db.toast.enabled ~= false end,
        function(v) ns.db.toast.enabled = v end)
      y = makeCheck(p, y, L["Play a sound with the notification"],
        function() return ns.db.toast.sound ~= false end,
        function(v) ns.db.toast.sound = v end)
      y = makeCheck(p, y, L["Announce missing set pieces when entering an instance"],
        function() return ns.db.assist.enabled ~= false end,
        function(v) ns.db.assist.enabled = v end)
      y = makeCheck(p, y, L["Show the announcement as a toast (chat is always used)"],
        function() return ns.db.assist.toast ~= false end,
        function(v) ns.db.assist.toast = v end)
    end,
  },
  {
    title = L["Window"],
    build = function(p)
      local y = -8
      y = makeNote(p, y, L["Size the window to your screen, and keep (or hide) the minimap button."])
      y = makeStepper(p, y, L["Window size"],
        function() return ns.db.windowScale or 1 end,
        function(dir)
          local v = (ns.db.windowScale or 1) + dir * 0.05
          v = math.max(0.7, math.min(1.4, v))
          ns.db.windowScale = v
          if ns.UI and ns.UI.frame then ns.UI.frame:SetScale(v) end
        end,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end)
      y = makeCheck(p, y, L["Show the minimap button"],
        function() return not (ns.db.minimap and ns.db.minimap.hide) end,
        function(v)
          ns.db.minimap = ns.db.minimap or {}
          ns.db.minimap.hide = not v
          if ns.Minimap then
            if not ns.Minimap.button and ns.Minimap.Init then ns.Minimap.Init() end
            if ns.Minimap.button then ns.Minimap.button:SetShown(v) end
          end
        end)
    end,
  },
  {
    title = L["All set!"],
    build = function(p)
      local y = -8
      y = makeBody(p, y, L["Type /esc or click the minimap button to open the window — a short tour will point out the main controls the first time. Good farming!"])
      local btn = W.MakeButton(p, "primary")
      btn:SetSize(200, 24)
      btn:SetPoint("TOPLEFT", PAD, y - 6)
      btn.label:SetText(L["Open the window now"])
      btn:SetScript("OnClick", function()
        Setup.Finish()
        if ns.UI and ns.UI.Show then ns.UI.Show() end
      end)
    end,
  },
}

-- --- the window --------------------------------------------------------------------

local function ensureFrame()
  if frame then return end

  frame = CreateFrame("Frame", "EasySetCollectionSetup", UIParent, "BackdropTemplate")
  -- Esc dismisses the wizard without marking it done (it comes back for
  -- fresh installs; × or Finish end it for good)
  tinsert(UISpecialFrames, "EasySetCollectionSetup")
  frame:SetSize(FRAME_W, FRAME_H)
  frame:SetPoint("CENTER", 0, 60)
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop(W.BD1)
  frame:SetBackdropColor(W.C_BG[1], W.C_BG[2], W.C_BG[3], 0.98)
  frame:SetBackdropBorderColor(W.C_GOLD_BRD[1], W.C_GOLD_BRD[2], W.C_GOLD_BRD[3], 1)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOP", 0, -16)
  frame.title:SetText(W.WHITE .. L["EasySetCollection"] .. "|r")

  frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.subtitle:SetPoint("TOP", 0, -42)
  frame.subtitle:SetTextColor(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3])

  frame.close = W.MakeButton(frame, "nav", "GameFontNormalLarge")
  frame.close:SetSize(22, 22)
  frame.close:SetPoint("TOPRIGHT", -10, -11)
  frame.close.label:SetText("×")
  frame.close:SetScript("OnClick", function() Setup.Finish() end)

  local sep = frame:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(W.C_SEP[1], W.C_SEP[2], W.C_SEP[3], 1)
  sep:SetPoint("TOPLEFT", 1, -64)
  sep:SetPoint("TOPRIGHT", -1, -64)
  sep:SetHeight(1)

  frame.prevBtn = W.MakeButton(frame, "nav")
  frame.prevBtn:SetSize(90, 24)
  frame.prevBtn:SetPoint("BOTTOMLEFT", PAD, 14)
  frame.prevBtn.label:SetText(L["Previous"])
  frame.prevBtn:SetScript("OnClick", function() Setup.ShowPage(currentPage - 1) end)

  frame.counter = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.counter:SetPoint("BOTTOM", 0, 21)
  frame.counter:SetTextColor(0.55, 0.55, 0.60)

  frame.nextBtn = W.MakeButton(frame, "primary")
  frame.nextBtn:SetSize(90, 24)
  frame.nextBtn:SetPoint("BOTTOMRIGHT", -PAD, 14)
  frame.nextBtn:SetScript("OnClick", function()
    -- leaving the welcome page: honour the profile box (a new name creates
    -- and switches, the rest of the setup then configures THAT profile)
    if currentPage == 1 and frame.profileBox and ns.Profiles then
      local name = (frame.profileBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if name ~= "" and name ~= ns.Profiles.Current() then ns.Profiles.Switch(name) end
      frame.profileBox:ClearFocus()
    end
    if currentPage >= #PAGES then Setup.Finish() else Setup.ShowPage(currentPage + 1) end
  end)

  pageFrames = {}
  for i, def in ipairs(PAGES) do
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 0, -72)
    p:SetPoint("BOTTOMRIGHT", 0, 48)
    p.rows = {}
    def.build(p)
    p:Hide()
    pageFrames[i] = p
  end
end

--- Show wizard page `i` and repaint its rows from the current db state.
function Setup.ShowPage(i)
  currentPage = math.max(1, math.min(#PAGES, i))
  for k, p in ipairs(pageFrames) do p:SetShown(k == currentPage) end
  local p = pageFrames[currentPage]
  for _, row in ipairs(p.rows) do row.refresh() end
  frame.subtitle:SetText(PAGES[currentPage].title)
  frame.counter:SetText(("%d/%d"):format(currentPage, #PAGES))
  W.SetBtn(frame.prevBtn, currentPage > 1)
  frame.nextBtn.label:SetText(currentPage == #PAGES and L["Finish"] or L["Continue"])
end

--- Open the wizard (first page). `/esc setup` calls this too.
function Setup.Show()
  ensureFrame()
  frame:Show()
  Setup.ShowPage(1)
end

--- Close the wizard and never auto-open it again (still available via /esc setup).
function Setup.Finish()
  if frame then frame:Hide() end
  if ns.gdb and ns.gdb.onboard then ns.gdb.onboard.wizard = true end
end
