-- Draws the flight map into a root frame: the Strip style in the bottom letterbox bar, or the
-- Overlay style's route over the view in the bottom right. Used twice: on the overlay in game
-- (Map.lua), and scaled down in the options preview (MapOptions.lua). Placement comes from
-- Layout.MapStrip / Layout.MapBox, so Layout.MapReserve keeps bottom text clear of it.
--
-- Built only from what the spike (#54) proved on Forever: CreateLine for routes, the taxi map's
-- own art (GetMapArtLayers / GetMapArtLayerTextures), desaturate + vertex colour + alpha, and our
-- own soft-edged mask texture (the game's masks are all hard cut-outs).
local addonName, ns = ...
local Layout, Route = ns.Layout, ns.Route

local MapView = {}
MapView.__index = MapView
ns.MapView = MapView

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SOFT_MASK = "Interface\\AddOns\\" .. addonName .. "\\textures\\MapMask"
local FONTS = { title = "Fonts\\MORPHEUS.TTF", body = "Fonts\\FRIZQT__.TTF" }

local GOLD = { 0.88, 0.72, 0.38 }
local CREAM = { 1.00, 0.96, 0.86 }
local DIM = { 0.80, 0.76, 0.70 }
local TEAL = { 0.35, 0.85, 0.85 } -- terrain tint, as tried in the spike
local TERRAIN_MAX = 0.85          -- terrain alpha at strength 100
local STRIP_FADE = 0.75           -- the dark gradient under a strip without bars
local LINE_GAP = 16               -- strip: between a name and the line
local BOX_PAD = 26                -- overlay: between the route and the box's edges
local BOX_TEXT_H = 66             -- overlay: room at the top for the destination block
local DOT, GAP = 4, 5             -- overlay: the remaining route's dots and the gaps between

-- Pools of textures, lines and font strings, reused every redraw.
local function Pool(make) return { items = {}, used = 0, make = make } end

local function Take(pool)
  pool.used = pool.used + 1
  local item = pool.items[pool.used]
  if not item then
    item = pool.make()
    pool.items[pool.used] = item
  end
  if item.ClearAllPoints then item:ClearAllPoints() end -- lines are placed by start and end points
  item:Show()
  return item
end

local function Begin(pool) pool.used = 0 end

local function Finish(pool)
  for i = pool.used + 1, #pool.items do pool.items[i]:Hide() end
end

local function Label(parent, font, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONTS[font], size, "")
  fs:SetTextColor(color[1], color[2], color[3], 1)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
  fs:SetWordWrap(false)
  return fs
end

local function Dot(parent)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetTexture(WHITE)
  local mask = parent:CreateMaskTexture()
  mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(t)
  t:AddMaskTexture(mask)
  return t
end

-- Places a pooled dot centred on x, y (units from parent's top-left, y downward).
local function PutDot(pool, parent, x, y, size, color, alpha)
  local d = Take(pool)
  d:SetSize(size, size)
  d:SetVertexColor(color[1], color[2], color[3], alpha or 1)
  d:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
  return d
end

local function PutLine(pool, parent, ax, ay, bx, by, thickness, color, alpha)
  local l = Take(pool)
  l:SetStartPoint("TOPLEFT", parent, ax, -ay)
  l:SetEndPoint("TOPLEFT", parent, bx, -by)
  l:SetThickness(thickness)
  l:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end

-- The flight marker: a chevron at x, y pointing along the unit heading dx, dy.
local function PutArrow(pool, parent, x, y, dx, dy, size)
  local tipX, tipY = x + dx * size * 0.5, y + dy * size * 0.5
  for _, a in ipairs({ 2.6, -2.6 }) do -- radians either side of straight back
    local c, s = math.cos(a), math.sin(a)
    local wx, wy = dx * c - dy * s, dx * s + dy * c
    PutLine(pool, parent, tipX, tipY, tipX + wx * size, tipY + wy * size, 2.5, CREAM)
  end
end

function MapView.New(root)
  local self = setmetatable({ root = root }, MapView)
  local f = CreateFrame("Frame", nil, root)
  f:SetAllPoints()
  self.frame = f

  -- Strip.
  self.strip = CreateFrame("Frame", nil, f)
  self.strip:SetAllPoints()
  local strip = self.strip
  self.stripBg = strip:CreateTexture(nil, "BACKGROUND")
  self.stripBg:SetTexture(WHITE)
  self.stripBg:SetGradient("VERTICAL", CreateColor(0, 0, 0, STRIP_FADE), CreateColor(0, 0, 0, 0))
  self.stripBase = strip:CreateTexture(nil, "ARTWORK")
  self.stripBase:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
  self.stripFill = strip:CreateTexture(nil, "ARTWORK", nil, 1)
  self.stripFill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  self.origin = Label(strip, "body", 13, CREAM)
  self.dest = Label(strip, "body", 13, CREAM)
  self.markerText = Label(strip, "body", 11, CREAM)
  self.stripDots = Pool(function() return Dot(strip) end)
  self.stripLabels = Pool(function() return Label(strip, "body", 10, DIM) end)
  self.stripLines = Pool(function() return strip:CreateLine(nil, "OVERLAY") end)

  -- Overlay: terrain under the route, both clipped to the box.
  self.box = CreateFrame("Frame", nil, f)
  local box = self.box
  self.terrain = CreateFrame("Frame", nil, box)
  self.terrain:SetAllPoints()
  self.terrain:SetClipsChildren(true)
  self.softMask = self.terrain:CreateMaskTexture()
  self.softMask:SetTexture(SOFT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  self.softMask:SetAllPoints(box)
  self.tiles = Pool(function()
    local t = self.terrain:CreateTexture(nil, "ARTWORK")
    t:AddMaskTexture(self.softMask)
    return t
  end)
  self.route = CreateFrame("Frame", nil, box)
  self.route:SetAllPoints()
  local route = self.route
  self.boxLines = Pool(function() return route:CreateLine(nil, "ARTWORK") end)
  self.boxDots = Pool(function() return Dot(route) end)
  self.boxLabels = Pool(function() return Label(route, "body", 11, CREAM) end)
  -- Top right: "Flying to" small, the destination large, then the details.
  self.flyingTo = Label(route, "body", 11, DIM)
  self.flyingTo:SetJustifyH("RIGHT")
  self.flyingTo:SetPoint("TOPRIGHT")
  self.flyingTo:SetText("Flying to")
  self.title = Label(route, "title", 20, CREAM)
  self.title:SetJustifyH("RIGHT")
  self.title:SetPoint("TOPRIGHT", self.flyingTo, "BOTTOMRIGHT", 0, -2)
  self.info = Label(route, "body", 12, CREAM)
  self.info:SetJustifyH("RIGHT")
  self.info:SetWordWrap(true)
  self.info:SetPoint("TOPRIGHT", self.title, "BOTTOMRIGHT", 0, -3)

  f:Hide()
  return self
end

-- The taxi map's art for the Overlay style's terrain, or false when there's none. Cached per map.
local artCache = {}
function MapView.Art(mapID)
  if artCache[mapID] ~= nil then return artCache[mapID] end
  local art = false
  pcall(function()
    local layer = C_Map.GetMapArtLayers(mapID)[1]
    local files = C_Map.GetMapArtLayerTextures(mapID, 1)
    local lw, lh, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
    if lw > 0 and lh > 0 and tw > 0 and th > 0 and type(files) == "table" and #files > 0 then
      art = { aspect = lw / lh, layerW = lw, layerH = lh, tileW = tw, tileH = th,
        cols = math.ceil(lw / tw), files = files }
    end
  end)
  artCache[mapID] = art
  return art
end

local function DrawStrip(self, d, w, h)
  local r = Layout.MapStrip(w, h, d.bars)
  local strip, route = self.strip, d.route
  local stops = route.stops

  self.stripBg:SetShown(not d.bars)
  self.stripBg:ClearAllPoints()
  self.stripBg:SetPoint("TOPLEFT", strip, "TOPLEFT", r.left, -r.top)
  self.stripBg:SetSize(r.width, r.height)

  local y = r.top + r.height * 0.55
  self.origin:SetText(Route.ShortName(stops[1].name))
  self.origin:ClearAllPoints()
  self.origin:SetPoint("LEFT", strip, "TOPLEFT", Layout.PAD.side, -y)
  self.dest:SetText(Route.ShortName(stops[#stops].name))
  self.dest:ClearAllPoints()
  self.dest:SetPoint("RIGHT", strip, "TOPLEFT", w - Layout.PAD.side, -y)

  local x0 = Layout.PAD.side + self.origin:GetStringWidth() + LINE_GAP
  local x1 = w - Layout.PAD.side - self.dest:GetStringWidth() - LINE_GAP
  local len = math.max(x1 - x0, 1)
  local function X(at) return x0 + len * at end

  self.stripBase:ClearAllPoints()
  self.stripBase:SetPoint("LEFT", strip, "TOPLEFT", x0, -y)
  self.stripBase:SetSize(len, 2)
  local filled = len * d.progress
  self.stripFill:SetShown(filled >= 1)
  self.stripFill:ClearAllPoints()
  self.stripFill:SetPoint("LEFT", strip, "TOPLEFT", x0, -y)
  self.stripFill:SetSize(math.max(filled, 1), 2)

  Begin(self.stripDots)
  Begin(self.stripLabels)
  Begin(self.stripLines)
  for i, s in ipairs(stops) do
    local passed = s.at <= d.progress
    local ends = i == 1 or i == #stops
    PutDot(self.stripDots, strip, X(s.at), y, ends and 6 or 7, passed and GOLD or DIM)
    if not ends and s.name then
      local label = Take(self.stripLabels)
      label:SetText(Route.ShortName(s.name))
      local color = d.nextStop == s and CREAM or DIM -- the next stop stands out
      label:SetTextColor(color[1], color[2], color[3], 1)
      label:SetPoint("TOP", strip, "TOPLEFT", X(s.at), -(y + 7))
    end
  end
  local mx = X(d.progress)
  PutArrow(self.stripLines, strip, mx, y, 1, 0, 9)
  Finish(self.stripDots)
  Finish(self.stripLabels)
  Finish(self.stripLines)

  local parts = {}
  if d.eta then parts[#parts + 1] = Route.FormatTime(d.eta) end
  if d.nextStop then parts[#parts + 1] = "next: " .. Route.ShortName(d.nextStop.name) end
  self.markerText:SetText(table.concat(parts, "  ·  "))
  self.markerText:ClearAllPoints()
  self.markerText:SetPoint("BOTTOM", strip, "TOPLEFT", mx, -(y - 8))
  self.markerText:SetShown(#parts > 0)

end

local function DrawBox(self, d, w, h)
  local r = Layout.MapBox(w, h, d.bars)
  local box, routeFrame, route = self.box, self.route, d.route
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", self.frame, "TOPLEFT", r.left, -r.top)
  box:SetSize(r.width, r.height)

  local art = d.art
  local aspect = art and art.aspect or 1 -- the spike's taxi maps are square (512x512)
  local fit = Route.Fit(route, aspect, r.width, r.height - BOX_TEXT_H, BOX_PAD)
  fit.oy = fit.oy + BOX_TEXT_H
  local function P(x, y) return Route.Place(fit, x, y) end

  -- Terrain: the whole taxi map's art in the route's space, faded at the box's edges.
  Begin(self.tiles)
  self.terrain:SetShown(art and true or false)
  if art then
    local k = aspect * fit.scale / art.layerW -- box units per art pixel
    for i, file in ipairs(art.files) do
      local col, row = (i - 1) % art.cols, math.floor((i - 1) / art.cols)
      local t = Take(self.tiles)
      t:SetTexture(file)
      t:SetDesaturated(true)
      t:SetVertexColor(TEAL[1], TEAL[2], TEAL[3], 1)
      t:SetSize(art.tileW * k, art.tileH * k)
      t:SetPoint("TOPLEFT", self.terrain, "TOPLEFT", fit.ox + col * art.tileW * k, -(fit.oy + row * art.tileH * k))
    end
    self.terrain:SetAlpha(TERRAIN_MAX * d.strength / 100)
  end
  Finish(self.tiles)

  -- Travelled: solid gold. Still to fly: dotted.
  Begin(self.boxLines)
  local function Dotted(ax, ay, bx, by)
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    if len <= 0 then return end
    local ux, uy = (bx - ax) / len, (by - ay) / len
    for s = 0, len, DOT + GAP do
      local e = math.min(s + DOT, len)
      PutLine(self.boxLines, routeFrame, ax + ux * s, ay + uy * s, ax + ux * e, ay + uy * e, 2, CREAM, 0.8)
    end
  end
  local stops = route.stops
  local px, py, hx, hy = Route.PointAt(route, d.progress)
  local mx, my = P(px, py)
  for i = 1, #stops - 1 do
    local a, b = stops[i], stops[i + 1]
    local ax, ay = P(a.x, a.y)
    local bx, by = P(b.x, b.y)
    if b.at <= d.progress then
      PutLine(self.boxLines, routeFrame, ax, ay, bx, by, 2.5, GOLD)
    elseif a.at >= d.progress then
      Dotted(ax, ay, bx, by)
    else
      PutLine(self.boxLines, routeFrame, ax, ay, mx, my, 2.5, GOLD)
      Dotted(mx, my, bx, by)
    end
  end
  -- The heading in box units: x is stretched by the map's aspect.
  local dx, dy = hx * aspect, hy
  local hl = math.sqrt(dx * dx + dy * dy)
  if hl > 0 then dx, dy = dx / hl, dy / hl end
  PutArrow(self.boxLines, routeFrame, mx, my, dx, dy, 11)
  Finish(self.boxLines)

  Begin(self.boxDots)
  Begin(self.boxLabels)
  for i, s in ipairs(stops) do
    local x, y = P(s.x, s.y)
    local ends = i == 1 or i == #stops
    PutDot(self.boxDots, routeFrame, x, y, ends and 8 or 6, s.at <= d.progress and GOLD or CREAM)
    if s.name then
      local label = Take(self.boxLabels)
      label:SetText(Route.ShortName(s.name))
      if x > r.width * 0.62 then
        label:SetPoint("RIGHT", routeFrame, "TOPLEFT", x - 8, -y)
      else
        label:SetPoint("LEFT", routeFrame, "TOPLEFT", x + 8, -y)
      end
    end
  end
  Finish(self.boxDots)
  Finish(self.boxLabels)

  self.title:SetText(Route.ShortName(stops[#stops].name))
  local lines = {}
  if d.eta then lines[#lines + 1] = Route.FormatTime(d.eta) .. " to arrival" end
  if d.nextStop then lines[#lines + 1] = "Next stop: " .. Route.ShortName(d.nextStop.name) end
  self.info:SetText(table.concat(lines, "\n"))
  self.info:SetShown(#lines > 0)
end

-- d: { style = "strip" | "overlay" | "off", bars, route, progress, eta, nextStop, art, strength }.
-- eta, nextStop and art are nil when not shown; Map.lua decides which details
-- are on. nextStop is a stop on the way, never the destination.
function MapView:Apply(d)
  if not d or d.style == "off" or not d.route then
    self.frame:Hide()
    return
  end
  local w, h = self.root:GetWidth(), self.root:GetHeight()
  self.frame:Show()
  self.strip:SetShown(d.style == "strip")
  self.box:SetShown(d.style == "overlay")
  if d.style == "strip" then
    DrawStrip(self, d, w, h)
  else
    DrawBox(self, d, w, h)
  end
end

function MapView:Hide()
  self.frame:Hide()
end
