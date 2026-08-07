-- Arrow.lua — our own on-screen "point me there" arrow. It renders ONLY
-- direction + distance to the destination that Waypoint handed us; routing
-- (which portal / item / hop to take) stays with FarstriderLib (Nav.lua).
-- No external library: player and target world positions both come from the
-- native C_Map API, and the heading uses GetPlayerFacing().
--
-- Angle convention (must match GetPlayerFacing, which is radians counter-clockwise
-- from north): we replicate HereBeDragons' GetWorldVector math on native world
-- coordinates. C_Map.GetWorldPosFromMapPos returns a vector whose first component
-- is the "north" axis and second is the "west" axis, so the bearing is
-- atan2(-deltaNorth, deltaWest) normalised into [0, 2pi) CCW-from-north.

local ADDON, ns = ...
ns.Arrow = ns.Arrow or {}
local Arrow = ns.Arrow
local L = ns.L

local TWO_PI = math.pi * 2
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local sqrt = math.sqrt

-- Our own grayscale 3D arrow, tinted at runtime by DISTANCE. It's a SPRITE SHEET:
-- one pre-rendered 3D frame per direction (fixed camera) so the perspective holds
-- in every direction. Frame 0 = pointing away (up). We pick a frame from the angle
-- instead of rotating a single texture.
local ARROW_TEXTURE = "Interface\\AddOns\\EasySetCollection\\Media\\arrow.tga"
local COLS, ROWS, FRAMES = 8, 8, 64          -- sprite grid (must match gen-arrow.py)
Arrow.SPIN = 1                               -- flip to -1 if it turns the wrong way
local FAR_YARDS = 1500     -- at/beyond this the colour is fully red
local GREEN_YARDS = 30     -- at/within this the colour is fully green (well before it hides)

--- Point the sprite-sheet arrow at a screen-relative angle (radians, CCW from up)
--- by selecting the matching pre-rendered 3D frame.
local function setFrame(tex, angle)
  local f = math.floor((angle % TWO_PI) / TWO_PI * FRAMES + 0.5) % FRAMES
  local col, row = f % COLS, math.floor(f / COLS)
  tex:SetTexCoord(col / COLS, (col + 1) / COLS, row / ROWS, (row + 1) / ROWS)
end
Arrow.ROTATION_OFFSET = 0        -- radians added to the computed rotation
local ARRIVE_YARDS = 6           -- within this distance you've "arrived" → hide the arrow (~5 m)
local THROTTLE = 0.05            -- OnUpdate recompute interval (seconds)
local BASE_SIZE = 54             -- arrow edge in px at scale 1 (there's a size slider)
local TEXT_WIDTH = 220           -- wrap width for the text lines (before text scale)

local dest        -- { map, x (0-1), y (0-1), title } — what we were asked to point at
local destWorld   -- { cont, wx, wy } — dest resolved to continent world yards
-- last computed values, exposed for calibration dumps
Arrow.debug = { bearing = nil, facing = nil, rel = nil, dist = nil }

local onUpdate  -- forward declaration (Ensure wires it as the OnUpdate script)

--- Format a yard distance for display, honouring the metric preference
--- (ns.db.arrow.metric): yards by default, else metres / kilometres.
function Arrow.FormatDistance(yards)
  if ns.db and ns.db.arrow and ns.db.arrow.metric then
    local m = yards * 0.9144
    if m >= 1000 then return string.format("%.2f km", m / 1000) end
    return string.format("%d m", m)
  end
  return string.format("%d yd", yards)
end

--- HSV -> RGB (h in 0-360, s/v in 0-1). Used for smooth distance colouring.
local function hsvToRgb(h, s, v)
  local c = v * s
  local hp = (h % 360) / 60
  local x = c * (1 - math.abs(hp % 2 - 1))
  local r, g, b = 0, 0, 0
  if hp < 1 then r, g, b = c, x, 0
  elseif hp < 2 then r, g, b = x, c, 0
  elseif hp < 3 then r, g, b = 0, c, x
  elseif hp < 4 then r, g, b = 0, x, c
  elseif hp < 5 then r, g, b = x, 0, c
  else r, g, b = c, 0, x end
  local m = v - c
  return r + m, g + m, b + m
end

--- Distance (yards) -> colour, hue interpolated red→orange→yellow→green as you
--- get closer. Log scale so the useful WoW distances spread out nicely.
local function distColor(d)
  local t
  if d <= GREEN_YARDS then t = 1
  elseif d >= FAR_YARDS then t = 0
  else t = 1 - math.log(d / GREEN_YARDS) / math.log(FAR_YARDS / GREEN_YARDS) end
  return hsvToRgb(120 * t, 1.0, 1.0)   -- hue 0=red .. 120=green
end

--- Resolve the player's current continent-space world position (yards), via the
--- same native path the target uses so both are comparable.
local function playerWorld()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition
          and C_Map.GetWorldPosFromMapPos) then return end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return end
  local ppos = C_Map.GetPlayerMapPosition(map, "player")
  if not ppos then return end
  local ok, cont, wpos = pcall(C_Map.GetWorldPosFromMapPos, map, ppos)
  if not ok or not cont or not wpos then return end
  local wx, wy = wpos:GetXY()
  if not wx then return end
  return cont, wx, wy
