-- Widgets.lua — the shared flat design kit: 1px WHITE8x8 backdrop, palette,
-- button/panel/check-row factories, plus a debounced search box and a
-- progress bar.

local ADDON, ns = ...
ns.Widgets = ns.Widgets or {}
local W = ns.Widgets

-- text colors (escape codes)
W.AMBER = "|cfff0a94a"
W.GREY  = "|cff8a8a8a"
W.WHITE = "|cffe9e9ec"
W.GREEN = "|cff62d06e"

-- rgb accents
W.C_BG        = { 0.086, 0.090, 0.106 }
W.C_BORDER    = { 0.22, 0.22, 0.27 }
W.C_SEP       = { 0.19, 0.19, 0.23 }
W.C_PANEL_BG  = { 0.15, 0.15, 0.18 }
W.C_PANEL_BRD = { 0.30, 0.30, 0.36 }
W.C_GOLD_BRD  = { 0.55, 0.40, 0.14 }
W.C_AMBER_TX  = { 0.96, 0.72, 0.32 }
W.C_EPIC      = { 0.64, 0.21, 0.93 }
W.C_RARE      = { 0.12, 0.55, 0.90 }
W.C_GREEN     = { 0.38, 0.82, 0.43 }

-- 1px flat backdrop, fully colorable
W.BD1 = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
}

local BTN_COLORS = {
  primary = { bg = {0.24,0.17,0.05}, hov = {0.34,0.25,0.08}, brd = {0.85,0.65,0.25}, tx = {1.0,0.82,0.40} },
  warn    = { bg = {0.20,0.14,0.04}, hov = {0.28,0.20,0.06}, brd = {0.80,0.55,0.15}, tx = {1.0,0.78,0.35} },
  nav     = { bg = {0.15,0.15,0.18}, hov = {0.22,0.22,0.27}, brd = {0.30,0.30,0.36}, tx = {0.86,0.86,0.90} },
}

--- Repaint a flat button to reflect its kind and enabled/hover state.
function W.Paint(b, hover)
  local c = BTN_COLORS[b._kind] or BTN_COLORS.nav
  local on = b:IsEnabled()
  local a = on and 1 or 0.4
  local bg = (hover and on) and c.hov or c.bg
  b:SetBackdropColor(bg[1], bg[2], bg[3], on and 0.95 or 0.5)
  b:SetBackdropBorderColor(c.brd[1], c.brd[2], c.brd[3], a)
  b.label:SetTextColor(c.tx[1], c.tx[2], c.tx[3], a)
end

--- Enable or disable a flat button and repaint it accordingly.
function W.SetBtn(b, enabled)
  if enabled then b:Enable() else b:Disable() end
  W.Paint(b, false)
end

--- Create a flat, colorable button with a centered label and hover repainting.
---@param kind string  a BTN_COLORS key ("primary" | "warn" | "nav")
---@param font string?  font object name for the label (default "GameFontNormalSmall")
function W.MakeButton(parent, kind, font)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetBackdrop(W.BD1)
  b.label = b:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
  b.label:SetPoint("CENTER")
  b.label:SetJustifyH("CENTER")
  b._kind = kind
  b:SetScript("OnEnter", function(s) W.Paint(s, true) end)
  b:SetScript("OnLeave", function(s) W.Paint(s, false) end)
  W.Paint(b, false)
  return b
end

--- Create a flat, colorable panel frame using the 1px backdrop.
function W.MakePanel(parent)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  p:SetBackdrop(W.BD1)
  return p
end

-- flat check row (checkbox + label), matching the window's look
local C_CHK_ON = { 0.24, 0.17, 0.05 }   -- amber fill when ticked
local C_CHK_OFF = { 0.12, 0.12, 0.15 }

--- Repaint a check row to reflect its ticked state.
function W.PaintCheck(row, checked)
  local bg = checked and C_CHK_ON or C_CHK_OFF
  row.box:SetBackdropColor(bg[1], bg[2], bg[3], 0.95)
  local brd = checked and W.C_GOLD_BRD or W.C_PANEL_BRD
  row.box:SetBackdropBorderColor(brd[1], brd[2], brd[3], 1)
  row.check:SetShown(checked)
  if checked then
    row.text:SetTextColor(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3])
  else
    row.text:SetTextColor(0.55, 0.55, 0.60)
  end
