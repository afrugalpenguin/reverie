-- Text element content, the full-screen overlay frame, and unlock mode.
local _, ns = ...
local Layout = ns.Layout
local state = ns.state

local Text = {}
ns.Text = Text

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

local live -- { frame, renderer, fadeAnim, wakeAnim, fade }

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

  -- Faded text comes back quickly when the mouse moves.
  local wake = renderer.text:CreateAnimationGroup()
  local back = wake:CreateAnimation("Alpha")
  back:SetFromAlpha(0)
  back:SetToAlpha(1)
  back:SetDuration(0.3)
  wake:SetToFinalAlpha(true)

  live = { frame = f, renderer = renderer, fadeAnim = anim, wakeAnim = wake }
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

-- Fades the text after Layout.FADE_DELAY seconds without mouse movement; moving the mouse brings
-- it back and restarts the delay. The cursor is polled rather than caught with mouse events, so
-- the overlay never takes clicks from the world. The camera orbit doesn't move the cursor.
local function FadeUpdate()
  local x, y = GetCursorPosition()
  local action = Layout.FadeStep(live.fade, x, y, GetTime())
  if action == "fade" then
    live.wakeAnim:Stop()
    live.fadeAnim:Play()
  elseif action == "show" then
    if live.fadeAnim:IsPlaying() then -- caught part-way: straight back
      live.fadeAnim:Stop()
      live.renderer.text:SetAlpha(1)
    else
      live.wakeAnim:Play()
    end
  end
end

function Text.StartFade()
  Text.StopFade()
  local x, y = GetCursorPosition()
  live.fade = Layout.NewFade(GetTime(), x, y)
  live.frame:SetScript("OnUpdate", FadeUpdate)
end

function Text.StopFade()
  if not live then return end
  live.frame:SetScript("OnUpdate", nil)
  live.fade = nil
  live.fadeAnim:Stop()
  live.wakeAnim:Stop()
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
    print("|cfff2deaeReverie|r: Text can't be unlocked during combat.")
    return
  end
  -- Leave the overlay first so the interface is back; triggers resume after /reverie lock.
  ns.Stop()
  state.unlocked = true
  Text.Show()
  Text.Render()
  print("|cfff2deaeReverie|r: Text unlocked. Drag any text to move it, then type /reverie lock or "
    .. "press Escape when you're done.")
end

function Text.Lock()
  if not state.unlocked then return end
  state.unlocked = false
  live.renderer:Apply(ns.settings, ns.Texts(false)) -- drops outlines and mouse handling
  Text.Hide()
  -- Triggers resume on their next poll (within half a second). Not evaluated here: Lock also
  -- runs as combat starts, and the overlay must not start then.
  print("|cfff2deaeReverie|r: Text locked in place.")
end