end

--- Build the arrow frame once (movable, position/scale persisted in ns.db.arrow).
function Arrow.Ensure()
  if Arrow.frame then return Arrow.frame end
  local f = CreateFrame("Button", "EasySetCollectionArrow", UIParent)
  Arrow.frame = f
  f:SetSize(BASE_SIZE, BASE_SIZE)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(not (ns.db and ns.db.arrow and ns.db.arrow.locked))   -- click-through when locked
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("RightButtonUp")
  f:SetClampedToScreen(true)
  f:SetScript("OnClick", function(self, button)
    if button == "RightButton" then Arrow.OpenMenu(self) end
  end)

  local pos = (ns.db and ns.db.arrow and ns.db.arrow.pos) or { "CENTER", 0, 200 }
  f:SetPoint(pos[1] or "CENTER", UIParent, pos[1] or "CENTER", pos[2] or 0, pos[3] or 200)

  local tex = f:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(ARROW_TEXTURE)
  tex:SetAllPoints(f)
  f.arrow = tex

  -- Text lives in its own frame so it can be scaled independently of the arrow.
  -- Its anchor is (re)set by Arrow.ApplyScale so it hugs the arrow at any size.
  local tf = CreateFrame("Frame", nil, f)
  tf:SetSize(TEXT_WIDTH, 10)
  f.textFrame = tf

  -- text stack: guided set (amber) / router instruction (white) / distance.
  f.name = tf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.name:SetPoint("TOP", tf, "TOP", 0, 0)
  f.name:SetWidth(TEXT_WIDTH)
  f.name:SetJustifyH("CENTER")
  f.name:SetWordWrap(true)
  f.name:SetSpacing(2)

  f.instr = tf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")   -- white
  f.instr:SetPoint("TOP", f.name, "BOTTOM", 0, -3)
  f.instr:SetWidth(TEXT_WIDTH)
  f.instr:SetJustifyH("CENTER")
  f.instr:SetWordWrap(true)

  f.dist = tf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")    -- white
  f.dist:SetPoint("TOP", f.instr, "BOTTOM", 0, -3)
  f.dist:SetJustifyH("CENTER")

  f:SetScript("OnDragStart", function(self)
    if not (ns.db and ns.db.arrow and ns.db.arrow.locked) then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, xo, yo = self:GetPoint()
    ns.db.arrow = ns.db.arrow or {}
    ns.db.arrow.pos = { point, xo, yo }
  end)
  f:SetScript("OnUpdate", onUpdate)
  Arrow.ApplyScale()
  f:Hide()
  return f
end

--- Apply the saved arrow size (ns.db.arrow.scale) and text size (ns.db.arrow.textScale).
--- Safe to call live from the settings sliders.
function Arrow.ApplyScale()
  local f = Arrow.frame
  if not f then return end
  local a = (ns.db and ns.db.arrow) or {}
  local size = BASE_SIZE * (a.scale or 1)
  f:SetSize(size, size)
  if f.textFrame then
    local ts = a.textScale or 1
    f.textFrame:SetScale(ts)
    -- Pull the text up to hug the arrow: the sprite leaves ~30% empty at the bottom
    -- of its cell, so anchor into that gap (÷ts cancels the child-frame scaling).
    f.textFrame:ClearAllPoints()
    f.textFrame:SetPoint("TOP", f, "BOTTOM", 0, size * 0.16 / ts)
  end
end

local SCALE_PRESETS = { 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5 }

--- Right-click context menu on the arrow: arrow size, text size, and lock.
--- Locking makes the arrow click-through, so it can only be UNlocked from the
--- Settings panel afterwards (by design).
function Arrow.OpenMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(L["EasySetCollection"])

    local function sizeSubmenu(label, key)
      local sub = root:CreateButton(label)
      for _, v in ipairs(SCALE_PRESETS) do
        local pct = string.format("%d%%", v * 100)
        sub:CreateRadio(pct,
          function() return math.abs(((ns.db.arrow and ns.db.arrow[key]) or 1) - v) < 0.001 end,
          function()
            ns.db.arrow = ns.db.arrow or {}
            ns.db.arrow[key] = v
            if Arrow.ApplyScale then Arrow.ApplyScale() end
            return MenuResponse and MenuResponse.Refresh
          end)
      end
    end
    sizeSubmenu(L["Arrow size"], "scale")
    sizeSubmenu(L["Text size"], "textScale")

    root:CreateDivider()
    root:CreateButton(L["Lock the arrow position"], function()
      ns.db.arrow = ns.db.arrow or {}
      ns.db.arrow.locked = true
      if Arrow.frame then Arrow.frame:EnableMouse(false) end   -- click-through when locked
    end)
    root:CreateDivider()
    root:CreateButton(L["Close"], function()
      -- clears our native waypoint too, not just the arrow
      if ns.Waypoint then ns.Waypoint.Clear() else Arrow.Hide() end
    end)
  end)
