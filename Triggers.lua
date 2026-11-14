-- What starts and stops the overlay: flight paths, flying mount, AFK, and the preview.
local _, ns = ...
local state = ns.state

local Triggers = {}
ns.Triggers = Triggers

local POLL = 0.5 -- seconds between trigger checks

function Triggers.Evaluate()
  if not ns.settings or not ns.Text.live then return end
  local o = ns.settings.options

  local afk, onTaxi, flying = UnitIsAFK("player"), UnitOnTaxi("player"), IsFlying()
  -- In restricted moments the client can return these as secret values, which an addon can't
  -- test. Then there's no telling what's happening, so leave everything as it is until the next
  -- poll. (Combat still closes the overlay: Core's PLAYER_REGEN_DISABLED doesn't come here.)
  if ns.Layout.HasSecret(issecretvalue, afk, onTaxi, flying) then return end

  if afk and not state.afkSince then
    state.afkSince = GetTime()
  elseif not afk then
    state.afkSince = nil
  end

  -- Unlock mode and a running photo have the screen; triggers wait until they finish.
  if state.unlocked or state.photo then return end

  local want = state.manual
    or (o.taxi and onTaxi)
    or (o.flying and flying and not onTaxi)
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
