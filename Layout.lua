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
  { title = "Overlay", keys = { "bars", "fade", "surname" },
    labels = { "Letterbox bars", "Fade text after 10s", "Show surname" } },
  { title = "Camera", keys = { "orbit", "zoom" },
    labels = { "Slow orbit", "Zoom out" } },
}

-- Photo mode -------------------------------------------------------------------

-- Shot types, in the order a photo saves them.
Layout.PHOTO_TYPES = { "clean", "stamped", "vignetted", "saturated", "sepia" }
Layout.PHOTO_TYPE_NAMES = {
  clean = "Clean", stamped = "Stamped", vignetted = "Vignetted", saturated = "Saturated", sepia = "Sepia",
}

-- The stamp's lines, drawn by Overlay like the text elements, stacked in this order.
Layout.STAMP_ORDER = { "name", "guild", "zone", "date" }
Layout.STAMP_META = {
  name  = { label = "Name",  font = "title", size = 22, color = { 1.00, 0.96, 0.86 } },
  guild = { label = "Guild", font = "body",  size = 13, color = { 0.65, 0.94, 0.63 } },
  zone  = { label = "Zone",  font = "body",  size = 13, color = { 1.00, 0.91, 0.82 }, caps = true },
  date  = { label = "Date",  font = "body",  size = 12, color = { 0.85, 0.82, 0.76 } },
}
Layout.STAMP_CORNERS = { "TL", "TR", "BL", "BR" }

Layout.FRAMES = { "full", "film", "square", "portrait" }
Layout.FRAME_NAMES = { full = "Full", film = "Film 2.39:1", square = "Square", portrait = "Portrait 9:16" }
local FRAME_RATIO = { film = 2.39, square = 1, portrait = 9 / 16 }

Layout.CAMERAS = { "current", "portrait", "profile", "wide" }
Layout.CAMERA_NAMES = { current = "Current", portrait = "Portrait", profile = "Profile", wide = "Wide" }

Layout.TIMERS = { 0, 3, 5, 10 } -- seconds; 0 = off

Layout.FORMATS = { "jpeg", "png" } -- the values the screenshotFormat CVar takes
Layout.FORMAT_NAMES = { jpeg = "JPG", png = "PNG" }

Layout.AUTO = { "level", "zone", "achievement", "boss" }
Layout.AUTO_NAMES = {
  level = "Level up", zone = "First visit to a zone", achievement = "Achievement", boss = "Boss defeated",
}

-- Saved-variables schema. v1 (Reverie 0.1.x) had no version key and stored free
-- positions as screen percentages (0-100); v2 stores them as fractions (0-1).
Layout.SCHEMA = 2

-- Spacing in UI units: from the screen's left/right edges, from a letterbox bar,
-- from the top/bottom edge without bars, and between stacked lines.
Layout.PAD = { side = 60, bar = 18, edge = 24, line = 4 }

