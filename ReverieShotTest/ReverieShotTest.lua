-- ReverieShotTest: throwaway spike harness that proves the APIs photo mode needs on the
-- Forever client. NOT part of Reverie. Copy this folder into Interface\AddOns and type /rst.
--
-- Rules every test follows:
--   * every client API call goes through try() (pcall), so a missing or blocked function
--     prints a readable FAIL line instead of raising a Lua error;
--   * every asynchronous callback goes through guard(), which runs restoreAll() if the
--     callback itself errors, so the UI is never left hidden and no overlay stays up;
--   * the cvars test restores every value it changes and reads it back to prove it.
--
-- luacheck: globals SLASH_REVERIESHOTTEST1
-- luacheck: read globals C_CVar DEFAULT_CHAT_FRAME FlipCameraYaw Screenshot SetView debugprofilestop

local PREFIX = "|cff33ff99[RST]|r "

local function out(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end
local function pass(msg) out("|cff00ff00PASS|r " .. msg) end
local function fail(msg) out("|cffff3333FAIL|r " .. msg) end
local function info(msg) out("|cffffff00INFO|r " .. msg) end

-- Milliseconds, as precise as the client allows.
local function now()
  if type(debugprofilestop) == "function" then return debugprofilestop() end
  return GetTime() * 1000
end

local function ms(value) return string.format("%.1f ms", value) end

local function packn(...) return { n = select("#", ...), ... } end

-- Calls fn(...) under pcall. Returns false after printing FAIL when fn is missing or errors,
-- otherwise true followed by fn's return values.
local function try(label, fn, ...)
  if type(fn) ~= "function" then
    fail(label .. ": function missing (" .. type(fn) .. ")")
    return false
  end
  local r = packn(pcall(fn, ...))
  if not r[1] then
    fail(label .. ": " .. tostring(r[2]))
    return false
  end
  return unpack(r, 1, r.n)
end

---------------------------------------------------------------------------------------------
-- Shared state: one test at a time, a watchdog timer, a frame counter, overlay textures.
---------------------------------------------------------------------------------------------

local busy               -- name of the running test, or nil
local onShotEvent        -- current listener for SCREENSHOT_* events, or nil
local watchdogToken = 0  -- bumped to cancel any pending watchdog

local frameTicker = CreateFrame("Frame")  -- no parent, so it keeps ticking while UIParent is hidden

local overlay = CreateFrame("Frame", nil, WorldFrame)
overlay:SetAllPoints(WorldFrame)
overlay:Hide()
local burstTex = overlay:CreateTexture(nil, "ARTWORK")
burstTex:SetAllPoints(overlay)
local blendTex = overlay:CreateTexture(nil, "ARTWORK")
blendTex:SetAllPoints(overlay)

local restoreAll  -- forward declaration

-- Wraps an async callback so an error in it restores everything instead of stranding the UI.
local function guard(label, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      fail(label .. " callback errored: " .. tostring(err))
      restoreAll()
    end
  end
end

local function begin(name)
  if busy then
    fail(name .. ": '" .. busy .. "' is still running, wait for it (or /rst reset)")
    return false
  end
  busy = name
  return true
end

local function arm(seconds, label, fn)
  watchdogToken = watchdogToken + 1
  local mine = watchdogToken
  C_Timer.After(seconds, guard(label, function()
    if mine == watchdogToken then fn() end
  end))
end

local function disarm() watchdogToken = watchdogToken + 1 end

local function afterFrames(count, label, fn)
  local seen = 0
  frameTicker:SetScript("OnUpdate", guard(label, function(self)
    seen = seen + 1
    if seen >= count then
      self:SetScript("OnUpdate", nil)
      fn()
    end
  end))
end

local function cancelFrames() frameTicker:SetScript("OnUpdate", nil) end

-- Colours a texture; SetColorTexture may not exist on older clients, so fall back to SetTexture.
local function colorTexture(tex, r, g, b, a)
  if type(tex.SetColorTexture) == "function" then
    return try("SetColorTexture", tex.SetColorTexture, tex, r, g, b, a)
  end
  info("SetColorTexture missing, falling back to SetTexture(r, g, b, a)")
  return try("SetTexture(r, g, b, a)", tex.SetTexture, tex, r, g, b, a)
end

local function hideOverlays()
  burstTex:Hide()
  blendTex:Hide()
  overlay:Hide()
end

local function hideUI()
  local ok = try("UIParent:Hide()", UIParent.Hide, UIParent)
  if ok and UIParent:IsShown() then
    fail("UIParent:Hide() returned but UIParent is still shown")
    return false
  end
  return ok
end

local function showUI()
  if UIParent:IsShown() then return true end
  try("UIParent:Show()", UIParent.Show, UIParent)
  if UIParent:IsShown() then
    info("UI restored")
    return true
  end
  fail("UI NOT restored - press Alt+Z or /reload")
  return false
end

restoreAll = function()
  disarm()
  cancelFrames()
  onShotEvent = nil
  hideOverlays()
  showUI()
  busy = nil
end

---------------------------------------------------------------------------------------------
-- Screenshot events. Registration is attempted under pcall so an unknown event is a FAIL line.
---------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local registered = {}
for _, event in ipairs({ "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED" }) do
  registered[event] = try("RegisterEvent(" .. event .. ")", events.RegisterEvent, events, event) and true or false
end
events:SetScript("OnEvent", guard("screenshot event", function(_, event)
  local listener = onShotEvent
  onShotEvent = nil
  if listener then
    listener(event)
  else
    info("unsolicited " .. event .. " (late event after a timeout, or a Print Screen press)")
  end
end))

local function reportRegistration()
  for _, event in ipairs({ "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED" }) do
    if registered[event] then pass("event registered: " .. event) else fail("event NOT registered: " .. event) end
  end
end

local function checkCombat(name)
  if InCombatLockdown() then
    fail(name .. ": in combat, refusing (protected UI and CVars may not restore). Try out of combat.")
    return false
  end
  return true
end

---------------------------------------------------------------------------------------------
-- /rst shot
---------------------------------------------------------------------------------------------

local function cmdShot()
  if not begin("shot") then return end
  if not checkCombat("shot") then busy = nil return end
  reportRegistration()

  local tHide, tShot
  local function finish(result)
    disarm()
    cancelFrames()
    onShotEvent = nil
    showUI()
    local elapsed = tShot and ms(now() - tShot) or "n/a"
    if result == "SCREENSHOT_SUCCEEDED" then
      pass("shot: SCREENSHOT_SUCCEEDED fired, " .. elapsed .. " after Screenshot()")
    elseif result == "SCREENSHOT_FAILED" then
      fail("shot: SCREENSHOT_FAILED fired, " .. elapsed .. " after Screenshot()")
    else
      fail("shot: " .. result .. " (elapsed since Screenshot(): " .. elapsed .. ")")
    end
    busy = nil
  end

  arm(5, "shot timeout", function() finish("TIMEOUT - no screenshot event within 5 s of hiding the UI") end)
  tHide = now()
  if not hideUI() then finish("could not hide UIParent") return end

  afterFrames(2, "shot frame wait", function()
    info("shot: two frames passed in " .. ms(now() - tHide) .. ", calling Screenshot()")
    onShotEvent = finish
    tShot = now()
    if not try("Screenshot()", Screenshot) then finish("Screenshot() call failed") end
  end)
end

---------------------------------------------------------------------------------------------
-- /rst burst
---------------------------------------------------------------------------------------------

local BURST = {
  { label = "RED overlay",  color = { 1, 0, 0, 0.35 } },
  { label = "NO overlay" },
  { label = "BLUE overlay", color = { 0, 0.3, 1, 0.35 } },
}

local function cmdBurst()
  if not begin("burst") then return end
  if not checkCombat("burst") then busy = nil return end
  reportRegistration()

  local results = {}
  local tStart = now()

  local function finish(problem)
    disarm()
    cancelFrames()
    onShotEvent = nil
    hideOverlays()
    showUI()
    for i, step in ipairs(BURST) do
      local r = results[i]
      if not r then
        info("burst shot " .. i .. " (" .. step.label .. "): not taken")
      elseif r.event == "SCREENSHOT_SUCCEEDED" then
        pass("burst shot " .. i .. " (" .. step.label .. "): " .. r.event .. " in " .. ms(r.elapsed)
          .. " (gap since previous step " .. ms(r.gap) .. ")")
      else
        fail("burst shot " .. i .. " (" .. step.label .. "): " .. r.event
          .. (r.elapsed and (" after " .. ms(r.elapsed)) or ""))
      end
    end
    if problem then
      fail("burst: stopped - " .. problem .. ", total " .. ms(now() - tStart))
    else
      pass("burst: all " .. #BURST .. " shots succeeded, total " .. ms(now() - tStart)
        .. ". Check the files show red / none / blue in that order.")
    end
    busy = nil
  end

  local function shoot(i, tPrev)
    if i > #BURST then finish() return end
    local step = BURST[i]

    arm(5, "burst timeout", function()
      results[i] = results[i] or { event = "TIMEOUT (no event within 5 s)" }
      finish("shot " .. i .. " timed out")
    end)

    if step.color then
      if not colorTexture(burstTex, unpack(step.color)) then finish("could not colour overlay for shot " .. i) return end
      burstTex:Show()
      overlay:Show()
    else
      burstTex:Hide()
      overlay:Hide()
    end

    afterFrames(2, "burst frame wait", function()
      local tShot = now()
      local gap = tShot - tPrev
      onShotEvent = function(event)
        results[i] = { event = event, elapsed = now() - tShot, gap = gap }
        if event == "SCREENSHOT_SUCCEEDED" then
          shoot(i + 1, now())
        else
          finish("shot " .. i .. " got " .. event)
        end
      end
      if not try("Screenshot() #" .. i, Screenshot) then
        results[i] = { event = "Screenshot() call failed" }
        finish("Screenshot() call failed on shot " .. i)
      end
    end)
  end

  if not hideUI() then finish("could not hide UIParent") return end
  shoot(1, now())
end

---------------------------------------------------------------------------------------------
-- /rst cvars
---------------------------------------------------------------------------------------------

local CVARS = {
  "screenshotFormat", "screenshotQuality",
  "nameplateShowAll", "nameplateShowFriends", "nameplateShowEnemies",
  "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName", "UnitNameNPC",
}

local function testValueFor(name, current)
  if name == "screenshotFormat" then
    return current == "jpeg" and "png" or "jpeg"
  elseif name == "screenshotQuality" then
    return current == "5" and "6" or "5"
  end
  return current == "1" and "0" or "1"
end

local function cmdCvars()
  if not begin("cvars") then return end
  if not checkCombat("cvars") then busy = nil return end

  local api = type(C_CVar) == "table" and C_CVar or nil
  local getFn = api and api.GetCVar
  local setFn = api and api.SetCVar
  local getLabel, setLabel = "C_CVar.GetCVar", "C_CVar.SetCVar"
  if type(getFn) == "function" then
    pass("C_CVar.GetCVar exists")
  else
    fail("C_CVar.GetCVar missing (C_CVar is " .. type(C_CVar) .. "), falling back to global GetCVar")
    getFn, getLabel = GetCVar, "GetCVar"
  end
  if type(setFn) == "function" then
    pass("C_CVar.SetCVar exists")
  else
    fail("C_CVar.SetCVar missing, falling back to global SetCVar")
    setFn, setLabel = SetCVar, "SetCVar"
  end

  local leftChanged = 0
  for _, name in ipairs(CVARS) do
    local okGet, original = try(getLabel .. "(" .. name .. ")", getFn, name)
    if okGet and original == nil then
      fail(name .. ": GetCVar returned nil (CVar does not exist on this client), not touching it")
    elseif okGet then  -- when the read failed, try() has already printed the FAIL line
      original = tostring(original)
      local testValue = testValueFor(name, original)
      local _, setResult = try(setLabel .. "(" .. name .. ", " .. testValue .. ")", setFn, name, testValue)
      local _, readBack = try(getLabel .. "(" .. name .. ")", getFn, name)
      if tostring(readBack) == testValue then
        pass(name .. ": read '" .. original .. "', set '" .. testValue .. "' stuck (set returned "
          .. tostring(setResult) .. ")")
      else
        fail(name .. ": read '" .. original .. "', set '" .. testValue .. "' BLOCKED/IGNORED, reads back '"
          .. tostring(readBack) .. "' (set returned " .. tostring(setResult) .. ")")
      end

      -- Restore, and prove it by reading back. Fall back to the global setter if needed.
      try(setLabel .. "(" .. name .. ", " .. original .. ") restore", setFn, name, original)
      local _, restored = try(getLabel .. "(" .. name .. ") after restore", getFn, name)
      if tostring(restored) ~= original and setFn ~= SetCVar then
        try("SetCVar(" .. name .. ") fallback restore", SetCVar, name, original)
        _, restored = try(getLabel .. "(" .. name .. ") after fallback restore", getFn, name)
      end
      if tostring(restored) == original then
        info(name .. ": restored to '" .. original .. "'")
      else
        leftChanged = leftChanged + 1
        fail(name .. ": NOT RESTORED, now '" .. tostring(restored) .. "'. Fix with: /console " .. name .. " " .. original)
      end
    end
  end

  if leftChanged == 0 then
    pass("cvars: every CVar is back to its original value")
  else
    fail("cvars: " .. leftChanged .. " CVar(s) left changed, see lines above")
  end
  busy = nil
end

---------------------------------------------------------------------------------------------
-- /rst blend
---------------------------------------------------------------------------------------------

local BLEND_STAGES = {
  { label = "MOD warm (judge for Sepia/Saturated)",  mode = "MOD", color = { 1.0, 0.82, 0.58, 1 } },
  { label = "ADD dim orange (judge for Sepia/Saturated)", mode = "ADD", color = { 0.22, 0.10, 0.0, 1 } },
}

local function cmdBlend()
  if not begin("blend") then return end

  local function finish()
    disarm()
    hideOverlays()
    try("SetBlendMode(BLEND) reset", blendTex.SetBlendMode, blendTex, "BLEND")
    info("blend: overlays removed")
    busy = nil
  end

  local function stage(i)
    local s = BLEND_STAGES[i]
    if not s then finish() return end
    blendTex:Hide()
    local okMode = try("SetBlendMode(" .. s.mode .. ")", blendTex.SetBlendMode, blendTex, s.mode)
    local okColor = colorTexture(blendTex, unpack(s.color))
    if okMode then
      local _, readMode = try("GetBlendMode()", blendTex.GetBlendMode, blendTex)
      if readMode == s.mode then
        pass("blend: SetBlendMode(" .. s.mode .. ") accepted, GetBlendMode reads " .. tostring(readMode))
      else
        fail("blend: SetBlendMode(" .. s.mode .. ") but GetBlendMode reads " .. tostring(readMode))
      end
    end
    if okMode and okColor then
      blendTex:Show()
      overlay:Show()
      info("blend " .. i .. "/" .. #BLEND_STAGES .. ": showing " .. s.label .. " for 5 s")
    end
    arm(5, "blend stage", function() stage(i + 1) end)
  end

  stage(1)
end

---------------------------------------------------------------------------------------------
-- /rst cam
---------------------------------------------------------------------------------------------

local function cmdCam()
  if not begin("cam") then return end

  if type(SetView) == "function" then pass("SetView exists") else fail("SetView missing (" .. type(SetView) .. ")") end

  if not try("FlipCameraYaw(180)", FlipCameraYaw, 180) then
    busy = nil
    return
  end
  pass("cam: FlipCameraYaw(180) ran, camera should now face the other way; flipping back in 2 s")

  arm(2, "cam flip back", function()
    if try("FlipCameraYaw(180) back", FlipCameraYaw, 180) then
      pass("cam: FlipCameraYaw(180) back ran, camera should be where it started")
    end
    busy = nil
  end)
end

---------------------------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------------------------

local COMMANDS = { shot = cmdShot, burst = cmdBurst, cvars = cmdCvars, blend = cmdBlend, cam = cmdCam }

SLASH_REVERIESHOTTEST1 = "/rst"
SlashCmdList.REVERIESHOTTEST = function(msg)
  local sub = strtrim(msg or ""):lower()
  if sub == "reset" then
    restoreAll()
    info("reset: UI shown, overlays hidden, timers cancelled")
    return
  end
  local fn = COMMANDS[sub]
  if not fn then
    info("usage: /rst shot | burst | cvars | blend | cam | reset")
    return
  end
  local ok, err = pcall(fn)
  if not ok then
    fail(sub .. " errored: " .. tostring(err))
    restoreAll()
  end
end
