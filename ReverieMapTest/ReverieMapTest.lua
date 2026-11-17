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
-- luacheck: read globals GetTaxiMapID GetPlayerFacing GetFileIDFromPath

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
  elseif d < 0.01 then
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

-- One sample of everything the in-flight map would read. Never prints; returns a record.
local function readSample()
  local s = {}
  s.mapID, s.mapErr = bestMap()
  s.x, s.y = playerPos(s.mapID)
  if s.x == nil then s.posErr = s.y; s.y = nil end
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
    .. " | zone " .. v(s.zone) .. " / " .. v(s.sub)
    .. " | facing " .. (s.facingErr and ("[" .. s.facingErr .. "]") or v(s.facing))
  if flight and flight.destX then
    local d = dist(s.cx, s.cy, flight.destX, flight.destY)
    line = line .. " | to dest node " .. (d and v(d) or "n/a")
  end
  return line
end

local function sample()
  local f = flight
  f.samples = f.samples + 1
  local n = f.samples
  local s = readSample()
  if s.mapErr then f.stats.map = f.stats.map + 1 end
  if s.posErr then f.stats.pos = f.stats.pos + 1 end
  if s.contErr then f.stats.cont = f.stats.cont + 1 end
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
    .. st.pos .. ", continent position failed " .. st.cont .. ", facing failed " .. st.facing
    .. "; maps seen: " .. table.concat(f.maps, ", "))
  -- Second coordinate check: the player at the destination against the destination node.
  if f.destX then
    local s = readSample()
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
    stats = { map = 0, pos = 0, cont = 0, facing = 0 },
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

-- Candidate soft-edged masks. Guesses: the test reports which exist on this client.
local MASK_PATHS = {
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

local function cmdArt()
  if not begin("art") then return end
  local function finish(problem)
    cancelTimers()
    cleanArt()
    if problem then fail("art: stopped - " .. problem) end
    info("art: frame hidden and tiles reset")
    busy = nil
  end

  local best, err = bestMap()
  if not best then finish("C_Map.GetBestMapForUnit: " .. tostring(err)) return end
  local contID, chain = continentOf(best)
  info("art: map chain " .. tostring(chain))
  if not contID then finish("no continent map") return end

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
  info(string.format("art: continent %s drawn at scale %.3f (%.0fx%.0f) on WorldFrame", v(contID), scale,
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
-- Reset and slash command
---------------------------------------------------------------------------------------------

resetAll = function()
  cancelTimers()
  pcall(cleanArt)
  pcall(cleanLine)
  disarmTaxi()
  busy = nil
end

local COMMANDS = { arm = cmdArm, art = cmdArt, line = cmdLine }

SLASH_REVERIEMAPTEST1 = "/rmt"
SlashCmdList.REVERIEMAPTEST = function(msg)
  local sub = strtrim(msg or ""):lower()
  if sub == "reset" then
    resetAll()
    info("reset: frames hidden, tiles reset, timers cancelled, taxi logging disarmed")
    return
  end
  local fn = COMMANDS[sub]
  if not fn then
    info("usage: /rmt arm | art | line | reset")
    return
  end
  local ok, err = pcall(fn)
  if not ok then
    fail(sub .. " errored: " .. tostring(err))
    resetAll()
  end
end
