-- Pure layout logic: no WoW API calls, so tests/run.lua can load it outside the client.
local _, ns = ...

local Layout = {}
ns.Layout = Layout

-- Display order; elements sharing a corner stack in this order.
Layout.ORDER = { "name", "guild", "realm", "level", "zone", "subzone", "away" }

-- Labels for the options panel, and how each element is drawn.
-- font: "title" = the fantasy serif, "body" = the default UI font.
Layout.META = {
  name    = { label = "Character name",     font = "title", size = 30, color = { 1.00, 0.96, 0.86 } },
  guild   = { label = "Guild",              font = "body",  size = 15, color = { 0.65, 0.94, 0.63 } },
  realm   = { label = "Realm",              font = "body",  size = 13, color = { 0.94, 0.89, 0.82 } },
  level   = { label = "Level, race, class", font = "body",  size = 14, color = { 0.93, 0.93, 0.93 } },
  zone    = { label = "Zone",               font = "title", size = 24, color = { 1.00, 0.96, 0.86 }, caps = true },
  subzone = { label = "Subzone",            font = "body",  size = 13, color = { 1.00, 0.91, 0.82 }, caps = true },
  away    = { label = "Away timer",         font = "body",  size = 14, color = { 0.93, 0.86, 0.69 }, caps = true },
}

Layout.ANCHORS = { "TL", "TC", "TR", "ML", "MC", "MR", "BL", "BC", "BR" }

Layout.ANCHOR_NAMES = {
  TL = "Top left",    TC = "Top middle",    TR = "Top right",
  ML = "Middle left", MC = "Centre",        MR = "Middle right",
  BL = "Bottom left", BC = "Bottom middle", BR = "Bottom right",
}

-- Option keys, grouped as the options panel shows them.
Layout.OPTION_GROUPS = {
  { title = "Start automatically", keys = { "taxi", "flying", "afk" },
    labels = { "Flight paths", "Flying mount", "When AFK" } },
  { title = "Overlay", keys = { "bars", "fade" },
    labels = { "Letterbox bars", "Fade text after 10s" } },
  { title = "Camera", keys = { "orbit", "zoom" },
    labels = { "Slow orbit", "Zoom out" } },
}

local DEFAULTS = {
  elements = {
    name    = { show = true,  anchor = "BL", free = false, x = 20, y = 72 },
    guild   = { show = true,  anchor = "BL", free = false, x = 20, y = 79 },
    realm   = { show = false, anchor = "BL", free = false, x = 20, y = 84 },
    level   = { show = true,  anchor = "BL", free = false, x = 20, y = 88 },
    zone    = { show = true,  anchor = "TC", free = false, x = 50, y = 16 },
    subzone = { show = true,  anchor = "TC", free = false, x = 50, y = 22 },
    away    = { show = true,  anchor = "TR", free = false, x = 85, y = 12 },
  },
  options = { taxi = true, flying = true, afk = true, bars = true, fade = true, orbit = true, zoom = true },
}

local function copy(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = type(v) == "table" and copy(v) or v
  end
  return out
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local VALID_ANCHOR = {}
for _, a in ipairs(Layout.ANCHORS) do VALID_ANCHOR[a] = true end

function Layout.Defaults()
  return copy(DEFAULTS)
end

-- Builds settings from saved variables, filling gaps with defaults and
-- discarding anything malformed, so a hand-edited SavedVariables file can't break the overlay.
function Layout.Merge(saved)
  local out = Layout.Defaults()
  if type(saved) ~= "table" then return out end

  if type(saved.elements) == "table" then
    for id, def in pairs(out.elements) do
      local s = saved.elements[id]
      if type(s) == "table" then
        if type(s.show) == "boolean" then def.show = s.show end
        if type(s.free) == "boolean" then def.free = s.free end
        if VALID_ANCHOR[s.anchor] then def.anchor = s.anchor end
        if type(s.x) == "number" then def.x = clamp(s.x, 0, 100) end
        if type(s.y) == "number" then def.y = clamp(s.y, 0, 100) end
      end
    end
  end

  if type(saved.options) == "table" then
    for key in pairs(out.options) do
      if type(saved.options[key]) == "boolean" then out.options[key] = saved.options[key] end
    end
  end

  return out
end

-- anchor -> ordered list of element ids shown there (free-positioned ones excluded).
function Layout.Cells(settings)
  local cells = {}
  for _, a in ipairs(Layout.ANCHORS) do cells[a] = {} end
  for _, id in ipairs(Layout.ORDER) do
    local e = settings.elements[id]
    if e.show and not e.free then
      table.insert(cells[e.anchor], id)
    end
  end
  return cells
end

function Layout.FreeItems(settings)
  local list = {}
  for _, id in ipairs(Layout.ORDER) do
    local e = settings.elements[id]
    if e.show and e.free then table.insert(list, id) end
  end
  return list
end

function Layout.FormatAway(seconds)
  seconds = math.floor(seconds)
  local h = math.floor(seconds / 3600)
  local m = math.floor(seconds / 60) % 60
  local s = seconds % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

-- Letterbox bar height: 11% of the screen, as in the design (79px at 720p).
function Layout.BarHeight(screenHeight, barsOn)
  if not barsOn then return 0 end
  return math.floor(screenHeight * 0.11 + 0.5)
end
