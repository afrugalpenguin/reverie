-- Options window, Map tab: the flight map's style, when it shows, its details, the Overlay style's
-- terrain, the map key, and learned flight times. The shared preview shows the overlay with the
-- chosen style drawn for a sample flight.
local _, ns = ...
local Layout, Route = ns.Layout, ns.Route

local BINDING = "REVERIE_MAP" -- from Bindings.xml
local PREFIX = "|cfff2deaeReverie|r: "
local CONFIRM_SECONDS = 5     -- how long "Forget learned times" waits for the second click

local STYLE_NOTES = {
  strip = "A line along the bottom letterbox bar, from where you started to where you're going.",
  overlay = "The route drawn over the view, bottom right, with the land underneath.",
  off = "No map on flight paths. The map key still shows it for one flight.",
}

-- The sample flight in the preview: Thunder Bluff to Ratchet, by way of the Crossroads, on the
-- Kalimdor taxi map (positions from the spike's log, #54).
local SAMPLE_MAP = 1464
local SAMPLE_NODES = {
  { nodeID = 22, name = "Thunder Bluff, Mulgore", x = 0.4495, y = 0.5615 },
  { nodeID = 25, name = "Crossroads, The Barrens", x = 0.5574, y = 0.5305 },
  { nodeID = 80, name = "Ratchet, The Barrens", x = 0.6057, y = 0.5491 },
}
local SAMPLE_PROGRESS = 0.45
local SAMPLE_ETA = 96

local UI
local view, sample
local confirmUntil = 0
local widgets = { styles = {}, details = {} }

local function Map() return ns.settings.map end
local function Changed() ns.Refresh() end

local function At(widget, parent, x, y)
  widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

local function Note(parent, x, y, width, text)
  local fs = UI.Text(parent, 12, UI.C.muted)
  At(fs, parent, x, y)
  fs:SetWidth(width)
  fs:SetSpacing(3)
  fs:SetText(text or "")
  return fs
end

local function Heading(parent, x, y, label)
  local fs = UI.Heading(parent, label)
  At(fs, parent, x, y)
  return fs
end

local function Learned()
  local n = 0
  for _ in pairs(ns.settings.flightTimes) do n = n + 1 end
  return n
end

-- Left column ---------------------------------------------------------------------------------

local function BuildLeft(page)
  local col = UI.Box(page, UI.C.panel, UI.C.border)
  col:SetPoint("TOPLEFT", 20, -20)
  col:SetPoint("BOTTOMLEFT", 20, 20)
  col:SetWidth(330)

  Heading(col, 20, 18, "Style")
  for i, style in ipairs(Layout.MAP_STYLES) do
    local b = UI.Button(col, 92, 26, Layout.MAP_STYLE_NAMES[style], 12)
    At(b, col, 20 + (i - 1) * 99, 34)
    b:SetScript("OnClick", function()
      Map().style = style
      Changed()
    end)
    widgets.styles[style] = b
  end
  widgets.styleNote = Note(col, 20, 68, 290)

  widgets.auto = UI.Check(col, "Show automatically on flight paths", function(on)
    Map().auto = on
    Changed()
  end)
  At(widgets.auto, col, 16, 106)

  Heading(col, 20, 150, "Details")
  for i, key in ipairs(Layout.MAP_DETAILS) do
    local cb = UI.Check(col, Layout.MAP_DETAIL_NAMES[key], function(on)
      Map().details[key] = on
      Changed()
    end)
    At(cb, col, 16, 166 + (i - 1) * 30)
    widgets.details[key] = cb
  end

  Heading(col, 20, 270, "Terrain")
  -- Only the Overlay style draws terrain, so its controls are in one frame shown for it alone.
  local box = CreateFrame("Frame", nil, col)
  box:SetSize(300, 80)
  At(box, col, 16, 286)
  widgets.terrainBox = box
  widgets.terrain = UI.Check(box, "Show the land under the route", function(on)
    Map().terrain = on
    Changed()
  end)
  At(widgets.terrain, box, 0, 0)
  widgets.strength = UI.Slider(box, 286, function(v)
    Map().strength = v
    Changed()
  end, Layout.MAP_STRENGTH_MIN, 100)
  At(widgets.strength, box, 4, 56)
  widgets.terrainOff = Note(col, 20, 290, 290, "Terrain is drawn in the Overlay style.")

  Heading(col, 20, 384, "Map key")
  widgets.key = Note(col, 20, 400, 290)

  Heading(col, 20, 486, "Learned flight times")
  widgets.count = Note(col, 20, 502, 290)
  widgets.forget = UI.Button(col, 290, 26, "", 12)
  At(widgets.forget, col, 20, 546)
  widgets.forget:SetScript("OnClick", function()
    if Learned() == 0 then return end
    if GetTime() < confirmUntil then
      confirmUntil = 0
      ns.settings.flightTimes = {}
      print(PREFIX .. "Learned flight times forgotten. Reverie learns them again as you fly.")
    else
      confirmUntil = GetTime() + CONFIRM_SECONDS
      C_Timer.After(CONFIRM_SECONDS, ns.RefreshOptions)
    end
    Changed()
  end)
end

-- Right column, under the shared preview ---------------------------------------------------------

local function BuildRight(page)
  local col = CreateFrame("Frame", nil, page)
  col:SetPoint("TOPLEFT", 370, -20)
  col:SetPoint("BOTTOMRIGHT", -20, 20)

  local box = UI.Box(col, UI.C.panel, UI.C.border)
  box:SetSize(UI.PREVIEW_W, 186)
  At(box, col, 0, UI.PREVIEW_H + 20)
  Heading(box, 14, 14, "How the map works")
  Note(box, 14, 34, UI.PREVIEW_W - 28,
    "The map shows the flight path you're on while the overlay is up: where you started, any "
    .. "stops on the way, where you're going, and how far along you are.\n\n"
    .. "Time to arrival appears once Reverie has timed a route. On a route's first flight the map "
    .. "follows your position instead. Times are learned from flights that reach their "
    .. "destination, and averaged with earlier flights on the same route.\n\n"
    .. "The preview shows a sample flight from Thunder Bluff to Ratchet.")
end

-- Called once by Options.lua when the window is first built. mapRoot is the preview's
-- screen-sized frame for the sample map.
function ns.BuildMapPage(page, mapRoot)
  UI = ns.UI
  view = ns.MapView.New(mapRoot)
  local function hop(a, b) return { a.x, a.y, b.x, b.y } end
  local n = SAMPLE_NODES
  sample = Route.Build({ hop(n[1], n[2]), hop(n[2], n[3]) }, SAMPLE_NODES)
  BuildLeft(page)
  BuildRight(page)
  -- The key note follows the binding, wherever it's changed.
  page:RegisterEvent("UPDATE_BINDINGS")
  page:SetScript("OnEvent", function() ns.RefreshOptions() end)
end

-- Bottom text in the preview moves clear of the sample map, as it does in game.
function ns.MapPreviewReserve(w, h)
  return Layout.MapReserve(Map().style, w, h, ns.settings.options.bars)
end

function ns.RefreshMapPage()
  local m = Map()

  for style, b in pairs(widgets.styles) do UI.SetActive(b, style == m.style) end
  widgets.styleNote:SetText(STYLE_NOTES[m.style])
  widgets.auto:SetChecked(m.auto)
  for key, cb in pairs(widgets.details) do cb:SetChecked(m.details[key]) end

  local overlay = m.style == "overlay"
  widgets.terrainBox:SetShown(overlay)
  widgets.terrainOff:SetShown(not overlay)
  widgets.terrain:SetChecked(m.terrain)
  UI.SetSlider(widgets.strength, "Terrain strength", m.strength)
  widgets.strength:SetAlpha(m.terrain and 1 or 0.5)

  local bound = GetBindingKey(BINDING)
  widgets.key:SetText((bound and ("Map key: |cfff2deae" .. GetBindingText(bound) .. "|r. ") or "Map key: not set. ")
    .. "On a flight it switches between Strip, Overlay and Off for that flight only. Set it in "
    .. "Options > Keybindings > Reverie, or type /reverie map.")

  local n = Learned()
  widgets.count:SetText(n == 0 and "No flight times learned yet."
    or (n == 1 and "Times learned for 1 route." or ("Times learned for " .. n .. " routes.")))
  local confirming = n > 0 and GetTime() < confirmUntil
  widgets.forget.label:SetText(confirming and ("Click again to forget " .. (n == 1 and "1 route" or (n .. " routes")))
    or "Forget learned times")
  UI.SetActive(widgets.forget, confirming)
  widgets.forget:SetAlpha(n > 0 and 1 or 0.5)

  local nextStop, isDestination = Route.NextStop(sample, SAMPLE_PROGRESS)
  view:Apply({
    style = m.style, bars = ns.settings.options.bars, route = sample, progress = SAMPLE_PROGRESS,
    eta = m.details.eta and SAMPLE_ETA or nil,
    nextStop = (m.details.nextStop and not isDestination) and nextStop or nil,
    art = (overlay and m.terrain) and ns.MapView.Art(SAMPLE_MAP) or nil,
    strength = m.strength,
  })
end
