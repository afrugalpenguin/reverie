-- Pure flight route logic for the flight map: building a route from the taxi hops, how far along
-- it the player is, time to arrival, the next stop, and learning flight times. No WoW API calls,
-- so tests/run.lua can load it outside the client.
--
-- Every position is on the flight master's taxi map (GetTaxiMapID: 1463 Eastern Kingdoms, 1464
-- Kalimdor), as x, y fractions with y growing downward. The spike (#54) showed the route and the
-- player only line up there: the continent map is 0.01 to 0.025 off.
local _, ns = ...
local Layout = ns.Layout

local Route = {}
ns.Route = Route

Route.MIN_TIME, Route.MAX_TIME = Layout.FLIGHT_MIN, Layout.FLIGHT_MAX
Route.LEARN_CAP = Layout.LEARN_CAP
Route.MATCH = 0.003     -- a hop's end this close to a taxi node is that node
Route.ARRIVE = 0.01     -- landing this close to the destination counts as arriving (spike: 0)
Route.MIN_SPAN = 0.08   -- the overlay never zooms in further than this much of the map
Route.RESUME_SLOP = 5   -- seconds GetTime may drift from the clock and still count as the same session

local function number(v) return type(v) == "number" and v == v end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function dist(ax, ay, bx, by)
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- The taxi node at x, y, or nil. Old nodes left in the data ("zzOLD...") can share a real node's
-- position, so they never match.
local function NodeAt(nodes, x, y)
  local best, bestD
  for _, node in ipairs(nodes or {}) do
    local name = node.name
    if number(node.x) and number(node.y) and not (type(name) == "string" and name:find("^zzOLD")) then
      local d = dist(node.x, node.y, x, y)
      if d <= Route.MATCH and (not bestD or d < bestD) then best, bestD = node, d end
    end
  end
  return best
end

-- A route from the chosen flight's hops (each { srcX, srcY, destX, destY }, from TaxiGetSrcX/Y and
-- TaxiGetDestX/Y) and the taxi map's nodes ({ nodeID, name, x, y }) for names. Returns
-- { points = { {x, y}, ... }, stops = { {x, y, at, name, nodeID}, ... }, length }, one stop per
-- point: the origin, each stop on the way, the destination. at is the stop's fraction of the
-- route's length. nil when the hops can't make a route.
function Route.Build(hops, nodes)
  if type(hops) ~= "table" or #hops == 0 then return nil end
  local points = {}
  for i, h in ipairs(hops) do
    if type(h) ~= "table" or not (number(h[1]) and number(h[2]) and number(h[3]) and number(h[4])) then
      return nil
    end
    if i == 1 then points[1] = { x = h[1], y = h[2] } end
    points[#points + 1] = { x = h[3], y = h[4] }
  end

  local length, along = 0, { 0 }
  for i = 2, #points do
    length = length + dist(points[i - 1].x, points[i - 1].y, points[i].x, points[i].y)
    along[i] = length
  end
  if length <= 0 then return nil end

  local stops = {}
  for i, p in ipairs(points) do
    local node = NodeAt(nodes, p.x, p.y)
    stops[i] = { x = p.x, y = p.y, at = along[i] / length, name = node and node.name, nodeID = node and node.nodeID }
  end
  return { points = points, stops = stops, length = length }
end

-- The key learned times are stored under: "originID>destinationID", or the names when there are
-- no node IDs. nil when neither end can be named.
function Route.Key(route)
  local o, d = route.stops[1], route.stops[#route.stops]
  if o.nodeID and d.nodeID then return o.nodeID .. ">" .. d.nodeID end
  if o.name and d.name then return o.name .. ">" .. d.name end
  return nil
end

-- How far along the route the point x, y is, as a fraction: the nearest point on the route. from
-- (optional) is progress so far; hops before the one it's on are skipped, so a route that passes
-- near itself can't send the marker back.
function Route.Project(route, x, y, from)
  local stops = route.stops
  local first = 1
  if from then
    for i = 1, #stops - 1 do
      if stops[i + 1].at >= from then
        first = i
        break
      end
    end
  end

  local best, bestD
  for i = first, #stops - 1 do
    local a, b = stops[i], stops[i + 1]
    local vx, vy = b.x - a.x, b.y - a.y
    local len2 = vx * vx + vy * vy
    local t = len2 > 0 and clamp(((x - a.x) * vx + (y - a.y) * vy) / len2, 0, 1) or 0
    local d = dist(a.x + vx * t, a.y + vy * t, x, y)
    if not bestD or d < bestD then
      best, bestD = a.at + (b.at - a.at) * t, d
    end
  end
  return best or 0
end

-- Progress (0 to 1) and seconds to arrival. p: { elapsed, learned, x, y, prev }.
--   A learned time gives progress by time and a time to arrival.
--   Otherwise the player's taxi map position is projected onto the route; flight paths curve
--   around the straight hops, so it never goes back from prev, and there's no time to arrival.
function Route.Progress(route, p)
  local prev = p.prev or 0
  if number(p.learned) and p.learned > 0 and number(p.elapsed) then
    return clamp(p.elapsed / p.learned, 0, 1), math.max(0, p.learned - p.elapsed)
  end
  if number(p.x) and number(p.y) then
    return math.max(prev, Route.Project(route, p.x, p.y, prev)), nil
  end
  return prev, nil
end

-- The point at a fraction of the route, and the heading there as a unit vector (dx, dy).
function Route.PointAt(route, progress)
  local stops = route.stops
  progress = clamp(progress, 0, 1)
  for i = 1, #stops - 1 do
    local a, b = stops[i], stops[i + 1]
    if progress <= b.at or i == #stops - 1 then
      local span = b.at - a.at
      local t = span > 0 and clamp((progress - a.at) / span, 0, 1) or 0
      local vx, vy = b.x - a.x, b.y - a.y
      local len = math.sqrt(vx * vx + vy * vy)
      return a.x + vx * t, a.y + vy * t, len > 0 and vx / len or 1, len > 0 and vy / len or 0
    end
  end
end

-- The first stop not yet reached, and whether it's the destination; nil once arrived.
function Route.NextStop(route, progress)
  local stops = route.stops
  for i = 2, #stops do
    if stops[i].at > progress + 1e-9 then return stops[i], i == #stops end
  end
  return nil
end

-- A stop's name without its zone ("Thunder Bluff, Mulgore" is "Thunder Bluff"); "" for none.
function Route.ShortName(name)
  if type(name) ~= "string" then return "" end
  return name:match("^([^,]+)") or name
end

-- "m:ss", rounding up so it reaches 0:00 on arrival rather than a second early.
function Route.FormatTime(seconds)
  if not number(seconds) or seconds < 0 then seconds = 0 end
  seconds = math.ceil(seconds)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Folds a flight's time into the route's learned time. entry: { seconds, count } or nil.
-- completed: the flight landed at its destination. Returns the new entry and true, or the old
-- entry and false when the time is discarded (implausible, or the flight ended early).
-- The first LEARN_CAP flights are a plain average; after that each new one counts 1 in LEARN_CAP,
-- so a changed route catches up.
function Route.Learn(entry, seconds, completed)
  if not completed or not number(seconds) or seconds < Route.MIN_TIME or seconds > Route.MAX_TIME then
    return entry, false
  end
  if not entry then return { seconds = seconds, count = 1 }, true end
  local n = math.min(entry.count, Route.LEARN_CAP - 1)
  return {
    seconds = entry.seconds + (seconds - entry.seconds) / (n + 1),
    count = math.min(entry.count + 1, Route.LEARN_CAP),
  }, true
end

-- True when x, y (the player on the taxi map, on landing) is at the destination.
function Route.Arrived(route, x, y)
  if not (number(x) and number(y)) then return false end
  local d = route.stops[#route.stops]
  return dist(d.x, d.y, x, y) <= Route.ARRIVE
end

-- The style after this one on the map key: strip, overlay, off, and round again.
function Route.NextStyle(style)
  local styles = Layout.MAP_STYLES
  for i, s in ipairs(styles) do
    if s == style then return styles[i % #styles + 1] end
  end
  return styles[1]
end

-- The style to show: the current flight's map key choice, else the saved style when the map shows
-- automatically, else off.
function Route.Style(map, override)
  if override then return override end
  return map.auto and map.style or "off"
end

-- Fits the route into a w x h box with pad around it, keeping the map's shape. aspect is the taxi
-- map's width over its height (its positions are fractions of each). Returns a fit for Place.
function Route.Fit(route, aspect, w, h, pad)
  local minX, maxX, minY, maxY
  for _, s in ipairs(route.stops) do
    local x = s.x * aspect
    minX, maxX = math.min(minX or x, x), math.max(maxX or x, x)
    minY, maxY = math.min(minY or s.y, s.y), math.max(maxY or s.y, s.y)
  end
  local spanX = math.max(maxX - minX, Route.MIN_SPAN)
  local spanY = math.max(maxY - minY, Route.MIN_SPAN)
  local scale = math.min((w - 2 * pad) / spanX, (h - 2 * pad) / spanY)
  return {
    aspect = aspect,
    scale = scale,
    ox = w / 2 - (minX + maxX) / 2 * scale,
    oy = h / 2 - (minY + maxY) / 2 * scale,
  }
end

-- A taxi map position in the fitted box, in units from its top-left (y downward).
function Route.Place(fit, x, y)
  return fit.ox + x * fit.aspect * fit.scale, fit.oy + y * fit.scale
end

-- A saved flight after a /reload or login. Kept while still on the taxi and younger than any
-- flight can be. GetTime survives a /reload but restarts with the client, so when it no longer
-- lines up with the clock the start is moved to match (to the second).
function Route.Resume(flight, now, wall, onTaxi)
  if type(flight) ~= "table" or not onTaxi then return nil end
  local age = wall - flight.chosenWall
  if age < 0 or age > Route.MAX_TIME then return nil end
  if math.abs((now - flight.chosenAt) - age) > Route.RESUME_SLOP then
    flight.chosenAt = now - age
  end
  return flight
end
