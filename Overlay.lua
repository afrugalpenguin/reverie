-- Draws the letterbox bars and text elements into a root frame.
-- Used twice: full-screen in game, and scaled down in the options preview.
local _, ns = ...
local Layout = ns.Layout

local Overlay = {}
Overlay.__index = Overlay
ns.Overlay = Overlay

local FONTS = { title = "Fonts\\MORPHEUS.TTF", body = "Fonts\\FRIZQT__.TTF" }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 0.88, 0.72, 0.38, 1 }

local FADE_ALPHA = 0.55  -- the soft shadow under each bar
local HIDDEN_ALPHA = 0.45 -- unlock mode: elements switched off in settings
local OUTLINE_PAD = 6    -- unlock mode: gap between the text and its dashed outline
local DASH, DASH_GAP, DASH_W = 6, 4, 2

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

-- Unlock mode decoration: a dashed outline around the element, redrawn for its size.
local function DrawOutline(handle)
  handle.dashes = handle.dashes or {}
  local w = handle:GetWidth() + 2 * OUTLINE_PAD
  local h = handle:GetHeight() + 2 * OUTLINE_PAD
  local n = 0
  local function dash(x, y, dw, dh)
    n = n + 1
    local t = handle.dashes[n]
    if not t then
      t = handle:CreateTexture(nil, "OVERLAY")
      t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
      handle.dashes[n] = t
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", handle, "TOPLEFT", x - OUTLINE_PAD, OUTLINE_PAD - y)
    t:SetSize(dw, dh)
    t:Show()
  end
  for x = 0, w - 1, DASH + DASH_GAP do
    local len = math.min(DASH, w - x)
    dash(x, 0, len, DASH_W)
    dash(x, h - DASH_W, len, DASH_W)
  end
  for y = 0, h - 1, DASH + DASH_GAP do
    local len = math.min(DASH, h - y)
    dash(0, y, DASH_W, len)
    dash(w - DASH_W, y, DASH_W, len)
  end
  for i = n + 1, #handle.dashes do handle.dashes[i]:Hide() end
end

local function HideOutline(handle)
  for _, t in ipairs(handle.dashes or {}) do t:Hide() end
end

function Overlay.New(root)
  local self = setmetatable({ root = root, strings = {}, handles = {} }, Overlay)

  self.topBar, self.topFade = Bar(root, "TOP", "BOTTOM")
  self.bottomBar, self.bottomFade = Bar(root, "BOTTOM", "TOP")

  -- All text lives on one layer so it can fade out together.
  self.text = CreateFrame("Frame", nil, root)
  self.text:SetAllPoints()

  -- Each element is a handle frame holding its text. The handle is what gets positioned,
  -- and in unlock mode it's what the mouse drags.
  for _, id in ipairs(Layout.ORDER) do
    local meta = Layout.META[id]
    local handle = CreateFrame("Frame", nil, self.text)
    handle.id = id
    handle:SetMovable(true)
    handle:EnableMouse(false)
    handle:RegisterForDrag("LeftButton")
    handle:Hide()

    local fs = handle:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONTS[meta.font], meta.size, "")
    fs:SetTextColor(meta.color[1], meta.color[2], meta.color[3], 1)
    fs:SetShadowColor(0, 0, 0, 0.95)
    fs:SetShadowOffset(1, -1)
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT")

    handle.label = handle:CreateFontString(nil, "OVERLAY")
    handle.label:SetFont(FONTS.body, 11, "")
    handle.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    handle.label:SetShadowColor(0, 0, 0, 1)
    handle.label:SetShadowOffset(1, -1)
    handle.label:SetPoint("BOTTOMLEFT", handle, "TOPLEFT", -OUTLINE_PAD, OUTLINE_PAD + 3)
    handle.label:Hide()

    handle:SetScript("OnDragStart", function(h)
      if not h.onDrop then return end
      h:SetClampedToScreen(true) -- only while dragging, so free elements near an edge aren't nudged
      h:StartMoving()
    end)
    handle:SetScript("OnDragStop", function(h)
      h:StopMovingOrSizing()
      h:SetClampedToScreen(false)
      if not h.onDrop then return end
      -- Handle and root share an effective scale (nothing in between is scaled).
      local cx, cy = h:GetCenter()
      local left, top = root:GetLeft(), root:GetTop()
      if cx and left then
        h.onDrop(h.id, cx - left, top - cy, root:GetWidth(), root:GetHeight())
      end
    end)

    self.handles[id] = handle
    self.strings[id] = fs
  end

  -- Dashed-ring stand-in: a thin gold outline around the selected element (options preview only).
  self.ring = CreateFrame("Frame", nil, self.text, "BackdropTemplate")
  self.ring:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
  self.ring:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
  self.ring:Hide()

  return self
end

-- settings: from Layout.Merge; texts: id -> string ("" hides it); selected: id to outline, or nil.
-- unlock: nil normally; in unlock mode { onDrop = function(id, x, y, w, h) } where x/y is the
-- dropped element's centre in screen units from the top-left. Every element is then placed,
-- outlined, labelled and draggable, even ones switched off in settings.
function Overlay:Apply(settings, texts, selected, unlock)
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

  -- Measure every element that has text; the layout skips the rest.
  local sizes = {}
  for _, id in ipairs(Layout.ORDER) do
    local text = texts[id]
    if text and text ~= "" then
      if Layout.META[id].caps then text = string.upper(text) end
      local fs = self.strings[id]
      self.handles[id]:Show() -- measure while shown; it's hidden again below if it isn't placed
      fs:SetText(text)
      sizes[id] = { w = math.max(fs:GetStringWidth(), 1), h = math.max(fs:GetStringHeight(), 1) }
    end
  end

  local positions = Layout.Positions(settings, w, h, sizes, unlock ~= nil)

  for _, id in ipairs(Layout.ORDER) do
    local handle, p = self.handles[id], positions[id]
    handle:ClearAllPoints()
    if p then
      handle:SetSize(sizes[id].w, sizes[id].h)
      handle:SetPoint("TOPLEFT", root, "TOPLEFT", p.left, -p.top)
      handle:SetAlpha((unlock and not settings.elements[id].show) and HIDDEN_ALPHA or 1)
      handle:Show()
    else
      handle:Hide()
    end

    handle.onDrop = unlock and unlock.onDrop or nil
    handle:EnableMouse(unlock ~= nil)
    if unlock and p then
      local label = Layout.META[id].label
      handle.label:SetText(settings.elements[id].show and label or (label .. " (off)"))
      handle.label:Show()
      DrawOutline(handle)
    else
      handle.label:Hide()
      HideOutline(handle)
    end
  end

  local target = selected and self.handles[selected]
  if target and target:IsShown() then
    self.ring:ClearAllPoints()
    self.ring:SetPoint("TOPLEFT", target, "TOPLEFT", -8, 6)
    self.ring:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 8, -6)
    self.ring:Show()
  else
    self.ring:Hide()
  end
end
