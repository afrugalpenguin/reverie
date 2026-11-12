-- Settings, triggers (flight path, flying mount, AFK), and the in-game overlay.
local addonName, ns = ...
local Layout = ns.Layout

local ORBIT_SPEED = 0.03   -- MoveViewLeftStart multiplier: a slow, steady turn
local ZOOM_OUT = 8         -- camera distance added while the overlay is up
local FADE_DELAY = 10      -- seconds before text fades, when "Fade text after 10s" is on
local POLL = 0.5           -- seconds between trigger checks

local state = {
  active = false,
  manual = false,     -- started from "Preview in game" or /reverie preview
  dismissed = false,  -- Escape pressed; stays down until the trigger ends
  afkSince = nil,
}
ns.state = state

local live -- { frame, renderer, fadeAnim }

function ns.Texts(sample)
  local guild = GetGuildInfo("player")
  local zone, subzone = GetZoneText() or "", GetSubZoneText() or ""
  if subzone == zone then subzone = "" end

  local away = ""
  if state.afkSince then
    away = "Away " .. Layout.FormatAway(GetTime() - state.afkSince)
  elseif sample then
    away = "Away 12:04"
  end

  return {
    -- GetUnitName(unit, true) gives the full "First Surname" on Forever.
    name = Layout.DisplayName(GetUnitName("player", true), nil, ns.settings.options.surname),
    guild = guild and ("<" .. guild .. ">") or (sample and "<Guild>" or ""),
    realm = GetRealmName() or "",
    level = string.format("%s %d %s %s", LEVEL, UnitLevel("player"), UnitRace("player") or "", UnitClass("player") or ""),
    zone = zone,
    subzone = (subzone ~= "" or not sample) and subzone or "Subzone",
    away = away,
  }
end

local function RenderLive()
  if live and state.active then
    live.renderer:Apply(ns.settings, ns.Texts(false))
  end
end

local function CreateLive()
  -- Parentless so it stays visible while UIParent is hidden.
  local f = CreateFrame("Frame", "ReverieOverlay", nil)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetScale(UIParent:GetScale())
  f:SetAllPoints(WorldFrame)
  f:Hide()

  -- Escape leaves the overlay; every other key passes through to the game.
  f:EnableKeyboard(true)
  f:SetPropagateKeyboardInput(true)
  f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      state.dismissed = true
      ns.Stop()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  local renderer = ns.Overlay.New(f)
  local anim = renderer.text:CreateAnimationGroup()
  local alpha = anim:CreateAnimation("Alpha")
  alpha:SetFromAlpha(1)
  alpha:SetToAlpha(0)
  alpha:SetDuration(1.5)
  anim:SetToFinalAlpha(true)

  live = { frame = f, renderer = renderer, fadeAnim = anim }
end

local function RestoreOwnName()
  if state.restoreOwnName then
    SetCVar("UnitNameOwn", "1")
    state.restoreOwnName = false
  end
end

function ns.Start()
  if state.active or InCombatLockdown() then return end
  local o = ns.settings.options
  state.active = true

  UIParent:Hide()
  -- The name above the character isn't part of UIParent, so hide it separately.
  if GetCVar("UnitNameOwn") == "1" then
    SetCVar("UnitNameOwn", "0")
    state.restoreOwnName = true
  end
  live.frame:SetScale(UIParent:GetScale())
  live.frame:SetPropagateKeyboardInput(true)
  live.fadeAnim:Stop()
  live.renderer.text:SetAlpha(1)
  live.frame:Show()
  RenderLive()

  if o.fade then
    state.fadeTimer = C_Timer.NewTimer(FADE_DELAY, function() live.fadeAnim:Play() end)
  end
  if o.zoom then
    state.zoomStart = GetCameraZoom()
    CameraZoomOut(ZOOM_OUT)
  end
  if o.orbit then
    MoveViewLeftStart(ORBIT_SPEED)
    state.orbiting = true
  end
end

function ns.Stop()
  state.manual = false
  if not state.active then return end
  state.active = false

  if state.fadeTimer then
    state.fadeTimer:Cancel()
    state.fadeTimer = nil
  end
  live.fadeAnim:Stop()
  live.renderer.text:SetAlpha(1)

  if state.orbiting then
    MoveViewLeftStop()
    state.orbiting = false
  end
  if state.zoomStart then
    CameraZoomIn(math.max(0, GetCameraZoom() - state.zoomStart))
    state.zoomStart = nil
  end

  RestoreOwnName()
  live.frame:Hide()
  if InCombatLockdown() then
    state.showUIAfterCombat = true
  else
    UIParent:Show()
  end
end

local function Evaluate()
  if not ns.settings or not live then return end
  local o = ns.settings.options

  local afk = UnitIsAFK("player")
  if afk and not state.afkSince then
    state.afkSince = GetTime()
  elseif not afk then
    state.afkSince = nil
  end

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

-- Called whenever settings change: redraw the overlay and the options preview.
function ns.Refresh()
  RenderLive()
  if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.ResetSettings()
  ns.settings = Layout.Defaults()
  ReverieDB = ns.settings
  ns.Refresh()
end

function ns.Preview()
  state.manual = true
  state.dismissed = false
  Evaluate()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, arg1)
  if event == "PLAYER_LOGOUT" then
    -- Settings are saved on logout (an AFK timeout logs out with the overlay up).
    RestoreOwnName()
  elseif event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    ns.settings = Layout.Merge(ReverieDB)
    ReverieDB = ns.settings
    self:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    CreateLive()
    if ns.RegisterSettingsCategory then ns.RegisterSettingsCategory() end
    for _, e in ipairs({
      "PLAYER_FLAGS_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
      "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
      "PLAYER_GUILD_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    }) do
      self:RegisterEvent(e)
    end
    C_Timer.NewTicker(POLL, function()
      Evaluate()
      if state.afkSince then RenderLive() end -- keeps the away timer ticking
    end)
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- Fires just before combat lockdown, while UIParent can still be shown.
    ns.Stop()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if state.showUIAfterCombat then
      state.showUIAfterCombat = false
      if not state.active then UIParent:Show() end
    end
    Evaluate()
  elseif event:find("^ZONE_CHANGED") or event == "PLAYER_GUILD_UPDATE" then
    ns.Refresh()
  else
    Evaluate()
  end
end)

SLASH_REVERIE1 = "/reverie"
SlashCmdList.REVERIE = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "preview" then
    ns.Preview()
  elseif msg == "stop" then
    state.dismissed = true
    ns.Stop()
  else
    ns.ToggleOptions()
  end
end
