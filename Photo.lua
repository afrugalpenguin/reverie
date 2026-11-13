-- Photo mode. Layout.PhotoPlan turns the Photo tab's settings into a list of steps; this file runs
-- them one at a time. Every game call goes through try() and every callback through guard(), and
-- one Cleanup() undoes whatever the plan changed, in the order Layout.CleanupOrder gives. Cleanup
-- runs on success, failure, timeout, Escape, entering combat and logout.
local _, ns = ...
local Layout = ns.Layout
local state = ns.state

local Photo = {}
ns.Photo = Photo

local PREFIX = "|cfff2deaeReverie|r: "
local TOAST_TIME = 3        -- seconds the toast stays before fading
local SPACING_MARGIN = 0.1  -- seconds after the clock's second changes, before the next shot
-- Shot spacing fallback: nil waits for the clock's next second after each shot (filenames only go
-- down to the second). If shots ever overwrite each other, set a fixed wait in seconds instead
-- (the spike used 1.5).
local FIXED_SPACING = nil

local run    -- the running sequence, or nil. Every pending callback checks it's still current.
local root, looks, hintBar, hint, countdown, toast, toastFade
local ticker = CreateFrame("Frame") -- parentless, so it keeps ticking while UIParent is hidden
local events = CreateFrame("Frame")
local own = { [ticker] = true, [events] = true } -- Reverie frames "hide extras" never touches

local function Say(msg) print(PREFIX .. msg) end

-- Calls fn under pcall. Returns ok, and the error text when it failed or fn is missing.
local function try(fn, ...)
  if type(fn) ~= "function" then return false, "function missing" end
  local ok, err = pcall(fn, ...)
  return ok, (not ok) and tostring(err) or nil
end

local Cleanup -- forward declaration

-- Wraps a callback so an error in it ends the sequence and restores everything.
local function guard(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      Say("photo error: " .. tostring(err))
      Cleanup("something went wrong")
    end
  end
end

-- Runs fn after `seconds`, unless the sequence that scheduled it has ended.
local function Later(seconds, fn)
  local r = run
  C_Timer.After(seconds, guard(function()
    if run and run == r then fn() end
  end))
end

-- Runs fn after `count` frames have been drawn.
local function AfterFrames(count, fn)
  local r, seen = run, 0
  ticker:SetScript("OnUpdate", guard(function(self)
    seen = seen + 1
    if seen < count then return end
    self:SetScript("OnUpdate", nil)
    if run and run == r then fn() end
  end))
end

-- Runs fn once the clock's whole second has moved on from `second`.
local function AfterSecond(second, fn)
  local r = run
  ticker:SetScript("OnUpdate", guard(function(self)
    if not Layout.NewSecond(second, time()) then return end
    self:SetScript("OnUpdate", nil)
    if run and run == r then fn() end
  end))
end

-- Frames ----------------------------------------------------------------------------------------

-- Same units as UIParent, so looks and text match the overlay's size at any UI scale.
local function FitToUI(f)
  local worldScale = WorldFrame:GetEffectiveScale()
  f:SetScale(UIParent:GetEffectiveScale() / (worldScale > 0 and worldScale or 1))
end

local function Create()
  if root then return end

  -- WorldFrame children, so they stay up while UIParent is hidden.
  root = CreateFrame("Frame", "ReveriePhoto", WorldFrame)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetAllPoints(WorldFrame)
  root:Hide()
  own[root] = true

  -- Escape cancels; every other key passes through.
  root:EnableKeyboard(true)
  root:SetPropagateKeyboardInput(true)
  root:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" and run then
      self:SetPropagateKeyboardInput(false)
      Cleanup("cancelled")
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  looks = ns.Looks.New(root)

  hintBar = root:CreateTexture(nil, "OVERLAY", nil, 3)
  hintBar:SetColorTexture(0, 0, 0, 0.6)
  hintBar:SetPoint("TOPLEFT")
  hintBar:SetPoint("TOPRIGHT")
  hintBar:SetHeight(34)
  hint = root:CreateFontString(nil, "OVERLAY")
  hint:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
  hint:SetTextColor(0.95, 0.87, 0.68, 1)
  hint:SetPoint("CENTER", hintBar, "CENTER")

  countdown = root:CreateFontString(nil, "OVERLAY")
  countdown:SetFont("Fonts\\MORPHEUS.TTF", 96, "OUTLINE")
  countdown:SetTextColor(1, 0.96, 0.86, 1)
  countdown:SetPoint("CENTER")

  -- The toast only appears after everything is restored, and is hidden as soon as a photo starts,
  -- so it can never end up in a shot.
  toast = CreateFrame("Frame", "ReveriePhotoToast", WorldFrame)
  toast:SetFrameStrata("FULLSCREEN_DIALOG")
  toast:SetSize(420, 40)
  toast:SetPoint("TOP", WorldFrame, "TOP", 0, -90)
  toast:Hide()
  own[toast] = true
  local bg = toast:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0.055, 0.047, 0.071, 0.9)
  bg:SetAllPoints()
  toast.text = toast:CreateFontString(nil, "OVERLAY")
  toast.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
  toast.text:SetTextColor(0.95, 0.87, 0.68, 1)
  toast.text:SetPoint("CENTER")
  toastFade = toast:CreateAnimationGroup()
  local alpha = toastFade:CreateAnimation("Alpha")
  alpha:SetFromAlpha(1)
  alpha:SetToAlpha(0)
  alpha:SetDuration(0.6)
  alpha:SetStartDelay(TOAST_TIME)
  toastFade:SetScript("OnFinished", function() toast:Hide() end)
