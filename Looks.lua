-- Photo looks drawn over a root frame: crop guide shading, vignette, saturated and sepia tints,
-- and the stamp. Shared by the options preview and, later, the photo capture.
local _, ns = ...
local Layout = ns.Layout

local Looks = {}
Looks.__index = Looks
ns.Looks = Looks

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GUIDE_ALPHA = 0.6     -- shading outside the chosen frame (a guide, never saved)
local VIGNETTE_MAX = 0.85   -- edge darkness at strength 100
local VIGNETTE_DEPTH = 0.3  -- how far in from each edge the vignette reaches, as a share of the screen
local GUIDE_LINE = { 1, 1, 1, 0.35 }    -- thirds lines
local GUIDE_DASH = { 0.95, 0.87, 0.68, 0.9 } -- dashed frame around the crop
local DASH, DASH_GAP, DASH_W = 10, 6, 2

-- Addons can't run shaders, so colour looks are a full-screen colour with a blend mode.
-- The spike picked MOD with a warm colour; both are first passes to tune in game.
local TINTS = {
  sepia     = { mode = "MOD", color = { 1.00, 0.82, 0.58 } },
  saturated = { mode = "MOD", color = { 1.00, 0.91, 0.80 } },
}

local function Solid(root, layer, sublevel)
  local t = root:CreateTexture(nil, layer, nil, sublevel)
  t:SetColorTexture(0, 0, 0, 1)
  t:Hide()
  return t
end

function Looks.New(root)
  local self = setmetatable({ root = root, edges = {}, bands = {}, thirds = {}, dashes = {} }, Looks)

  self.tint = Solid(root, "ARTWORK", 0)
  self.tint:SetAllPoints()

  -- Vignette: a dark-to-clear gradient along each edge.
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "ARTWORK", nil, 1)
    t:SetTexture(WHITE)
    if side == "TOP" or side == "BOTTOM" then
      t:SetPoint(side .. "LEFT")
      t:SetPoint(side .. "RIGHT")
    else
      t:SetPoint("TOP" .. side)
      t:SetPoint("BOTTOM" .. side)
    end
    t:Hide()
    self.edges[side] = t
  end

  -- Crop guide: four shaded bands around the frame's rectangle.
  for _, band in ipairs({ "top", "bottom", "left", "right" }) do
    local t = Solid(root, "OVERLAY", 0)
    t:SetAlpha(GUIDE_ALPHA)
    self.bands[band] = t
  end

  -- Rule-of-thirds lines inside the crop: two across, two down.
  for i = 1, 4 do
    local t = root:CreateTexture(nil, "OVERLAY", nil, 1)
    t:SetColorTexture(GUIDE_LINE[1], GUIDE_LINE[2], GUIDE_LINE[3], GUIDE_LINE[4])
    t:Hide()
    self.thirds[i] = t
  end

  -- The stamp is text, drawn by Overlay with Layout.Positions like the overlay's elements.
  self.stampFrame = CreateFrame("Frame", nil, root)
  self.stampFrame:SetAllPoints()
  self.stamp = ns.Overlay.New(self.stampFrame, { order = Layout.STAMP_ORDER, meta = Layout.STAMP_META })
  self.stampFrame:Hide()

  return self
end

-- Raw stamp parts for the player, for Layout.StampTexts. sample = true fills a missing guild.
function Looks.Parts(sample)
  local guild = GetGuildInfo("player")
  return {
    name = Layout.DisplayName(GetUnitName("player", true), nil, ns.settings.options.surname),
    guild = guild or (sample and "Guild" or ""),
    zone = GetZoneText() or "",
    date = date("%d %b %Y"),
  }
end

