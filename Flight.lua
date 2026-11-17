-- Flight paths: captures the route when a flight is chosen, times it to landing and learns the
-- time per route. The flight in progress is saved in ReverieDB.flight so a /reload mid-flight
-- keeps the map; learned times are in ReverieDB.flightTimes. The decisions are in Route.lua.
--
-- From the spike (#54): TakeTaxiNode's post-hook can still read the taxi data; positions are on
-- the flight master's taxi map (GetTaxiMapID), not the continent; PLAYER_CONTROL_GAINED marks the
-- landing exactly but also fires outside flights, so it only counts while a flight is watched.
local _, ns = ...
local Layout, Route = ns.Layout, ns.Route

local Flight = {}
ns.Flight = Flight

local POLL = 0.5          -- seconds between UnitOnTaxi checks while a flight is watched
local BOARD_TIMEOUT = 15  -- seconds after choosing a flight to wait for the taxi
local LOGIN_GRACE = 5     -- seconds after a login or /reload before "not on the taxi" means landed
local CONTROL_WINDOW = 3  -- PLAYER_CONTROL_GAINED this soon before the poll sees the landing is its time

local graceUntil = 0

local function number(v) return type(v) == "number" and v == v end

local function Secret(...) return Layout.HasSecret(issecretvalue, ...) end

-- Calls fn(...) under pcall: its results, or nothing when it's missing or errors.
local function call(fn, ...)
  if type(fn) ~= "function" then return end
  local r = { pcall(fn, ...) }
  if r[1] then return unpack(r, 2, table.maxn(r)) end
end

function Flight.Current()
  return ns.settings and ns.settings.flight
end

-- The player on a map: x, y, or nil.
function Flight.PlayerPos(mapID)
  if type(C_Map) ~= "table" then return nil end
  local pos = call(C_Map.GetPlayerMapPosition, mapID, "player")
  if type(pos) ~= "table" then return nil end
  local x, y = call(pos.GetXY, pos)
  if not (number(x) and number(y)) or Secret(x, y) then return nil end
  return x, y
end

-- The taxi map's nodes as { nodeID, name, x, y }, for naming the route's stops.
local function Nodes(mapID)
  local out = {}
  local all = type(C_TaxiMap) == "table" and call(C_TaxiMap.GetAllTaxiNodes, mapID)
  for _, n in ipairs(type(all) == "table" and all or {}) do
    local x, y
    if type(n.position) == "table" then x, y = call(n.position.GetXY, n.position) end
    if number(x) and number(y) then out[#out + 1] = { nodeID = n.nodeID, name = n.name, x = x, y = y } end
  end
  if #out > 0 then return out end
  -- Without C_TaxiMap: the open taxi map's slots, names only.
  for slot = 1, call(NumTaxiNodes) or 0 do
    local x, y = call(TaxiNodePosition, slot)
    if number(x) and number(y) then out[#out + 1] = { name = call(TaxiNodeName, slot), x = x, y = y } end
  end
  return out
end

-- The chosen flight's hops as { srcX, srcY, destX, destY }.
local function Hops(slot)
  local hops = {}
  for hop = 1, call(GetNumRoutes, slot) or 0 do
    hops[hop] = {
      call(TaxiGetSrcX, slot, hop), call(TaxiGetSrcY, slot, hop),
      call(TaxiGetDestX, slot, hop), call(TaxiGetDestY, slot, hop),
    }
  end
  return hops
end

local watcher = CreateFrame("Frame")

local function Stop() watcher:SetScript("OnUpdate", nil) end

function Flight.Clear()
  Stop()
  if ns.settings then ns.settings.flight = nil end
  if ns.Map then ns.Map.Update() end
end

-- The flight has ended: learn its time if it reached its destination, then forget it.
local function Land()
  local f = Flight.Current()
  if not f then return end
  local now = GetTime()
  local landedAt = (number(f.controlAt) and now - f.controlAt <= CONTROL_WINDOW) and f.controlAt or now
  if f.key then
    local x, y = Flight.PlayerPos(f.map)
    local times = ns.settings.flightTimes
    local entry, learned = Route.Learn(times[f.key], landedAt - f.chosenAt, Route.Arrived(f.route, x, y))
    if learned then times[f.key] = entry end
  end
  Flight.Clear()
end

local function Tick()
  local f = Flight.Current()
  if not f then return Stop() end
  local onTaxi = UnitOnTaxi("player")
  if Secret(onTaxi) then return end -- can't tell now; ask again next poll
  if not f.boarded then
    if onTaxi then
      f.boarded = true
      if ns.Map then ns.Map.Update() end
    elseif GetTime() - f.chosenAt > BOARD_TIMEOUT then
      Flight.Clear() -- the flight never started
    end
  elseif onTaxi then
    f.resumed = nil -- seen on the taxi since the /reload, so its landing counts
  elseif GetTime() >= graceUntil then
    -- A flight resumed after a login but never seen on the taxi since ended while the game was
    -- away: forget it without learning.
    if f.resumed then Flight.Clear() else Land() end
  end
end

local function Watch()
  local wait = 0
  watcher:SetScript("OnUpdate", function(_, elapsed)
    wait = wait + elapsed
    if wait < POLL then return end
    wait = 0
    local ok, err = pcall(Tick)
    if not ok then
      Stop()
      error(err, 0)
    end
  end)
end

-- TakeTaxiNode's post-hook: the taxi map is still open, so its route and nodes can be read.
local function Capture(slot)
  if not ns.settings then return end
  local mapID = call(GetTaxiMapID)
  if not number(mapID) or mapID == 0 then return end
  local route = Route.Build(Hops(slot), Nodes(mapID))
  if not route then return end
  ns.settings.flight = {
    key = Route.Key(route), map = mapID, route = route,
    chosenAt = GetTime(), chosenWall = time(), boarded = false,
  }
  Watch()
end

if type(TakeTaxiNode) == "function" then
  hooksecurefunc("TakeTaxiNode", function(slot) pcall(Capture, slot) end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_CONTROL_GAINED")
events:SetScript("OnEvent", function(_, event)
  local f = Flight.Current()
  if not f then return end
  if event == "PLAYER_CONTROL_GAINED" then
    -- Only a watched flight's landing; the poll confirms it.
    if f.boarded then f.controlAt = GetTime() end
  else
    -- A /reload or login with a flight saved. UnitOnTaxi may not be settled this early, so the
    -- poll decides: the flight carries on once the player is seen on the taxi within
    -- LOGIN_GRACE, otherwise it's forgotten without learning.
    ns.settings.flight = Route.Resume(f, GetTime(), time(), true)
    f = ns.settings.flight
    if f then
      f.boarded, f.resumed, f.controlAt = true, true, nil
      graceUntil = GetTime() + LOGIN_GRACE
      Watch()
    end
  end
end)