-- x/y: where a free element's centre sits, as fractions of the screen.
local DEFAULTS = {
  version = Layout.SCHEMA,
  elements = {
    name    = { show = true,  anchor = "BL", free = false, x = 0.20, y = 0.72 },
    guild   = { show = true,  anchor = "BL", free = false, x = 0.20, y = 0.79 },
    realm   = { show = false, anchor = "BL", free = false, x = 0.20, y = 0.84 },
    level   = { show = true,  anchor = "BL", free = false, x = 0.20, y = 0.88 },
    zone    = { show = true,  anchor = "TC", free = false, x = 0.50, y = 0.16 },
    subzone = { show = true,  anchor = "TC", free = false, x = 0.50, y = 0.22 },
    away    = { show = true,  anchor = "TR", free = false, x = 0.85, y = 0.12 },
  },
  options = { taxi = true, flying = true, afk = true, bars = true, fade = true, surname = true,
    orbit = true, zoom = true },
  photo = {
    types = { clean = true, stamped = true, vignetted = true, saturated = true, sepia = true },
    stamp = { name = true, guild = true, zone = true, date = true, corner = "BR" },
    vignette = 60,      -- strength, 0 to 100
    frame = "film",     -- crop guide only; the saved file is always the full screen
    camera = "current",
    timer = 3,          -- seconds
    hidePlates = true,
    hideNames = true,
    hideExtras = false,
    format = "jpeg",
    quality = 9,        -- 1 to 10
    auto = { level = true, zone = false, achievement = false, boss = false },
  },
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

local function set(list)
  local out = {}
  for _, v in ipairs(list) do out[v] = true end
  return out
end

local VALID_ANCHOR = set(Layout.ANCHORS)
local VALID_CORNER = set(Layout.STAMP_CORNERS)
local VALID_FRAME = set(Layout.FRAMES)
local VALID_CAMERA = set(Layout.CAMERAS)
local VALID_TIMER = set(Layout.TIMERS)
local VALID_FORMAT = set(Layout.FORMATS)

function Layout.Defaults()
  return copy(DEFAULTS)
end

-- Brings a save up to Layout.SCHEMA. Returns a new table (the input is left alone), or nil
-- if there's no save. Everything it doesn't understand is carried over untouched.
function Layout.Migrate(saved)
  if type(saved) ~= "table" then return nil end
  local out = copy(saved)
  local version = type(out.version) == "number" and out.version or 1

  -- v1 stored percentages. Only values above 1 are percentages: a downgrade to 0.1.x drops
  -- the version key but keeps v2 fractions, and those must not be divided again.
  if version < 2 and type(out.elements) == "table" then
    for _, e in pairs(out.elements) do
      if type(e) == "table" then
        if type(e.x) == "number" and e.x > 1 then e.x = e.x / 100 end
        if type(e.y) == "number" and e.y > 1 then e.y = e.y / 100 end
      end
    end
  end

  if version < Layout.SCHEMA then out.version = Layout.SCHEMA end
  return out
end

local function position(v, default)
  if type(v) ~= "number" or v ~= v then return default end -- v ~= v catches NaN
  return clamp(v, 0, 1)
end

-- Merge helpers: each replaces a bad or missing value with its default and leaves other keys alone.
local function subtable(parent, key)
  if type(parent[key]) ~= "table" then parent[key] = {} end
  return parent[key]
end

local function booleans(t, defaults)
  for key, def in pairs(defaults) do
    if type(def) == "boolean" and type(t[key]) ~= "boolean" then t[key] = def end
  end
end

local function choice(v, valid, default)
  if v ~= nil and valid[v] then return v end
  return default
end

local function wholeNumber(v, lo, hi, default)
  if type(v) ~= "number" or v ~= v then return default end
  v = math.floor(v + 0.5)
  if v < lo or v > hi then return default end
  return v
end

local function MergePhoto(out, defaults)
  local p = subtable(out, "photo")
  booleans(p, defaults)
  booleans(subtable(p, "types"), defaults.types)
  local stamp = subtable(p, "stamp")
  booleans(stamp, defaults.stamp)
  stamp.corner = choice(stamp.corner, VALID_CORNER, defaults.stamp.corner)
  p.vignette = wholeNumber(p.vignette, 0, 100, defaults.vignette)
  p.frame = choice(p.frame, VALID_FRAME, defaults.frame)
  p.camera = choice(p.camera, VALID_CAMERA, defaults.camera)
  p.timer = choice(p.timer, VALID_TIMER, defaults.timer)
  p.format = choice(p.format, VALID_FORMAT, defaults.format)
  p.quality = wholeNumber(p.quality, 1, 10, defaults.quality)
  booleans(subtable(p, "auto"), defaults.auto)
end

-- Builds settings from saved variables: migrates, keeps the user's values and any keys it
-- doesn't know, replaces malformed known values with defaults, and fills gaps with defaults.
-- A hand-edited SavedVariables file can't break the overlay.
function Layout.Merge(saved)
  local defaults = Layout.Defaults()
  local out = Layout.Migrate(saved) or {}
  out.version = type(out.version) == "number" and out.version or Layout.SCHEMA

  if type(out.elements) ~= "table" then out.elements = {} end
  for id, def in pairs(defaults.elements) do
    local e = out.elements[id]
    if type(e) ~= "table" then
      e = {}
      out.elements[id] = e
    end
    if type(e.show) ~= "boolean" then e.show = def.show end
    if type(e.free) ~= "boolean" then e.free = def.free end
    if not VALID_ANCHOR[e.anchor] then e.anchor = def.anchor end
    e.x = position(e.x, def.x)
    e.y = position(e.y, def.y)
  end

  if type(out.options) ~= "table" then out.options = {} end
  for key, def in pairs(defaults.options) do
    if type(out.options[key]) ~= "boolean" then out.options[key] = def end
  end

  MergePhoto(out, defaults.photo)
  return out
end

-- Where each element's text goes, as its top-left corner in screen units (y grows downward).
--   sizes:   id -> { w, h } of the rendered text; elements with no text have no entry and are
--            skipped, so they leave no gap.
--   showAll: place hidden elements too (unlock mode).
--   order:   element ids in stacking order; Layout.ORDER by default (the photo stamp passes its own).
-- Anchored elements sharing an anchor stack in Layout.ORDER, aligned to that side. Top and
-- bottom anchors sit inside the letterbox bars when they're on. Free elements are centred on
-- their x/y fraction of the screen.
function Layout.Positions(settings, screenW, screenH, sizes, showAll, order)
  local PAD = Layout.PAD
  local barH = Layout.BarHeight(screenH, settings.options.bars)
  local edge = barH > 0 and (barH + PAD.bar) or PAD.edge

  local out, stacks = {}, {}
  for _, a in ipairs(Layout.ANCHORS) do stacks[a] = {} end

  for _, id in ipairs(order or Layout.ORDER) do
    local e, size = settings.elements[id], sizes[id]
    if size and (e.show or showAll) then
      if e.free then
        out[id] = { left = e.x * screenW - size.w / 2, top = e.y * screenH - size.h / 2 }
      else
        table.insert(stacks[e.anchor], id)
      end
    end
  end

  for anchor, ids in pairs(stacks) do
    if #ids > 0 then
      local total = PAD.line * (#ids - 1)
      for _, id in ipairs(ids) do total = total + sizes[id].h end

      local row, col = anchor:sub(1, 1), anchor:sub(2, 2)
      local y
      if row == "T" then
        y = edge
      elseif row == "B" then
        y = screenH - edge - total
      else
        y = (screenH - total) / 2
      end

      for _, id in ipairs(ids) do
        local size = sizes[id]
        local left
        if col == "L" then
          left = PAD.side
        elseif col == "R" then
          left = screenW - PAD.side - size.w
        else
          left = (screenW - size.w) / 2
        end
        out[id] = { left = left, top = y }
        y = y + size.h + PAD.line
      end
    end
  end

  return out
end

-- Ticked shot types, in Layout.PHOTO_TYPES order.
function Layout.TickedTypes(photo)
  local out = {}
  for _, t in ipairs(Layout.PHOTO_TYPES) do
    if photo.types[t] then out[#out + 1] = t end
  end
  return out
end

-- The largest centred rectangle with the frame's aspect ratio that fits the screen, as
-- { left, top, width, height } in screen units from the top-left. "full" is the whole screen.
function Layout.CropRect(frame, screenW, screenH)
  local ratio = FRAME_RATIO[frame]
  if not ratio or screenH <= 0 then return { left = 0, top = 0, width = screenW, height = screenH } end
  if screenW / screenH > ratio then
    local width = screenH * ratio
    return { left = (screenW - width) / 2, top = 0, width = width, height = screenH }
  end
  local height = screenW / ratio
  return { left = 0, top = (screenH - height) / 2, width = screenW, height = height }
end

-- Stamp line text for each Layout.STAMP_ORDER id. parts: id -> raw string (guild without
-- brackets). Unticked or empty parts give "", which the layout skips.
function Layout.StampTexts(stamp, parts)
  local out = {}
  for _, id in ipairs(Layout.STAMP_ORDER) do
    local v = parts[id]
    if stamp[id] and type(v) == "string" and v ~= "" then
      out[id] = id == "guild" and ("<" .. v .. ">") or v
    else
      out[id] = ""
    end
  end
  return out
end

-- Settings shaped for Layout.Positions and Overlay, placing the stamp lines in their corner.
-- Photos have no letterbox bars.
function Layout.StampSettings(photo)
  local elements = {}
  for _, id in ipairs(Layout.STAMP_ORDER) do
    elements[id] = { show = photo.stamp[id] and true or false, anchor = photo.stamp.corner, free = false, x = 0, y = 0 }
  end
  return { options = { bars = false }, elements = elements }
end

-- A dropped element's centre (screen units from the top-left) as clamped x/y fractions.
function Layout.FreeFromPoint(px, py, screenW, screenH)
  if screenW <= 0 or screenH <= 0 then return 0.5, 0.5 end
  return clamp(px / screenW, 0, 1), clamp(py / screenH, 0, 1)
end

Layout.TEXT_USAGE = "/reverie text <element> on|off, /reverie text <element> anchor <TL|TC|TR|ML|MC|MR|BL|BC|BR>, "
  .. "/reverie text <element> free. Elements: " .. table.concat(Layout.ORDER, ", ")

-- Parses what follows "/reverie text". Returns { id, show | anchor | free } or nil, message.
function Layout.ParseTextCommand(args)
  local words = {}
  for word in tostring(args or ""):gmatch("%S+") do words[#words + 1] = word:lower() end
  local id, verb, arg = words[1], words[2], words[3]

  if not id then return nil, Layout.TEXT_USAGE end
  if not Layout.META[id] then
    return nil, "Unknown element '" .. id .. "'. Elements: " .. table.concat(Layout.ORDER, ", ")
  end

  if #words == 2 and (verb == "on" or verb == "off") then
    return { id = id, show = verb == "on" }
  elseif #words == 2 and verb == "free" then
    return { id = id, free = true }
  elseif #words == 3 and verb == "anchor" then
    local anchor = arg:upper()
    if VALID_ANCHOR[anchor] then return { id = id, anchor = anchor } end
    return nil, "Anchor must be one of " .. table.concat(Layout.ANCHORS, ", ")
  end
  return nil, Layout.TEXT_USAGE
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

-- Character name for the title card. Forever characters can have a surname, which may
-- arrive as a separate value or inside one "First Last" string; full = false keeps the first name.
function Layout.DisplayName(name, surname, full)
  name = name or ""
  if surname and surname ~= "" then
    return full and (name .. " " .. surname) or name
  end
  if full then return name end
  return name:match("^(%S+)") or name
end

-- Letterbox bar height: 11% of the screen, as in the design (79px at 720p).
function Layout.BarHeight(screenHeight, barsOn)
  if not barsOn then return 0 end
  return math.floor(screenHeight * 0.11 + 0.5)
end
