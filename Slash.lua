-- /reverie: options, preview, stop, unlock/lock, and per-element text settings.
local _, ns = ...
local Layout = ns.Layout
local state = ns.state

local PREFIX = "|cfff2deaeReverie|r: "

local function TextCommand(args)
  local cmd, err = Layout.ParseTextCommand(args)
  if not cmd then
    print(PREFIX .. err)
    return
  end

  local e = ns.settings.elements[cmd.id]
  local label = Layout.META[cmd.id].label
  if cmd.show ~= nil then
    e.show = cmd.show
    print(PREFIX .. label .. (cmd.show and " shown." or " hidden."))
  elseif cmd.anchor then
    e.anchor, e.free = cmd.anchor, false
    print(PREFIX .. label .. " pinned to " .. Layout.ANCHOR_NAMES[cmd.anchor]:lower() .. ".")
  elseif cmd.free then
    e.free = true
    print(string.format("%s%s placed freely at %d%% across, %d%% down.", PREFIX, label,
      math.floor(e.x * 100 + 0.5), math.floor(e.y * 100 + 0.5)))
  end
  ns.Refresh()
end

SLASH_REVERIE1 = "/reverie"
SlashCmdList.REVERIE = function(msg)
  msg = strtrim(msg or "")
  local sub, rest = msg:match("^(%S*)%s*(.-)$")
  sub = sub:lower()

  if sub == "preview" then
    ns.Preview()
  elseif sub == "stop" then
    state.dismissed = true
    ns.Stop()
  elseif sub == "unlock" then
    ns.Text.Unlock()
  elseif sub == "lock" then
    ns.Text.Lock()
  elseif sub == "text" then
    TextCommand(rest)
  else
    ns.ToggleOptions()
  end
end
