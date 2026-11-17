-- Draws the flight map into a root frame: the Strip style in the bottom letterbox bar, or the
-- Overlay style's route over the view in the bottom right. Used twice: on the overlay in game
-- (Map.lua), and scaled down in the options preview (MapOptions.lua). Placement comes from
-- Layout.MapStrip / Layout.MapBox, so Layout.MapReserve keeps bottom text clear of it.
--
-- Built on what the spike (#54) proved on Forever: CreateLine for routes, the taxi map's own art
-- (GetMapArtLayers / GetMapArtLayerTextures), desaturate + vertex colour + alpha, and our own
-- soft-edged mask textures (the game's masks are all hard cut-outs). The Overlay style's textures
-- (textures/Map*.tga) come from tools/make_textures.py. Not proven in the spike, so on the PR's
-- checklist: textured Lines with ADD blend (the route glow) and SetRotation (the marker).
local addonName, ns = ...
local Layout, Route = ns.Layout, ns.Route

local MapView = {}
MapView.__index = MapView
ns.MapView = MapView

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TEX = "Interface\\AddOns\\" .. addonName .. "\\textures\\"
local TERRAIN_MASK = TEX .. "MapTerrainMask" -- a smaller solid centre and a steeper fade than MapMask
local BACKING_MASK = TEX .. "MapBacking"     -- soft rounded falloff, nothing well inside its edges
local GLOW_LINE = TEX .. "MapGlowLine"       -- white along the middle, clear across the width
local GLOW = TEX .. "MapGlow"                -- round soft glow
local ARROW = TEX .. "MapArrow"              -- filled arrow pointing right, with a dark edge
local FONTS = { title = "Fonts\\MORPHEUS.TTF", body = "Fonts\\FRIZQT__.TTF" }

local GOLD = { 0.88, 0.72, 0.38 }
local CREAM = { 1.00, 0.96, 0.86 }
local DIM = { 0.80, 0.76, 0.70 }
-- Overlay style.
local ROUTE_GOLD = { 0.96, 0.78, 0.41 }
local INK = { 0.06, 0.05, 0.07 }       -- the dark centre of each stop's ring
local CHARCOAL = { 0.30, 0.29, 0.33 }  -- terrain: darkened relief, not a tint
local TERRAIN_MAX = 0.85               -- terrain alpha at strength 100
local BACKING_ALPHA = 0.55             -- the dark backing, in the middle
local STRIP_FADE = 0.75           -- the dark gradient under a strip without bars
local LINE_GAP = 16               -- strip: between a name and the line
local BOX_PAD = 26                -- overlay: between the route and the box's edges
local BOX_TEXT_H = 66             -- overlay: room at the top for the destination block
local ROUTE_W = 4                 -- overlay: travelled route
local GLOW_W, GLOW_ALPHA = 12, 0.35 -- overlay: the glow line under it
local DASH, GAP = 10, 8           -- overlay: the remaining route's dashes and the gaps between
local REMAIN_W, REMAIN_ALPHA = 3, 0.85
local RING, RING_INNER = 12, 6    -- overlay: a stop's gold ring and its dark centre
local DEST_RING, DEST_INNER = 18, 11
local DEST_GLOW, MARKER_GLOW, SOFT_GLOW_ALPHA = 46, 44, 0.35
local MARKER = 22
local LABEL_SIZE = 15             -- overlay: stop names

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

local function Label(parent, font, size, color, flags)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONTS[font], size, flags or "")
  fs:SetTextColor(color[1], color[2], color[3], 1)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
  fs:SetWordWrap(false)
  return fs
end

local function Dot(parent, sublevel)
  local t = parent:CreateTexture(nil, "OVERLAY", nil, sublevel)
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

-- A soft glow under a line: the glow texture, tinted, added to what's behind it.
local function PutGlowLine(pool, parent, ax, ay, bx, by)
  local l = Take(pool)
  l:SetStartPoint("TOPLEFT", parent, ax, -ay)
  l:SetEndPoint("TOPLEFT", parent, bx, -by)
  l:SetThickness(GLOW_W)
  l:SetVertexColor(ROUTE_GOLD[1], ROUTE_GOLD[2], ROUTE_GOLD[3], GLOW_ALPHA)
end

-- A round soft glow centred on x, y.
local function PutGlow(pool, parent, x, y, size)
  local g = Take(pool)
  g:SetSize(size, size)
  g:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
end

-- The strip's flight marker: a chevron at x, y pointing along the unit heading dx, dy.
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

  -- Overlay, back to front: a dark backing reaching past the box, the terrain (clipped to the
  -- box), then the route, stops, marker and labels.
  self.box = CreateFrame("Frame", nil, f)
  local box = self.box
  local reach = Layout.MAP_BACKING
  self.backing = box:CreateTexture(nil, "BACKGROUND")
  self.backing:SetTexture(WHITE)
  self.backing:SetVertexColor(0, 0, 0, BACKING_ALPHA)
  self.backing:SetPoint("TOPLEFT", box, "TOPLEFT", -reach, reach)
  self.backing:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", reach, -reach)
  local backingMask = box:CreateMaskTexture()
  backingMask:SetTexture(BACKING_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  backingMask:SetAllPoints(self.backing)
  self.backing:AddMaskTexture(backingMask)

  self.terrain = CreateFrame("Frame", nil, box)
  self.terrain:SetAllPoints()
  self.terrain:SetClipsChildren(true)
  self.terrainMask = self.terrain:CreateMaskTexture()
  self.terrainMask:SetTexture(TERRAIN_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  self.terrainMask:SetAllPoints(box)
  self.tiles = Pool(function()
    local t = self.terrain:CreateTexture(nil, "ARTWORK")
    t:AddMaskTexture(self.terrainMask)
    return t
  end)

  self.route = CreateFrame("Frame", nil, box)
  self.route:SetAllPoints()
  local route = self.route
  self.glowLines = Pool(function()
    local l = route:CreateLine(nil, "ARTWORK", nil, 0)
    l:SetTexture(GLOW_LINE)
    l:SetBlendMode("ADD")
    return l
  end)
  self.boxLines = Pool(function() return route:CreateLine(nil, "ARTWORK", nil, 2) end)
  self.glows = Pool(function()
    local t = route:CreateTexture(nil, "OVERLAY", nil, 0)
    t:SetTexture(GLOW)
    t:SetBlendMode("ADD")
    t:SetVertexColor(ROUTE_GOLD[1], ROUTE_GOLD[2], ROUTE_GOLD[3], SOFT_GLOW_ALPHA)
    return t
  end)
  self.rings = Pool(function() return Dot(route, 1) end)
  self.ringCentres = Pool(function() return Dot(route, 2) end)
  self.marker = route:CreateTexture(nil, "OVERLAY", nil, 3)
  self.marker:SetTexture(ARROW)
  self.marker:SetSize(MARKER, MARKER)
  self.marker:SetVertexColor(ROUTE_GOLD[1], ROUTE_GOLD[2], ROUTE_GOLD[3], 1)
  self.boxLabels = Pool(function() return Label(route, "body", LABEL_SIZE, CREAM, "OUTLINE") end)
  -- Top right, the map's own label: "Flying to" small, the destination in gold, then the details.
  -- Smaller and a different colour from the title card's name, so the two never read as one.
  self.flyingTo = Label(route, "body", 11, DIM)
  self.flyingTo:SetJustifyH("RIGHT")
  self.flyingTo:SetPoint("TOPRIGHT")
  self.flyingTo:SetText("Flying to")
  self.title = Label(route, "title", 20, ROUTE_GOLD)
  self.title:SetJustifyH("RIGHT")
  self.title:SetPoint("TOPRIGHT", self.flyingTo, "BOTTOMRIGHT", 0, -2)
  self.info = Label(route, "body", 12, CREAM)
  self.info:SetJustifyH("RIGHT")
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
      t:SetVertexColor(CHARCOAL[1], CHARCOAL[2], CHARCOAL[3], 1)
      t:SetSize(art.tileW * k, art.tileH * k)
      t:SetPoint("TOPLEFT", self.terrain, "TOPLEFT", fit.ox + col * art.tileW * k, -(fit.oy + row * art.tileH * k))
    end
    self.terrain:SetAlpha(TERRAIN_MAX * d.strength / 100)
  end
  Finish(self.tiles)

  -- Travelled: solid gold over a soft glow. Still to fly: cream dashes.
  Begin(self.boxLines)
  Begin(self.glowLines)
  local function Solid(ax, ay, bx, by)
    PutGlowLine(self.glowLines, routeFrame, ax, ay, bx, by)
    PutLine(self.boxLines, routeFrame, ax, ay, bx, by, ROUTE_W, ROUTE_GOLD)
  end
  local function Dashed(ax, ay, bx, by)
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    if len <= 0 then return end
    local ux, uy = (bx - ax) / len, (by - ay) / len
    for s = 0, len, DASH + GAP do
      local e = math.min(s + DASH, len)
      PutLine(self.boxLines, routeFrame, ax + ux * s, ay + uy * s, ax + ux * e, ay + uy * e,
        REMAIN_W, CREAM, REMAIN_ALPHA)
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
      Solid(ax, ay, bx, by)
    elseif a.at >= d.progress then
      Dashed(ax, ay, bx, by)
    else
      Solid(ax, ay, mx, my)
      Dashed(mx, my, bx, by)
    end
  end
  Finish(self.boxLines)
  Finish(self.glowLines)

  -- Stops: a gold ring with a dark centre; the destination larger, with a glow behind it.
  Begin(self.glows)
  Begin(self.rings)
  Begin(self.ringCentres)
  Begin(self.boxLabels)
  for i, s in ipairs(stops) do
    local x, y = P(s.x, s.y)
    local dest = i == #stops
    if dest then PutGlow(self.glows, routeFrame, x, y, DEST_GLOW) end
    local outer = dest and DEST_RING or RING
    PutDot(self.rings, routeFrame, x, y, outer, ROUTE_GOLD)
    PutDot(self.ringCentres, routeFrame, x, y, dest and DEST_INNER or RING_INNER, INK)
    if s.name then
      local label = Take(self.boxLabels)
      label:SetText(Route.ShortName(s.name))
      local gap = outer / 2 + 6
      if x > r.width * 0.62 then
        label:SetPoint("RIGHT", routeFrame, "TOPLEFT", x - gap, -y)
      else
        label:SetPoint("LEFT", routeFrame, "TOPLEFT", x + gap, -y)
      end
    end
  end

  -- The marker: the arrow turned to the heading, with a glow behind it. The heading is in box
  -- units (x stretched by the map's aspect); SetRotation turns anticlockwise with y up.
  PutGlow(self.glows, routeFrame, mx, my, MARKER_GLOW)
  self.marker:ClearAllPoints()
  self.marker:SetPoint("CENTER", routeFrame, "TOPLEFT", mx, -my)
  self.marker:SetRotation(math.atan2(-hy, hx * aspect))
  Finish(self.glows)
  Finish(self.rings)
  Finish(self.ringCentres)
  Finish(self.boxLabels)

  self.title:SetText(Route.ShortName(stops[#stops].name))
  local parts = {}
  if d.eta then parts[#parts + 1] = Route.FormatTime(d.eta) .. " to arrival" end
  if d.nextStop then parts[#parts + 1] = "next stop " .. Route.ShortName(d.nextStop.name) end
  self.info:SetText(table.concat(parts, "  ·  "))
  self.info:SetShown(#parts > 0)
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
