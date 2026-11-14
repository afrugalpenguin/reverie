-- Options window: a Text tab (show, anchor or free-position each text element) and a Photo tab
-- (PhotoOptions.lua), sharing one live preview.
local _, ns = ...
local Layout = ns.Layout

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"

local C = {
  bg        = { 0.055, 0.047, 0.071, 0.97 }, -- #0e0c12
  panel     = { 0.090, 0.078, 0.114, 1 },    -- #17141d
  inner     = { 0.114, 0.102, 0.141, 1 },    -- #1d1a24
  border    = { 0.180, 0.165, 0.220, 1 },    -- #2e2a38
  control   = { 0.133, 0.118, 0.165, 1 },    -- #221e2a
  controlBd = { 0.227, 0.208, 0.275, 1 },    -- #3a3546
  rowSel    = { 0.165, 0.141, 0.200, 1 },    -- #2a2433
  gold      = { 0.878, 0.722, 0.376, 1 },    -- #e0b860
  goldFill  = { 0.227, 0.184, 0.102, 1 },    -- #3a2f1a
  dot       = { 0.353, 0.329, 0.400, 1 },    -- #5a5466
  text      = { 0.925, 0.910, 0.949, 1 },    -- #ece8f2
  muted     = { 0.639, 0.624, 0.690, 1 },    -- #a39fb0
  title     = { 0.949, 0.871, 0.682, 1 },    -- #f2deae
  onGold    = { 0.102, 0.078, 0.031, 1 },    -- #1a1408
  none      = { 0, 0, 0, 0 },
}

local PREVIEW_W, PREVIEW_H = 600, 338
local SCREEN_W, SCREEN_H = 1365, 768 -- a 16:9 screen in UI units, scaled into the preview
local TAB_H = 40                     -- height of the tab bar above both pages

local frame, renderer, textRoot, photoRoot
local selected = "name"
local activeTab = "text"
local tabs, pages = {}, {}
local widgets = { rows = {}, anchors = {}, options = {} }

-- Helpers ---------------------------------------------------------------

local function Box(parent, bg, border)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(unpack(bg))
  f:SetBackdropBorderColor(unpack(border))
  return f
end

local function Text(parent, size, color, font)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(font or BODY_FONT, size, "")
  fs:SetTextColor(unpack(color))
  fs:SetJustifyH("LEFT")
  return fs
end

local function Heading(parent, label)
  local fs = Text(parent, 10, C.muted)
  fs:SetText(string.upper(label))
  return fs
end

local function Button(parent, w, h, label, size)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  b.label = Text(b, size or 12, C.text)
  b.label:SetPoint("CENTER")
  b.label:SetText(label or "")
  b:SetHighlightTexture(WHITE)
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
  return b
end

local function SetActive(b, active)
  b:SetBackdropColor(unpack(active and C.goldFill or C.control))
  b:SetBackdropBorderColor(unpack(active and C.gold or C.controlBd))
end

local function Tooltip(b, text)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
end

local function Check(parent, label, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  local fs = Text(parent, 13, C.text)
  fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  fs:SetText(label)
  -- Clicking the label toggles the box too.
  cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 8), 0, 0)
  cb.label = fs
  cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
  return cb
end

-- lo, hi: the value range (0 to 100 when omitted).
local function Slider(parent, width, onChange, lo, hi)
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(width, 18)
  s:SetMinMaxValues(lo or 0, hi or 100)
  s:SetValueStep(1)
  s:SetObeyStepOnDrag(true)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(unpack(C.controlBd))
  track:SetHeight(4)
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  s:SetThumbTexture(WHITE)
  local thumb = s:GetThumbTexture()
  thumb:SetSize(10, 18)
  thumb:SetVertexColor(unpack(C.gold))
  s.label = Text(parent, 12, C.muted)
  s.label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
  s:SetScript("OnValueChanged", function(self, value)
    if not self.updating then onChange(math.floor(value + 0.5)) end
  end)
  return s
end

-- suffix: shown after the value ("%" when omitted).
local function SetSlider(s, label, value, suffix)
  s.updating = true
  s:SetValue(value)
  s.updating = false
  s.label:SetText(label .. " " .. value .. (suffix or "%"))
