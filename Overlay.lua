-- Draws the letterbox bars and text elements into a root frame.
-- Used twice: full-screen in game, and scaled down in the options preview.
local _, ns = ...
local Layout = ns.Layout

local Overlay = {}
Overlay.__index = Overlay
ns.Overlay = Overlay

local FONTS = { title = "Fonts\\MORPHEUS.TTF", body = "Fonts\\FRIZQT__.TTF" }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local POINTS = {
  TL = "TOPLEFT", TC = "TOP", TR = "TOPRIGHT",
  ML = "LEFT", MC = "CENTER", MR = "RIGHT",
  BL = "BOTTOMLEFT", BC = "BOTTOM", BR = "BOTTOMRIGHT",
}
local SIDE = { L = { "LEFT", "LEFT" }, C = { "", "CENTER" }, R = { "RIGHT", "RIGHT" } }

local SIDE_PAD = 60      -- distance of the text grid from the screen's left/right edges
local BAR_GAP = 18       -- distance of the text grid from a letterbox bar
local EDGE_PAD = 24      -- distance of the text grid from the screen edge without bars
local LINE_GAP = 4
local FADE_ALPHA = 0.55  -- the soft shadow under each bar

local function Bar(root, point, relPoint)
  local bar = root:CreateTexture(nil, "BACKGROUND")
  bar:SetColorTexture(0, 0, 0, 1)
  bar:SetPoint(point .. "LEFT")
  bar:SetPoint(point .. "RIGHT")

  local fade = root:CreateTexture(nil, "BACKGROUND")
  fade:SetTexture(WHITE)
  fade:SetPoint(point .. "LEFT", bar, relPoint .. "LEFT")
  fade:SetPoint(point .. "RIGHT", bar, relPoint .. "RIGHT")
  -- VERTICAL gradients run from the bottom colour to the top colour.
  local dark, clear = CreateColor(0, 0, 0, FADE_ALPHA), CreateColor(0, 0, 0, 0)
  if point == "TOP" then
    fade:SetGradient("VERTICAL", clear, dark)
  else
    fade:SetGradient("VERTICAL", dark, clear)
  end
  return bar, fade
end

function Overlay.New(root)
  local self = setmetatable({ root = root, strings = {}, holders = {} }, Overlay)

  self.topBar, self.topFade = Bar(root, "TOP", "BOTTOM")
  self.bottomBar, self.bottomFade = Bar(root, "BOTTOM", "TOP")

  -- All text lives on one layer so it can fade out together.
  self.text = CreateFrame("Frame", nil, root)
  self.text:SetAllPoints()
  self.grid = CreateFrame("Frame", nil, self.text)

  for _, anchor in ipairs(Layout.ANCHORS) do
    self.holders[anchor] = CreateFrame("Frame", nil, self.grid)
  end

  for _, id in ipairs(Layout.ORDER) do
    local meta = Layout.META[id]
    local fs = self.text:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONTS[meta.font], meta.size, "")
    fs:SetTextColor(meta.color[1], meta.color[2], meta.color[3], 1)
    fs:SetShadowColor(0, 0, 0, 0.95)
    fs:SetShadowOffset(1, -1)
    fs:SetWordWrap(false)
    fs:Hide()
    self.strings[id] = fs
  end

  -- Dashed-ring stand-in: a thin gold outline around the selected element (options preview only).
  self.ring = CreateFrame("Frame", nil, self.text, "BackdropTemplate")
  self.ring:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
  self.ring:SetBackdropBorderColor(0.88, 0.72, 0.38, 1)
  self.ring:Hide()

  return self
end

-- settings: from Layout.Merge; texts: id -> string ("" hides it); selected: id to outline, or nil.
function Overlay:Apply(settings, texts, selected)
  local root = self.root
  local w, h = root:GetWidth(), root:GetHeight()
  local barH = Layout.BarHeight(h, settings.options.bars)

  local bars = { self.topBar, self.topFade, self.bottomBar, self.bottomFade }
  for _, tex in ipairs(bars) do tex:SetShown(barH > 0) end
  if barH > 0 then
    self.topBar:SetHeight(barH)
    self.bottomBar:SetHeight(barH)
    self.topFade:SetHeight(math.floor(barH * 0.6))
    self.bottomFade:SetHeight(math.floor(barH * 0.6))
  end

  local pad = barH > 0 and (barH + BAR_GAP) or EDGE_PAD
  self.grid:ClearAllPoints()
  self.grid:SetPoint("TOPLEFT", root, "TOPLEFT", SIDE_PAD, -pad)
  self.grid:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -SIDE_PAD, pad)

  for _, fs in pairs(self.strings) do fs:Hide() end

  local function SetText(id)
    local text = texts[id]
    if not text or text == "" then return nil end
    local fs = self.strings[id]
    if Layout.META[id].caps then text = string.upper(text) end
    fs:SetText(text)
    fs:ClearAllPoints()
    fs:Show()
    return fs
  end

  -- Anchored elements: stack top to bottom inside a holder pinned to its cell.
  local cells = Layout.Cells(settings)
  for anchor, ids in pairs(cells) do
    local holder = self.holders[anchor]
    local side = SIDE[anchor:sub(2, 2)]
    holder:ClearAllPoints()
    holder:SetPoint(POINTS[anchor], self.grid, POINTS[anchor])
    local y, width = 0, 1
    for _, id in ipairs(ids) do
      local fs = SetText(id)
      if fs then
        fs:SetJustifyH(side[2])
        fs:SetPoint("TOP" .. side[1], holder, "TOP" .. side[1], 0, -y)
        y = y + fs:GetStringHeight() + LINE_GAP
        width = math.max(width, fs:GetStringWidth())
      end
    end
    holder:SetSize(width, math.max(y - LINE_GAP, 1))
  end

  -- Free elements: centred on a percentage of the whole screen.
  for _, id in ipairs(Layout.FreeItems(settings)) do
    local fs = SetText(id)
    if fs then
      local e = settings.elements[id]
      fs:SetJustifyH("CENTER")
      fs:SetPoint("CENTER", root, "TOPLEFT", w * e.x / 100, -h * e.y / 100)
    end
  end

  local target = selected and self.strings[selected]
  if target and target:IsShown() then
    self.ring:ClearAllPoints()
    self.ring:SetPoint("TOPLEFT", target, "TOPLEFT", -8, 6)
    self.ring:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 8, -6)
    self.ring:Show()
  else
    self.ring:Hide()
  end
end