end

local function HideToast()
  if not toast then return end
  toastFade:Stop()
  toast:Hide()
end

local function ShowToast(text)
  FitToUI(toast)
  toastFade:Stop()
  toast.text:SetText(text)
  toast:SetWidth(math.max(240, toast.text:GetStringWidth() + 48))
  toast:SetAlpha(1)
  toast:Show()
  toastFade:Play()
end

-- Other addons' extras ----------------------------------------------------------------------------

local function FrameName(f)
  local ok, name = pcall(f.GetName, f)
  return ok and name or nil
end

local function IsOurs(f)
  if own[f] then return true end
  if ns.Text.live and f == ns.Text.live.frame then return true end
  local name = FrameName(f)
  return name ~= nil and name:find("^Reverie") ~= nil
end

local function HasArea(f)
  local okW, w = pcall(f.GetWidth, f)
  local okH, h = pcall(f.GetHeight, f)
  return okW and okH and w * h > 0
end

-- With UIParent hidden, hides what other addons still draw: shown WorldFrame children and visible
-- parentless frames (waypoint arrows and the like). Never Reverie's frames, never nameplates.
-- Each frame is recorded before it's hidden so cleanup shows it again even after an error.
local function HideExtras(r)
  local seen = {}
  local function consider(f, parentless)
    if seen[f] then return end
    seen[f] = true
    local okCheck, isTarget = pcall(function()
      if IsOurs(f) or f == WorldFrame or f == UIParent then return false end
      local name = FrameName(f)
      if name and name:find("^NamePlate") then return false end -- left to the CVars
      if parentless then
        return f:GetParent() == nil and f:IsVisible() and HasArea(f)
      end
      return f:IsShown()
    end)
    if okCheck and isTarget then
      r.hiddenFrames[#r.hiddenFrames + 1] = f
      try(f.Hide, f)
    end
  end

  local kids = { pcall(WorldFrame.GetChildren, WorldFrame) }
  if kids[1] then
    for i = 2, #kids do consider(kids[i], false) end
  end

  if type(EnumerateFrames) == "function" then
    pcall(function()
      local f = EnumerateFrames()
      while f do
        consider(f, true)
        f = EnumerateFrames(f)
      end
    end)
  end
end

-- Cleanup ---------------------------------------------------------------------------------------

local UNDO = {
  cvars = function(r)
    local failed = ns.CVars.Restore("photoNames")
    if #failed > 0 then r.problems[#r.problems + 1] = "couldn't restore " .. table.concat(failed, ", ") end
  end,
  frames = function(r)
    for _, f in ipairs(r.hiddenFrames) do try(f.Show, f) end
  end,
  camera = function() ns.Camera.ClearPreset() end,
  fileFormat = function(r)
    local failed = ns.CVars.Restore("photoFile")
    if #failed > 0 then r.problems[#r.problems + 1] = "couldn't restore " .. table.concat(failed, ", ") end
  end,
  overlay = function(r)
    -- Only if the cinematic overlay is still meant to be up.
    if r.hidOverlay and state.active and ns.Text.live then ns.Text.live.frame:Show() end
  end,
  ui = function(r)
    if not r.hidUI then return end
    if InCombatLockdown() then
      state.showUIAfterCombat = true
    else
      UIParent:Show()
    end
  end,
  orbit = function(r)
    if r.pausedOrbit then ns.Camera.Resume() end
  end,
}

-- Ends the sequence: restores everything in CleanupOrder, then shows the toast.
-- reason: nil on success, otherwise what stopped it.
Cleanup = function(reason)
  local r = run
  if not r then return end
  run = nil -- every pending callback now does nothing
  ticker:SetScript("OnUpdate", nil)

  looks:Apply(r.photo, nil, r.parts, false)
  hintBar:Hide()
  hint:Hide()
  countdown:Hide()
  root:Hide()

  for _, key in ipairs(r.cleanup) do
    if r.done[key] then
      local ok, err = try(UNDO[key], r)
      if not ok then r.problems[#r.problems + 1] = key .. ": " .. err end
    end
  end
  state.photo = false

  for _, problem in ipairs(r.problems) do Say(problem .. ". It will be tried again at your next login.") end
  ShowToast(Layout.ToastText({ saved = r.saved, total = r.total, reason = reason, trigger = r.trigger }))

  -- An automatic shot may have queued up while this one ran.
  if ns.Auto then C_Timer.After(0.5, ns.Auto.Drain) end
end

-- Steps -------------------------------------------------------------------------------------------

local Next -- forward declaration

local STEPS = {
  pauseOrbit = function(r)
    r.done.orbit = true
    local ok, wasRunning = pcall(ns.Camera.Pause)
    r.pausedOrbit = ok and wasRunning
    Next()
  end,

  settle = function(_, step) Later(step.seconds, Next) end,

  hideUI = function(r)
    r.done.ui = true
    if UIParent:IsShown() then
      r.hidUI = true
      try(UIParent.Hide, UIParent)
      if UIParent:IsShown() then return Cleanup("couldn't hide the interface") end
    end
    Next()
  end,

  hideOverlay = function(r)
    r.done.overlay = true
    local live = ns.Text.live
    if live and live.frame:IsShown() then
      r.hidOverlay = true
      live.frame:Hide()
    end
    Next()
  end,

  fileFormat = function(r)
    r.done.fileFormat = true
    ns.CVars.Set("photoFile", "screenshotFormat", r.photo.format)
    ns.CVars.Set("photoFile", "screenshotQuality", tostring(r.photo.quality))
    Next()
  end,

  camera = function(r, step)
    r.done.camera = true
    local ok, err = try(ns.Camera.ApplyPreset, Layout.CAMERA_PRESETS[step.preset])
    if not ok then Say("camera preset failed: " .. err) end
    Next()
  end,

  extras = function(r)
    r.done.frames = true
    HideExtras(r)
    Next()
  end,

  cvars = function(r)
    r.done.cvars = true
    for _, name in ipairs(Layout.PhotoCVars(r.photo)) do ns.CVars.Set("photoNames", name, "0") end
    Next()
  end,

  waitFrames = function(_, step) AfterFrames(step.frames, Next) end,

  guides = function(r)
    looks:Apply(r.photo, nil, r.parts, true)
    hint:SetText(string.format("Frame your shot: %d %s. Escape cancels.", r.total, r.total == 1 and "shot" or "shots"))
    hintBar:Show()
    hint:Show()
    Next()
  end,

  countdown = function(_, step)
    local left = step.seconds
    local function tick()
      if left <= 0 then
        countdown:Hide()
        return Next()
      end
      countdown:SetText(tostring(left))
      countdown:Show()
      left = left - 1
      Later(1, tick)
    end
    tick()
  end,

  hideGuides = function(r)
    looks:Apply(r.photo, nil, r.parts, false)
    hintBar:Hide()
    hint:Hide()
    countdown:Hide()
    Next()
  end,

  look = function(r, step)
    looks:Apply(r.photo, step.type, r.parts, false)
    Next()
  end,

  shoot = function(r, step)
    r.shotId = r.shotId + 1
    local id = r.shotId
    r.waiting = function(event)
      r.waiting = nil
      if event == "SCREENSHOT_SUCCEEDED" then
        r.saved = r.saved + 1
        r.lastSecond = time()
        Next()
      else
        Cleanup("the game couldn't save the " .. Layout.PHOTO_TYPE_NAMES[step.type]:lower() .. " shot")
      end
    end
    Later(Layout.SHOT_TIMEOUT, function()
      if r.waiting and r.shotId == id then Cleanup("no screenshot event") end
    end)
    local ok, err = try(Screenshot)
    if not ok then Cleanup("Screenshot() failed: " .. err) end
  end,

  clearLook = function(r)
    looks:Apply(r.photo, nil, r.parts, false)
    Next()
  end,

  space = function(r)
    if FIXED_SPACING then
      Later(FIXED_SPACING, Next)
    else
      AfterSecond(r.lastSecond, function() Later(SPACING_MARGIN, Next) end)
    end
  end,

  finish = function() Cleanup(nil) end,
}

Next = function()
  local r = run
  if not r then return end
  r.i = r.i + 1
  local step = r.steps[r.i]
  if not step then return Cleanup(nil) end
  STEPS[step.op](r, step)
end

events:RegisterEvent("SCREENSHOT_SUCCEEDED")
events:RegisterEvent("SCREENSHOT_FAILED")
events:SetScript("OnEvent", guard(function(_, event)
  local r = run
  if r and r.waiting then r.waiting(event) end
end))

-- Public ------------------------------------------------------------------------------------------

function Photo.IsRunning() return run ~= nil end

-- /reverie photo and the key binding, and automatic shots.
-- opts (automatic shots only): { trigger = toast name, afterSecond = the plain screenshot's
-- clock second, so the first clean shot can't overwrite it }.
function Photo.Take(opts)
  if run then return end -- a second press while a photo is in progress does nothing
  if InCombatLockdown() then
    Say("can't take a photo in combat.")
    return
  end
  if state.unlocked then
    Say("can't take a photo while the text is unlocked. /reverie lock first.")
    return
  end
  if not ns.settings then return end

  local photo = ns.settings.photo
  local steps, err = Layout.PhotoPlan(photo, opts and { auto = true } or nil)
  if not steps then
    Say(err)
    return
  end

  Create()
  HideToast()
  FitToUI(root)
  root:SetPropagateKeyboardInput(true)
  root:Show()

  run = {
    photo = photo,
    parts = ns.Looks.Parts(false),
    steps = steps,
    cleanup = Layout.CleanupOrder(steps),
    total = #Layout.TickedTypes(photo),
    trigger = opts and opts.trigger,
    lastSecond = opts and opts.afterSecond,
    i = 0, saved = 0, shotId = 0,
    done = {}, hiddenFrames = {}, problems = {},
  }
  state.photo = true

  -- Watchdog: however the sequence gets stuck, everything comes back.
  Later((opts and 0 or photo.timer) + run.total * (Layout.SHOT_TIMEOUT + 2) + 10, function() Cleanup("took too long") end)

  guard(Next)()
end

-- Stops a running photo and restores everything (entering combat, logout).
function Photo.Abort(reason)
  if run then Cleanup(reason) end
end
