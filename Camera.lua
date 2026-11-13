-- Slow camera orbit and zoom out while the overlay is up.
local _, ns = ...

local Camera = {}
ns.Camera = Camera

local ORBIT_SPEED = 0.02 -- MoveViewLeftStart multiplier: a slow, steady turn
local ZOOM_OUT = 8       -- camera distance added while the overlay is up

local orbiting = false
local zoomStart -- camera distance before zooming out, or nil

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
  if orbiting then
    MoveViewLeftStop()
    orbiting = false
  end
  if zoomStart then
    CameraZoomIn(math.max(0, GetCameraZoom() - zoomStart))
    zoomStart = nil
  end
end