local function DrawVignette(self, strength, w, h)
  local dark = CreateColor(0, 0, 0, VIGNETTE_MAX * strength)
  local clear = CreateColor(0, 0, 0, 0)
  local e = self.edges
  -- Gradients run from the first colour (bottom or left) to the second (top or right).
  e.TOP:SetHeight(h * VIGNETTE_DEPTH)
  e.TOP:SetGradient("VERTICAL", clear, dark)
  e.BOTTOM:SetHeight(h * VIGNETTE_DEPTH)
  e.BOTTOM:SetGradient("VERTICAL", dark, clear)
  e.LEFT:SetWidth(w * VIGNETTE_DEPTH)
  e.LEFT:SetGradient("HORIZONTAL", dark, clear)
  e.RIGHT:SetWidth(w * VIGNETTE_DEPTH)
  e.RIGHT:SetGradient("HORIZONTAL", clear, dark)
end

-- A dashed rectangle from pooled textures.
local function DashedRect(self, r)
  local n = 0
  local function dash(x, y, w, h)
    n = n + 1
    local t = self.dashes[n]
    if not t then
      t = self.root:CreateTexture(nil, "OVERLAY", nil, 2)
      t:SetColorTexture(GUIDE_DASH[1], GUIDE_DASH[2], GUIDE_DASH[3], GUIDE_DASH[4])
      self.dashes[n] = t
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", x, -y)
    t:SetSize(w, h)
    t:Show()
  end
  for x = 0, r.width - 1, DASH + DASH_GAP do
    local len = math.min(DASH, r.width - x)
    dash(r.left + x, r.top, len, DASH_W)
    dash(r.left + x, r.top + r.height - DASH_W, len, DASH_W)
  end
  for y = 0, r.height - 1, DASH + DASH_GAP do
    local len = math.min(DASH, r.height - y)
    dash(r.left, r.top + y, DASH_W, len)
    dash(r.left + r.width - DASH_W, r.top + y, DASH_W, len)
  end
  for i = n + 1, #self.dashes do self.dashes[i]:Hide() end
end

local function Line(t, x, y, w, h)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", x, -y)
  t:SetSize(w, h)
  t:Show()
end

local function Band(t, x, y, w, h)
  if w <= 0 or h <= 0 then
    t:Hide()
    return
  end
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", x, -y)
  t:SetSize(w, h)
  t:Show()
end

-- photo: settings.photo. look: one of Layout.PHOTO_TYPES, or nil for none. parts: from
-- Looks.Parts. showGuides: framing guides (shading outside the chosen frame, a dashed frame
-- around it, thirds lines); shown while framing a shot, never in a saved file.
function Looks:Apply(photo, look, parts, showGuides)
  local w, h = self.root:GetWidth(), self.root:GetHeight()

  local tint = TINTS[look]
  if tint then
    self.tint:SetColorTexture(tint.color[1], tint.color[2], tint.color[3], 1)
    self.tint:SetBlendMode(tint.mode)
    self.tint:Show()
  else
    self.tint:Hide()
  end

  local strength = look == "vignetted" and photo.vignette / 100 or 0
  for _, t in pairs(self.edges) do t:SetShown(strength > 0) end
  if strength > 0 then DrawVignette(self, strength, w, h) end

  if look == "stamped" then
    self.stampFrame:Show()
    self.stamp:Apply(Layout.StampSettings(photo), Layout.StampTexts(photo.stamp, parts))
  else
    self.stampFrame:Hide()
  end

  local b = self.bands
  local r = showGuides and Layout.CropRect(photo.frame, w, h)
  if r and photo.frame ~= "full" then
    Band(b.top, 0, 0, w, r.top)
    Band(b.bottom, 0, r.top + r.height, w, h - r.top - r.height)
    Band(b.left, 0, r.top, r.left, r.height)
    Band(b.right, r.left + r.width, r.top, w - r.left - r.width, r.height)
    DashedRect(self, r)
  else
    for _, t in pairs(b) do t:Hide() end
    for _, t in ipairs(self.dashes) do t:Hide() end
  end

  if r then
    local th = self.thirds
    Line(th[1], r.left + r.width / 3, r.top, 1, r.height)
    Line(th[2], r.left + r.width * 2 / 3, r.top, 1, r.height)
    Line(th[3], r.left, r.top + r.height / 3, r.width, 1)
    Line(th[4], r.left, r.top + r.height * 2 / 3, r.width, 1)
  else
    for _, t in ipairs(self.thirds) do t:Hide() end
  end
end