end

--- OnUpdate driver: recompute heading + distance and orient the arrow. Kept
--- running while a destination is set (frame shown); it hides only the arrow art
--- (not the frame) when no bearing is computable, so it recovers automatically
--- once the player is back on the destination's continent.
onUpdate = function(self, elapsed)
  self._acc = (self._acc or 0) + elapsed
  if self._acc < THROTTLE then return end
  self._acc = 0

  if not destWorld then return end   -- Hide() clears dest and hides the frame

  -- Keep the arrow BELOW the options panel / game menu (so it doesn't cover them),
  -- but still VISIBLE — so its size can be tweaked live from the panel. LOW is below
  -- any dialog strata; HIGH is a normal HUD strata during play.
  local menuOpen = (SettingsPanel and SettingsPanel:IsShown())
                or (GameMenuFrame and GameMenuFrame:IsShown()) or false
  if menuOpen ~= self._menuOpen then
    self._menuOpen = menuOpen
    self:SetFrameStrata(menuOpen and "LOW" or "HIGH")
  end

  local pcont, pwx, pwy = playerWorld()
  local facing = GetPlayerFacing and GetPlayerFacing()
  Arrow.debug.facing = facing
  if not pcont or not facing or pcont ~= destWorld.cont then
    -- cross-continent / inside an instance / on a taxi: no meaningful heading.
    self.arrow:Hide()
    if self.textFrame then self.textFrame:Hide() end
    Arrow.debug.bearing, Arrow.debug.rel, Arrow.debug.dist = nil, nil, nil
    return
  end

  -- wpos:GetXY() returns (comp1, comp2). Per HereBeDragons, WoW's world axes are
  -- TRANSPOSED vs GetXY order (same reason UnitPosition returns y,x): the world
  -- vector is atan2(-deltaComp2, deltaComp1), normalised CCW-from-north to match
  -- GetPlayerFacing. Swapping the two components sends the arrow 90/180 degrees off.
  local d1 = destWorld.wx - pwx   -- comp1 delta
  local d2 = destWorld.wy - pwy   -- comp2 delta
  local dist = sqrt(d1 * d1 + d2 * d2)

  local bearing = atan2(-d2, d1)
  if bearing > 0 then bearing = TWO_PI - bearing else bearing = -bearing end
  local rel = bearing - facing

  Arrow.debug.bearing, Arrow.debug.rel, Arrow.debug.dist = bearing, rel, dist

  if dist <= ARRIVE_YARDS then
    -- Arrived at this waypoint: hide the arrow + its text. It reappears if you move
    -- away or the route advances to the next hop; Waypoint.Clear() removes it for good.
    self.arrow:Hide()
    if self.textFrame then self.textFrame:Hide() end
    return
  end

  self.arrow:Show()
  if self.textFrame then self.textFrame:Show() end
  setFrame(self.arrow, Arrow.SPIN * rel + Arrow.ROTATION_OFFSET)   -- matching 3D frame
  local r, g, b = distColor(dist)                                  -- red (far) → green (near)
  self.arrow:SetVertexColor(r, g, b)
  self.dist:SetText(Arrow.FormatDistance(dist))
end

--- Point the arrow at a UI map point. Coordinates are 0-1 (as Waypoint.SetTo uses).
---@param map number  uiMapID of the destination
---@param x number  normalized X (0-1)
---@param y number  normalized Y (0-1)
---@param title string?  label shown under the arrow
function Arrow.Show(map, x, y, title)
  if not (map and x and y) then return end
  if ns.db and ns.db.arrow and ns.db.arrow.enabled == false then return end
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end

  dest = { map = map, x = x, y = y, title = title }
  local ok, cont, wpos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
  if ok and cont and wpos then
    local wx, wy = wpos:GetXY()
    destWorld = wx and { cont = cont, wx = wx, wy = wy } or nil
  else
    destWorld = nil
  end
  if not destWorld then return end   -- no world pos → nothing to point at

  Arrow.Ensure()
  -- Top line = the guided SET (stable across hops), amber like the main window.
  -- Second line = the router's own step instruction (title), in white.
  local nameLine
  if ns.UI and ns.UI.ArrowText then
    nameLine = ns.UI.ArrowText()
  end
  Arrow.frame.name:SetText(nameLine or "")
  -- Don't echo the instruction when it's just the set name again (plain fallback).
  local plain = nameLine and nameLine:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local instr = (title and title ~= "" and title ~= plain) and title or ""
  Arrow.frame.instr:SetText(instr)
  Arrow.frame:Show()
end

--- Hide the arrow and forget the destination.
function Arrow.Hide()
  dest, destWorld = nil, nil
  if Arrow.frame then Arrow.frame:Hide() end
end
