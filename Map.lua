-- The flight map on the overlay: shown while the overlay is up on a flight path, in the style the
-- Map tab chose (or the map key's choice for this flight). Draws with MapView on the overlay frame,
-- so Escape and the end of the flight take it away with the rest of the overlay.
--
-- Like the chat box it never appears in screenshots: photo mode hides it for the whole photo
-- (Map.HideForPhoto), the automatic plain screenshot hides it first (Chat.BeforeShot calls
-- Map.HideForShot), and any other Screenshot() call hides it from a hook until the file is saved.
local _, ns = ...
local Layout, Route = ns.Layout, ns.Route
local state = ns.state

local Map = {}
ns.Map = Map

local PREFIX = "|cfff2deaeReverie|r: "
local TICK = 0.1          -- seconds between redraws while the overlay is up
local SHOT_TIMEOUT = 5    -- seconds to wait for a screenshot's save event before showing again

local view
local progress, progressOf = 0, nil -- progress so far, and the flight (its chosenAt) it belongs to
local hiddenForShot, hiddenForPhoto = false, false
local shotToken = 0
local laidOut -- the style and bars the overlay text was last laid out around
local ticker = CreateFrame("Frame")

local function OnTaxi()
  local onTaxi = UnitOnTaxi("player")
  -- A secret value can't be tested; the flight being watched is the better guess.
  if Layout.HasSecret(issecretvalue, onTaxi) then return true end
  return onTaxi
end

-- The style to draw: the map key's choice for this flight, else the saved one; "off" when not
-- on a flight path or the overlay isn't up.
function Map.Style()
  local f = ns.Flight.Current()
  if not (state.active and f and f.boarded and ns.settings and OnTaxi()) then return "off" end
  return Route.Style(ns.settings.map, f.style)
end

-- Room the map takes from bottom-anchored overlay text (Layout.Positions' reserve), or nil.
function Map.Reserve(w, h)
  if not ns.settings then return nil end
  return Layout.MapReserve(Map.Style(), w, h, ns.settings.options.bars)
end

local function Data(style)
  local f, m = ns.Flight.Current(), ns.settings.map
  if progressOf ~= f.chosenAt then progress, progressOf = 0, f.chosenAt end

  local learned = f.key and ns.settings.flightTimes[f.key]
  local x, y
  if not learned then x, y = ns.Flight.PlayerPos(f.map) end
  local p, eta = Route.Progress(f.route, {
    elapsed = GetTime() - f.chosenAt, learned = learned and learned.seconds, x = x, y = y, prev = progress,
  })
  progress = p

  local nextStop, isDestination = Route.NextStop(f.route, p)
  local zone = m.details.zone and GetZoneText() or nil
  return {
    style = style, bars = ns.settings.options.bars, route = f.route, progress = p,
    eta = m.details.eta and eta or nil,
    nextStop = (m.details.nextStop and not isDestination) and nextStop or nil,
    zone = (zone and zone ~= "") and zone or nil,
    art = (style == "overlay" and m.terrain) and ns.MapView.Art(f.map) or nil,
    strength = m.strength,
  }
end

-- Redraws the map. Also lays the overlay text out again when the map's place changes, so bottom
-- text moves clear of it.
function Map.Update()
  if not view then return end
  local style = Map.Style()
  local layout = style .. tostring(ns.settings.options.bars)
  if layout ~= laidOut then
    laidOut = layout
    ns.Text.Render()
  end
  if style == "off" or hiddenForShot or hiddenForPhoto then
    view:Hide()
    return
  end
  view:Apply(Data(style))
end

-- Called by ns.Start when the overlay comes up.
function Map.Start()
  local live = ns.Text.live
  if not live then return end
  if not view then view = ns.MapView.New(live.frame) end
  hiddenForShot, hiddenForPhoto, laidOut = false, false, nil
  local wait = 0
  ticker:SetScript("OnUpdate", function(_, elapsed)
    wait = wait + elapsed
    if wait < TICK then return end
    wait = 0
    local ok, err = pcall(Map.Update)
    if not ok then
      -- Stop rather than repeat the error ten times a second; the next overlay tries again.
      ticker:SetScript("OnUpdate", nil)
      if view then view:Hide() end
      error(err, 0)
    end
  end)
  Map.Update()
end

-- Called by ns.Stop.
function Map.Stop()
  ticker:SetScript("OnUpdate", nil)
  hiddenForShot, hiddenForPhoto, laidOut = false, false, nil
  if view then view:Hide() end
end

-- The map key and /reverie map: Strip, Overlay, Off for this flight only.
function Map.Cycle()
  local f = ns.Flight.Current()
  if not (f and f.boarded and OnTaxi()) then
    print(PREFIX .. "The flight map shows while you're on a flight path.")
    return
  end
  f.style = Route.NextStyle(Route.Style(ns.settings.map, f.style))
  if not state.active then
    print(PREFIX .. "Flight map: " .. Layout.MAP_STYLE_NAMES[f.style] .. ". It shows while the overlay is up.")
  end
  Map.Update()
end

-- Hides the map until the next screenshot is saved (or SHOT_TIMEOUT passes). Returns true if it
-- was showing.
function Map.HideForShot()
  if not (view and view.frame:IsShown()) then return false end
  view:Hide()
  hiddenForShot = true
  shotToken = shotToken + 1
  local mine = shotToken
  C_Timer.After(SHOT_TIMEOUT, function()
    if hiddenForShot and shotToken == mine then
      hiddenForShot = false
      Map.Update()
    end
  end)
  return true
end

-- Photo mode: hidden for the whole photo, until ShowAfterPhoto.
function Map.HideForPhoto()
  hiddenForPhoto, hiddenForShot = true, false
  if view then view:Hide() end
end

function Map.ShowAfterPhoto()
  hiddenForPhoto = false
  Map.Update()
end

local events = CreateFrame("Frame")
events:RegisterEvent("SCREENSHOT_SUCCEEDED")
events:RegisterEvent("SCREENSHOT_FAILED")
events:SetScript("OnEvent", function()
  if hiddenForShot then
    hiddenForShot = false
    Map.Update()
  end
end)

hooksecurefunc("Screenshot", Map.HideForShot)
