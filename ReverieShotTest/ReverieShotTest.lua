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
-- luacheck: globals SLASH_REVERIESHOTTEST1 ReverieShotTestLog
-- luacheck: read globals C_CVar DEFAULT_CHAT_FRAME FlipCameraYaw Screenshot SetView debugprofilestop date
-- luacheck: read globals EnumerateFrames

local PREFIX = "|cff33ff99[RST]|r "

-- /chatlog does not record AddMessage output, so every line is also kept here and saved to
-- WTF\Account\<account>\SavedVariables\ReverieShotTest.lua on logout or /reload.
local sessionLog = {}

local function out(msg)
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
  local plain = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  sessionLog[#sessionLog + 1] = date("%H:%M:%S ") .. plain
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= "ReverieShotTest" then return end
  ReverieShotTestLog = sessionLog  -- keep only this session's lines
  self:UnregisterEvent("ADDON_LOADED")
end)
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

local restoreAll           -- forward declaration
local restorePendingCVars  -- forward declaration, defined with the CVar helpers
local restorePendingFrames -- forward declaration, defined with /rst world

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
  if restorePendingCVars then restorePendingCVars() end
  if restorePendingFrames then restorePendingFrames() end
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

local BURST_SPACING = 1.5  -- seconds between one shot's success and the next shot

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
          .. " (gap since previous success " .. ms(r.gap) .. ")")
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
        if event == "SCREENSHOT_SUCCEEDED" and i == #BURST then
          finish()
        elseif event == "SCREENSHOT_SUCCEEDED" then
          -- Screenshot filenames only go down to the second, so shots closer than that overwrite.
          local tDone = now()
          arm(BURST_SPACING, "burst spacing", function() shoot(i + 1, tDone) end)
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
-- CVar helpers shared by /rst cvars and /rst names
---------------------------------------------------------------------------------------------

-- Every CVar that might draw a name, title or nameplate over the world. Ones that do not exist
-- on this client read back nil and are reported, never touched.
local NAME_CVARS = {
  "nameplateShowAll", "nameplateShowEnemies",
  "UnitNameOwn", "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName",
  "UnitNameNPC", "UnitNameFriendlySpecialNPCName", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
  "UnitNameNonCombatCreatureName", "UnitNamePlayerGuild", "UnitNamePlayerPVPTitle",
  "UnitNameFriendlyPetName", "UnitNameEnemyPetName", "UnitNameFriendlyGuardianName",
  "UnitNameEnemyGuardianName", "UnitNameFriendlyTotemName", "UnitNameEnemyTotemName",
}