end

local function Changed()
  ns.Refresh()
end

-- Shared with the Photo tab so both pages look the same.
ns.UI = {
  C = C, Box = Box, Text = Text, Heading = Heading, Button = Button, SetActive = SetActive,
  Tooltip = Tooltip, Check = Check, Slider = Slider, SetSlider = SetSlider,
  TITLE_FONT = TITLE_FONT, WHITE = WHITE, PREVIEW_W = PREVIEW_W, PREVIEW_H = PREVIEW_H,
}

-- Refresh ---------------------------------------------------------------

function ns.RefreshOptions()
  if not frame or not frame:IsShown() then return end

  for key, page in pairs(pages) do
    page:SetShown(key == activeTab)
    SetActive(tabs[key], key == activeTab)
  end
  textRoot:SetShown(activeTab == "text")
  photoRoot:SetShown(activeTab == "photo")
  if activeTab == "photo" then
    ns.RefreshPhotoPage()
    return
  end

  local els = ns.settings.elements
  local sel = els[selected]

  for _, id in ipairs(Layout.ORDER) do
    local row, e = widgets.rows[id], els[id]
    row.check:SetChecked(e.show)
    row.pos.label:SetText(e.free and "Free" or Layout.ANCHOR_NAMES[e.anchor])
    SetActive(row.pos, false)
    if id == selected then
      row:SetBackdropColor(unpack(C.rowSel))
      row:SetBackdropBorderColor(unpack(C.gold))
    else
      row:SetBackdropColor(unpack(C.none))
      row:SetBackdropBorderColor(unpack(C.none))
    end
  end

  widgets.selLabel:SetText("Position: |cfff2deae" .. Layout.META[selected].label .. "|r")
  for anchor, b in pairs(widgets.anchors) do
    local active = not sel.free and sel.anchor == anchor
    SetActive(b, active)
    b.dot:SetVertexColor(unpack(active and C.gold or C.dot))
  end

  SetActive(widgets.free, sel.free)
  widgets.sliderX:SetShown(sel.free)
  widgets.sliderX.label:SetShown(sel.free)
  widgets.sliderY:SetShown(sel.free)
  widgets.sliderY.label:SetShown(sel.free)
  widgets.hint:SetShown(not sel.free)
  -- Positions are saved as fractions of the screen; the sliders show them as percentages.
  SetSlider(widgets.sliderX, "Across", math.floor(sel.x * 100 + 0.5))
  SetSlider(widgets.sliderY, "Down", math.floor(sel.y * 100 + 0.5))

  for key, cb in pairs(widgets.options) do
    cb:SetChecked(ns.settings.options[key])
  end

  renderer:Apply(ns.settings, ns.Texts(true), selected)
end

-- Build -----------------------------------------------------------------