end

--- Create a flat check row (clickable checkbox + label) in a parent.
function W.MakeCheckRow(parent, label, width)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(width, 20)
  row.box = W.MakePanel(row)
  row.box:SetSize(15, 15)
  row.box:SetPoint("LEFT", 4, 0)
  row.check = row.box:CreateTexture(nil, "OVERLAY")
  row.check:SetPoint("CENTER")
  row.check:SetSize(16, 16)
  row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.text:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetText(label)
  return row
end

--- Create a flat search box: a BD1 panel skinning an EditBox, with placeholder
--- text, a clear (×) button and a debounced change callback.
---@param width number  total widget width (height is 24)
---@param placeholder string  dim text shown while empty and unfocused
---@param onChanged function  receives the new text ~150ms after the last keystroke
function W.MakeSearchBox(parent, width, placeholder, onChanged)
  local holder = W.MakePanel(parent)
  holder:SetSize(width, 24)
  holder:SetBackdropColor(0.06, 0.065, 0.08, 1)
  holder:SetBackdropBorderColor(W.C_PANEL_BRD[1], W.C_PANEL_BRD[2], W.C_PANEL_BRD[3], 1)

  local eb = CreateFrame("EditBox", nil, holder)
  eb:SetPoint("TOPLEFT", 8, 0)
  eb:SetPoint("BOTTOMRIGHT", -22, 0)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetMaxLetters(60)

  local ph = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", 2, 0)
  ph:SetText(placeholder)

  local clear = W.MakeButton(holder, "nav")
  clear:SetSize(16, 16)
  clear:SetPoint("RIGHT", -4, 0)
  clear.label:SetText("×")
  clear:Hide()

  local pending
  local function fire(txt)
    if pending then pending:Cancel(); pending = nil end
    onChanged(txt)
  end
  eb:SetScript("OnTextChanged", function(s, userInput)
    local txt = s:GetText() or ""
    ph:SetShown(txt == "" and not s:HasFocus())
    clear:SetShown(txt ~= "")
    if not userInput then return end
    if pending then pending:Cancel() end
    pending = C_Timer.NewTimer(0.15, function()
      pending = nil
      onChanged(eb:GetText() or "")
    end)
  end)
  eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
  eb:SetScript("OnEditFocusGained", function()
    ph:Hide()
    holder:SetBackdropBorderColor(W.C_GOLD_BRD[1], W.C_GOLD_BRD[2], W.C_GOLD_BRD[3], 1)
  end)
  eb:SetScript("OnEditFocusLost", function(s)
    ph:SetShown((s:GetText() or "") == "")
    holder:SetBackdropBorderColor(W.C_PANEL_BRD[1], W.C_PANEL_BRD[2], W.C_PANEL_BRD[3], 1)
  end)
  clear:SetScript("OnClick", function()
    eb:SetText("")
    eb:ClearFocus()
    fire("")
  end)

  holder.editBox = eb
  return holder
end

--- Anchor GameTooltip to one of our frames with a NORMALIZED scale. The
--- tooltip inherits its owner's effective scale, and our window has its own
--- user-configurable scale — without this, our tooltips render bigger or
--- smaller than every other tooltip in the UI.
function W.OwnTooltip(owner, anchor)
  GameTooltip:SetScale(1)   -- reset any previous correction
  GameTooltip:SetOwner(owner, anchor)
  local eff = GameTooltip:GetEffectiveScale()
  local want = UIParent:GetEffectiveScale()
  if eff and eff > 0 and want and math.abs(eff - want) > 0.001 then
    GameTooltip:SetScale(GameTooltip:GetScale() * want / eff)
    GameTooltip._escScaled = true
    -- restore the scale when OUR tooltip hides: GameTooltip is shared, and a
    -- lingering correction rescales every other tooltip in the game
    if not W._tooltipHooked then
      W._tooltipHooked = true
      GameTooltip:HookScript("OnHide", function(tt)
        if tt._escScaled then
          tt._escScaled = nil
          tt:SetScale(1)
        end
      end)
    end
  end
  return GameTooltip
