-- Settings, shared state, the overlay session (Start/Stop) and event wiring.
local addonName, ns = ...
local Layout = ns.Layout

local state = {
  active = false,
  manual = false,     -- started from "Preview in game" or /reverie preview
  dismissed = false,  -- Escape pressed; stays down until the trigger ends
  unlocked = false,   -- /reverie unlock: elements are draggable, triggers are paused
  photo = false,      -- a photo sequence is running; triggers are paused
  afkSince = nil,
}
ns.state = state

function ns.Start()
  if state.active or state.unlocked or InCombatLockdown() then return end
  local o = ns.settings.options
  state.active = true

  ns.Chat.Remember() -- while the game's chat window is still laid out
  UIParent:Hide()
  -- The name above the character isn't part of UIParent, so hide it separately. CVars.Set records
  -- the original first, so a crash with the overlay up is repaired at the next login.
  ns.CVars.Set("overlay", "UnitNameOwn", "0")
  ns.Text.Show()
  ns.Text.Render()
  if o.fade then ns.Text.StartFade() end
  ns.Chat.Start()
  ns.Camera.Begin(o)
end

function ns.Stop()
  state.manual = false
  if not state.active then return end
  state.active = false

  ns.Text.StopFade()
  ns.Chat.Stop()
  ns.Camera.End()
  ns.CVars.Restore("overlay")
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
  -- Not settings, so a reset keeps them: CVars still waiting to be put back, zones visited, and
  -- whether the tour has been seen.
  local restore = ns.settings and ns.settings.restore
  local visited = ns.settings and ns.settings.visited
  local tourSeen = ns.settings and ns.settings.tourSeen
  ns.settings = Layout.Defaults()
  ns.settings.restore = restore
  ns.settings.visited = visited or ns.settings.visited
  if tourSeen ~= nil then ns.settings.tourSeen = tourSeen end
  ReverieDB = ns.settings
  ns.Refresh()
end

function ns.Preview()
  state.manual = true
  state.dismissed = false
  ns.Triggers.Evaluate()
end

local tourNews = false -- a save from before the tour: tell them about /reverie tour at login
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, arg1)
  if event == "PLAYER_LOGOUT" then
    -- Settings are saved on logout (an AFK timeout logs out with the overlay up), so put every
    -- changed CVar back first.
    ns.Photo.Abort("logged out")
    ns.CVars.RestoreAll()
  elseif event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    tourNews = Layout.TourNews(ReverieDB)
    ns.settings = Layout.Merge(ReverieDB)
    ReverieDB = ns.settings
    self:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    -- Repair CVars left changed by a crash or reload in the middle of a photo or the overlay.
    local count, failed = ns.CVars.RestoreAll()
    if count > 0 then
      -- A crash or reload mid-photo or mid-overlay; say what was fixed, and what wasn't.
      local fixed = count - #failed
      print("|cfff2deaeReverie|r: Your last session ended while Reverie had changed some game "
        .. "settings. " .. (fixed == 1 and "1 setting has" or (fixed .. " settings have"))
        .. " been put back."
        .. (#failed > 0 and (" These couldn't be put back: " .. table.concat(failed, ", ") .. ".") or ""))
    end
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
    if tourNews then
      print("|cfff2deaeReverie|r: New in this version: a short tour of what Reverie does. "
        .. "Type /reverie tour to start it.")
    end
    ns.Tour.AutoLater()
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- Fires just before combat lockdown, while UIParent can still be shown.
    ns.Photo.Abort("entered combat")
    ns.Text.Lock()
    ns.Stop()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if state.showUIAfterCombat then
      state.showUIAfterCombat = false
      if not state.active then UIParent:Show() end
    end
    ns.Triggers.Evaluate()
    ns.Auto.Drain() -- an automatic shot queued during combat
  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    ns.Text.Rescale()
    ns.Refresh()
  elseif event:find("^ZONE_CHANGED") or event == "PLAYER_GUILD_UPDATE" then
    ns.Refresh()
  else
    ns.Triggers.Evaluate()
  end
end)
