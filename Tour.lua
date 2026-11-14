-- Onboarding tour: a small card that walks a new player through the overlay, a photo, the photo
-- key and the options. Shown once per account on a fresh install; /reverie tour replays it.
-- The card is a child of UIParent, so the overlay and photo mode hide it with the rest of the
-- interface (it can never end up in a photo). When the interface comes back, a step that was
-- waiting on its action moves on to its "done" text.
local _, ns = ...
local Layout = ns.Layout

local Tour = {}
ns.Tour = Tour

local PREFIX = "|cfff2deaeReverie|r: "
local AUTO_DELAY = 3 -- seconds after login, so the loading screen and login chat are out of the way

local STEPS = {
  { title = "Welcome to Reverie",
    body = "Reverie hides your interface while you travel or step away, so you can just enjoy "
      .. "the view. It also takes clean screenshots of it.",
    next = "Start" },
  { title = "The overlay",
    body = "When you take a flight path, fly your mount or go AFK, your interface fades away and "
      .. "cinema bars appear. Press Escape or move to bring it back.",
    action = "Show me",
    run = function()
      ns.Preview()
      if ns.state.active then Tour.ShowExit() end
      -- Refused (text unlocked, say): don't leave it queued to start by itself later.
      if not ns.state.active then ns.state.manual = false end
      return ns.state.active
    end,
    doneBody = "That's the overlay. From now on it starts by itself." },
  { title = "Take a photo",
    body = "Photo mode hides everything, counts down, and saves a clean screenshot.",
    action = "Take a test photo",
    run = function()
      ns.Photo.Take()
      return ns.Photo.IsRunning()
    end,
    doneBody = "Photos are saved to the Screenshots folder inside your World of Warcraft "
      .. "_forever_ folder." },
  { title = "A photo key",
    body = "Pick a key to take photos with. This is optional; you can always do it later.",
    key = true },
  { title = "Make it yours",
    body = "Type /reverie any time to choose what shows, where it goes and what starts the "
      .. "overlay. /reverie tour shows this tour again.",
    next = "Done" },
}

local UI
local card, counter, title, body, note, keyButton, back, skip, action
local index = 1
local waiting = false -- the step's action started; it's done when the interface comes back
local done = false    -- the step's action has finished, so it shows doneBody and Next
-- Set from PLAYER_REGEN_DISABLED, which fires just before combat lockdown starts, so
-- InCombatLockdown() alone would still be false when the card redraws for it.
local inCombat = false

local function InCombat() return inCombat or InCombatLockdown() end

