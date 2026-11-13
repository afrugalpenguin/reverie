-- Plain Lua 5.1 test runner for Reverie's pure logic (no WoW client needed).
-- Run from the repo root:  lua tests/run.lua
local ns = {}
assert(loadfile("Layout.lua"))("Reverie", ns)
local L = ns.Layout

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL " .. name .. "\n  " .. tostring(err))
  end
end

local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function near(actual, expected, msg)
  if type(actual) ~= "number" or math.abs(actual - expected) > 1e-9 then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

-- Every element with the same text size, unless overridden.
local function sizes(w, h, overrides)
  local out = {}
  for _, id in ipairs(L.ORDER) do out[id] = { w = w, h = h } end
  for id, s in pairs(overrides or {}) do out[id] = s end
  return out
end

-- Settings with only `id` shown, at `anchor`.
local function only(id, anchor, bars)
  local s = L.Defaults()
  for _, other in ipairs(L.ORDER) do s.elements[other].show = false end
  s.elements[id].show = true
  s.elements[id].anchor = anchor
  s.options.bars = bars
  return s
end

-- Defaults --------------------------------------------------------------------

test("defaults match the design's options panel", function()
  local d = L.Defaults()
  eq(d.version, L.SCHEMA)
  eq(d.elements.name.show, true)
  eq(d.elements.name.anchor, "BL")
  eq(d.elements.guild.anchor, "BL")
  eq(d.elements.level.anchor, "BL")
  eq(d.elements.realm.show, false)
  eq(d.elements.zone.anchor, "TC")
  eq(d.elements.subzone.anchor, "TC")
  eq(d.elements.away.anchor, "TR")
  eq(d.options.bars, true)
  eq(d.options.fade, true)
  eq(d.options.taxi, true)
end)

test("Defaults returns a fresh copy each time", function()
  local a = L.Defaults()
  a.elements.name.show = false
  eq(L.Defaults().elements.name.show, true)
end)

test("default free positions are fractions of the screen", function()
  for _, id in ipairs(L.ORDER) do
    local e = L.Defaults().elements[id]
    eq(e.x >= 0 and e.x <= 1 and e.y >= 0 and e.y <= 1, true, id)
  end
end)

-- Migration and merge ---------------------------------------------------------

-- What v0.1.0 / v0.1.1 actually wrote to ReverieDB: no version, x/y in percent.
local function v011Save()
  return {
    elements = {
      name  = { show = false, anchor = "TL", free = false, x = 20, y = 72 },
      guild = { show = true, anchor = "BL", free = true, x = 35, y = 60 },
      zone  = { show = true, anchor = "BC", free = false, x = 50, y = 16, colour = "gold" },
      bogus = { show = true },
    },
    options = { taxi = false, flying = true, afk = true, bars = false, fade = false, surname = false,
      orbit = false, zoom = true, futureOption = 7 },
    somethingElse = { kept = true },
  }
end

test("Migrate stamps the schema version on a v0.1.x save", function()
  eq(L.Migrate(v011Save()).version, L.SCHEMA)
  eq(L.SCHEMA, 2)
end)

test("Migrate converts v0.1.x percent positions to fractions", function()
  local m = L.Migrate(v011Save())
  near(m.elements.guild.x, 0.35)
  near(m.elements.guild.y, 0.60)
  near(m.elements.name.x, 0.20)
end)

test("Migrate leaves a current save's fractions alone", function()
  local m = L.Migrate({ version = 2, elements = { guild = { x = 0.35, y = 0.6 } } })
  near(m.elements.guild.x, 0.35)
  near(m.elements.guild.y, 0.6)
end)

