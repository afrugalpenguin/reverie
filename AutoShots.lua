-- Automatic shots: level up, first visit to a zone, achievement earned, boss defeated. Each
-- enabled trigger takes a plain screenshot straight away (the UI as it is, fine in combat), then
-- the clean photo-mode capture with the ticked types and no self-timer. In combat, during a photo
-- or while unlocked, the clean capture is queued (one at most) and dropped after 30 seconds.
-- The decisions are in Layout (AutoAction, AutoQueue, AutoTake, AutoDuplicate, FirstVisit).
local _, ns = ...
local Layout = ns.Layout
local state = ns.state

local Auto = {}
ns.Auto = Auto

local PREFIX = "|cfff2deaeReverie|r: "
local ZONE_DELAY = 2      -- seconds after arriving in a new zone, so the world has drawn
local PLAIN_TIMEOUT = 5   -- seconds to wait for the plain screenshot's save event

local queued     -- { trigger, at } clean capture waiting for combat or a photo to end
local last       -- { trigger, at } the last trigger accepted, for de-duplication
local plain      -- { trigger, clean } a plain screenshot waiting for its save event
local lastSecond -- clock second of the most recent saved screenshot

local function CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function CanRunClean()
  return not (ns.Photo.IsRunning() or InCombatLockdown() or state.unlocked)
end

local function RunClean(trigger)
  if #Layout.TickedTypes(ns.settings.photo) == 0 then return end -- nothing to take
  ns.Photo.Take({ trigger = Layout.AUTO_TOAST[trigger], afterSecond = lastSecond })
end

-- After the plain screenshot is saved (or its event never comes): start or queue the clean one.
local function AfterPlain()
  local p = plain
  plain = nil
  if not p then return end
  if p.clean == "now" and CanRunClean() then
    RunClean(p.trigger)
  else
    queued = Layout.AutoQueue(queued, p.trigger, GetTime())
  end
end

function Auto.Fire(trigger)
  local photo = ns.settings and ns.settings.photo
  if not photo or not photo.auto[trigger] then return end

  local now = GetTime()
  if Layout.AutoDuplicate(last, trigger, now) then return end
  last = { trigger = trigger, at = now }

  local action = Layout.AutoAction({
    running = ns.Photo.IsRunning(), combat = InCombatLockdown(), unlocked = state.unlocked,
  })

  if action.plain and not plain then
    plain = { trigger = trigger, clean = action.clean }
    local mine = plain
    -- The overlay chat box is hidden first, so it isn't in the screenshot.
    ns.Chat.BeforeShot(function()
      if plain ~= mine then return end
      local ok = pcall(Screenshot)
      if not ok then
        AfterPlain()
      else
        C_Timer.After(PLAIN_TIMEOUT, function()
          if plain == mine then AfterPlain() end
        end)
      end
    end)
  else
    queued = Layout.AutoQueue(queued, trigger, now)
  end
end

-- Runs the queued clean capture if nothing is in the way. Called after combat and after a photo.
function Auto.Drain()
  if not queued or plain or not CanRunClean() then return end
  local trigger, expired = Layout.AutoTake(queued, GetTime())
  local name = Layout.AUTO_TOAST[queued.trigger]
  queued = nil
  if expired then
    print(PREFIX .. "Skipped the " .. name:lower() .. " photo because it couldn't be taken within "
      .. Layout.AUTO_QUEUE_SECONDS .. " seconds, for example during a long fight.")
  elseif trigger then
    RunClean(trigger)
  end
end

-- Events --------------------------------------------------------------------------------------

local seeded = false -- the zone you log in to is recorded, not photographed

local function Arrived()
  local visited = ns.settings and ns.settings.visited
  if not visited then return end
  if Layout.FirstVisit(visited, CharKey(), GetZoneText()) and seeded then
    C_Timer.After(ZONE_DELAY, function() Auto.Fire("zone") end)
  end
  seeded = true
end

local events = CreateFrame("Frame")
for _, e in ipairs({
  "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "ENCOUNTER_END",
  "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
}) do
  events:RegisterEvent(e)
end
-- Not every client has achievements; skip cleanly if the event doesn't exist on this one.
Auto.achievements = pcall(events.RegisterEvent, events, "ACHIEVEMENT_EARNED")

events:SetScript("OnEvent", function(_, event, ...)
  if event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
    if event == "SCREENSHOT_SUCCEEDED" then lastSecond = time() end
    if plain then AfterPlain() end
  elseif event == "PLAYER_LEVEL_UP" then
    -- UnitLevel can still return the old level for a moment, so the stamp uses this too.
    Auto.newLevel = tonumber((...))
    Auto.Fire("level")
  elseif event == "ACHIEVEMENT_EARNED" then
    Auto.Fire("achievement")
  elseif event == "ENCOUNTER_END" then
    local success = select(5, ...)
    if success == 1 or success == true then Auto.Fire("boss") end
  else -- ZONE_CHANGED_NEW_AREA, PLAYER_ENTERING_WORLD
    Arrived()
  end
end)
