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

local function ids(list)
  return table.concat(list, ",")
end

test("defaults match the design's options panel", function()
  local d = L.Defaults()
  eq(d.elements.name.show, true)
  eq(d.elements.name.anchor, "BL")
  eq(d.elements.realm.show, false)
  eq(d.elements.zone.anchor, "TC")
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

test("Merge fills missing keys and keeps saved values", function()
  local merged = L.Merge({ elements = { name = { show = false } }, options = { bars = false } })
  eq(merged.elements.name.show, false)
  eq(merged.elements.name.anchor, "BL")
  eq(merged.elements.guild.show, true)
  eq(merged.options.bars, false)
  eq(merged.options.fade, true)
end)

test("Merge drops invalid anchors and out-of-range positions", function()
  local merged = L.Merge({ elements = { name = { anchor = "XX", x = 140, y = -5 } } })
  eq(merged.elements.name.anchor, "BL")
  eq(merged.elements.name.x, 100)
  eq(merged.elements.name.y, 0)
end)

test("Merge ignores unknown element ids and handles nil", function()
  local merged = L.Merge({ elements = { bogus = { show = true } } })
  eq(merged.elements.bogus, nil)
  eq(L.Merge(nil).elements.name.show, true)
end)

test("Cells stacks shown, anchored elements in list order", function()
  local cells = L.Cells(L.Defaults())
  eq(ids(cells.BL), "name,guild,level")
  eq(ids(cells.TC), "zone,subzone")
  eq(ids(cells.TR), "away")
  eq(#cells.MC, 0)
end)

test("Cells skips hidden and free elements; FreeItems lists free ones", function()
  local s = L.Defaults()
  s.elements.guild.free = true
  s.elements.level.show = false
  eq(ids(L.Cells(s).BL), "name")
  eq(ids(L.FreeItems(s)), "guild")
end)

test("FormatAway renders mm:ss and h:mm:ss", function()
  eq(L.FormatAway(0), "0:00")
  eq(L.FormatAway(724), "12:04")
  eq(L.FormatAway(3725), "1:02:05")
end)

test("BarHeight is 11% of the screen and zero when bars are off", function()
  eq(L.BarHeight(720, true), 79)
  eq(L.BarHeight(720, false), 0)
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
