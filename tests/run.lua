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

-- Photo capture plan --------------------------------------------------------------

local function ops(steps)
  local out = {}
  for _, s in ipairs(steps) do out[#out + 1] = s.op .. (s.type and (":" .. s.type) or "") end
  return table.concat(out, ",")
end

local function shotsOf(steps)
  local out = {}
  for _, s in ipairs(steps) do
    if s.op == "shoot" then out[#out + 1] = s.type end
  end
  return table.concat(out, ",")
end

local function count(steps, op)
  local n = 0
  for _, s in ipairs(steps) do
    if s.op == op then n = n + 1 end
  end
  return n
end

test("PhotoPlan with every type shoots all five in order, spaced between shots", function()
  local steps = L.PhotoPlan(L.Defaults().photo)
  eq(shotsOf(steps), "clean,stamped,vignetted,saturated,sepia")
  eq(count(steps, "space"), 4)
  eq(count(steps, "look"), 5)
  eq(count(steps, "clearLook"), 5)
  eq(steps[#steps].op, "finish")
end)

test("PhotoPlan: every shot is look, wait 2 frames, shoot, clear", function()
  local steps = L.PhotoPlan(L.Defaults().photo)
  for i, s in ipairs(steps) do
    if s.op == "shoot" then
      eq(steps[i - 2].op, "look")
      eq(steps[i - 2].type, s.type)
      eq(steps[i - 1].op, "waitFrames")
      eq(steps[i - 1].frames, 2)
      eq(steps[i + 1].op, "clearLook")
    end
  end
end)

test("PhotoPlan setup runs before the guides, in the order cleanup reverses", function()
  local p = L.Defaults().photo
  p.camera, p.hideExtras = "portrait", true
  local steps = L.PhotoPlan(p)
  eq(ops({ unpack(steps, 1, 10) }),
    "pauseOrbit,settle,hideUI,shotOverlay,fileFormat,camera,extras,cvars,waitFrames,guides")
  eq(steps[2].seconds, L.PHOTO_SETTLE)
  eq(steps[9].frames, 5)
end)

test("PhotoPlan with none ticked refuses with a message", function()
  local p = L.Defaults().photo
  for _, t in ipairs(L.PHOTO_TYPES) do p.types[t] = false end
  local steps, err = L.PhotoPlan(p)
  eq(steps, nil)
  eq(type(err), "string")
end)

test("PhotoPlan with one ticked takes one shot and never spaces", function()
  local p = L.Defaults().photo
  for _, t in ipairs(L.PHOTO_TYPES) do p.types[t] = false end
  p.types.sepia = true
  local steps = L.PhotoPlan(p)
  eq(shotsOf(steps), "sepia")
  eq(count(steps, "space"), 0)
end)

test("PhotoPlan skips the camera, extras and CVar steps when they're off", function()
  local p = L.Defaults().photo
  p.camera, p.hideExtras, p.hidePlates, p.hideNames = "current", false, false, false
  local steps = L.PhotoPlan(p)
  eq(count(steps, "camera"), 0)
  eq(count(steps, "extras"), 0)
  eq(count(steps, "cvars"), 0)
  eq(count(steps, "fileFormat"), 1) -- always checked; it only changes what differs
end)

test("PhotoPlan with the timer off has no guides or countdown", function()
  local p = L.Defaults().photo
  p.timer = 0
  local steps = L.PhotoPlan(p)
  eq(count(steps, "guides"), 0)
  eq(count(steps, "countdown"), 0)
  eq(count(steps, "hideGuides"), 0)
  p.timer = 5
  steps = L.PhotoPlan(p)
  eq(count(steps, "guides"), 1)
  eq(count(steps, "hideGuides"), 1)
  for _, s in ipairs(steps) do
    if s.op == "countdown" then eq(s.seconds, 5) end
  end
end)

test("CleanupOrder undoes setup in reverse: CVars, frames, camera, file, overlay, UI, orbit", function()
  local p = L.Defaults().photo
  p.camera, p.hideExtras = "wide", true
  eq(table.concat(L.CleanupOrder(L.PhotoPlan(p)), ","), "cvars,frames,camera,fileFormat,overlay,ui,orbit")
end)

test("CleanupOrder leaves out what the plan never changed", function()
  local p = L.Defaults().photo
  p.camera, p.hideExtras, p.hidePlates, p.hideNames = "current", false, false, false
  eq(table.concat(L.CleanupOrder(L.PhotoPlan(p)), ","), "fileFormat,overlay,ui,orbit")
end)

test("PhotoCVars follows the hide settings and covers the spike's list", function()
  local p = L.Defaults().photo
  local all = L.PhotoCVars(p)
  eq(#all, #L.PLATE_CVARS + #L.NAME_CVARS)
  p.hidePlates = false
  eq(table.concat(L.PhotoCVars(p), ","), table.concat(L.NAME_CVARS, ","))
  p.hidePlates, p.hideNames = true, false
  eq(table.concat(L.PhotoCVars(p), ","), table.concat(L.PLATE_CVARS, ","))
  local names = {}
  for _, n in ipairs(L.NAME_CVARS) do names[n] = true end
  eq(names.UnitNameOwn, true)
  eq(names.UnitNameHostleNPC, true)
  eq(names.UnitNameEnemyTotemName, true)
end)

test("NewSecond only allows the next shot once the clock's second has changed", function()
  eq(L.NewSecond(1000, 1000), false)
  eq(L.NewSecond(1000, 1001), true)
  eq(L.NewSecond(nil, 1000), true) -- first shot
end)

test("camera presets: portrait and profile turn the camera, wide zooms out", function()
  eq(L.CAMERA_PRESETS.portrait.yaw, 180)
  eq(L.CAMERA_PRESETS.profile.yaw, 90)
  eq(L.CAMERA_PRESETS.wide.zoom > 0, true)
  eq(L.CAMERA_PRESETS.current, nil)
end)

test("ToastText reports what was saved or what failed", function()
  eq(L.ToastText({ saved = 5, total = 5 }), "Screenshot saved: 5 shots")
  eq(L.ToastText({ saved = 1, total = 1 }), "Screenshot saved")
  eq(L.ToastText({ saved = 3, total = 5, reason = "entered combat" }), "Saved 3 of 5 shots: entered combat")
  eq(L.ToastText({ saved = 0, total = 5, reason = "cancelled" }), "Screenshot cancelled")
  eq(L.ToastText({ saved = 0, total = 2, reason = "no screenshot event" }), "Screenshot failed: no screenshot event")
end)

-- Automatic shots ---------------------------------------------------------------

test("AutoAction: idle takes the plain shot and the clean capture now", function()
  local a = L.AutoAction({ running = false, combat = false, unlocked = false })
  eq(a.plain, true)
  eq(a.clean, "now")
end)

test("AutoAction: in combat the plain shot still happens and the clean capture queues", function()
  local a = L.AutoAction({ running = false, combat = true, unlocked = false })
  eq(a.plain, true)
  eq(a.clean, "queue")
end)

test("AutoAction: during a photo there's no plain shot and the clean capture queues", function()
  local a = L.AutoAction({ running = true, combat = false, unlocked = false })
  eq(a.plain, false)
  eq(a.clean, "queue")
  eq(L.AutoAction({ running = false, combat = false, unlocked = true }).clean, "queue")
end)

test("AutoQueue holds one trigger and keeps the first while it's fresh", function()
  local q = L.AutoQueue(nil, "boss", 100)
  eq(q.trigger, "boss")
  eq(q.at, 100)
  q = L.AutoQueue(q, "achievement", 110)
  eq(q.trigger, "boss")
  eq(q.at, 100)
  q = L.AutoQueue(q, "boss", 120)
  eq(q.at, 100)
end)

test("AutoQueue replaces an expired trigger", function()
  local q = L.AutoQueue(L.AutoQueue(nil, "boss", 100), "level", 100 + L.AUTO_QUEUE_SECONDS + 1)
  eq(q.trigger, "level")
end)

test("AutoTake returns a fresh trigger and drops an expired one", function()
  eq(L.AutoTake(nil, 100), nil)
  eq(L.AutoTake({ trigger = "boss", at = 100 }, 100 + L.AUTO_QUEUE_SECONDS), "boss")
  local trigger, expired = L.AutoTake({ trigger = "boss", at = 100 }, 100 + L.AUTO_QUEUE_SECONDS + 0.5)
  eq(trigger, nil)
  eq(expired, true)
  eq(L.AUTO_QUEUE_SECONDS, 30)
end)

test("AutoDuplicate ignores the same trigger again within a few seconds", function()
  eq(L.AutoDuplicate(nil, "achievement", 100), false)
  local last = { trigger = "achievement", at = 100 }
  eq(L.AutoDuplicate(last, "achievement", 100 + L.AUTO_REPEAT_SECONDS - 1), true)
  eq(L.AutoDuplicate(last, "achievement", 100 + L.AUTO_REPEAT_SECONDS + 1), false)
  eq(L.AutoDuplicate(last, "boss", 101), false)
end)

test("FirstVisit is true once per zone per character and records it", function()
  local visited = {}
  eq(L.FirstVisit(visited, "Aldric-Camelot", "Elwynn Forest"), true)
  eq(visited["Aldric-Camelot"]["Elwynn Forest"], true)
  eq(L.FirstVisit(visited, "Aldric-Camelot", "Elwynn Forest"), false)
  eq(L.FirstVisit(visited, "Aldric-Camelot", "Westfall"), true)
  eq(L.FirstVisit(visited, "Brynn-Camelot", "Elwynn Forest"), true)
  eq(L.FirstVisit(visited, "Aldric-Camelot", ""), false)
  eq(L.FirstVisit(visited, "Aldric-Camelot", nil), false)
end)

test("Merge keeps visited zones and drops malformed entries", function()
  local m = L.Merge({ version = 2, visited = {
    ["Aldric-Camelot"] = { ["Elwynn Forest"] = true, Westfall = "yes", [3] = true },
    ["Brynn-Camelot"] = "junk",
  } })
  eq(m.visited["Aldric-Camelot"]["Elwynn Forest"], true)
  eq(m.visited["Aldric-Camelot"].Westfall, nil)
  eq(m.visited["Aldric-Camelot"][3], nil)
  eq(m.visited["Brynn-Camelot"], nil)
  eq(type(L.Merge({ version = 2, visited = 5 }).visited), "table")
  eq(next(L.Merge(nil).visited), nil)
end)

test("PhotoPlan for an automatic shot: no self-timer, and a wait for a new second first", function()
  local p = L.Defaults().photo
  p.timer = 10
  local steps = L.PhotoPlan(p, { auto = true })
  eq(count(steps, "guides"), 0)
  eq(count(steps, "countdown"), 0)
  for i, s in ipairs(steps) do
    if s.op == "look" then
      eq(steps[i - 1].op, "space", "the first look waits for a new second")
      break
    end
  end
  eq(count(steps, "space"), 5)
  eq(count(L.PhotoPlan(p), "countdown"), 1) -- manual photos keep the timer
end)

test("ToastText names the trigger", function()
  eq(L.ToastText({ saved = 5, total = 5, trigger = "Level up" }), "Level up: Screenshot saved: 5 shots")
  eq(L.ToastText({ saved = 0, total = 5, reason = "entered combat", trigger = "Boss defeated" }),
    "Boss defeated: Screenshot failed: entered combat")
end)

-- Text fade and mouse wake (#19) -------------------------------------------------

test("FadeStep fades the text after the delay with no mouse movement", function()
  local f = L.NewFade(100, 0, 0)
  eq(L.FadeStep(f, 0, 0, 100 + L.FADE_DELAY - 0.1), nil)
  eq(L.FadeStep(f, 0, 0, 100 + L.FADE_DELAY), "fade")
  eq(L.FadeStep(f, 0, 0, 100 + L.FADE_DELAY + 5), nil, "fades only once")
end)

test("FadeStep: moving the mouse brings faded text back and restarts the delay", function()
  local f = L.NewFade(100, 0, 0)
  eq(L.FadeStep(f, 0, 0, 100 + L.FADE_DELAY), "fade")
  eq(L.FadeStep(f, 50, 20, 120), "show")
  eq(L.FadeStep(f, 50, 20, 120 + L.FADE_DELAY - 0.1), nil)
  eq(L.FadeStep(f, 50, 20, 120 + L.FADE_DELAY), "fade")
end)

test("FadeStep: moving before the fade postpones it without a show", function()
  local f = L.NewFade(100, 0, 0)
  eq(L.FadeStep(f, 30, 0, 105), nil)
  eq(L.FadeStep(f, 30, 0, 100 + L.FADE_DELAY), nil, "the delay restarted at 105")
  eq(L.FadeStep(f, 30, 0, 105 + L.FADE_DELAY), "fade")
end)

test("FadeStep ignores cursor jitter within the slop", function()
  local f = L.NewFade(100, 10, 10)
  eq(L.FadeStep(f, 10, 10, 100 + L.FADE_DELAY), "fade")
  eq(L.FadeStep(f, 10 + L.CURSOR_SLOP, 10 - L.CURSOR_SLOP, 111), nil)
  eq(L.FadeStep(f, 10 + L.CURSOR_SLOP + 1, 10, 112), "show")
end)

-- Overlay chat (#30) ---------------------------------------------------------------

test("Show chat is on by default and a saved false survives Merge", function()
  eq(L.Defaults().options.chat, true)
  local saved = L.Defaults()
  saved.options.chat = false
  eq(L.Merge(saved).options.chat, false)
end)

test("Chat events cover guild, officer, whispers, party and raid only", function()
  local want = {
    CHAT_MSG_GUILD = "GUILD", CHAT_MSG_OFFICER = "OFFICER",
    CHAT_MSG_WHISPER = "WHISPER", CHAT_MSG_BN_WHISPER = "BN_WHISPER",
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY_LEADER",
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID_LEADER", CHAT_MSG_RAID_WARNING = "RAID_WARNING",
  }
  local n = 0
  for event, chatType in pairs(L.CHAT_EVENTS) do
    n = n + 1
    eq(chatType, want[event], event)
  end
  eq(n, 9)
end)

test("ChatLine labels channels and drops the author's realm", function()
  eq(L.ChatLine("GUILD", "Thrall-Forever", "hello"), "[Guild] Thrall: hello")
  eq(L.ChatLine("OFFICER", "Jaina", "meeting"), "[Officer] Jaina: meeting")
  eq(L.ChatLine("PARTY_LEADER", "Rexxar", "pull"), "[Party Leader] Rexxar: pull")
  eq(L.ChatLine("RAID_WARNING", "Cairne", "move"), "[Raid Warning] Cairne: move")
  eq(L.ChatLine("WHISPER", "Sylvanas-Other", "psst"), "Sylvanas whispers: psst")
  eq(L.ChatLine("BN_WHISPER", "Varian", "hi"), "Varian whispers: hi")
end)

test("ChatLine copes with a missing author", function()
  eq(L.ChatLine("GUILD", nil, "hello"), "[Guild] hello")
  eq(L.ChatLine("GUILD", "", "hello"), "[Guild] hello")
end)

test("ChatRect sits bottom right, just above the letterbox bar", function()
  local r = L.ChatRect(1920, 1080, true)
  eq(r.right, L.PAD.side)
  eq(r.bottom, L.BarHeight(1080, true) + L.PAD.bar)
  eq(r.width, math.floor(1920 * L.CHAT_WIDTH))
  eq(r.height, L.CHAT_LINES * L.CHAT_LINE_H)
  eq(L.ChatRect(1920, 1080, false).bottom, L.PAD.edge, "no bars: the screen edge padding")
end)

-- Key binding capture ------------------------------------------------------------

test("BindingKey: a plain key binds as itself", function()
  eq(L.BindingKey("P"), "P")
end)

test("BindingKey: modifiers come first, in ALT-CTRL-SHIFT order", function()
  eq(L.BindingKey("P", true, false, false), "ALT-P")
  eq(L.BindingKey("P", false, true, true), "CTRL-SHIFT-P")
  eq(L.BindingKey("F12", true, true, true), "ALT-CTRL-SHIFT-F12")
end)

test("BindingKey: a modifier on its own is not a binding yet", function()
  for _, k in ipairs({ "LSHIFT", "RSHIFT", "LCTRL", "RCTRL", "LALT", "RALT", "LMETA", "RMETA", "UNKNOWN" }) do
    eq(L.BindingKey(k, false, false, true), nil, k)
  end
end)

test("KeyDecision: a free key binds straight away", function()
  eq(L.KeyDecision("F12", "", nil), "bind")
  eq(L.KeyDecision("F12", nil, nil), "bind")
end)

test("KeyDecision: a key that's already the photo key binds straight away", function()
  eq(L.KeyDecision("F12", "REVERIE_PHOTO", nil), "bind")
end)

test("KeyDecision: a key that does something else asks first", function()
  eq(L.KeyDecision("/", "OPENCHATSLASH", nil), "confirm")
  eq(L.KeyDecision("ENTER", "OPENCHAT", "/"), "confirm", "a different key starts a new question")
end)

test("KeyDecision: pressing the same key again confirms", function()
  eq(L.KeyDecision("/", "OPENCHATSLASH", "/"), "bind")
end)

-- Onboarding tour -----------------------------------------------------------------

test("Tour: a fresh install hasn't seen the tour", function()
  eq(L.Merge(nil).tourSeen, false)
  eq(L.Defaults().tourSeen, false)
end)

test("Tour: an existing save from before the tour counts as seen", function()
  eq(L.Merge({ version = 2 }).tourSeen, true)
  eq(L.Merge(v011Save()).tourSeen, true)
end)

test("Tour: a saved tourSeen is kept either way", function()
  eq(L.Merge({ version = 2, tourSeen = false }).tourSeen, false)
  eq(L.Merge({ version = 2, tourSeen = true }).tourSeen, true)
end)

test("Tour: a malformed tourSeen on an existing save counts as seen", function()
  eq(L.Merge({ version = 2, tourSeen = "yes" }).tourSeen, true)
end)

test("TourNews: only an existing save without tourSeen gets the chat line", function()
  eq(L.TourNews(nil), false, "fresh install gets the tour, not the line")
  eq(L.TourNews({ version = 2 }), true)
  eq(L.TourNews({ version = 2, tourSeen = true }), false)
  eq(L.TourNews({ version = 2, tourSeen = false }), false)
end)

-- Overlay chat in the game chat window's place ---------------------------------------

test("ChatRectFrom converts the game chat window into overlay units", function()
  -- Chat frame at scale 1.0, overlay at 0.5: everything doubles.
  local r = L.ChatRectFrom(30, 40, 400, 120, 1.0, 0.5)
  eq(r.left, 60)
  eq(r.bottom, 80)
  eq(r.width, 800)
  eq(r.height, 240)
end)

test("ChatRectFrom with matching scales keeps the numbers", function()
  local r = L.ChatRectFrom(30, 40, 400, 120, 0.8, 0.8)
  near(r.left, 30)
  near(r.height, 120)
end)

test("ChatRectFrom gives nothing when the chat window can't be measured", function()
  eq(L.ChatRectFrom(nil, 40, 400, 120, 1, 1), nil, "no position")
  eq(L.ChatRectFrom(30, 40, 0, 120, 1, 1), nil, "no width")
  eq(L.ChatRectFrom(30, 40, 400, 120, 1, 0), nil, "no overlay scale")
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