local function Render()
  local s = STEPS[index]
  counter:SetText(index .. " of " .. #STEPS)
  title:SetText(s.title)
  body:SetText(done and s.doneBody or s.body)
  keyButton:SetShown(s.key == true)
  back:SetShown(index > 1)
  skip.label:SetText(index == #STEPS and "Open options" or "Skip tour")

  local pending = s.run and not done
  action.label:SetText(pending and s.action or s.next or "Next")
  local blocked = pending and InCombat()
  action:SetEnabled(not blocked)
  action:SetAlpha(blocked and 0.5 or 1)
  note:SetShown(blocked and true or false)
end

local function Go(i)
  index, waiting, done = i, false, false
  Render()
end

-- A "Back to the tour" button in the overlay's bottom bar, shown only for the tour's preview,
-- so a first-time player isn't left wondering how to get out. It's a child of the overlay, so
-- it goes when the overlay does; HideExit makes sure it isn't there next time the overlay starts.
local exit

function Tour.ShowExit()
  local live = ns.Text.live
  if not live then return end
  if not exit then
    exit = UI.Button(live.frame, 280, 30, "Back to the tour (or press Escape)", 13)
    UI.SetActive(exit, true)
    exit:SetScript("OnClick", function()
      -- The same as Escape on the overlay.
      ns.state.dismissed = true
      ns.Stop()
    end)
  end
  local barH = Layout.BarHeight(live.frame:GetHeight(), ns.settings.options.bars)
  exit:ClearAllPoints()
  exit:SetPoint("BOTTOM", live.frame, "BOTTOM", 0, barH > 0 and math.max(4, (barH - 30) / 2) or 40)
  exit:Show()
end

local function HideExit()
  if exit then exit:Hide() end
end

local function Finish()
  ns.settings.tourSeen = true
  waiting, done = false, false
  HideExit()
  card:Hide()
end

local function Create()
  if card then return end
  UI = ns.UI
  local C = UI.C

  card = UI.Box(UIParent, C.bg, C.border)
  card:SetSize(400, 210)
  card:SetPoint("TOP", UIParent, "TOP", 0, -120)
  card:SetFrameStrata("DIALOG")
  card:EnableMouse(true)
  card:Hide()

  counter = UI.Text(card, 11, C.muted)
  counter:SetPoint("TOPLEFT", 18, -16)
  title = UI.Text(card, 20, C.title, UI.TITLE_FONT)
  title:SetPoint("TOPLEFT", 18, -34)
  body = UI.Text(card, 13, C.text)
  body:SetPoint("TOPLEFT", 18, -68)
  body:SetWidth(364)
  body:SetSpacing(3)

  keyButton = UI.Button(card, 260, 26, "", 12)
  keyButton:SetPoint("TOP", card, "TOP", 0, -120)
  ns.PhotoKeyButton(keyButton, function(text, listening)
    keyButton.label:SetText(text)
    UI.SetActive(keyButton, listening)
  end)

  note = UI.Text(card, 11, C.muted)
  note:SetPoint("BOTTOMLEFT", 18, 52)
  note:SetText("Not available in combat. Try again when combat ends.")

  back = UI.Button(card, 80, 26, "Back", 12)
  UI.SetActive(back, false) -- UI.Button has no colours until SetActive
  back:SetPoint("BOTTOMLEFT", 18, 16)
  back:SetScript("OnClick", function() Go(index - 1) end)

  action = UI.Button(card, 150, 26, "", 12)
  action:SetPoint("BOTTOMRIGHT", -18, 16)
  UI.SetActive(action, true)
  action:SetScript("OnClick", function()
    local s = STEPS[index]
    if s.run and not done then
      -- A click in combat would leave the overlay queued to start by itself when combat ends.
      if InCombat() then return Render() end
      -- Not waiting if it was refused (no shot types ticked, text unlocked): the interface never hid.
      waiting = s.run() and true or false
      return
    end
    if index == #STEPS then return Finish() end
    Go(index + 1)
  end)

  skip = UI.Button(card, 110, 26, "", 12)
  skip:SetPoint("RIGHT", action, "LEFT", -8, 0)
  UI.SetActive(skip, false)
  skip:SetScript("OnClick", function()
    local last = index == #STEPS
    Finish()
    if last then ns.ShowOptions() end
  end)

  -- The interface came back after the overlay or a photo: that step is done.
  card:SetScript("OnShow", function()
    HideExit()
    if waiting then
      waiting, done = false, true
    end
    Render()
  end)

  -- Escape closes the tour (counts as skipping it); every other key passes through. Same pattern
  -- as the overlay and photo mode, so Escape there never reaches this card.
  card:EnableKeyboard(true)
  card:SetPropagateKeyboardInput(true)
  card:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      Finish()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  card:RegisterEvent("PLAYER_REGEN_DISABLED")
  card:RegisterEvent("PLAYER_REGEN_ENABLED")
  card:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    Render()
  end)
end

-- /reverie tour and the "Show the tour" button: start from the first step.
function Tour.Start()
  if InCombatLockdown() then
    print(PREFIX .. "The tour can't start during combat. Type /reverie tour when combat ends.")
    return
  end
  Create()
  card:SetPropagateKeyboardInput(true)
  Go(1)
  card:Show()
end

-- At login: start the tour if it hasn't been seen, once combat allows.
local waitFrame
function Tour.Auto()
  if not ns.settings or ns.settings.tourSeen then return end
  if card and card:IsShown() then return end
  if InCombatLockdown() then
    waitFrame = waitFrame or CreateFrame("Frame")
    waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    waitFrame:SetScript("OnEvent", function(self)
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
      Tour.Auto()
    end)
    return
  end
  Tour.Start()
end

function Tour.AutoLater()
  C_Timer.After(AUTO_DELAY, Tour.Auto)
end