-- The same free placement saved three ways. A downgrade to 0.1.x rewrites ReverieDB without
-- the version key but keeps v2 fractions, so a later upgrade sees "versionless" fractions.
test("v1 percentages, versionless fractions and v2 fractions all place free elements alike", function()
  local function freeSave(x, y, version)
    return { version = version, elements = { guild = { show = true, free = true, x = x, y = y } } }
  end
  local saves = {
    v1 = freeSave(35, 60, nil),
    versionless = freeSave(0.35, 0.60, nil),
    v2 = freeSave(0.35, 0.60, 2),
  }
  for label, saved in pairs(saves) do
    local m = L.Merge(saved)
    near(m.elements.guild.x, 0.35, label .. " x")
    near(m.elements.guild.y, 0.60, label .. " y")
    local p = L.Positions(m, 1000, 800, sizes(100, 20))
    near(p.guild.left, 300, label .. " left")
    near(p.guild.top, 470, label .. " top")
  end
end)

test("Migrate is safe to run twice, even after the version key is lost", function()
  local once = L.Migrate(v011Save())
  once.version = nil -- what 0.1.x's Merge does on a downgrade
  local twice = L.Migrate(once)
  near(twice.elements.guild.x, 0.35)
  near(twice.elements.guild.y, 0.60)
  near(twice.elements.name.x, 0.20)
end)

test("Migrate does not change the table it is given", function()
  local saved = v011Save()
  L.Migrate(saved)
  eq(saved.version, nil)
  eq(saved.elements.guild.x, 35)
end)

test("Migrate returns nil for a missing save", function()
  eq(L.Migrate(nil), nil)
  eq(L.Migrate("junk"), nil)
end)

test("Merge keeps every v0.1.x user value", function()
  local m = L.Merge(v011Save())
  eq(m.version, 2)
  eq(m.elements.name.show, false)
  eq(m.elements.name.anchor, "TL")
  eq(m.elements.guild.free, true)
  near(m.elements.guild.x, 0.35)
  eq(m.elements.zone.anchor, "BC")
  eq(m.options.taxi, false)
  eq(m.options.bars, false)
  eq(m.options.fade, false)
  eq(m.options.surname, false)
  eq(m.options.orbit, false)
end)

test("Merge preserves unknown keys at every level", function()
  local m = L.Merge(v011Save())
  eq(m.somethingElse.kept, true)
  eq(m.options.futureOption, 7)
  eq(m.elements.zone.colour, "gold")
  eq(m.elements.bogus.show, true)
end)

test("Merge fills gaps with defaults", function()
  local m = L.Merge(v011Save())
  eq(m.elements.realm.show, false)        -- element missing entirely
  eq(m.elements.realm.anchor, "BL")
  eq(m.elements.zone.show, true)
  eq(m.elements.away.anchor, "TR")
  local partial = L.Merge({ version = 2, elements = { name = { show = false } }, options = { bars = false } })
  eq(partial.elements.name.anchor, "BL")
  eq(partial.elements.guild.show, true)
  eq(partial.options.fade, true)
end)

test("Merge replaces malformed known values and clamps positions", function()
  local m = L.Merge({ version = 2, elements = {
    name = { anchor = "XX", show = "yes", x = 1.4, y = -0.5 },
    guild = { x = 0 / 0 },
  }, options = { surname = "no" } })
  eq(m.elements.name.anchor, "BL")
  eq(m.elements.name.show, true)
  eq(m.elements.name.x, 1)
  eq(m.elements.name.y, 0)
  near(m.elements.guild.x, L.Defaults().elements.guild.x)
  eq(m.options.surname, true)
end)

test("Merge clamps out-of-range v0.1.x percentages after converting", function()
  local m = L.Merge({ elements = { name = { x = 140, y = -5 } } })
  eq(m.elements.name.x, 1)
  eq(m.elements.name.y, 0)
end)

test("Merge of nothing is the defaults", function()
  local m = L.Merge(nil)
  eq(m.version, 2)
  eq(m.elements.name.show, true)
  eq(m.elements.zone.anchor, "TC")
end)

-- Positions: anchors ----------------------------------------------------------

