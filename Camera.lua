-- Slow camera orbit and zoom out while the overlay is up, and photo mode's camera presets.
local _, ns = ...

local Camera = {}
ns.Camera = Camera

local ORBIT_SPEED = 0.02 -- MoveViewLeftStart multiplier: a slow, steady turn
local ZOOM_OUT = 8       -- camera distance added while the overlay is up

local orbiting = false
local paused = false -- orbit stopped by Pause, to start again on Resume
local zoomStart      -- camera distance before zooming out, or nil
local preset         -- the applied photo preset: { yaw, zoomFrom }, or nil

function Camera.Begin(o)
  if o.zoom then
    zoomStart = GetCameraZoom()
    CameraZoomOut(ZOOM_OUT)
  end
  if o.orbit then
    MoveViewLeftStart(ORBIT_SPEED)
    orbiting = true
  end
end

function Camera.End()
  paused = false
  if orbiting then
    MoveViewLeftStop()
    orbiting = false
  end
  if zoomStart then
    CameraZoomIn(math.max(0, GetCameraZoom() - zoomStart))
    zoomStart = nil
  end
end

-- Stops the orbit for a photo. Returns true if it was running.
function Camera.Pause()
  if not orbiting then return false end
  MoveViewLeftStop()
  orbiting = false
  paused = true
  return true
end

-- Starts the orbit again if Pause stopped it (and the overlay hasn't ended since).
function Camera.Resume()
  if not paused then return end
  paused = false
  MoveViewLeftStart(ORBIT_SPEED)
  orbiting = true
end

-- p: an entry of Layout.CAMERA_PRESETS. Records what it changes so ClearPreset can undo it.
function Camera.ApplyPreset(p)
  preset = {}
  if p.yaw then
    FlipCameraYaw(p.yaw)
    preset.yaw = p.yaw
  end
  if p.zoom then
    preset.zoomFrom = GetCameraZoom()
    CameraZoomOut(p.zoom)
  end
end

function Camera.ClearPreset()
  if not preset then return end
  local p = preset
  preset = nil
  if p.yaw then FlipCameraYaw(360 - p.yaw) end -- the rest of the turn brings it back round
  if p.zoomFrom then CameraZoomIn(math.max(0, GetCameraZoom() - p.zoomFrom)) end
end
