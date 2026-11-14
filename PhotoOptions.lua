-- Options window, Photo tab: shot types, stamp, vignette, frame guide, camera, self-timer, what
-- to hide during the shot, file format and auto-capture, with a preview of each ticked look.
-- Settings are stored now; photo mode uses them in a later update.
local _, ns = ...
local Layout = ns.Layout

local TIMER_NAMES = { [0] = "Off", [3] = "3s", [5] = "5s", [10] = "10s" }
local HIDE = {
  { key = "hidePlates", label = "Hide nameplates", tip = "Hide nameplates during the shot" },
  { key = "hideNames",  label = "Hide player names", tip = "Hide other players' names during the shot" },
  { key = "hideExtras", label = "Hide addon extras", tip = "Hide other addons' on-screen extras, such as waypoint arrows" },
}

local BINDING = "REVERIE_PHOTO" -- from Bindings.xml
local PREFIX = "|cfff2deaeReverie|r: "

local UI
local looks
local previewLook -- the ticked type shown in the preview
local widgets = {
  types = {}, stamp = {}, corners = {}, frames = {}, cameras = {}, timers = {}, hide = {},
  formats = {}, auto = {}, looks = {},
}

local function Photo() return ns.settings.photo end
local function Changed() ns.Refresh() end

local function At(widget, parent, x, y)
  widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

-- A row (or grid, with perRow) of buttons, one per value. Returns buttons keyed by value.
local function Choices(parent, x, y, values, names, width, perRow, onPick)
  local out = {}
  for i, v in ipairs(values) do
    local b = UI.Button(parent, width, 26, names[v], 12)
    local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
    At(b, parent, x + col * (width + 6), y + row * 32)
    b:SetScript("OnClick", function()
      onPick(v)
      Changed()
    end)
    out[v] = b
  end
  return out
end

local function Note(parent, x, y, width, text)
  local fs = UI.Text(parent, 12, UI.C.muted)
  At(fs, parent, x, y)
  fs:SetWidth(width)
  fs:SetSpacing(3)
  fs:SetText(text)
  return fs
end

local function Heading(parent, x, y, label)
  local fs = UI.Heading(parent, label)
  At(fs, parent, x, y)
  return fs
end

-- Left column ---------------------------------------------------------------------------------

