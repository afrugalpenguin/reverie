std = "lua51"
max_line_length = 140
exclude_files = { "tests/" }

globals = {
  "ReverieDB", "SLASH_REVERIE1", "SlashCmdList", "UISpecialFrames",
  "BINDING_HEADER_REVERIE", "BINDING_NAME_REVERIE_PHOTO",
}

read_globals = {
  "CameraZoomIn", "CameraZoomOut", "CreateColor", "CreateFrame", "C_CVar", "C_Timer", "EnumerateFrames",
  "ChatTypeInfo", "FlipCameraYaw", "GetCursorPosition", "hooksecurefunc", "Screenshot", "time",
  "GameTooltip", "GameTooltip_Hide", "GetCameraZoom", "GetCVar", "SetCVar", "GetGuildInfo", "GetRealmName", "GetUnitName",
  "GetSubZoneText", "GetTime", "GetZoneText", "HideUIPanel", "InCombatLockdown",
  "InterfaceOptionsFrame", "InterfaceOptions_AddCategory", "IsFlying", "LEVEL",
  "MoveViewLeftStart", "MoveViewLeftStop", "Settings", "SettingsPanel", "UIParent",
  "UnitClass", "UnitIsAFK", "UnitLevel", "UnitName", "UnitOnTaxi", "UnitRace",
  "WorldFrame", "date", "strtrim",
}