end

--- Add a small down-pointing dropdown arrow at the right edge of a flat button
--- (a rotated texture — the ▾ glyph is missing from WoW's fonts and renders as
--- a placeholder square).
function W.AddDropdownArrow(btn)
  local tex = btn:CreateTexture(nil, "OVERLAY")
  tex:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  tex:SetSize(12, 12)
  tex:SetPoint("RIGHT", -3, 0)
  tex:SetRotation(-math.pi / 2)
  tex:SetVertexColor(0.75, 0.75, 0.8)
  btn.arrow = tex
  return tex
end

--- Flat slider matching the kit: a 1px track, a draggable amber grip, a label
--- on the left and the formatted value on the right. `onChanged` fires live
--- while dragging; `fmt` renders the value (defaults to a percentage).
---@param width number  total widget width (height is 34 with its label)
function W.MakeSlider(parent, width, min, max, step, label, fmt)
  fmt = fmt or function(v) return math.floor(v * 100 + 0.5) .. "%" end
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(width, 34)

  s.label = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  s.label:SetPoint("TOPLEFT", 0, 0)
  s.label:SetText(label)
  s.label:SetTextColor(0.86, 0.86, 0.90)

  s.value = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  s.value:SetPoint("TOPRIGHT", 0, 0)
  s.value:SetTextColor(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3])

  local track = s:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(W.C_PANEL_BRD[1], W.C_PANEL_BRD[2], W.C_PANEL_BRD[3], 1)
  track:SetHeight(2)
  track:SetPoint("BOTTOMLEFT", 0, 6)
  track:SetPoint("BOTTOMRIGHT", 0, 6)

  local fill = s:CreateTexture(nil, "OVERLAY")
  fill:SetColorTexture(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3], 1)
  fill:SetHeight(2)
  fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)

  -- the grip is a real Slider so dragging, clicking the track and the mouse
  -- wheel all behave the way players expect
  local slider = CreateFrame("Slider", nil, s)
  slider:SetOrientation("HORIZONTAL")
  slider:SetPoint("BOTTOMLEFT", 0, 0)
  slider:SetPoint("BOTTOMRIGHT", 0, 0)
  slider:SetHeight(14)
  slider:SetMinMaxValues(min, max)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  slider:EnableMouseWheel(true)

  local grip = slider:CreateTexture(nil, "OVERLAY")
  grip:SetColorTexture(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3], 1)
  grip:SetSize(6, 14)
  slider:SetThumbTexture(grip)

  slider:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / step + 0.5) * step
    s.value:SetText(fmt(v))
    local pct = (max > min) and ((v - min) / (max - min)) or 0
    fill:SetWidth(math.max(0.01, width * pct))
    if s.onChanged and not s._quiet then s.onChanged(v) end
  end)
  slider:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(self:GetValue() + delta * step)
  end)

  --- Set the displayed value without firing onChanged (initial paint).
  function s:SetValueSilently(v)
    s._quiet = true
    slider:SetValue(v)
    s._quiet = false
  end
  s.slider = slider
  return s
end

--- Create a flat progress bar with an optional centered "n/t" text.
--- Call bar:SetProgress(n, t, rgb) to update fill and text.
function W.MakeProgressBar(parent, width, height)
  local bar = W.MakePanel(parent)
  bar:SetSize(width, height)
  bar:SetBackdropColor(0.06, 0.065, 0.08, 1)
  bar:SetBackdropBorderColor(W.C_PANEL_BRD[1], W.C_PANEL_BRD[2], W.C_PANEL_BRD[3], 1)
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT", 1, -1)
  bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.text:SetPoint("CENTER")

  function bar:SetProgress(n, t, rgb)
    local frac = (t and t > 0) and math.min(1, n / t) or 0
    rgb = rgb or W.C_AMBER_TX
    self.fill:SetWidth(math.max(0.01, (self:GetWidth() - 2) * frac))
    self.fill:SetColorTexture(rgb[1], rgb[2], rgb[3], 0.9)
  end
  return bar
end