local function BuildLeft(parent)
  local col = Box(parent, C.panel, C.border)
  col:SetPoint("TOPLEFT", 20, -20)
  col:SetPoint("BOTTOMLEFT", 20, 20)
  col:SetWidth(330)

  local title = Text(col, 24, C.title, TITLE_FONT)
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText("Reverie")
  local sub = Text(col, 12, C.muted)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  sub:SetText("Options")

  local heading = Heading(col, "Text elements")
  heading:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20)

  local prev = heading
  for _, id in ipairs(Layout.ORDER) do
    local row = Box(col, C.none, C.none)
    row:SetSize(290, 36)
    row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", prev == heading and -6 or 0, prev == heading and -8 or -2)

    row.check = Check(row, Layout.META[id].label, function(on)
      ns.settings.elements[id].show = on
      Changed()
    end)
    row.check:SetPoint("LEFT", 4, 0)

    row.pos = Button(row, 104, 28, "")
    row.pos:SetPoint("RIGHT", -4, 0)
    row.pos:SetScript("OnClick", function()
      selected = id
      Changed()
    end)
    Tooltip(row.pos, "Position " .. Layout.META[id].label)

    widgets.rows[id] = row
    prev = row
  end

  local box = Box(col, C.inner, C.border)
  box:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -16)
  box:SetSize(290, 196)

  widgets.selLabel = Text(box, 13, C.muted)
  widgets.selLabel:SetPoint("TOPLEFT", 14, -14)

  local grid = CreateFrame("Frame", nil, box)
  grid:SetSize(128, 128)
  grid:SetPoint("TOPLEFT", widgets.selLabel, "BOTTOMLEFT", 0, -12)
  for i, anchor in ipairs(Layout.ANCHORS) do
    local b = Button(grid, 40, 40, "")
    local col_, row_ = (i - 1) % 3, math.floor((i - 1) / 3)
    b:SetPoint("TOPLEFT", col_ * 44, -row_ * 44)
    b.dot = b:CreateTexture(nil, "ARTWORK")
    b.dot:SetTexture(WHITE)
    b.dot:SetSize(10, 10)
    b.dot:SetPoint("CENTER")
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(b.dot)
    b.dot:AddMaskTexture(mask)
    b:SetScript("OnClick", function()
      local e = ns.settings.elements[selected]
      e.anchor, e.free = anchor, false
      Changed()
    end)
    Tooltip(b, Layout.ANCHOR_NAMES[anchor])
    widgets.anchors[anchor] = b
  end

  widgets.free = Button(box, 120, 40, "Free position", 13)
  widgets.free:SetPoint("TOPLEFT", grid, "TOPRIGHT", 16, 0)
  widgets.free:SetScript("OnClick", function()
    local e = ns.settings.elements[selected]
    e.free = not e.free
    Changed()
  end)

  local function setPos(key)
    return function(v)
      ns.settings.elements[selected][key] = v / 100
      Changed()
    end
  end
  widgets.sliderX = Slider(box, 120, setPos("x"))
  widgets.sliderX:SetPoint("TOPLEFT", widgets.free, "BOTTOMLEFT", 0, -28)
  widgets.sliderY = Slider(box, 120, setPos("y"))
  widgets.sliderY:SetPoint("TOPLEFT", widgets.sliderX, "BOTTOMLEFT", 0, -28)

  widgets.hint = Text(box, 12, C.muted)
  widgets.hint:SetPoint("TOPLEFT", widgets.free, "BOTTOMLEFT", 0, -12)
  widgets.hint:SetWidth(120)
  widgets.hint:SetSpacing(3)
  widgets.hint:SetText("Elements sharing a corner stack in list order.")
end

-- Preview, shared by both tabs: a dusk sky with the overlay (Text tab) or the photo looks
-- (Photo tab) drawn at screen scale, shrunk to fit.
local function BuildPreview(parent)
  local preview = CreateFrame("Frame", nil, parent)
  preview:SetSize(PREVIEW_W, PREVIEW_H)
  preview:SetPoint("TOPLEFT", 370, -(20 + TAB_H))
  preview:SetClipsChildren(true)
  local sky = preview:CreateTexture(nil, "BACKGROUND")
  sky:SetAllPoints()
  sky:SetTexture(WHITE)
  sky:SetGradient("VERTICAL", CreateColor(0.965, 0.718, 0.392, 1), CreateColor(0.165, 0.094, 0.188, 1))
  local ground = preview:CreateTexture(nil, "BORDER")
  ground:SetColorTexture(0.078, 0.051, 0.078, 1)
  ground:SetPoint("BOTTOMLEFT")
  ground:SetPoint("BOTTOMRIGHT")
  ground:SetHeight(math.floor(PREVIEW_H * 0.17))

  local function ScreenRoot()
    local root = CreateFrame("Frame", nil, preview)
    root:SetSize(SCREEN_W, SCREEN_H)
    root:SetScale(PREVIEW_W / SCREEN_W)
    root:SetPoint("TOPLEFT")
    return root
  end
  textRoot = ScreenRoot()
  renderer = ns.Overlay.New(textRoot)
  photoRoot = ScreenRoot()
  photoRoot:Hide()
  return preview
end

