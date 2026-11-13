-- Settings, shared state, the overlay session (Start/Stop) and event wiring.
local addonName, ns = ...
local Layout = ns.Layout

local state = {
  active = false,
  manual = false,     -- started from "Preview in game" or /reverie preview
  dismissed = false,  -- Escape pressed; stays down until the trigger ends
  unlocked = false,   -- /reverie unlock: elements are draggable, triggers are paused
  afkSince = nil,
}
ns.state = state

local function RestoreOwnName()
  if state.restoreOwnName then
    SetCVar("UnitNameOwn", "1")
    state.restoreOwnName = false
  end
end

function ns.Start()
  if state.active or state.unlocked or InCombatLockdown() then return end
  local o = ns.settings.options
  state.active = true

  UIParent:Hide()
  -- The name above the character isn't part of UIParent, so hide it separately.
  if GetCVar("UnitNameOwn") == "1" then
    SetCVar("UnitNameOwn", "0")
    state.restoreOwnName = true
  end
  ns.Text.Show()
  ns.Text.Render()
  if o.fade then ns.Text.StartFade() end
  ns.Camera.Begin(o)
end

function ns.Stop()
  state.manual = false
  if not state.active then return end
  state.active = false

  ns.Text.StopFade()
  ns.Camera.End()
  RestoreOwnName()
  ns.Text.Hide()
  if InCombatLockdown() then
    state.showUIAfterCombat = true
  else
    UIParent:Show()
  end
end

-- Called whenever settings change: redraw the overlay and the options preview.
function ns.Refresh()
  ns.Text.Render()
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
  ns.Triggers.Evaluate()
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
    ns.Text.Create()
    if ns.RegisterSettingsCategory then ns.RegisterSettingsCategory() end
    for _, e in ipairs({
      "PLAYER_FLAGS_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
      "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
      "PLAYER_GUILD_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
      "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
    }) do
      self:RegisterEvent(e)
    end
    ns.Triggers.Begin()
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- Fires just before combat lockdown, while UIParent can still be shown.
    ns.Text.Lock()
    ns.Stop()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if state.showUIAfterCombat then
      state.showUIAfterCombat = false
      if not state.active then UIParent:Show() end
    end
    ns.Triggers.Evaluate()
  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    ns.Text.Rescale()
    ns.Refresh()
  elseif event:find("^ZONE_CHANGED") or event == "PLAYER_GUILD_UPDATE" then
    ns.Refresh()
  else
    ns.Triggers.Evaluate()
  end
end)
