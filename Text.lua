-- Text element content, the full-screen overlay frame, and unlock mode.
local _, ns = ...
local Layout = ns.Layout
local state = ns.state

local Text = {}
ns.Text = Text

local FADE_DELAY = 10 -- seconds before text fades, when "Fade text after 10s" is on

-- Text for each element. sample = true fills empty ones with placeholders (options preview
-- and unlock mode), so every element has something to show.
function ns.Texts(sample)
  local guild = GetGuildInfo("player")
  local zone, subzone = GetZoneText() or "", GetSubZoneText() or ""
  if subzone == zone then subzone = "" end

  local away = ""
  if state.afkSince and ns.settings.options.afk then
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

local live -- { frame, renderer, fadeAnim, fadeTimer }

-- The overlay is a WorldFrame child so it stays up while UIParent is hidden. Scale it so its
-- units match UIParent's, keeping text the same size at any UI scale.
function Text.Rescale()
  if not live then return end
  local worldScale = WorldFrame:GetEffectiveScale()
  live.frame:SetScale(UIParent:GetEffectiveScale() / (worldScale > 0 and worldScale or 1))
end

function Text.Create()
  if live then return end
  local f = CreateFrame("Frame", "ReverieOverlay", WorldFrame)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetAllPoints(WorldFrame)
  f:Hide()

  -- Escape leaves the overlay (or unlock mode); every other key passes through to the game.
  f:EnableKeyboard(true)
  f:SetPropagateKeyboardInput(true)
  f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      if state.unlocked then
        Text.Lock()
      else
        state.dismissed = true
        ns.Stop()
      end
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
  Text.live = live
  Text.Rescale()
end

function Text.Show()
  Text.Rescale()
  live.frame:SetPropagateKeyboardInput(true)
  live.fadeAnim:Stop()
  live.renderer.text:SetAlpha(1)
  live.frame:Show()
end

function Text.Hide()
  live.frame:Hide()
end

function Text.StartFade()
  Text.StopFade()
  live.fadeTimer = C_Timer.NewTimer(FADE_DELAY, function() live.fadeAnim:Play() end)
end

function Text.StopFade()
  if not live then return end
  if live.fadeTimer then
    live.fadeTimer:Cancel()
    live.fadeTimer = nil
  end
  live.fadeAnim:Stop()
  live.renderer.text:SetAlpha(1)
end

-- Unlock mode -----------------------------------------------------------------

local function OnDrop(id, x, y, w, h)
  local e = ns.settings.elements[id]
  e.free = true
  e.x, e.y = Layout.FreeFromPoint(x, y, w, h)
  ns.Refresh()
end

function Text.Render()
  if not live then return end
  if state.unlocked then
    live.renderer:Apply(ns.settings, ns.Texts(true), nil, { onDrop = OnDrop })
  elseif state.active then
    live.renderer:Apply(ns.settings, ns.Texts(false))
  end
end

function Text.Unlock()
  if state.unlocked then return end
  if InCombatLockdown() then
    print("|cfff2deaeReverie|r: can't unlock in combat.")
    return
  end
  -- Leave the overlay first so the interface is back; triggers resume after /reverie lock.
  ns.Stop()
  state.unlocked = true
  Text.Show()
  Text.Render()
  print("|cfff2deaeReverie|r: unlocked. Drag text to place it freely; /reverie lock or Escape when done.")
end

function Text.Lock()
  if not state.unlocked then return end
  state.unlocked = false
  live.renderer:Apply(ns.settings, ns.Texts(false)) -- drops outlines and mouse handling
  Text.Hide()
  -- Triggers resume on their next poll (within half a second). Not evaluated here: Lock also
  -- runs as combat starts, and the overlay must not start then.
  print("|cfff2deaeReverie|r: locked.")
end
