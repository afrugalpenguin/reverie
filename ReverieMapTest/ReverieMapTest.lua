-- ReverieMapTest: throwaway spike harness that proves the APIs an in-flight map needs on the
-- Forever client. NOT part of Reverie. Copy this folder into Interface\AddOns and type /rmt.
--
-- Rules every test follows:
--   * every client API call goes through try() (pcall) or an explicit pcall, so a missing or
--     blocked function prints a readable FAIL line instead of raising a Lua error;
--   * every asynchronous callback (timers, OnUpdate, events, the TakeTaxiNode hook) goes through
--     guard(), which runs resetAll() if the callback itself errors, so nothing stays on screen;
--   * every test hides what it drew and resets every texture it changed when it finishes.
--
-- luacheck: globals SLASH_REVERIEMAPTEST1 ReverieMapTestLog
-- luacheck: read globals C_Map C_TaxiMap Enum TakeTaxiNode TaxiNodeName TaxiNodeGetType TaxiNodePosition
-- luacheck: read globals GetNumRoutes TaxiGetSrcX TaxiGetSrcY TaxiGetDestX TaxiGetDestY NumTaxiNodes
-- luacheck: read globals GetTaxiMapID GetPlayerFacing GetFileIDFromPath debugprofilestop

local PREFIX = "|cff33ccff[RMT]|r "

-- /chatlog does not record AddMessage output, so every line is also kept here and saved to
-- WTF\Account\<account>\SavedVariables\ReverieMapTest.lua on logout or /reload.
local sessionLog = {}

local function out(msg)
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
  local plain = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  sessionLog[#sessionLog + 1] = date("%H:%M:%S ") .. plain
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= "ReverieMapTest" then return end
  ReverieMapTestLog = sessionLog  -- keep only this session's lines
  self:UnregisterEvent("ADDON_LOADED")
end)
local function pass(msg) out("|cff00ff00PASS|r " .. msg) end
local function fail(msg) out("|cffff3333FAIL|r " .. msg) end
local function info(msg) out("|cffffff00INFO|r " .. msg) end

local function packn(...) return { n = select("#", ...), ... } end

-- Calls fn(...) under pcall. Returns false after printing FAIL when fn is missing or errors,
-- otherwise true followed by fn's return values.
local function try(label, fn, ...)
  if type(fn) ~= "function" then
    fail(label .. ": function missing (" .. type(fn) .. ")")
    return false
  end
  local r = packn(pcall(fn, ...))
  if not r[1] then
    fail(label .. ": " .. tostring(r[2]))
    return false
  end
  return unpack(r, 1, r.n)
end

-- Formats any value for the log. Secret values (Midnight restrictions) are named, never touched.
local function v(x)
  if type(issecretvalue) == "function" and issecretvalue(x) then return "<secret>" end
  if type(x) == "number" and x ~= math.floor(x) then return string.format("%.4f", x) end
  if type(x) == "string" then return "'" .. x .. "'" end
  return tostring(x)
end

local function fmtXY(x, y) return "(" .. v(x) .. ", " .. v(y) .. ")" end

-- x, y of a Vector2D-like value, or nil.
local function xyOf(pos)
  if type(pos) ~= "table" then return nil end
  local ok, x, y = pcall(function()
    if type(pos.GetXY) == "function" then return pos:GetXY() end
    return pos.x, pos.y
  end)
  if ok then return x, y end
  return nil
end

-- Straight-line distance, or nil when any value is missing or secret.
local function dist(ax, ay, bx, by)
  local ok, d = pcall(function() return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end)
  if ok then return d end
  return nil
end

