-- Onboard.lua — first-open tour: three sequential bubbles spotlighting the
-- window's key controls (search, Suggest, options), so a fresh install gets
-- discovered and configured without reading anything else. Shown once
-- (resumes at the saved step if the window closes mid-tour), skippable.

local ADDON, ns = ...
local L = ns.L
local W = ns.Widgets

ns.Onboard = ns.Onboard or {}
local Onboard = ns.Onboard

-- each step: the control to spotlight, what to say, how to hang the bubble
local STEPS = {
  {
    target = function(f) return f.search end,
    text = L["Every set of every class is in here: search, then narrow down with the class and filter buttons."],
    point = "TOPLEFT", rel = "BOTTOMLEFT",
  },
  {
    target = function(f) return f.suggestBtn end,
    text = L["Suggest picks the closest set you can still farm this week and guides you to it. Right-click to choose among the best candidates."],
    point = "TOPLEFT", rel = "BOTTOMLEFT",
  },
  {
    target = function(f) return f.gear end,
    text = L["Tune the in-instance assistant, the loot toast and the guidance arrow in the options."],
    point = "TOPRIGHT", rel = "BOTTOMRIGHT",
  },
}

local bubble, highlight

local function ensureFrames(parent)
  if bubble then return end

  -- pulsing 2px outline around the spotlighted control
  highlight = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
  highlight:SetBackdropBorderColor(W.C_AMBER_TX[1], W.C_AMBER_TX[2], W.C_AMBER_TX[3], 1)
  highlight:SetFrameStrata("DIALOG")
  highlight.pulse = highlight:CreateAnimationGroup()
  highlight.pulse:SetLooping("BOUNCE")
  local a = highlight.pulse:CreateAnimation("Alpha")
  a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.7)

  bubble = W.MakePanel(parent)
  bubble:SetFrameStrata("DIALOG")
  bubble:SetWidth(280)
  bubble:SetBackdropColor(W.C_BG[1], W.C_BG[2], W.C_BG[3], 0.98)
  bubble:SetBackdropBorderColor(W.C_GOLD_BRD[1], W.C_GOLD_BRD[2], W.C_GOLD_BRD[3], 1)

  bubble.text = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bubble.text:SetPoint("TOPLEFT", 14, -12)
  bubble.text:SetWidth(252)
  bubble.text:SetJustifyH("LEFT")
  bubble.text:SetSpacing(2)

  bubble.skipBtn = W.MakeButton(bubble, "nav")
  bubble.skipBtn:SetSize(60, 20)
  bubble.skipBtn:SetPoint("BOTTOMLEFT", 10, 10)
  bubble.skipBtn.label:SetText(L["Skip"])
  bubble.skipBtn:SetScript("OnClick", Onboard.Finish)

  bubble.counter = bubble:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bubble.counter:SetPoint("BOTTOM", 0, 13)
  bubble.counter:SetTextColor(0.55, 0.55, 0.60)

  bubble.nextBtn = W.MakeButton(bubble, "primary")
  bubble.nextBtn:SetSize(76, 20)
  bubble.nextBtn:SetPoint("BOTTOMRIGHT", -10, 10)
  bubble.nextBtn:SetScript("OnClick", function()
    local i = (ns.gdb.onboard and ns.gdb.onboard.step) or 1
    if i >= #STEPS then Onboard.Finish() else Onboard.ShowStep(i + 1) end
  end)
end

--- Show tour step `i`, spotlighting its control; out-of-range ends the tour.
function Onboard.ShowStep(i)
  local f = ns.UI and ns.UI.frame
  if not f or not f:IsShown() then return end
  local step = STEPS[i]
  local target = step and step.target(f)
  if not target then return Onboard.Finish() end

  ensureFrames(f)
  ns.gdb.onboard.step = i

  bubble.text:SetText(step.text)
  bubble.counter:SetText(("%d/%d"):format(i, #STEPS))
  bubble.nextBtn.label:SetText(i == #STEPS and L["Got it"] or L["Next"])
  bubble:ClearAllPoints()
  bubble:SetPoint(step.point, target, step.rel, 0, -10)
  bubble:SetHeight(12 + bubble.text:GetStringHeight() + 12 + 20 + 10)

  highlight:ClearAllPoints()
  highlight:SetPoint("TOPLEFT", target, "TOPLEFT", -4, 4)
  highlight:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 4, -4)

  bubble:Show()
  highlight:Show()
  highlight.pulse:Play()
end

--- End the tour for good (Skip, last step, or a vanished target).
function Onboard.Finish()
  if bubble then bubble:Hide() end
  if highlight then highlight.pulse:Stop(); highlight:Hide() end
  local ob = ns.gdb and ns.gdb.onboard
  if ob then ob.done = true; ob.step = nil end
end

--- Entry point, called on every UI.Show: runs (or resumes) the tour until done.
function Onboard.MaybeStart()
  local ob = ns.gdb and ns.gdb.onboard
  if not ob or ob.done then return end
  Onboard.ShowStep(ob.step or 1)
end
