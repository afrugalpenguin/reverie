-- What starts and stops the overlay: flight paths, flying mount, AFK, and the preview.
local _, ns = ...
local state = ns.state

local Triggers = {}
ns.Triggers = Triggers

local POLL = 0.5 -- seconds between trigger checks

function Triggers.Evaluate()
  if not ns.settings or not ns.Text.live then return end
  local o = ns.settings.options

  local afk = UnitIsAFK("player")
  if afk and not state.afkSince then
    state.afkSince = GetTime()
  elseif not afk then
    state.afkSince = nil
  end

  -- Unlock mode and a running photo have the screen; triggers wait until they finish.
  if state.unlocked or state.photo then return end

  local onTaxi = UnitOnTaxi("player")
  local want = state.manual
    or (o.taxi and onTaxi)
    or (o.flying and IsFlying() and not onTaxi)
    or (o.afk and afk)
  if InCombatLockdown() then want = false end

  if not want then state.dismissed = false end

  if want and not state.dismissed then
    ns.Start()
  elseif state.active then
    ns.Stop()
  end
end

function Triggers.Begin()
  C_Timer.NewTicker(POLL, function()
    Triggers.Evaluate()
    if state.afkSince then ns.Text.Render() end -- keeps the away timer ticking
  end)
end
