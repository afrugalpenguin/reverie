-- A faded chat box on the overlay: guild, officer, whispers, party and raid messages, so they
-- aren't missed on a long flight. It's Reverie's own frame copying incoming messages; the game's
-- chat window stays where it is, hidden with the rest of the interface. Display only.
--
-- It never appears in screenshots: photo mode hides it for the whole photo (Chat.HideForPhoto)
-- while keeping the rest of the overlay in the shot. The automatic plain screenshot hides it
-- first (Chat.BeforeShot). Any other Screenshot() call, such
-- as the game's screenshot key if it goes through Lua, hides it from a hook; whether that's in
-- time for the captured frame needs checking in game. It comes back once the screenshot is saved.
local _, ns = ...
local Layout = ns.Layout
local state = ns.state

local Chat = {}
ns.Chat = Chat

local FONT = "Fonts\\FRIZQT__.TTF"
local ALPHA = 0.8        -- the whole box is slightly see-through
local FADE_SECONDS = 3   -- how long a message takes to fade out
local SHOT_TIMEOUT = 5   -- seconds to wait for a screenshot's save event before showing again

local box
local gameRect -- where the game's chat window was, in screen pixels, when the overlay started
local hiddenForShot = false
local shotToken = 0 -- so only the latest screenshot's timeout can show the box again

local function Create()
  box = CreateFrame("ScrollingMessageFrame", "ReverieChat", ns.Text.live.frame)
  box:SetFont(FONT, 14, "")
  box:SetShadowColor(0, 0, 0, 0.95)
  box:SetShadowOffset(1, -1)
  box:SetJustifyH("LEFT")
  box:SetMaxLines(50)
  box:SetFading(true)
  box:SetTimeVisible(Layout.CHAT_FADE_AFTER)
  box:SetFadeDuration(FADE_SECONDS)
  box:SetAlpha(ALPHA)
  box:EnableMouse(false)
  box:Hide()
end

-- In the game chat window's place, where players expect chat; bottom right if it couldn't be
-- measured.
local function Place()
  local root = ns.Text.live.frame
  box:ClearAllPoints()
  local g = gameRect and Layout.ChatRectFrom(gameRect.left, gameRect.bottom, gameRect.width,
    gameRect.height, 1, root:GetEffectiveScale())
  if g then
    box:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", g.left, g.bottom)
    box:SetSize(g.width, g.height)
    return
  end
  local r = Layout.ChatRect(root:GetWidth(), root:GetHeight(), ns.settings.options.bars)
  box:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -r.right, r.bottom)
  box:SetSize(r.width, r.height)
end

-- Called by ns.Start just before it hides the interface, while the game's chat window is still
-- laid out: remembers where it is, in screen pixels.
function Chat.Remember()
  local f = DEFAULT_CHAT_FRAME
  if not f then return end
  local okL, left, bottom, width, height = pcall(f.GetRect, f)
  local okS, scale = pcall(f.GetEffectiveScale, f)
  local px = okL and okS and Layout.ChatRectFrom(left, bottom, width, height, scale, 1)
  if px then gameRect = px end -- otherwise keep the last good one
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, text, author)
  if event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
    if hiddenForShot then
      hiddenForShot = false
      if state.active and box then box:Show() end
    end
    return
  end
  local chatType = Layout.CHAT_EVENTS[event]
  if not chatType or not box or type(text) ~= "string" then return end
  local info = ChatTypeInfo and ChatTypeInfo[chatType]
  box:AddMessage(Layout.ChatLine(chatType, author, text), info and info.r or 1, info and info.g or 1, info and info.b or 1)
end)
events:RegisterEvent("SCREENSHOT_SUCCEEDED")
events:RegisterEvent("SCREENSHOT_FAILED")

-- Called by ns.Start when the overlay comes up.
function Chat.Start()
  if not ns.settings.options.chat or not ns.Text.live then return end
  if not box then Create() end
  box:Clear()
  Place()
  hiddenForShot = false
  box:Show()
  for event in pairs(Layout.CHAT_EVENTS) do
    pcall(events.RegisterEvent, events, event) -- not every client has every event
  end
end

-- Called by ns.Stop.
function Chat.Stop()
  for event in pairs(Layout.CHAT_EVENTS) do
    pcall(events.UnregisterEvent, events, event)
  end
  hiddenForShot = false
  if box then
    box:Hide()
    box:Clear()
  end
end

-- Hides the box until the next screenshot is saved (or SHOT_TIMEOUT passes). Returns true if it
-- was showing.
local function HideForShot()
  if not (box and box:IsShown()) then return false end
  box:Hide()
  hiddenForShot = true
  shotToken = shotToken + 1
  local mine = shotToken
  C_Timer.After(SHOT_TIMEOUT, function()
    if hiddenForShot and shotToken == mine then
      hiddenForShot = false
      if state.active then box:Show() end
    end
  end)
  return true
end

-- Photo mode: hide the box for the whole photo. Photo mode owns it until ShowAfterPhoto, so a
-- screenshot's save event or an earlier shot's timeout mustn't bring it back. Returns true if
-- it was showing.
function Chat.HideForPhoto()
  if not (box and box:IsShown()) then return false end
  hiddenForShot = false
  box:Hide()
  return true
end

function Chat.ShowAfterPhoto()
  if box and state.active then box:Show() end
end

-- Calls fn once the box is off screen: straight away if it isn't showing, otherwise after
-- Layout.FRAMES_AFTER_LOOK frames so the hide has been drawn.
local waiter = CreateFrame("Frame")
function Chat.BeforeShot(fn)
  if not HideForShot() then return fn() end
  local frames = 0
  waiter:SetScript("OnUpdate", function(self)
    frames = frames + 1
    if frames >= Layout.FRAMES_AFTER_LOOK then
      self:SetScript("OnUpdate", nil)
      fn()
    end
  end)
end

hooksecurefunc("Screenshot", HideForShot)