-- 1000x800 screen, 100x20 text. Without bars the edge padding is 24; sides are 60.
local ANCHOR_EXPECT_NO_BARS = {
  TL = { 60, 24 },  TC = { 450, 24 },  TR = { 840, 24 },
  ML = { 60, 390 }, MC = { 450, 390 }, MR = { 840, 390 },
  BL = { 60, 756 }, BC = { 450, 756 }, BR = { 840, 756 },
}

-- With bars: bar = floor(800 * 0.11 + 0.5) = 88, plus an 18 gap = 106 from top and bottom.
local ANCHOR_EXPECT_BARS = {
  TL = { 60, 106 },  TC = { 450, 106 },  TR = { 840, 106 },
  ML = { 60, 390 },  MC = { 450, 390 },  MR = { 840, 390 },
  BL = { 60, 674 },  BC = { 450, 674 },  BR = { 840, 674 },
}

for _, anchor in ipairs(L.ANCHORS) do
  test("anchor " .. anchor .. " without bars", function()
    local p = L.Positions(only("name", anchor, false), 1000, 800, sizes(100, 20))
    near(p.name.left, ANCHOR_EXPECT_NO_BARS[anchor][1], "left")
    near(p.name.top, ANCHOR_EXPECT_NO_BARS[anchor][2], "top")
  end)
  test("anchor " .. anchor .. " with bars", function()
    local p = L.Positions(only("name", anchor, true), 1000, 800, sizes(100, 20))
    near(p.name.left, ANCHOR_EXPECT_BARS[anchor][1], "left")
    near(p.name.top, ANCHOR_EXPECT_BARS[anchor][2], "top")
  end)
end

test("top and bottom anchors sit inside the bars' inner edge", function()
  local barH = L.BarHeight(800, true)
  local top = L.Positions(only("name", "TC", true), 1000, 800, sizes(100, 20))
  local bottom = L.Positions(only("name", "BC", true), 1000, 800, sizes(100, 20))
  eq(top.name.top > barH, true, "top anchor below the top bar")
  eq(bottom.name.top + 20 < 800 - barH, true, "bottom anchor above the bottom bar")
end)

-- Positions: stacking ---------------------------------------------------------

local function allAt(anchor, bars)
  local s = L.Defaults()
  for _, id in ipairs(L.ORDER) do
    s.elements[id].show = true
    s.elements[id].free = false
    s.elements[id].anchor = anchor
  end
  s.options.bars = bars
  return s
end

-- Distinct heights so a wrong order shows up in the numbers.
local MIXED = {
  name = { w = 200, h = 30 }, guild = { w = 120, h = 15 }, realm = { w = 90, h = 13 },
  level = { w = 160, h = 14 }, zone = { w = 220, h = 24 }, subzone = { w = 110, h = 13 },
  away = { w = 100, h = 14 },
}

for _, anchor in ipairs({ "TL", "MC", "BR" }) do
  test("stacking order is fixed at " .. anchor, function()
    local p = L.Positions(allAt(anchor, false), 1000, 800, MIXED)
    for i = 2, #L.ORDER do
      local prev, cur = L.ORDER[i - 1], L.ORDER[i]
      near(p[cur].top, p[prev].top + MIXED[prev].h + L.PAD.line, cur .. " follows " .. prev)
    end
  end)
end

test("a top stack starts at the top padding", function()
  local p = L.Positions(allAt("TC", true), 1000, 800, MIXED)
  near(p.name.top, 106)
end)

test("a bottom stack ends at the bottom padding", function()
  local p = L.Positions(allAt("BL", true), 1000, 800, MIXED)
  near(p.away.top + MIXED.away.h, 800 - 106)
  local q = L.Positions(allAt("BL", false), 1000, 800, MIXED)
  near(q.away.top + MIXED.away.h, 800 - 24)
end)