local function BuildRight(parent, preview)
  local col = CreateFrame("Frame", nil, parent)
  col:SetPoint("TOPLEFT", 370, -20)
  col:SetPoint("BOTTOMRIGHT", -20, 20)

  -- Three option groups.
  local groupW = math.floor((PREVIEW_W - 32) / 3)
  for i, group in ipairs(Layout.OPTION_GROUPS) do
    local box = Box(col, C.panel, C.border)
    box:SetSize(groupW, 176)
    box:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", (i - 1) * (groupW + 16), -20)
    local heading = Heading(box, group.title)
    heading:SetPoint("TOPLEFT", 14, -14)
    for j, key in ipairs(group.keys) do
      local cb = Check(box, group.labels[j], function(on)
        ns.settings.options[key] = on
        Changed()
      end)
      cb:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", -4, -6 - (j - 1) * 34)
      widgets.options[key] = cb
    end
  end

  local previewBtn = Button(col, 150, 44, "Preview in game", 14)
  previewBtn:SetPoint("BOTTOMRIGHT")
  previewBtn:SetBackdropColor(unpack(C.gold))
  previewBtn:SetBackdropBorderColor(unpack(C.gold))
  previewBtn.label:SetTextColor(unpack(C.onGold))
  previewBtn:SetScript("OnClick", function() ns.Preview() end)
  Tooltip(previewBtn, "Press Escape to leave the preview")

  local resetBtn = Button(col, 160, 44, "Reset to defaults", 14)
  resetBtn:SetPoint("RIGHT", previewBtn, "LEFT", -12, 0)
  resetBtn:SetBackdropColor(unpack(C.none))
  resetBtn:SetBackdropBorderColor(unpack(C.controlBd))
  resetBtn:SetScript("OnClick", function()
    selected = "name"
    ns.ResetSettings()
  end)
end

local function Build()
  frame = Box(UIParent, C.bg, C.border)
  frame:SetSize(990, 640 + TAB_H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:Hide()
  frame:SetScript("OnShow", ns.RefreshOptions)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  -- Escape closes the window like other UI panels.
  _G.ReverieOptionsFrame = frame
  table.insert(UISpecialFrames, "ReverieOptionsFrame")

  -- Tabs, each with a page below the tab bar.
  for i, key in ipairs({ "text", "photo" }) do
    local tab = Button(frame, 110, 28, key == "text" and "Text" or "Photo", 13)
    tab:SetPoint("TOPLEFT", 20 + (i - 1) * 118, -14)
    tab:SetScript("OnClick", function()
      activeTab = key
      ns.RefreshOptions()
    end)
    tabs[key] = tab

    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", 0, -TAB_H)
    page:SetPoint("BOTTOMRIGHT")
    page:Hide()
    pages[key] = page
  end

  local preview = BuildPreview(frame)
  BuildLeft(pages.text)
  BuildRight(pages.text, preview)
  ns.BuildPhotoPage(pages.photo, photoRoot)
end

function ns.ShowOptions()
  if not frame then Build() end
  frame:Show()
end

function ns.ToggleOptions()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    ns.ShowOptions()
  end
end

-- A small page in the game's own options that opens the window above.
function ns.RegisterSettingsCategory()
  local function CloseGameOptions()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
  end

  local panel = CreateFrame("Frame")
  panel.name = "Reverie"
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Reverie")
  local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  open:SetSize(200, 26)
  open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
  open:SetText("Open Reverie options")
  open:SetScript("OnClick", function()
    CloseGameOptions()
    ns.ShowOptions()
  end)

  -- The photo key, so it can be set here without opening the window.
  local key = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  key:SetSize(260, 26)
  key:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -12)
  local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("LEFT", key, "RIGHT", 10, 0)
  hint:SetText("Click, then press a key. Right-click to clear.")
  ns.PhotoKeyButton(key, function(text) key:SetText(text) end)

  local tour = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  tour:SetSize(200, 26)
  tour:SetPoint("TOPLEFT", key, "BOTTOMLEFT", 0, -12)
  tour:SetText("Show the tour")
  tour:SetScript("OnClick", function()
    -- In combat the tour refuses to start, so leave the game's options open.
    if InCombatLockdown() then return ns.Tour.Start() end
    CloseGameOptions()
    ns.Tour.Start()
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Reverie")
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end