local CVARS = { "screenshotFormat", "screenshotQuality", "nameplateShowFriends" }
for _, name in ipairs(NAME_CVARS) do CVARS[#CVARS + 1] = name end

local function testValueFor(name, current)
  if name == "screenshotFormat" then
    return current == "jpeg" and "png" or "jpeg"
  elseif name == "screenshotQuality" then
    return current == "5" and "6" or "5"
  end
  return current == "1" and "0" or "1"
end

-- Picks the getter and setter, preferring C_CVar and falling back to the globals.
local function cvarApi()
  local c = type(C_CVar) == "table" and C_CVar or {}
  local api = { get = c.GetCVar, set = c.SetCVar, getLabel = "C_CVar.GetCVar", setLabel = "C_CVar.SetCVar" }
  if type(api.get) ~= "function" then
    fail("C_CVar.GetCVar missing, falling back to global GetCVar")
    api.get, api.getLabel = GetCVar, "GetCVar"
  end
  if type(api.set) ~= "function" then
    fail("C_CVar.SetCVar missing, falling back to global SetCVar")
    api.set, api.setLabel = SetCVar, "SetCVar"
  end
  return api
end

-- Returns the value as a string, or nil (already reported) when unreadable or missing.
local function readCVar(api, name)
  local ok, value = try(api.getLabel .. "(" .. name .. ")", api.get, name)
  if not ok then return nil end
  if value == nil then
    fail(name .. ": does not exist on this client, not touching it")
    return nil
  end
  return tostring(value)
end

-- Sets a value and reads it back. Returns stuck, readBack, setter's return value.
local function setCVar(api, name, value)
  local _, result = try(api.setLabel .. "(" .. name .. ", " .. value .. ")", api.set, name, value)
  local _, readBack = try(api.getLabel .. "(" .. name .. ")", api.get, name)
  return tostring(readBack) == value, tostring(readBack), result
end

-- Restores a value, proves it by reading back, and tries the global setter if that fails.
local function restoreCVar(api, name, original)
  local ok, current = setCVar(api, name, original)
  if not ok and api.set ~= SetCVar then
    try("SetCVar(" .. name .. ") fallback restore", SetCVar, name, original)
    local _, value = try(api.getLabel .. "(" .. name .. ")", api.get, name)
    current = tostring(value)
    ok = current == original
  end
  if not ok then
    fail(name .. ": NOT RESTORED, now '" .. current .. "'. Fix with: /console " .. name .. " " .. original)
  end
  return ok
end

-- CVars /rst names has changed and not yet restored. restoreAll() restores these too, so an
-- error mid-test cannot leave names switched off.
local pendingCVars

restorePendingCVars = function()
  if not pendingCVars then return 0, 0 end
  local pending = pendingCVars
  pendingCVars = nil
  local left = 0
  for _, c in ipairs(pending.list) do
    if not restoreCVar(pending.api, c.name, c.original) then left = left + 1 end
  end
  return left, #pending.list
end

---------------------------------------------------------------------------------------------
-- /rst cvars
---------------------------------------------------------------------------------------------

local function cmdCvars()
  if not begin("cvars") then return end
  if not checkCombat("cvars") then busy = nil return end

  local api = cvarApi()
  info("cvars: using " .. api.getLabel .. " / " .. api.setLabel)

  local leftChanged = 0
  for _, name in ipairs(CVARS) do
    local original = readCVar(api, name)
    if original then
      local testValue = testValueFor(name, original)
      local stuck, readBack, result = setCVar(api, name, testValue)
      if stuck then
        pass(name .. ": read '" .. original .. "', set '" .. testValue .. "' stuck (set returned " .. tostring(result) .. ")")
      else
        fail(name .. ": read '" .. original .. "', set '" .. testValue .. "' BLOCKED/IGNORED, reads back '"
          .. readBack .. "' (set returned " .. tostring(result) .. ")")
      end
      if restoreCVar(api, name, original) then
        info(name .. ": restored to '" .. original .. "'")
      else
        leftChanged = leftChanged + 1
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
-- /rst names: every name CVar off, UI hidden, one screenshot, then everything restored.
-- The file shows whether any name, title or nameplate is still drawn.
---------------------------------------------------------------------------------------------

local function cmdNames()
  if not begin("names") then return end
  if not checkCombat("names") then busy = nil return end

  local api = cvarApi()
  pendingCVars = { api = api, list = {} }
  local tShot

  local function finish(result)
    disarm()
    cancelFrames()
    onShotEvent = nil
    showUI()
    local left, total = restorePendingCVars()
    if result == "SCREENSHOT_SUCCEEDED" then
      pass("names: SCREENSHOT_SUCCEEDED " .. ms(now() - tShot) .. " after Screenshot(). Check the file for leftover names.")
    else
      fail("names: " .. tostring(result))
    end
    if left == 0 then
      pass("names: all " .. total .. " changed CVar(s) restored")
    else
      fail("names: " .. left .. " CVar(s) left changed, see lines above")
    end
    busy = nil
  end

  for _, name in ipairs(NAME_CVARS) do
    local original = readCVar(api, name)
    if original == "0" then
      info(name .. ": already '0'")
    elseif original then
      -- Recorded before setting, so even a half-applied set gets restored.
      local list = pendingCVars.list
      list[#list + 1] = { name = name, original = original }
      local stuck, readBack = setCVar(api, name, "0")
      if stuck then
        pass(name .. ": '" .. original .. "' -> '0'")
      else
        fail(name .. ": set to '0' BLOCKED/IGNORED, reads back '" .. readBack .. "'")
      end
    end
  end

  arm(5, "names timeout", function() finish("TIMEOUT - no screenshot event within 5 s of hiding the UI") end)
  if not hideUI() then finish("could not hide UIParent") return end

  -- A few extra frames so the name changes are drawn before the capture.
  afterFrames(5, "names frame wait", function()
    onShotEvent = finish
    tShot = now()
    if not try("Screenshot()", Screenshot) then finish("Screenshot() call failed") end
  end)
end

---------------------------------------------------------------------------------------------
-- /rst world: finds frames that stay visible with UIParent hidden (WorldFrame children and
-- parentless frames, e.g. waypoint arrows), hides them for one shot, then shows them again.
-- Nameplates are listed but left alone; the name CVars handle those.
---------------------------------------------------------------------------------------------

local OWN_FRAMES = { [frameTicker] = true, [overlay] = true, [events] = true, [loader] = true }

local pendingFrames  -- { { frame = f, label = s }, ... } hidden by /rst world, not yet shown again

restorePendingFrames = function()
  if not pendingFrames then return 0, 0 end
  local list = pendingFrames
  pendingFrames = nil
  local left = 0
  for _, entry in ipairs(list) do
    try("Show " .. entry.label, entry.frame.Show, entry.frame)
    local ok, shown = pcall(entry.frame.IsShown, entry.frame)
    if not (ok and shown) then
      left = left + 1
      fail(entry.label .. ": NOT shown again - /reload to fix")
    end
  end
  return left, #list
end

local function frameName(frame)
  local ok, name = pcall(frame.GetName, frame)
  return (ok and name) or nil
end

local function describe(frame)
  local okT, kind = pcall(frame.GetObjectType, frame)
  local okP, protected = pcall(frame.IsProtected, frame)
  local okW, w = pcall(frame.GetWidth, frame)
  local okH, h = pcall(frame.GetHeight, frame)
  return string.format("%s [%s%s, %.0fx%.0f]", frameName(frame) or "<anonymous>", okT and kind or "?",
    (okP and protected) and ", PROTECTED" or "", okW and w or 0, okH and h or 0)
end

local function hasArea(frame)
  local okW, w = pcall(frame.GetWidth, frame)
  local okH, h = pcall(frame.GetHeight, frame)
  return okW and okH and w * h > 0
end

local function isNamePlate(frame)
  local name = frameName(frame)
  return name ~= nil and name:find("^NamePlate") ~= nil
end

local function cmdWorld()
  if not begin("world") then return end
  if not checkCombat("world") then busy = nil return end

  local targets = {}  -- { frame = f, label = s }
  local seen = {}

  -- 1. Direct children of WorldFrame.
  local kids = packn(pcall(WorldFrame.GetChildren, WorldFrame))
  if not kids[1] then
    fail("WorldFrame:GetChildren(): " .. tostring(kids[2]))
  else
    local hiddenCount, plateCount = 0, 0
    for i = 2, kids.n do
      local kid = kids[i]
      seen[kid] = true
      local okS, shown = pcall(kid.IsShown, kid)
      if OWN_FRAMES[kid] then  -- luacheck: ignore 542
        -- our own overlay, never hidden
      elseif isNamePlate(kid) then
        plateCount = plateCount + 1
      elseif okS and shown then
        targets[#targets + 1] = { frame = kid, label = "WorldFrame child " .. describe(kid) }
      else
        hiddenCount = hiddenCount + 1
      end
    end
    info("world: WorldFrame has " .. (kids.n - 1) .. " children: " .. #targets .. " shown, "
      .. hiddenCount .. " already hidden, " .. plateCount .. " nameplates (left to the CVars)")
  end

  local tShot
  local function finish(result)
    disarm()
    cancelFrames()
    onShotEvent = nil
    local left, total = restorePendingFrames()
    showUI()
    if result == "SCREENSHOT_SUCCEEDED" then
      pass("world: SCREENSHOT_SUCCEEDED " .. ms(now() - tShot) .. " after Screenshot(). Check the file for arrows.")
    else
      fail("world: " .. tostring(result))
    end
    if left == 0 then
      pass("world: all " .. total .. " hidden frame(s) shown again")
    else
      fail("world: " .. left .. " frame(s) not shown again, see lines above")
    end
    busy = nil
  end

  arm(5, "world timeout", function() finish("TIMEOUT - no screenshot event within 5 s of hiding the UI") end)
  if not hideUI() then finish("could not hide UIParent") return end

  -- 2. Parentless frames that are still drawn now UIParent is hidden.
  local parentless = 0
  local function scan()
    local frame = EnumerateFrames()
    while frame do
      local okCheck, isTarget = pcall(function()
        return not OWN_FRAMES[frame] and not seen[frame] and frame ~= WorldFrame and frame ~= UIParent
          and frame:GetParent() == nil and frame:IsVisible() and hasArea(frame)
      end)
      if okCheck and isTarget then
        parentless = parentless + 1
        targets[#targets + 1] = { frame = frame, label = "parentless " .. describe(frame) }
      end
      frame = EnumerateFrames(frame)
    end
  end
  if try("EnumerateFrames scan", scan) then
    info("world: " .. parentless .. " parentless frame(s) still visible with UIParent hidden")
  end

  -- 3. Hide every target. Each is recorded before hiding so restore covers partial failures.
  pendingFrames = {}
  for _, target in ipairs(targets) do
    pendingFrames[#pendingFrames + 1] = target
    try("Hide " .. target.label, target.frame.Hide, target.frame)
    local ok, shown = pcall(target.frame.IsShown, target.frame)
    if ok and not shown then
      pass("hid " .. target.label)
    else
      fail("could not hide " .. target.label)
    end
  end

  afterFrames(5, "world frame wait", function()
    onShotEvent = finish
    tShot = now()
    if not try("Screenshot()", Screenshot) then finish("Screenshot() call failed") end
  end)
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

local COMMANDS = { shot = cmdShot, burst = cmdBurst, cvars = cmdCvars, names = cmdNames, world = cmdWorld,
  blend = cmdBlend, cam = cmdCam }

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
    info("usage: /rst shot | burst | cvars | names | world | blend | cam | reset")
    return
  end
  local ok, err = pcall(fn)
  if not ok then
    fail(sub .. " errored: " .. tostring(err))
    restoreAll()
  end
end