test("a middle stack is centred vertically", function()
  local p = L.Positions(allAt("ML", false), 1000, 800, MIXED)
  local total = 0
  for _, id in ipairs(L.ORDER) do total = total + MIXED[id].h end
  total = total + L.PAD.line * (#L.ORDER - 1)
  near(p.name.top, (800 - total) / 2)
end)

test("a stack aligns to its side", function()
  local left = L.Positions(allAt("BL", false), 1000, 800, MIXED)
  local right = L.Positions(allAt("BR", false), 1000, 800, MIXED)
  local centre = L.Positions(allAt("BC", false), 1000, 800, MIXED)
  for _, id in ipairs(L.ORDER) do
    near(left[id].left, 60, id .. " left edge")
    near(right[id].left + MIXED[id].w, 1000 - 60, id .. " right edge")
    near(centre[id].left + MIXED[id].w / 2, 500, id .. " centre")
  end
end)

test("the default layout stacks name, guild, level bottom left and zone, subzone top middle", function()
  local p = L.Positions(L.Defaults(), 1000, 800, MIXED)
  eq(p.realm, nil)
  near(p.guild.top, p.name.top + 30 + L.PAD.line)
  near(p.level.top, p.guild.top + 15 + L.PAD.line)
  near(p.level.top + 14, 800 - 106)
  near(p.zone.top, 106)
  near(p.subzone.top, 106 + 24 + L.PAD.line)
  near(p.away.left + 100, 1000 - 60)
end)

test("an element without text is skipped with no gap", function()
  local s = MIXED
  local noSub = {}
  for id, v in pairs(s) do noSub[id] = v end
  noSub.subzone = nil
  local p = L.Positions(allAt("TL", false), 1000, 800, noSub)
  eq(p.subzone, nil)
  near(p.away.top, p.zone.top + 24 + L.PAD.line)
end)

test("hidden elements are skipped unless showAll is set", function()
  local s = allAt("TL", false)
  s.elements.guild.show = false
  local p = L.Positions(s, 1000, 800, MIXED)
  eq(p.guild, nil)
  near(p.realm.top, p.name.top + 30 + L.PAD.line)
  local all = L.Positions(s, 1000, 800, MIXED, true)
  near(all.guild.top, all.name.top + 30 + L.PAD.line)
end)

-- Positions: free mode --------------------------------------------------------

local function freeName(x, y)
  local s = only("name", "BL", true)
  s.elements.name.free = true
  s.elements.name.x, s.elements.name.y = x, y
  return s
end

test("a free element is centred on its fraction at 1000x800", function()
  local p = L.Positions(freeName(0.25, 0.5), 1000, 800, sizes(100, 20))
  near(p.name.left, 200)
  near(p.name.top, 390)
end)

test("a free element keeps its fraction at 2560x1440", function()
  local p = L.Positions(freeName(0.25, 0.5), 2560, 1440, sizes(100, 20))
  near(p.name.left + 50, 2560 * 0.25)
  near(p.name.top + 10, 1440 * 0.5)
end)

test("free elements ignore bars and don't join a stack", function()
  local s = allAt("BL", true)
  s.elements.guild.free = true
  s.elements.guild.x, s.elements.guild.y = 0.5, 0.05
  local p = L.Positions(s, 1000, 800, MIXED)
  near(p.guild.top, 800 * 0.05 - 15 / 2)
  near(p.realm.top, p.name.top + 30 + L.PAD.line)
end)

test("FreeFromPoint turns a drop point into clamped fractions", function()
  local x, y = L.FreeFromPoint(250, 200, 1000, 800)
  near(x, 0.25)
  near(y, 0.25)
  x, y = L.FreeFromPoint(-30, 900, 1000, 800)
  eq(x, 0)
  eq(y, 1)
end)

test("a drop round-trips through Positions at another resolution", function()
  local x, y = L.FreeFromPoint(640, 360, 1280, 720)
  local p = L.Positions(freeName(x, y), 2560, 1440, sizes(100, 20))
  near(p.name.left + 50, 1280)
  near(p.name.top + 10, 720)
end)

-- Slash command parsing -------------------------------------------------------

test("ParseTextCommand: on and off", function()
  local c = L.ParseTextCommand("guild off")
  eq(c.id, "guild")
  eq(c.show, false)
  eq(L.ParseTextCommand("Realm ON").show, true)
end)

test("ParseTextCommand: anchor, any case", function()
  local c = L.ParseTextCommand("zone anchor br")
  eq(c.id, "zone")
  eq(c.anchor, "BR")
  for _, a in ipairs(L.ANCHORS) do eq(L.ParseTextCommand("name anchor " .. a).anchor, a) end
end)

test("ParseTextCommand: free", function()
  local c = L.ParseTextCommand("away free")
  eq(c.id, "away")
  eq(c.free, true)
end)

test("ParseTextCommand rejects bad input with a message", function()
  local bad = { "", "bogus on", "name", "name maybe", "name anchor XX", "name anchor", "name on extra" }
  for _, input in ipairs(bad) do
    local c, err = L.ParseTextCommand(input)
    eq(c, nil, "'" .. input .. "'")
    eq(type(err), "string", "'" .. input .. "' message")
  end
end)

-- Text helpers ----------------------------------------------------------------

test("FormatAway renders mm:ss and h:mm:ss", function()
  eq(L.FormatAway(0), "0:00")
  eq(L.FormatAway(724), "12:04")
  eq(L.FormatAway(3725), "1:02:05")
end)

test("surname is shown by default and survives Merge", function()
  eq(L.Defaults().options.surname, true)
  eq(L.Merge({ options = { surname = false } }).options.surname, false)
end)

test("DisplayName joins a separate surname only when wanted", function()
  eq(L.DisplayName("Aldric", "Thorne", true), "Aldric Thorne")
  eq(L.DisplayName("Aldric", "Thorne", false), "Aldric")
end)

test("DisplayName splits a one-string full name", function()
  eq(L.DisplayName("Aldric Thorne", nil, true), "Aldric Thorne")
  eq(L.DisplayName("Aldric Thorne", nil, false), "Aldric")
  eq(L.DisplayName("Aldric Van Thorne", "", false), "Aldric")
end)

test("DisplayName copes with a single name and nil", function()
  eq(L.DisplayName("Aldric", nil, true), "Aldric")
  eq(L.DisplayName("Aldric", nil, false), "Aldric")
  eq(L.DisplayName(nil, nil, true), "")
end)

test("BarHeight is 11% of the screen and zero when bars are off", function()
  eq(L.BarHeight(720, true), 79)
  eq(L.BarHeight(720, false), 0)
end)

-- Photo settings ----------------------------------------------------------------

test("photo defaults", function()
  local p = L.Defaults().photo
  for _, t in ipairs(L.PHOTO_TYPES) do eq(p.types[t], true, t) end
  eq(p.stamp.name, true)
  eq(p.stamp.guild, true)
  eq(p.stamp.zone, true)
  eq(p.stamp.date, true)
  eq(p.stamp.corner, "BR")
  eq(p.vignette, 60)
  eq(p.frame, "film")
  eq(p.camera, "current")
  eq(p.timer, 3)
  eq(p.hidePlates, true)
  eq(p.hideNames, true)
  eq(p.hideExtras, false)
  eq(p.format, "jpeg")
  eq(p.quality, 9)
  eq(p.auto.level, true)
  eq(p.auto.zone, false)
  eq(p.auto.achievement, false)
  eq(p.auto.boss, false)
end)

test("Merge gives a save without a photo block the photo defaults", function()
  local m = L.Merge({ version = 2, elements = { name = { show = false } } })
  eq(m.photo.frame, "film")
  eq(m.photo.types.sepia, true)
  eq(m.elements.name.show, false)
  eq(L.Merge(v011Save()).photo.quality, 9) -- 0.1.x saves still load
  eq(L.Merge({ version = 2, photo = "junk" }).photo.timer, 3)
end)

test("Merge keeps good photo values", function()
  local m = L.Merge({ version = 2, photo = {
    types = { clean = false, sepia = false },
    stamp = { date = false, corner = "TL" },
    vignette = 0, frame = "portrait", camera = "wide", timer = 10,
    hidePlates = false, hideNames = false, hideExtras = true,
    format = "png", quality = 1, auto = { boss = true, level = false },
  } })
  local p = m.photo
  eq(p.types.clean, false)
  eq(p.types.sepia, false)
  eq(p.types.stamped, true)
  eq(p.stamp.date, false)
  eq(p.stamp.corner, "TL")
  eq(p.vignette, 0)
  eq(p.frame, "portrait")
  eq(p.camera, "wide")
  eq(p.timer, 10)
  eq(p.hidePlates, false)
  eq(p.hideNames, false)
  eq(p.hideExtras, true)
  eq(p.format, "png")
  eq(p.quality, 1)
  eq(p.auto.boss, true)
  eq(p.auto.level, false)
end)

test("Merge replaces bad photo values field by field", function()
  local p = L.Merge({ version = 2, photo = {
    types = { clean = "yes", stamped = 0 },
    stamp = { name = 1, corner = "TC" },
    vignette = 140, frame = "wide", camera = "fisheye", timer = 4,
    hidePlates = "no", hideExtras = nil, format = "gif", quality = 11,
    auto = { zone = "sometimes" },
  } }).photo
  eq(p.types.clean, true)
  eq(p.types.stamped, true)
  eq(p.stamp.name, true)
  eq(p.stamp.corner, "BR") -- TC is a text anchor, not a stamp corner
  eq(p.vignette, 60)
  eq(p.frame, "film")
  eq(p.camera, "current")
  eq(p.timer, 3)
  eq(p.hidePlates, true)
  eq(p.hideExtras, false)
  eq(p.format, "jpeg")
  eq(p.quality, 9)
  eq(p.auto.zone, false)
  local q = L.Merge({ version = 2, photo = { vignette = -1, quality = 0, timer = "3" } }).photo
  eq(q.vignette, 60)
  eq(q.quality, 9)
  eq(q.timer, 3)
  local r = L.Merge({ version = 2, photo = { vignette = 0 / 0, quality = 7.6, types = "all" } }).photo
  eq(r.vignette, 60)
  eq(r.quality, 8)
  eq(r.types.clean, true)
end)

test("Merge keeps unknown photo keys", function()
  local p = L.Merge({ version = 2, photo = {
    future = "x", types = { infrared = true }, stamp = { weather = true }, auto = { death = true },
  } }).photo
  eq(p.future, "x")
  eq(p.types.infrared, true)
  eq(p.stamp.weather, true)
  eq(p.auto.death, true)
end)

local function ids(list) return table.concat(list, ",") end

test("TickedTypes lists ticked types in the fixed order", function()
  local p = L.Defaults().photo
  eq(ids(L.TickedTypes(p)), "clean,stamped,vignetted,saturated,sepia")
  p.types.clean, p.types.saturated = false, false
  eq(ids(L.TickedTypes(p)), "stamped,vignetted,sepia")
  for _, t in ipairs(L.PHOTO_TYPES) do p.types[t] = false end
  eq(#L.TickedTypes(p), 0)
end)

-- Crop rectangles ---------------------------------------------------------------

local function checkCrop(frame, w, h, ratio)
  local r = L.CropRect(frame, w, h)
  near(r.width / r.height, ratio, frame .. " ratio at " .. w .. "x" .. h)
  eq(r.left >= 0 and r.top >= 0, true, "inside")
  eq(r.left + r.width <= w + 1e-9 and r.top + r.height <= h + 1e-9, true, "inside")
  -- As large as possible: it touches both edges along one axis.
  eq(math.abs(r.width - w) < 1e-9 or math.abs(r.height - h) < 1e-9, true, "fills one axis")
  near(r.left * 2 + r.width, w, "centred across")
  near(r.top * 2 + r.height, h, "centred down")
  return r
end

test("CropRect full is the whole screen", function()
  local r = L.CropRect("full", 1920, 1080)
  eq(r.left, 0)
  eq(r.top, 0)
  eq(r.width, 1920)
  eq(r.height, 1080)
end)

for _, screen in ipairs({ { 1920, 1080 }, { 2560, 1080 }, { 1080, 1920 }, { 1365, 768 } }) do
  local w, h = screen[1], screen[2]
  test("CropRect at " .. w .. "x" .. h, function()
    checkCrop("film", w, h, 2.39)
    checkCrop("square", w, h, 1)
    checkCrop("portrait", w, h, 9 / 16)
  end)
end

test("CropRect film letterboxes a 16:9 screen", function()
  local r = L.CropRect("film", 1920, 1080)
  eq(r.width, 1920)
  near(r.height, 1920 / 2.39)
  near(r.top, (1080 - 1920 / 2.39) / 2)
end)

test("CropRect portrait pillarboxes a 16:9 screen", function()
  local r = L.CropRect("portrait", 1920, 1080)
  eq(r.height, 1080)
  near(r.width, 607.5)
  near(r.left, 656.25)
end)

test("CropRect falls back to full for an unknown frame", function()
  eq(L.CropRect("bogus", 800, 600).width, 800)
end)

-- Stamp -------------------------------------------------------------------------

local PARTS = { name = "Aldric", guild = "Lantern Watch", zone = "Elwynn Forest", date = "13 Nov 2026" }

test("StampTexts builds each line from its part", function()
  local t = L.StampTexts(L.Defaults().photo.stamp, PARTS)
  eq(t.name, "Aldric")
  eq(t.guild, "<Lantern Watch>")
  eq(t.zone, "Elwynn Forest")
  eq(t.date, "13 Nov 2026")
end)

test("StampTexts leaves unticked and missing parts empty", function()
  local stamp = L.Defaults().photo.stamp
  stamp.zone = false
  local t = L.StampTexts(stamp, { name = "Aldric", date = "13 Nov 2026" })
  eq(t.zone, "")
  eq(t.guild, "") -- no guild
  eq(t.name, "Aldric")
  eq(L.StampTexts(stamp, { name = "Aldric", guild = "" }).guild, "")
end)

test("the stamp stacks name, guild, zone, date in its corner", function()
  local photo = L.Defaults().photo
  local stampSizes = {
    name = { w = 120, h = 18 }, guild = { w = 140, h = 13 }, zone = { w = 130, h = 13 }, date = { w = 90, h = 12 },
  }
  local p = L.Positions(L.StampSettings(photo), 1000, 800, stampSizes, false, L.STAMP_ORDER)
  for _, id in ipairs(L.STAMP_ORDER) do near(p[id].left + stampSizes[id].w, 1000 - L.PAD.side, id .. " right edge") end
  near(p.guild.top, p.name.top + 18 + L.PAD.line)
  near(p.zone.top, p.guild.top + 13 + L.PAD.line)
  near(p.date.top + 12, 800 - L.PAD.edge) -- no letterbox bars in a photo
end)

test("the stamp follows its corner and skips unticked parts", function()
  local photo = L.Defaults().photo
  photo.stamp.corner = "TL"
  photo.stamp.guild = false
  local stampSizes = { name = { w = 120, h = 18 }, guild = { w = 140, h = 13 }, zone = { w = 130, h = 13 } }
  local p = L.Positions(L.StampSettings(photo), 1000, 800, stampSizes, false, L.STAMP_ORDER)
  near(p.name.left, L.PAD.side)
  near(p.name.top, L.PAD.edge)
  eq(p.guild, nil)
  near(p.zone.top, p.name.top + 18 + L.PAD.line)
  eq(p.date, nil) -- no size: no text
end)

test("every stamp corner is a valid anchor", function()
  for _, c in ipairs(L.STAMP_CORNERS) do
    local photo = L.Defaults().photo
    photo.stamp.corner = c
    eq(L.StampSettings(photo).elements.name.anchor, c)
  end
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