local function BuildStamp(col)
  Heading(col, 20, 168, "Stamp")

  -- Everything that only applies when Stamped is ticked lives in one frame, shown or hidden.
  local box = CreateFrame("Frame", nil, col)
  box:SetSize(290, 70)
  At(box, col, 16, 184)
  widgets.stampBox = box
  for i, id in ipairs(Layout.STAMP_ORDER) do
    local cb = UI.Check(box, Layout.STAMP_META[id].label, function(on)
      Photo().stamp[id] = on
      Changed()
    end)
    At(cb, box, ((i - 1) % 2) * 90, math.floor((i - 1) / 2) * 30)
    widgets.stamp[id] = cb
  end

  local cornerLabel = UI.Text(box, 12, UI.C.muted)
  At(cornerLabel, box, 196, -14)
  cornerLabel:SetText("Corner")
  for i, corner in ipairs(Layout.STAMP_CORNERS) do
    local b = UI.Button(box, 26, 26, "")
    At(b, box, 196 + ((i - 1) % 2) * 30, math.floor((i - 1) / 2) * 30)
    -- A small square in the matching corner shows which corner it is.
    local dot = b:CreateTexture(nil, "ARTWORK")
    dot:SetColorTexture(UI.C.gold[1], UI.C.gold[2], UI.C.gold[3], 1)
    dot:SetSize(7, 7)
    dot:SetPoint(({ TL = "TOPLEFT", TR = "TOPRIGHT", BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT" })[corner],
      corner:sub(2, 2) == "L" and 5 or -5, corner:sub(1, 1) == "T" and -5 or 5)
    b:SetScript("OnClick", function()
      Photo().stamp.corner = corner
      Changed()
    end)
    UI.Tooltip(b, Layout.ANCHOR_NAMES[corner])
    widgets.corners[corner] = b
  end

  widgets.stampOff = Note(col, 20, 188, 290, "Tick Stamped above to add a stamp.")
end

-- Turns a button into the "Take photo" key setter, the same binding as Options > Keybindings.
-- Left-click, then press a key to set it; right-click clears it; Escape cancels. Bindings can't
-- change in combat. show(text, listening) draws the button; it redraws itself whenever the
-- bindings change, so every key button (here and in the game's AddOns page) agrees.
function ns.PhotoKeyButton(b, show)
  local listening = false

  local function Refresh()
    local bound = GetBindingKey(BINDING)
    show(listening and "Press a key (Escape cancels)"
      or bound and ("Take photo: " .. GetBindingText(bound)) or "Take photo: not set (click to set)",
      listening)
  end

  local function Listen(on)
    listening = on
    b:EnableKeyboard(on)
    Refresh()
  end

  local function ClearKeys()
    for _, k in ipairs({ GetBindingKey(BINDING) }) do SetBinding(k) end
  end

  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, button)
    if InCombatLockdown() then
      print(PREFIX .. "can't change keys in combat.")
      return
    end
    if button == "RightButton" then
      ClearKeys()
      SaveBindings(GetCurrentBindingSet())
      return Listen(false)
    end
    Listen(not listening)
  end)

  b:SetScript("OnKeyDown", function(_, key)
    if key == "ESCAPE" then return Listen(false) end
    local bind = Layout.BindingKey(key, IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown())
    if not bind then return end -- a modifier on its own; wait for the real key
    if InCombatLockdown() then
      print(PREFIX .. "can't change keys in combat.")
      return Listen(false)
    end
    local old = GetBindingAction(bind)
    ClearKeys()
    if SetBinding(bind, BINDING) then
      SaveBindings(GetCurrentBindingSet())
      if old ~= "" and old ~= BINDING then
        print(PREFIX .. GetBindingText(bind) .. " no longer does " .. (GetBindingName(old) or old) .. ".")
      end
    else
      print(PREFIX .. "couldn't bind " .. GetBindingText(bind) .. ".")
    end
    Listen(false)
  end)

  b:SetScript("OnShow", Refresh)
  b:SetScript("OnHide", function() if listening then Listen(false) end end)
  b:RegisterEvent("UPDATE_BINDINGS")
  b:SetScript("OnEvent", Refresh)
  Refresh()
end

local function BuildKey(col)
  local b = UI.Button(col, 290, 26, "", 12)
  At(b, col, 20, 566)
  UI.Tooltip(b, "Click, then press a key to take photos with it. Right-click to clear.")
  ns.PhotoKeyButton(b, function(text, listening)
    b.label:SetText(text)
    UI.SetActive(b, listening)
  end)
end

local function BuildLeft(page)
  local col = UI.Box(page, UI.C.panel, UI.C.border)
  col:SetPoint("TOPLEFT", 20, -20)
  col:SetPoint("BOTTOMLEFT", 20, 20)
  col:SetWidth(330)

  Heading(col, 20, 18, "Shot types")
  for i, t in ipairs(Layout.PHOTO_TYPES) do
    local cb = UI.Check(col, Layout.PHOTO_TYPE_NAMES[t], function(on)
      Photo().types[t] = on
      Changed()
    end)
    At(cb, col, 16 + ((i - 1) % 2) * 145, 34 + math.floor((i - 1) / 2) * 28)
    widgets.types[t] = cb
  end
  Note(col, 20, 124, 290, "Every ticked type is saved, about a second apart.")

  BuildStamp(col)

  widgets.vignette = UI.Slider(col, 290, function(v)
    Photo().vignette = v
    Changed()
  end)
  At(widgets.vignette, col, 20, 278)

  Heading(col, 20, 316, "Frame")
  widgets.frames = Choices(col, 20, 332, Layout.FRAMES, Layout.FRAME_NAMES, 142, 2, function(v) Photo().frame = v end)
  Note(col, 20, 398, 290, "Guides only, the saved file is always the full screen.")

  Heading(col, 20, 432, "Camera")
  widgets.cameras = Choices(col, 20, 448, Layout.CAMERAS, Layout.CAMERA_NAMES, 68, 4, function(v) Photo().camera = v end)

  Heading(col, 20, 492, "Self-timer")
  widgets.timers = Choices(col, 20, 508, Layout.TIMERS, TIMER_NAMES, 68, 4, function(v) Photo().timer = v end)

  Heading(col, 20, 550, "Key")
  BuildKey(col)
end

-- Right column, under the shared preview ---------------------------------------------------------

local function BuildRight(page)
  local col = CreateFrame("Frame", nil, page)
  col:SetPoint("TOPLEFT", 370, -20)
  col:SetPoint("BOTTOMRIGHT", -20, 20)

  -- One button per ticked type; laid out in RefreshPhotoPage.
  widgets.lookLabel = UI.Text(col, 12, UI.C.muted)
  At(widgets.lookLabel, col, 0, UI.PREVIEW_H + 18)
  widgets.lookLabel:SetText("Preview")
  for _, t in ipairs(Layout.PHOTO_TYPES) do
    local b = UI.Button(col, 92, 26, Layout.PHOTO_TYPE_NAMES[t], 12)
    b:SetScript("OnClick", function()
      previewLook = t
      Changed()
    end)
    b:Hide()
    widgets.looks[t] = b
  end
  widgets.noLook = Note(col, 64, UI.PREVIEW_H + 18, 520, "Tick a shot type to preview it.")

  local groupW = math.floor((UI.PREVIEW_W - 32) / 3)
  local top = UI.PREVIEW_H + 56
  local function Group(i, title)
    local box = UI.Box(col, UI.C.panel, UI.C.border)
    box:SetSize(groupW, 186)
    At(box, col, (i - 1) * (groupW + 16), top)
    Heading(box, 14, 14, title)
    return box
  end

  local during = Group(1, "During the shot")
  for i, h in ipairs(HIDE) do
    local cb = UI.Check(during, h.label, function(on)
      Photo()[h.key] = on
      Changed()
    end)
    At(cb, during, 10, 30 + (i - 1) * 30)
    UI.Tooltip(cb, h.tip)
    widgets.hide[h.key] = cb
  end
  Note(during, 14, 126, groupW - 28, "The camera orbit always pauses for a shot.")

  local file = Group(2, "File")
  widgets.formats = Choices(file, 14, 34, Layout.FORMATS, Layout.FORMAT_NAMES, 70, 2, function(v) Photo().format = v end)
  widgets.quality = UI.Slider(file, groupW - 28, function(v)
    Photo().quality = v
    Changed()
  end, 1, 10)
  At(widgets.quality, file, 14, 104)

  local auto = Group(3, "Take automatically")
  for i, key in ipairs(Layout.AUTO) do
    local cb = UI.Check(auto, Layout.AUTO_NAMES[key], function(on)
      Photo().auto[key] = on
      Changed()
    end)
    At(cb, auto, 10, 30 + (i - 1) * 30)
    widgets.auto[key] = cb
  end
end

-- Called once by Options.lua when the window is first built. photoRoot is the preview's
-- screen-sized frame for the photo looks.
function ns.BuildPhotoPage(page, photoRoot)
  UI = ns.UI
  looks = ns.Looks.New(photoRoot)
  BuildLeft(page)
  BuildRight(page)
end

local function SetChoices(buttons, current)
  for v, b in pairs(buttons) do UI.SetActive(b, v == current) end
end

function ns.RefreshPhotoPage()
  local p = Photo()

  for t, cb in pairs(widgets.types) do cb:SetChecked(p.types[t]) end

  widgets.stampBox:SetShown(p.types.stamped)
  widgets.stampOff:SetShown(not p.types.stamped)
  for id, cb in pairs(widgets.stamp) do cb:SetChecked(p.stamp[id]) end
  SetChoices(widgets.corners, p.stamp.corner)

  UI.SetSlider(widgets.vignette, "Vignette strength", p.vignette)
  SetChoices(widgets.frames, p.frame)
  SetChoices(widgets.cameras, p.camera)
  SetChoices(widgets.timers, p.timer)
  for key, cb in pairs(widgets.hide) do cb:SetChecked(p[key]) end
  SetChoices(widgets.formats, p.format)
  UI.SetSlider(widgets.quality, "Quality", p.quality, "")
  for key, cb in pairs(widgets.auto) do cb:SetChecked(p.auto[key]) end

  -- Preview buttons for the ticked types only; keep the chosen look if it's still ticked.
  local ticked = Layout.TickedTypes(p)
  local stillTicked = false
  for _, t in ipairs(ticked) do
    if t == previewLook then stillTicked = true end
  end
  if not stillTicked then previewLook = ticked[1] end

  for _, b in pairs(widgets.looks) do b:Hide() end
  local prev
  for _, t in ipairs(ticked) do
    local b = widgets.looks[t]
    b:ClearAllPoints()
    if prev then
      b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    else
      b:SetPoint("LEFT", widgets.lookLabel, "RIGHT", 12, 0)
    end
    UI.SetActive(b, t == previewLook)
    b:Show()
    prev = b
  end
  widgets.noLook:SetShown(#ticked == 0)

  looks:Apply(p, previewLook, ns.Looks.Parts(true), true)
end