local function keysOf(t)
  local keys = {}
  for k, val in pairs(t) do keys[#keys + 1] = tostring(k) .. ":" .. type(val) end
  table.sort(keys)
  return table.concat(keys, ", ")
end

-- Looks up "C_TaxiMap.GetAllTaxiNodes" style paths without erroring on a missing namespace.
local function lookup(path)
  local t = _G
  for part in path:gmatch("[^.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end

---------------------------------------------------------------------------------------------
-- Shared state: one drawing test at a time, a watchdog timer, the frames each test draws into.
---------------------------------------------------------------------------------------------

local busy               -- name of the running drawing test, or nil
local timerToken = 0     -- bumped to cancel any pending timer
local resetAll           -- forward declaration

-- Wraps an async callback so an error in it resets everything instead of stranding a frame.
local function guard(label, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      fail(label .. " callback errored: " .. tostring(err))
      resetAll()
    end
  end
end

local function begin(name)
  if busy then
    fail(name .. ": '" .. busy .. "' is still running, wait for it (or /rmt reset)")
    return false
  end
  busy = name
  return true
end

local function after(seconds, label, fn)
  timerToken = timerToken + 1
  local mine = timerToken
  C_Timer.After(seconds, guard(label, function()
    if mine == timerToken then fn() end
  end))
end

local function cancelTimers() timerToken = timerToken + 1 end

---------------------------------------------------------------------------------------------
-- Map helpers
---------------------------------------------------------------------------------------------

local CONTINENT = (type(Enum) == "table" and type(Enum.UIMapType) == "table" and Enum.UIMapType.Continent) or 2

-- Walks up parentMapID until a continent. Returns continentID, chain text; or nil, reason.
local function continentOf(mapID)
  if type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then return nil, "C_Map.GetMapInfo missing" end
  local id, chain = mapID, {}
  for _ = 1, 10 do
    if not id or id == 0 then break end
    local ok, mapInfo = pcall(C_Map.GetMapInfo, id)
    if not ok then return nil, "GetMapInfo(" .. v(id) .. "): " .. tostring(mapInfo) end
    if type(mapInfo) ~= "table" then return nil, "GetMapInfo(" .. v(id) .. ") returned " .. type(mapInfo) end
    chain[#chain + 1] = v(id) .. " " .. v(mapInfo.name) .. " [type " .. v(mapInfo.mapType) .. "]"
    if mapInfo.mapType == CONTINENT then return id, table.concat(chain, " -> ") end
    id = mapInfo.parentMapID
  end
  return nil, "no continent above: " .. table.concat(chain, " -> ")
end

-- Player position on a map: x, y; or nil, reason.
local function playerPos(mapID)
  if not mapID then return nil, "no map" end
  if type(C_Map) ~= "table" or type(C_Map.GetPlayerMapPosition) ~= "function" then
    return nil, "C_Map.GetPlayerMapPosition missing"
  end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
  if not ok then return nil, tostring(pos) end
  if pos == nil then return nil, "returned nil" end
  local x, y = xyOf(pos)
  if x == nil then return nil, "returned " .. type(pos) .. " without x/y" end
  return x, y
end

local function bestMap()
  if type(C_Map) ~= "table" then return nil, "C_Map missing" end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok then return nil, tostring(id) end
  if id == nil then return nil, "returned nil" end
  return id
end

-- Logs two positions side by side and whether they look like one coordinate space.
local function compareSpaces(label, ax, ay, bx, by)
  local d = dist(ax, ay, bx, by)
  if not d then
    fail("coords " .. label .. ": cannot compare " .. fmtXY(ax, ay) .. " with " .. fmtXY(bx, by))
  elseif d < 0.002 then  -- the first run showed 0.0003 on the right map and 0.0096 on the wrong one
    pass("coords " .. label .. ": " .. fmtXY(ax, ay) .. " vs " .. fmtXY(bx, by)
      .. ", distance " .. v(d) .. " - same coordinate space")
  else
    info("coords " .. label .. ": " .. fmtXY(ax, ay) .. " vs " .. fmtXY(bx, by)
      .. ", distance " .. v(d) .. " - different space, or you are not standing at this node")
  end
end

---------------------------------------------------------------------------------------------
-- Taxi helpers
---------------------------------------------------------------------------------------------

local function describeNode(e)
  local ok, text = pcall(function()
    local x, y = xyOf(e.position)
    return "nodeID=" .. v(e.nodeID) .. " name=" .. v(e.name) .. " slotIndex=" .. v(e.slotIndex)
      .. " state=" .. v(e.state) .. " pos=" .. fmtXY(x, y)
  end)
  return ok and text or ("<unreadable entry: " .. tostring(text) .. ">")
end

-- The map the flight master uses: GetTaxiMapID(), else the player's continent.
local function taxiMap()
  if type(GetTaxiMapID) == "function" then
    local ok, id = pcall(GetTaxiMapID)
    if ok and id and id ~= 0 then return id, "GetTaxiMapID()" end
    fail("GetTaxiMapID(): " .. (ok and ("returned " .. v(id)) or tostring(id)) .. ", using the player's continent")
  else
    fail("GetTaxiMapID missing, using the player's continent")
  end
  local id = bestMap()
  return (continentOf(id)), "player's continent"
end

-- Calls one C_TaxiMap node function and logs what comes back. focus = { slot =, name =, what = }.
-- listAll logs every entry; otherwise only the first three and the ones matching focus.
local function logNodeApi(name, mapID, focus, listAll)
  local fn = lookup("C_TaxiMap." .. name)
  local label = "C_TaxiMap." .. name .. "(" .. v(mapID) .. ")"
  local ok, nodes = try(label, fn, mapID)
  if not ok then return nil end
  if type(nodes) ~= "table" then
    fail(label .. " returned " .. v(nodes))
    return nil
  end
  if #nodes == 0 then
    fail(label .. " returned an empty table")
    return nodes
  end
  pass(label .. " returned " .. #nodes .. " node(s); entry fields: " .. keysOf(nodes[1]))
  local matched = 0
  for i, e in ipairs(nodes) do
    local okM, isFocus = pcall(function()
      return (focus.slot ~= nil and e.slotIndex == focus.slot) or (focus.name ~= nil and e.name == focus.name)
    end)
    if okM and isFocus then
      matched = matched + 1
      info("  " .. name .. " " .. focus.what .. ": " .. describeNode(e))
    elseif listAll or i <= 3 then
      info("  " .. name .. " #" .. i .. ": " .. describeNode(e))
    end
  end
  if matched == 0 then
    fail(label .. ": no entry matched the " .. focus.what .. " (slot " .. v(focus.slot) .. ", name " .. v(focus.name) .. ")")
  end
  return nodes
end

-- Legacy per-slot data: name, type, x, y. Logs FAIL lines for missing or empty values.
local function readSlot(slot, prefix)
  local _, name = try(prefix .. "TaxiNodeName(" .. v(slot) .. ")", TaxiNodeName, slot)
  local _, kind = try(prefix .. "TaxiNodeGetType(" .. v(slot) .. ")", TaxiNodeGetType, slot)
  local _, x, y = try(prefix .. "TaxiNodePosition(" .. v(slot) .. ")", TaxiNodePosition, slot)
  if name == nil or name == "" then fail(prefix .. "TaxiNodeName returned " .. v(name)) end
  if kind == nil then fail(prefix .. "TaxiNodeGetType returned nil") end
  if x == nil or y == nil or (x == 0 and y == 0) then fail(prefix .. "TaxiNodePosition returned " .. fmtXY(x, y)) end
  return name, kind, x, y
end

---------------------------------------------------------------------------------------------
-- /rmt arm: TakeTaxiNode hook, taxi map snapshot, in-flight sampling, landing
---------------------------------------------------------------------------------------------

local API_LIST = {
  "hooksecurefunc", "TakeTaxiNode", "NumTaxiNodes", "TaxiNodeName", "TaxiNodeGetType", "TaxiNodePosition",
  "GetNumRoutes", "TaxiGetSrcX", "TaxiGetSrcY", "TaxiGetDestX", "TaxiGetDestY", "GetTaxiMapID",
  "C_TaxiMap.GetAllTaxiNodes", "C_TaxiMap.GetTaxiNodesForMap",
  "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo",
  "C_Map.GetMapArtLayers", "C_Map.GetMapArtLayerTextures",
  "UnitOnTaxi", "GetZoneText", "GetSubZoneText", "GetPlayerFacing", "GetFileIDFromPath",
}

local BOARD_TIMEOUT = 15  -- seconds after choosing a flight to wait for UnitOnTaxi

local armed = false
local hooked = false
local flight          -- the flight being watched, or nil
local lastOpen        -- { mapID =, slots = { [slot] = { name, kind, x, y } } } from the last TAXIMAP_OPENED

local watcher = CreateFrame("Frame")  -- OnUpdate ticks once a second while a flight is watched
local taxiEvents = CreateFrame("Frame")

local function stopWatch() watcher:SetScript("OnUpdate", nil) end

local lastTaxiMapID   -- the flight master's map from the last TAXIMAP_OPENED; survives disarm for /rmt art taxi

-- One sample of everything the in-flight map would read. Never prints; returns a record.
-- taxiMapID (optional) is the flight master's map, whose space the taxi node positions use.
local function readSample(taxiMapID)
  local s = {}
  s.mapID, s.mapErr = bestMap()
  s.x, s.y = playerPos(s.mapID)
  if s.x == nil then s.posErr = s.y; s.y = nil end
  s.taxiMapID = taxiMapID
  if taxiMapID then
    s.tx, s.ty = playerPos(taxiMapID)
    if s.tx == nil then s.taxiErr = s.ty; s.ty = nil end
  end
  s.contID, s.chain = continentOf(s.mapID)
  s.cx, s.cy = playerPos(s.contID)
  if s.cx == nil then s.contErr = s.cy; s.cy = nil end
  local okZ, zone = pcall(GetZoneText)
  s.zone = okZ and zone or ("ERR " .. tostring(zone))
  local okS, sub = pcall(GetSubZoneText)
  s.sub = okS and sub or ("ERR " .. tostring(sub))
  local okF, facing = pcall(GetPlayerFacing)
  s.facing = okF and facing or nil
  if not okF then s.facingErr = tostring(facing) elseif facing == nil then s.facingErr = "returned nil" end
  return s
end

local function sampleLine(n, since, s)
  local line = "sample #" .. n .. " +" .. string.format("%.0f", since) .. "s: map " .. v(s.mapID)
    .. (s.mapErr and (" [" .. s.mapErr .. "]") or "")
    .. " pos " .. (s.posErr and ("[" .. s.posErr .. "]") or fmtXY(s.x, s.y))
    .. " | continent " .. v(s.contID) .. " pos " .. (s.contErr and ("[" .. s.contErr .. "]") or fmtXY(s.cx, s.cy))
  if s.taxiMapID then
    line = line .. " | taxi map " .. v(s.taxiMapID) .. " pos "
      .. (s.taxiErr and ("[" .. s.taxiErr .. "]") or fmtXY(s.tx, s.ty))
  end
  line = line .. " | zone " .. v(s.zone) .. " / " .. v(s.sub)
    .. " | facing " .. (s.facingErr and ("[" .. s.facingErr .. "]") or v(s.facing))
  if flight and flight.destX and s.taxiMapID then
    local d = dist(s.tx, s.ty, flight.destX, flight.destY)
    line = line .. " | to dest node (taxi map) " .. (d and v(d) or "n/a")
  end
  return line
end

local function sample()
  local f = flight
  f.samples = f.samples + 1
  local n = f.samples
  local s = readSample(f.taxiMapID)
  if s.mapErr then f.stats.map = f.stats.map + 1 end
  if s.posErr then f.stats.pos = f.stats.pos + 1 end
  if s.contErr then f.stats.cont = f.stats.cont + 1 end
  if s.taxiErr then f.stats.taxi = f.stats.taxi + 1 end
  if s.facingErr then f.stats.facing = f.stats.facing + 1 end
  if s.mapID ~= f.lastMap then
    f.lastMap = s.mapID
    f.maps[#f.maps + 1] = v(s.mapID)
    info("map now " .. v(s.mapID) .. ", chain: " .. tostring(s.chain))
  end
  if n <= 5 or n % 10 == 0 then info(sampleLine(n, GetTime() - f.tChosen, s)) end
end

local function landed()
  local f = flight
  stopWatch()
  local now = GetTime()
  pass("landed (UnitOnTaxi false, 1 s poll): " .. string.format("%.1f", now - f.tChosen)
    .. " s from choosing at " .. f.clock .. ", " .. string.format("%.1f", now - f.tBoarded) .. " s on the taxi")
  local st = f.stats
  info("flight summary: " .. f.samples .. " samples; best map failed " .. st.map .. ", map position failed "
    .. st.pos .. ", continent position failed " .. st.cont .. ", taxi map position failed " .. st.taxi
    .. ", facing failed " .. st.facing .. "; maps seen: " .. table.concat(f.maps, ", "))
  -- Second coordinate check: the player at the destination against the destination node.
  if f.destX then
    local s = readSample(f.taxiMapID)
    compareSpaces("landing: dest TaxiNodePosition vs player on taxi map " .. v(s.taxiMapID),
      f.destX, f.destY, s.tx, s.ty)
    compareSpaces("landing: dest TaxiNodePosition vs player on continent " .. v(s.contID),
      f.destX, f.destY, s.cx, s.cy)
  end
  f.landedPoll = true
end

local function tick()
  local f = flight
  if not f then stopWatch() return end
  local okT, onTaxi = pcall(UnitOnTaxi, "player")
  if not okT then
    fail("UnitOnTaxi: " .. tostring(onTaxi) .. ", stopped watching")
    stopWatch()
    return
  end
  local since = GetTime() - f.tChosen
  if not f.boarded then
    if not onTaxi then
      if since > BOARD_TIMEOUT then
        fail("UnitOnTaxi still false " .. BOARD_TIMEOUT .. " s after choosing, stopped watching")
        stopWatch()
      end
      return
    end
    f.boarded = true
    f.tBoarded = GetTime()
    pass("UnitOnTaxi true " .. string.format("%.1f", since) .. " s after choosing")
  end
  if onTaxi then sample() else landed() end
end

local function startWatch()
  local acc = 0
  watcher:SetScript("OnUpdate", guard("flight watcher", function(_, elapsed)
    acc = acc + elapsed
    if acc < 1 then return end
    acc = 0
    tick()
  end))
end

local function onTakeTaxiNode(slot)
  if not armed then return end
  local okC, clock = pcall(date, "%H:%M:%S")
  flight = {
    slot = slot, tChosen = GetTime(), clock = okC and clock or "?", samples = 0, maps = {},
    stats = { map = 0, pos = 0, cont = 0, taxi = 0, facing = 0 },
  }
  pass("TakeTaxiNode(" .. v(slot) .. ") seen by hook at " .. flight.clock .. " (GetTime " .. v(flight.tChosen) .. ")")

  local name, kind, x, y = readSlot(slot, "dest ")
  info("dest (live, after TakeTaxiNode): name " .. v(name) .. ", type " .. v(kind) .. ", position " .. fmtXY(x, y))
  -- The map may already be closing when the hook runs, so also show what the map-open snapshot saw.
  local snap = lastOpen and lastOpen.slots[slot]
  if snap then
    info("dest (snapshot at map open): name " .. v(snap.name) .. ", type " .. v(snap.kind)
      .. ", position " .. fmtXY(snap.x, snap.y))
    if name == nil or name == "" then name = snap.name end
    if x == nil or (x == 0 and y == 0) then x, y = snap.x, snap.y end
  else
    info("dest: no map-open snapshot for slot " .. v(slot))
  end
  flight.destX, flight.destY = x, y

  local okR, routes = try("GetNumRoutes(" .. v(slot) .. ")", GetNumRoutes, slot)
  if okR then
    if type(routes) == "number" and routes > 0 then
      pass("GetNumRoutes = " .. routes .. " hop(s)")
      for hop = 1, routes do
        local _, sx = try("TaxiGetSrcX", TaxiGetSrcX, slot, hop)
        local _, sy = try("TaxiGetSrcY", TaxiGetSrcY, slot, hop)
        local _, dx = try("TaxiGetDestX", TaxiGetDestX, slot, hop)
        local _, dy = try("TaxiGetDestY", TaxiGetDestY, slot, hop)
        info("  hop " .. hop .. "/" .. routes .. ": " .. fmtXY(sx, sy) .. " -> " .. fmtXY(dx, dy))
      end
    else
      fail("GetNumRoutes returned " .. v(routes))
    end
  end

  local mapID, source = taxiMap()
  info("flight master map: " .. v(mapID) .. " (from " .. source .. ")")
  flight.taxiMapID = mapID
  local focus = { slot = slot, name = name, what = "destination" }
  logNodeApi("GetAllTaxiNodes", mapID, focus, false)
  logNodeApi("GetTaxiNodesForMap", mapID, focus, false)
  startWatch()
end

-- Taxi map opened: the full node list, and the coordinate check for the node the player is at.
local function onTaxiMapOpened()
  info("taxi map opened at " .. date("%H:%M:%S"))
  local mapID, source = taxiMap()
  info("flight master map: " .. v(mapID) .. " (from " .. source .. ")")

  local okN, count = try("NumTaxiNodes()", NumTaxiNodes)
  local current
  lastOpen = { mapID = mapID, slots = {} }
  lastTaxiMapID = mapID
  if okN and type(count) == "number" and count > 0 then
    pass("NumTaxiNodes = " .. count)
    local others = 0
    for slot = 1, count do
      local okS, name, kind, x, y = pcall(function()
        local px, py = TaxiNodePosition(slot)
        return TaxiNodeName(slot), TaxiNodeGetType(slot), px, py
      end)
      if not okS then
        fail("slot " .. slot .. ": " .. tostring(name))
        break
      end
      lastOpen.slots[slot] = { name = name, kind = kind, x = x, y = y }
      if kind == "CURRENT" then current = { slot = slot, name = name, x = x, y = y } end
      if kind == "CURRENT" or kind == "REACHABLE" then
        info("  slot " .. slot .. ": " .. v(name) .. " " .. v(kind) .. " " .. fmtXY(x, y))
      else
        others = others + 1
      end
    end
    info("  plus " .. others .. " slot(s) that are neither CURRENT nor REACHABLE")
  elseif okN then
    fail("NumTaxiNodes returned " .. v(count))
  end

  local focus = { slot = current and current.slot, name = current and current.name, what = "current node" }
  local all = logNodeApi("GetAllTaxiNodes", mapID, focus, true)
  logNodeApi("GetTaxiNodesForMap", mapID, focus, false)

  -- Coordinate check: you are standing at the CURRENT node, so its position should match yours.
  if not current then
    fail("coords: no CURRENT slot found, cannot compare node and player positions")
    return
  end
  local best = bestMap()
  local contID, chain = continentOf(best)
  info("coords: player map chain " .. tostring(chain) .. "; taxi map " .. v(mapID)
    .. (contID == mapID and " IS" or " is NOT") .. " the player's continent " .. v(contID))
  local tx, ty = playerPos(mapID)
  local cx, cy = playerPos(contID)
  compareSpaces("TaxiNodePosition vs player on taxi map " .. v(mapID), current.x, current.y, tx, ty)
  compareSpaces("TaxiNodePosition vs player on continent " .. v(contID), current.x, current.y, cx, cy)
  if type(all) == "table" then
    for _, e in ipairs(all) do
      local okM, isCurrent = pcall(function() return e.slotIndex == current.slot end)
      if okM and isCurrent then
        local nx, ny = xyOf(e.position)
        compareSpaces("C_TaxiMap position vs player on continent " .. v(contID), nx, ny, cx, cy)
      end
    end
  end
end

local TAXI_EVENTS = { "TAXIMAP_OPENED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }

taxiEvents:SetScript("OnEvent", guard("taxi event", function(_, event)
  if not armed then return end
  if event == "TAXIMAP_OPENED" then
    onTaxiMapOpened()
  elseif event == "PLAYER_CONTROL_LOST" then
    if flight then
      flight.controlLost = true
      info("PLAYER_CONTROL_LOST " .. string.format("%.1f", GetTime() - flight.tChosen) .. " s after choosing")
    end
  elseif event == "PLAYER_CONTROL_GAINED" then
    if flight and (flight.boarded or flight.controlLost) and not flight.controlGained then
      flight.controlGained = true
      pass("PLAYER_CONTROL_GAINED " .. string.format("%.1f", GetTime() - flight.tChosen)
        .. " s after choosing at " .. flight.clock .. " (event time, exact)")
    else
      info("PLAYER_CONTROL_GAINED with no flight in progress")
    end
  end
end))

local function cmdArm()
  for _, path in ipairs(API_LIST) do
    local t = type(lookup(path))
    if t == "function" then pass("exists: " .. path) else fail("missing: " .. path .. " (" .. t .. ")") end
  end
  if not hooked then
    if try("hooksecurefunc(TakeTaxiNode)", hooksecurefunc, "TakeTaxiNode", guard("TakeTaxiNode hook", onTakeTaxiNode)) then
      hooked = true
      pass("TakeTaxiNode hooked (stays until /reload; does nothing while disarmed)")
    end
  end
  for _, event in ipairs(TAXI_EVENTS) do
    if try("RegisterEvent(" .. event .. ")", taxiEvents.RegisterEvent, taxiEvents, event) then
      pass("event registered: " .. event)
    end
  end
  armed = true

  -- Where the player is now, so the first log shows the map chain even before a flight.
  local s = readSample()
  info("now: " .. sampleLine(0, 0, s))
  info("map chain: " .. tostring(s.chain))
  info("armed: open a flight master's map (logs nodes and the coordinate check), then pick a flight. "
    .. "/rmt reset disarms.")
end

local function disarmTaxi()
  armed = false
  stopWatch()
  flight = nil
  lastOpen = nil
  pcall(taxiEvents.UnregisterAllEvents, taxiEvents)
end

---------------------------------------------------------------------------------------------
-- /rmt art: continent map tiles in a 460x330 frame, plain, teal, faded, then masked
---------------------------------------------------------------------------------------------

local ART_W, ART_H = 460, 330
local STAGE_SECONDS = 10  -- each look (plain, teal, 50% alpha)
local MASK_SECONDS = 5    -- each mask
local TEAL = { 0.35, 0.85, 0.85 }

-- Candidate masks. Run 2 showed every Blizzard one below is a hard cut-out, so the first is our
-- own: white with alpha fading to 0 over the outer 40 of 256 px. GetFileIDFromPath may not know
-- addon files, so "exists NO" for it means nothing; judge it by eye.
local MASK_PATHS = {
  "Interface\\AddOns\\ReverieMapTest\\SoftEdgeMask",
  "Interface\\CharacterFrame\\TempPortraitAlphaMask",
  "Interface\\Masks\\CircleMaskScalable",
  "Interface\\Masks\\SquareMask",
  "Interface\\Common\\common-iconmask",
  "Interface\\FullScreenTextures\\LowHealth",
  "Textures\\MinimapMask",
}

local artFrame = CreateFrame("Frame", nil, WorldFrame)
artFrame:SetSize(ART_W, ART_H)
artFrame:SetPoint("CENTER")
artFrame:Hide()
local artCanvas = CreateFrame("Frame", nil, artFrame)
local artTiles = {}
local artMask  -- MaskTexture, created on first use
local artMaskOn = false

local function setMaskOnTiles(on)
  if not artMask or artMaskOn == on then return end
  local method = on and "AddMaskTexture" or "RemoveMaskTexture"
  local failed = 0
  for _, tex in ipairs(artTiles) do
    if not pcall(tex[method], tex, artMask) then failed = failed + 1 end
  end
  if failed > 0 then fail(method .. " failed on " .. failed .. " tile(s)") end
  artMaskOn = on
end

local function cleanArt()
  setMaskOnTiles(false)
  for _, tex in ipairs(artTiles) do
    pcall(tex.SetDesaturated, tex, false)
    pcall(tex.SetVertexColor, tex, 1, 1, 1, 1)
    pcall(tex.SetTexture, tex, nil)
    tex:Hide()
  end
  pcall(artFrame.SetAlpha, artFrame, 1)
  artFrame:Hide()
end

-- arg: "" for the player's continent, "taxi" for the last flight master's map, or a uiMapID.
-- contID below is whichever map was chosen.
local function cmdArt(arg)
  if not begin("art") then return end
  local function finish(problem)
    cancelTimers()
    cleanArt()
    if problem then fail("art: stopped - " .. problem) end
    info("art: frame hidden and tiles reset")
    busy = nil
  end

  local contID
  if arg == "taxi" then
    if not lastTaxiMapID then
      finish("no flight master map seen yet: /rmt arm, open a flight master's map, then /rmt art taxi")
      return
    end
    contID = lastTaxiMapID
    info("art: using the flight master's map " .. v(contID))
  elseif tonumber(arg) then
    contID = tonumber(arg)
    info("art: using map " .. v(contID) .. " from the command")
  elseif arg ~= "" then
    finish("unknown map '" .. arg .. "', use /rmt art, /rmt art taxi or /rmt art <mapID>")
    return
  else
    local best, err = bestMap()
    if not best then finish("C_Map.GetBestMapForUnit: " .. tostring(err)) return end
    local chain
    contID, chain = continentOf(best)
    info("art: map chain " .. tostring(chain))
    if not contID then finish("no continent map") return end
  end
  local okI, mapInfo = pcall(lookup("C_Map.GetMapInfo"), contID)
  if okI and type(mapInfo) == "table" then
    info("art: map " .. v(contID) .. " is " .. v(mapInfo.name) .. " [type " .. v(mapInfo.mapType)
      .. ", parent " .. v(mapInfo.parentMapID) .. "]")
  else
    fail("art: GetMapInfo(" .. v(contID) .. ") returned " .. (okI and v(mapInfo) or tostring(mapInfo)))
  end

  local okL, layers = try("C_Map.GetMapArtLayers(" .. v(contID) .. ")", lookup("C_Map.GetMapArtLayers"), contID)
  if not okL then finish("GetMapArtLayers failed") return end
  if type(layers) ~= "table" or #layers == 0 then finish("GetMapArtLayers returned " .. v(layers)) return end
  pass("GetMapArtLayers: " .. #layers .. " layer(s); fields: " .. keysOf(layers[1]))
  for i, layer in ipairs(layers) do
    info("  layer " .. i .. ": layer " .. v(layer.layerWidth) .. "x" .. v(layer.layerHeight) .. ", tile "
      .. v(layer.tileWidth) .. "x" .. v(layer.tileHeight) .. ", scale " .. v(layer.minScale) .. "-" .. v(layer.maxScale))
  end
  local layer = layers[1]
  local lw, lh, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
  if not (type(lw) == "number" and type(lh) == "number" and type(tw) == "number" and type(th) == "number"
      and lw > 0 and lh > 0 and tw > 0 and th > 0) then
    finish("layer 1 sizes unusable")
    return
  end
  local cols, rows = math.ceil(lw / tw), math.ceil(lh / th)

  local okT, files = try("C_Map.GetMapArtLayerTextures(" .. v(contID) .. ", 1)",
    lookup("C_Map.GetMapArtLayerTextures"), contID, 1)
  if not okT then finish("GetMapArtLayerTextures failed") return end
  if type(files) ~= "table" or #files == 0 then finish("GetMapArtLayerTextures returned " .. v(files)) return end
  local preview = {}
  for i = 1, math.min(4, #files) do preview[i] = v(files[i]) end
  local expect = cols * rows
  local note = (#files == expect) and "matches" or "does NOT match"
  pass("GetMapArtLayerTextures: " .. #files .. " texture(s), " .. note .. " " .. cols .. "x" .. rows
    .. " = " .. expect .. " tiles; first: " .. table.concat(preview, ", "))

  -- Fit the layer into the frame, keep its aspect, centre it; the canvas clips overhanging tiles.
  local scale = math.min(ART_W / lw, ART_H / lh)
  artCanvas:ClearAllPoints()
  artCanvas:SetSize(lw * scale, lh * scale)
  artCanvas:SetPoint("CENTER")
  try("SetClipsChildren(true)", artCanvas.SetClipsChildren, artCanvas, true)
  local setFailed = 0
  for i, file in ipairs(files) do
    local tex = artTiles[i]
    if not tex then
      tex = artCanvas:CreateTexture(nil, "ARTWORK")
      artTiles[i] = tex
    end
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    tex:ClearAllPoints()
    tex:SetSize(tw * scale, th * scale)
    tex:SetPoint("TOPLEFT", artCanvas, "TOPLEFT", col * tw * scale, -row * th * scale)
    if not pcall(tex.SetTexture, tex, file) then setFailed = setFailed + 1 end
    tex:Show()
  end
  if setFailed > 0 then fail("SetTexture failed on " .. setFailed .. " tile(s)") end
  artFrame:Show()
  info(string.format("art: map %s drawn at scale %.3f (%.0fx%.0f) on WorldFrame", v(contID), scale,
    lw * scale, lh * scale))

  local stages
  local function runStage(i)
    local stage = stages[i]
    if not stage then finish() return end
    stage.apply()
    after(stage.seconds, "art stage " .. i, function() runStage(i + 1) end)
  end

  stages = {
    { seconds = STAGE_SECONDS, apply = function()
      info("art 1: tiles as is for " .. STAGE_SECONDS .. " s")
    end },
    { seconds = STAGE_SECONDS, apply = function()
      local failed = 0
      for _, tex in ipairs(artTiles) do
        if not (pcall(tex.SetDesaturated, tex, true) and pcall(tex.SetVertexColor, tex, TEAL[1], TEAL[2], TEAL[3], 1)) then
          failed = failed + 1
        end
      end
      local okD, desat = pcall(artTiles[1].IsDesaturated, artTiles[1])
      if failed == 0 then pass("art 2: SetDesaturated + teal SetVertexColor on every tile") else
        fail("art 2: desaturate/teal failed on " .. failed .. " tile(s)") end
      info("art 2: IsDesaturated reads " .. (okD and v(desat) or ("ERR " .. tostring(desat)))
        .. "; desaturated teal for " .. STAGE_SECONDS .. " s")
    end },
    { seconds = STAGE_SECONDS, apply = function()
      try("SetAlpha(0.5)", artFrame.SetAlpha, artFrame, 0.5)
      local _, alpha = try("GetAlpha()", artFrame.GetAlpha, artFrame)
      info("art 3: teal at 50% alpha (GetAlpha reads " .. v(alpha) .. ") for " .. STAGE_SECONDS .. " s")
    end },
  }

  for _, path in ipairs(MASK_PATHS) do
    stages[#stages + 1] = { seconds = MASK_SECONDS, apply = function()
      setMaskOnTiles(false)
      pcall(artFrame.SetAlpha, artFrame, 1)
      local exists = "unknown (GetFileIDFromPath missing)"
      if type(GetFileIDFromPath) == "function" then
        local okF, id = pcall(GetFileIDFromPath, path)
        exists = okF and ((id and id ~= 0) and ("yes, file " .. v(id)) or "NO") or ("ERR " .. tostring(id))
      end
      if not artMask then
        local okM, mask = try("CreateMaskTexture()", artCanvas.CreateMaskTexture, artCanvas)
        if not okM or not mask then fail("mask: no MaskTexture, skipping " .. path) return end
        artMask = mask
        artMask:SetAllPoints(artCanvas)
      end
      local okS, ret = try("mask SetTexture(" .. path .. ")", artMask.SetTexture, artMask, path,
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      if not okS then return end
      setMaskOnTiles(true)
      info("mask " .. path .. ": exists " .. exists .. ", SetTexture returned " .. v(ret)
        .. ". Look now: do the map's edges fade? (" .. MASK_SECONDS .. " s, teal, full alpha)")
    end }
  end

  runStage(1)
end

---------------------------------------------------------------------------------------------
-- /rmt line: dashed route, node dots and labels drawn with CreateLine
---------------------------------------------------------------------------------------------

local LINE_SECONDS = 10
local DASH, GAP, THICKNESS = 10, 6, 3
local ROUTE = {  -- fractions of the frame, bottom-left origin
  { 0.10, 0.20, "Start" }, { 0.35, 0.55, "Hop 1" }, { 0.62, 0.45, "Hop 2" }, { 0.88, 0.85, "Destination" },
}

local lineFrame = CreateFrame("Frame", nil, WorldFrame)
lineFrame:SetSize(ART_W, ART_H)
lineFrame:SetPoint("CENTER")
lineFrame:Hide()
local lineBg = lineFrame:CreateTexture(nil, "BACKGROUND")
lineBg:SetAllPoints(lineFrame)
local linePool, dotPool, labelPool = {}, {}, {}

local function cleanLine()
  for _, pool in ipairs({ linePool, dotPool, labelPool }) do
    for _, obj in ipairs(pool) do obj:Hide() end
  end
  lineFrame:Hide()
end

local function cmdLine()
  if not begin("line") then return end
  local function finish(problem)
    cancelTimers()
    cleanLine()
    if problem then fail("line: stopped - " .. problem) end
    info("line: frame hidden")
    busy = nil
  end

  if type(lineFrame.CreateLine) ~= "function" then finish("CreateLine missing") return end
  pcall(lineBg.SetColorTexture, lineBg, 0, 0, 0, 0.5)

  local used = 0
  local function nextLine()
    used = used + 1
    local line = linePool[used]
    if not line then
      local ok, created = try("CreateLine()", lineFrame.CreateLine, lineFrame, nil, "ARTWORK")
      if not ok or not created then return nil end
      line = created
      linePool[used] = line
    end
    return line
  end

  -- One dashed segment from a to b, in pixels from the bottom-left corner.
  local function dashed(ax, ay, bx, by)
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    local ux, uy = (bx - ax) / len, (by - ay) / len
    local pos = 0
    while pos < len do
      local stop = math.min(pos + DASH, len)
      local line = nextLine()
      if not line then return false end
      line:SetStartPoint("BOTTOMLEFT", lineFrame, ax + ux * pos, ay + uy * pos)
      line:SetEndPoint("BOTTOMLEFT", lineFrame, ax + ux * stop, ay + uy * stop)
      line:SetThickness(THICKNESS)
      line:SetColorTexture(TEAL[1], TEAL[2], TEAL[3], 1)
      line:Show()
      pos = stop + GAP
    end
    return true
  end

  local ok, err = pcall(function()
    for i = 1, #ROUTE - 1 do
      local a, b = ROUTE[i], ROUTE[i + 1]
      if not dashed(a[1] * ART_W, a[2] * ART_H, b[1] * ART_W, b[2] * ART_H) then error("CreateLine failed") end
    end
  end)
  if not ok then finish("drawing dashes: " .. tostring(err)) return end
  pass("line: " .. used .. " dashes drawn with SetStartPoint / SetEndPoint / SetThickness")
  local okP, p1, rel, ox, oy = pcall(linePool[1].GetStartPoint, linePool[1])
  info("line: first dash GetStartPoint reads " .. (okP and (v(p1) .. " " .. tostring(rel) .. " " .. fmtXY(ox, oy))
    or ("ERR " .. tostring(p1))))

  local okD, errD = pcall(function()
    for i, node in ipairs(ROUTE) do
      local dot = dotPool[i]
      if not dot then
        dot = lineFrame:CreateTexture(nil, "OVERLAY")
        dotPool[i] = dot
      end
      dot:SetSize(10, 10)
      dot:SetColorTexture(1, 0.82, 0, 1)
      dot:ClearAllPoints()
      dot:SetPoint("CENTER", lineFrame, "BOTTOMLEFT", node[1] * ART_W, node[2] * ART_H)
      dot:Show()
      local label = labelPool[i]
      if not label then
        label = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        labelPool[i] = label
      end
      label:SetText(node[3])
      label:ClearAllPoints()
      label:SetPoint("BOTTOM", dot, "TOP", 0, 3)
      label:Show()
    end
  end)
  if okD then
    pass("line: " .. #ROUTE .. " node dots and labels drawn")
  else
    fail("line: dots/labels: " .. tostring(errD))
  end

  lineFrame:Show()
  info("line: showing for " .. LINE_SECONDS .. " s")
  after(LINE_SECONDS, "line timeout", function() finish() end)
end

---------------------------------------------------------------------------------------------
-- /rmt tilt [mapID]: the map lying flat on the ground, seen at an angle, built from map tiles
-- bent with Texture:SetVertexOffset. Stages, each on screen for a while:
--   1. which SetVertexOffset index is which corner (one test quad, each corner moved in turn)
--   2. the map art, tilted 50 degrees: whole tiles, then each tile as 4x4 sub-quads
--   3. the far edge faded by depth (SetGradient alpha on every sub-quad)
--   4. MapMask.tga on the bent sub-quads
--   5. a route (CreateLine) and an upright label at projected points; a timed full redraw first
---------------------------------------------------------------------------------------------

local TILT_W, TILT_H = 640, 440
local TILT_DEG, TURN_DEG = 50, 0
local CAMERA = 1.6            -- camera distance from the map's centre, in map heights
local TILT_MARGIN = 20        -- around the projected map inside the area
local SUB = 4                 -- sub-quads per tile side in the split stages
local FAR_FADE = 0.4          -- the farthest 40% of the map's depth fades to nothing
local TILT_STAGE = 10         -- seconds per stage
local CORNER_SECONDS = 2      -- seconds per corner in stage 1
local CORNER_MOVE = 40        -- units each corner moves in stage 1 (+x, +y: right and up)
local REDRAWS = 20            -- full redraws timed in stage 5
local TILT_MASK = "Interface\\AddOns\\ReverieMapTest\\MapMask"
local TILT_GOLD = { 0.96, 0.78, 0.41 }

-- The flight master's map for each continent (spike #54), and real route points on them.
local TAXI_FOR = { [1414] = 1464, [1415] = 1463 }
local TILT_ROUTES = {
  [1464] = { { 0.4495, 0.5615, "Thunder Bluff" }, { 0.5574, 0.5305, "Crossroads" }, { 0.6057, 0.5491, "Ratchet" } },
  [1463] = { { 0.4316, 0.9295, "Booty Bay" }, { 0.4483, 0.8364, "Grom'gol" }, { 0.5550, 0.5712, "Kargath" } },
}
local GENERIC_ROUTE = { { 0.3, 0.75, "Start" }, { 0.5, 0.5, "Stop" }, { 0.72, 0.28, "End" } }

local tiltFrame = CreateFrame("Frame", nil, WorldFrame)
tiltFrame:SetSize(TILT_W, TILT_H)
tiltFrame:SetPoint("CENTER")
tiltFrame:Hide()
local tiltBg = tiltFrame:CreateTexture(nil, "BACKGROUND")
tiltBg:SetAllPoints()
local testQuad = tiltFrame:CreateTexture(nil, "ARTWORK")
local cornerLabels = {}
local tiltQuads, tiltLines, tiltDots, tiltLabels = {}, {}, {}, {}
local tiltMask, tiltMaskOn = nil, false

-- Returns item n of a pool, making it with make() the first time.
local function poolItem(pool, n, make)
  local item = pool[n]
  if not item then
    item = make()
    pool[n] = item
  end
  item:Show()
  return item
end

local function hidePool(pool, from)
  for i = from or 1, #pool do pool[i]:Hide() end
end

local function setTiltMask(on)
  if not tiltMask or tiltMaskOn == on then return end
  local method = on and "AddMaskTexture" or "RemoveMaskTexture"
  local failed = 0
  for _, q in ipairs(tiltQuads) do
    if not pcall(q[method], q, tiltMask) then failed = failed + 1 end
  end
  if failed > 0 then fail("tilt: " .. method .. " failed on " .. failed .. " quad(s)") end
  tiltMaskOn = on
end

local function cleanTilt()
  setTiltMask(false)
  for _, q in ipairs(tiltQuads) do
    pcall(q.SetTexture, q, nil)
    pcall(q.SetVertexColor, q, 1, 1, 1, 1)
  end
  hidePool(tiltQuads)
  hidePool(tiltLines)
  hidePool(tiltDots)
  hidePool(tiltLabels)
  for _, l in pairs(cornerLabels) do l:Hide() end
  testQuad:Hide()
  tiltFrame:Hide()
end

-- Corner -> SetVertexOffset index. The retail constants when the client has them, else the
-- order they have there (1 upper left, 2 lower left, 3 upper right, 4 lower right).
local function vertexIndex()
  local idx = {
    TL = _G.UPPER_LEFT_VERTEX, BL = _G.LOWER_LEFT_VERTEX,
    TR = _G.UPPER_RIGHT_VERTEX, BR = _G.LOWER_RIGHT_VERTEX,
  }
  local all = idx.TL and idx.BL and idx.TR and idx.BR
  info("tilt: UPPER_LEFT_VERTEX=" .. v(idx.TL) .. " LOWER_LEFT_VERTEX=" .. v(idx.BL)
    .. " UPPER_RIGHT_VERTEX=" .. v(idx.TR) .. " LOWER_RIGHT_VERTEX=" .. v(idx.BR))
  if all then
    pass("tilt: the client defines the vertex index constants; using them")
    return idx
  end
  info("tilt: constants missing, assuming 1 upper left, 2 lower left, 3 upper right, 4 lower right")
  return { TL = 1, BL = 2, TR = 3, BR = 4 }
end

-- A perspective view of the map plane. Returns P(u, v) -> x, y (units from the area's bottom
-- left, y up) and depth. u, v are map fractions with v growing south; north is the far side.
local function projector(aspect, tiltDeg, turnDeg)
  local ct, st = math.cos(math.rad(tiltDeg)), math.sin(math.rad(tiltDeg))
  local cr, sr = math.cos(math.rad(turnDeg)), math.sin(math.rad(turnDeg))
  local function raw(u, vv)
    local X, Y = (u - 0.5) * aspect, 0.5 - vv
    X, Y = X * cr - Y * sr, X * sr + Y * cr
    local z = CAMERA + Y * st
    return X / z * CAMERA, Y * ct / z * CAMERA, z
  end
  -- Fit the whole projected map into the area.
  local minX, maxX, minY, maxY, minZ, maxZ
  for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    local x, y, z = raw(c[1], c[2])
    minX, maxX = math.min(minX or x, x), math.max(maxX or x, x)
    minY, maxY = math.min(minY or y, y), math.max(maxY or y, y)
    minZ, maxZ = math.min(minZ or z, z), math.max(maxZ or z, z)
  end
  local k = math.min((TILT_W - 2 * TILT_MARGIN) / (maxX - minX), (TILT_H - 2 * TILT_MARGIN) / (maxY - minY))
  local ox = TILT_W / 2 - (minX + maxX) / 2 * k
  local oy = TILT_H / 2 - (minY + maxY) / 2 * k
  return function(u, vv)
    local x, y, z = raw(u, vv)
    return ox + x * k, oy + y * k, z
  end, minZ, maxZ
end

-- Bends a texture to the projected quad of map rectangle (u0, v0)-(u1, v1): anchors it to the
-- quad's bounding box and moves each corner onto its projected point.
local function placeQuad(tex, P, idx, u0, v0, u1, v1)
  local tlx, tly = P(u0, v0)
  local trx, try_ = P(u1, v0)
  local blx, bly = P(u0, v1)
  local brx, bry = P(u1, v1)
  local l, r = math.min(tlx, blx, trx, brx), math.max(tlx, blx, trx, brx)
  local b, t = math.min(tly, bly, try_, bry), math.max(tly, bly, try_, bry)
  tex:ClearAllPoints()
  tex:SetPoint("BOTTOMLEFT", tiltFrame, "BOTTOMLEFT", l, b)
  tex:SetSize(math.max(r - l, 1), math.max(t - b, 1))
  tex:SetVertexOffset(idx.TL, tlx - l, tly - t)
  tex:SetVertexOffset(idx.TR, trx - r, try_ - t)
  tex:SetVertexOffset(idx.BL, blx - l, bly - b)
  tex:SetVertexOffset(idx.BR, brx - r, bry - b)
end

-- Alpha for a depth: 1 nearer than the far FAR_FADE of the map, fading to 0 at the far edge.
local function depthAlpha(z, minZ, maxZ)
  local start = maxZ - FAR_FADE * (maxZ - minZ)
  if z <= start then return 1 end
  return math.max(0, 1 - (z - start) / (maxZ - start))
end

-- Draws every tile, split into sub x sub quads. fade: apply the depth gradient. Returns the quad
-- count and how many calls failed.
local function drawTilted(art, idx, sub, fade, turnDeg)
  local P, minZ, maxZ = projector(art.aspect, TILT_DEG, turnDeg or TURN_DEG)
  local n, failed = 0, 0
  for i, file in ipairs(art.files) do
    local col, row = (i - 1) % art.cols, math.floor((i - 1) / art.cols)
    local u0, v0 = col * art.tileW / art.layerW, row * art.tileH / art.layerH
    local du, dv = art.tileW / art.layerW / sub, art.tileH / art.layerH / sub
    for sy = 0, sub - 1 do
      for sx = 0, sub - 1 do
        n = n + 1
        local q = poolItem(tiltQuads, n, function() return tiltFrame:CreateTexture(nil, "ARTWORK") end)
        local ok = pcall(function()
          q:SetTexture(file)
          q:SetTexCoord(sx / sub, (sx + 1) / sub, sy / sub, (sy + 1) / sub)
          local a0, b0 = u0 + sx * du, v0 + sy * dv
          placeQuad(q, P, idx, a0, b0, a0 + du, b0 + dv)
          if fade then
            local _, _, zTop = P(a0 + du / 2, b0)
            local _, _, zBottom = P(a0 + du / 2, b0 + dv)
            q:SetGradient("VERTICAL", CreateColor(1, 1, 1, depthAlpha(zBottom, minZ, maxZ)),
              CreateColor(1, 1, 1, depthAlpha(zTop, minZ, maxZ)))
          else
            q:SetVertexColor(1, 1, 1, 1)
          end
        end)
        if not ok then failed = failed + 1 end
      end
    end
  end
  hidePool(tiltQuads, n + 1)
  return n, failed, P
end

-- The art to tilt: [mapID], else the flight master's map for the player's continent, else the
-- continent. Returns { aspect, layerW, layerH, tileW, tileH, cols, files } or nil.
local function tiltArt(arg)
  local mapID = tonumber(arg)
  if not mapID then
    local cont, chain = continentOf((bestMap()))
    info("tilt: map chain " .. tostring(chain))
    mapID = cont and (TAXI_FOR[cont] or cont)
  end
  if not mapID then return nil end
  info("tilt: drawing map " .. v(mapID) .. (TAXI_FOR[mapID] and " (a continent)" or ""))
  local okL, layers = try("C_Map.GetMapArtLayers(" .. v(mapID) .. ")", lookup("C_Map.GetMapArtLayers"), mapID)
  if not okL or type(layers) ~= "table" or not layers[1] then return nil end
  local okT, files = try("C_Map.GetMapArtLayerTextures(" .. v(mapID) .. ", 1)",
    lookup("C_Map.GetMapArtLayerTextures"), mapID, 1)
  if not okT or type(files) ~= "table" or #files == 0 then return nil end
  local l = layers[1]
  pass("tilt: art " .. v(l.layerWidth) .. "x" .. v(l.layerHeight) .. ", tiles " .. v(l.tileWidth) .. "x"
    .. v(l.tileHeight) .. ", " .. #files .. " texture(s)")
  return {
    mapID = mapID, aspect = l.layerWidth / l.layerHeight, layerW = l.layerWidth, layerH = l.layerHeight,
    tileW = l.tileWidth, tileH = l.tileHeight, cols = math.ceil(l.layerWidth / l.tileWidth), files = files,
  }
end

local function cmdTilt(arg)
  if not begin("tilt") then return end
  local function finish(problem)
    cancelTimers()
    cleanTilt()
    if problem then fail("tilt: stopped - " .. problem) end
    info("tilt: everything hidden")
    busy = nil
  end

  if type(testQuad.SetVertexOffset) == "function" then
    pass("tilt: Texture:SetVertexOffset exists")
  else
    finish("Texture:SetVertexOffset missing (" .. type(testQuad.SetVertexOffset) .. ")")
    return
  end
  info("tilt: Texture:GetVertexOffset " .. (type(testQuad.GetVertexOffset) == "function" and "exists" or "missing")
    .. ", Texture:SetGradient " .. (type(testQuad.SetGradient) == "function" and "exists" or "missing"))
  local idx = vertexIndex()
  local art = tiltArt(arg)
  if not art then finish("no map art to tilt") return end

  try("SetClipsChildren(true)", tiltFrame.SetClipsChildren, tiltFrame, true)
  tiltBg:SetColorTexture(0, 0, 0, 0.35)
  tiltFrame:Show()

  local stages = {}
  local function run(i)
    local stage = stages[i]
    if not stage then finish() return end
    local seconds = stage.apply()
    after(seconds or TILT_STAGE, "tilt stage " .. i, function() run(i + 1) end)
  end

  -- 1. Which index is which corner: a test quad with its corners labelled, each index moved in turn.
  local corners = { { "TL", "TOPLEFT" }, { "TR", "TOPRIGHT" }, { "BL", "BOTTOMLEFT" }, { "BR", "BOTTOMRIGHT" } }
  stages[#stages + 1] = { apply = function()
    testQuad:ClearAllPoints()
    testQuad:SetPoint("CENTER")
    testQuad:SetSize(160, 160)
    testQuad:SetColorTexture(0.2, 0.6, 1.0, 0.85)
    testQuad:Show()
    for _, c in ipairs(corners) do
      local label = cornerLabels[c[1]]
      if not label then
        label = tiltFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        cornerLabels[c[1]] = label
      end
      label:SetText(c[1])
      label:ClearAllPoints()
      label:SetPoint("CENTER", testQuad, c[2], 0, 0)
      label:Show()
    end
    info("tilt 1: a blue square with its corners labelled TL TR BL BR. Each index moves its corner "
      .. CORNER_MOVE .. " right and up for " .. CORNER_SECONDS .. " s: note which label it leaves.")
    return 0.5
  end }
  for i = 1, 4 do
    stages[#stages + 1] = { apply = function()
      for j = 1, 4 do pcall(testQuad.SetVertexOffset, testQuad, j, 0, 0) end
      if try("SetVertexOffset(" .. i .. ", " .. CORNER_MOVE .. ", " .. CORNER_MOVE .. ")",
          testQuad.SetVertexOffset, testQuad, i, CORNER_MOVE, CORNER_MOVE) then
        local readBack = ""
        if type(testQuad.GetVertexOffset) == "function" then
          local okG, gx, gy = pcall(testQuad.GetVertexOffset, testQuad, i)
          readBack = okG and (", GetVertexOffset reads " .. fmtXY(gx, gy)) or (", GetVertexOffset: " .. tostring(gx))
        end
        local expect
        for name, n in pairs(idx) do if n == i then expect = name end end
        info("tilt 1: index " .. i .. " moved" .. readBack .. ". Expected corner: " .. tostring(expect)
          .. ". Which label did it pull away from?")
      end
      return CORNER_SECONDS
    end }
  end

  -- 2. The map tilted: whole tiles, then each tile as 4x4.
  stages[#stages + 1] = { apply = function()
    for j = 1, 4 do pcall(testQuad.SetVertexOffset, testQuad, j, 0, 0) end
    testQuad:Hide()
    for _, l in pairs(cornerLabels) do l:Hide() end
    local n, failed = drawTilted(art, idx, 1, false)
    if failed == 0 then pass("tilt 2a: " .. n .. " whole tile(s) bent with SetVertexOffset") else
      fail("tilt 2a: " .. failed .. " of " .. n .. " tile(s) failed") end
    info("tilt 2a: tilt " .. TILT_DEG .. ", turn " .. TURN_DEG .. ", whole tiles for " .. TILT_STAGE
      .. " s. Look for a bend or crease along each tile's diagonal.")
  end }
  stages[#stages + 1] = { apply = function()
    local n, failed = drawTilted(art, idx, SUB, false)
    if failed == 0 then pass("tilt 2b: " .. n .. " sub-quads (" .. SUB .. "x" .. SUB .. " per tile) with SetTexCoord") else
      fail("tilt 2b: " .. failed .. " of " .. n .. " sub-quad(s) failed") end
    info("tilt 2b: the same map as " .. SUB .. "x" .. SUB .. " sub-quads for " .. TILT_STAGE
      .. " s. Is the diagonal bend gone? Any seams or gaps between sub-quads?")
  end }

  -- 3. The far edge faded by depth.
  stages[#stages + 1] = { apply = function()
    local n, failed = drawTilted(art, idx, SUB, true)
    if failed == 0 then pass("tilt 3: SetGradient alpha on " .. n .. " bent sub-quads") else
      fail("tilt 3: " .. failed .. " of " .. n .. " sub-quad(s) failed with a gradient") end
    info("tilt 3: the farthest " .. math.floor(FAR_FADE * 100) .. "% fades out for " .. TILT_STAGE
      .. " s. Smooth fade towards the far edge, and still bent correctly (gradients and offsets together)?")
  end }

  -- 4. MapMask.tga on the bent sub-quads.
  stages[#stages + 1] = { apply = function()
    if not tiltMask then
      local okM, mask = try("CreateMaskTexture()", tiltFrame.CreateMaskTexture, tiltFrame)
      if not okM or not mask then fail("tilt 4: no MaskTexture") return end
      tiltMask = mask
      tiltMask:SetAllPoints(tiltFrame)
    end
    local okS, ret = try("mask SetTexture(MapMask)", tiltMask.SetTexture, tiltMask, TILT_MASK,
      "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if okS then
      setTiltMask(true)
      info("tilt 4: MapMask on every sub-quad (SetTexture returned " .. v(ret) .. ") for " .. TILT_STAGE
        .. " s. Do the area's edges fade softly, and do the bent quads still draw in the right place?")
    end
  end }

  -- 5. Timing, then a route and an upright label on the tilted plane.
  stages[#stages + 1] = { apply = function()
    local now = type(debugprofilestop) == "function" and debugprofilestop or function() return GetTime() * 1000 end
    local total, worst, n = 0, 0, 0
    for k = 1, REDRAWS do
      local t0 = now()
      n = drawTilted(art, idx, SUB, true, (k % 2 == 0) and 5 or 0) -- the view changes each time
      local dt = now() - t0
      total, worst = total + dt, math.max(worst, dt)
    end
    info(string.format("tilt 5: full redraw of %d sub-quads (projection, SetPoint, SetSize, 4 SetVertexOffset, "
      .. "SetTexCoord, SetGradient each): %.2f ms average, %.2f ms worst over %d redraws", n, total / REDRAWS,
      worst, REDRAWS))
    info(string.format("tilt 5: at 10 redraws a second that's %.1f ms a second", total / REDRAWS * 10))

    local _, _, P = drawTilted(art, idx, SUB, true, TURN_DEG) -- back to the view with no turn
    local points = TILT_ROUTES[art.mapID] or GENERIC_ROUTE
    local ok, err = pcall(function()
      for i, p in ipairs(points) do
        local x, y = P(p[1], p[2])
        local dot = poolItem(tiltDots, i, function() return tiltFrame:CreateTexture(nil, "OVERLAY") end)
        dot:SetColorTexture(TILT_GOLD[1], TILT_GOLD[2], TILT_GOLD[3], 1)
        dot:SetSize(10, 10)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", tiltFrame, "BOTTOMLEFT", x, y)
        local label = poolItem(tiltLabels, i, function()
          return tiltFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        end)
        label:SetText(p[3])
        label:ClearAllPoints()
        label:SetPoint("BOTTOM", tiltFrame, "BOTTOMLEFT", x, y + 8)
        if i > 1 then
          local px, py = P(points[i - 1][1], points[i - 1][2])
          local line = poolItem(tiltLines, i - 1, function() return tiltFrame:CreateLine(nil, "OVERLAY") end)
          line:SetStartPoint("BOTTOMLEFT", tiltFrame, px, py)
          line:SetEndPoint("BOTTOMLEFT", tiltFrame, x, y)
          line:SetThickness(4)
          line:SetColorTexture(TILT_GOLD[1], TILT_GOLD[2], TILT_GOLD[3], 1)
        end
      end
    end)
    if ok then
      pass("tilt 5: route of " .. #points .. " points drawn with projected CreateLine ends and upright labels")
    else
      fail("tilt 5: route: " .. tostring(err))
    end
    info("tilt 5: for " .. TILT_STAGE .. " s. Do the dots sit on the right places on the bent map ("
      .. (TILT_ROUTES[art.mapID] and "real flight masters" or "sample points") .. "), and the labels stay upright?")
  end }

  run(1)
end

---------------------------------------------------------------------------------------------
-- Reset and slash command
---------------------------------------------------------------------------------------------

resetAll = function()
  cancelTimers()
  pcall(cleanArt)
  pcall(cleanLine)
  pcall(cleanTilt)
  disarmTaxi()
  busy = nil
end

local COMMANDS = { arm = cmdArm, art = cmdArt, line = cmdLine, tilt = cmdTilt }

SLASH_REVERIEMAPTEST1 = "/rmt"
SlashCmdList.REVERIEMAPTEST = function(msg)
  local sub, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
  if sub == "reset" then
    resetAll()
    info("reset: frames hidden, tiles reset, timers cancelled, taxi logging disarmed")
    return
  end
  local fn = COMMANDS[sub]
  if not fn then
    info("usage: /rmt arm | art [taxi | <mapID>] | line | tilt [<mapID>] | reset")
    return
  end
  local ok, err = pcall(fn, arg)
  if not ok then
    fail(sub .. " errored: " .. tostring(err))
    resetAll()
  end
end
