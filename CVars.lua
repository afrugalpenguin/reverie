-- Game settings (CVars) Reverie changes for a while and must put back. Each change records the
-- original in ReverieDB.restore[owner] before the change is made, so if the game crashes or
-- reloads midway, the next login restores it. Every restore is confirmed by reading it back.
local _, ns = ...

local CVars = {}
ns.CVars = CVars

-- Owners, in the order a login repair restores them.
CVars.OWNERS = { "photoNames", "photoFile", "overlay" }

local function Api()
  local c = type(C_CVar) == "table" and C_CVar or {}
  local get = type(c.GetCVar) == "function" and c.GetCVar or GetCVar
  local set = type(c.SetCVar) == "function" and c.SetCVar or SetCVar
  return get, set
end

-- The CVar's value as a string, or nil if it doesn't exist on this client.
function CVars.Get(name)
  local get = Api()
  local ok, value = pcall(get, name)
  if ok and value ~= nil then return tostring(value) end
  return nil
end

-- Sets a value and reads it back; tries the global SetCVar if C_CVar's didn't stick.
local function Put(name, value)
  local _, set = Api()
  pcall(set, name, value)
  if CVars.Get(name) ~= value and set ~= SetCVar and type(SetCVar) == "function" then
    pcall(SetCVar, name, value)
  end
  return CVars.Get(name) == value
end

local function Store(owner, create)
  local db = ns.settings
  if not db then return nil end
  if type(db.restore) ~= "table" then
    if not create then return nil end
    db.restore = {}
  end
  if type(db.restore[owner]) ~= "table" then
    if not create then return nil end
    db.restore[owner] = {}
  end
  return db.restore[owner]
end

-- Changes name to value on behalf of owner. Returns true when it has that value, false when the
-- change didn't stick (it's put straight back), nil when the CVar doesn't exist on this client.
function CVars.Set(owner, name, value)
  local current = CVars.Get(name)
  if current == nil then return nil end
  if current == value then return true end

  local store = Store(owner, true)
  if store[name] == nil then store[name] = current end -- a repeat change keeps the first original
  if Put(name, value) then return true end

  Put(name, store[name])
  store[name] = nil
  return false
end

-- Puts back everything owner changed. Returns the names that couldn't be restored; those stay
-- recorded and are tried again at the next login.
function CVars.Restore(owner)
  local store = Store(owner, false)
  if not store then return {} end
  local failed = {}
  for name, original in pairs(store) do
    if Put(name, original) then
      store[name] = nil
    else
      failed[#failed + 1] = name
    end
  end
  local db = ns.settings
  if next(store) == nil then db.restore[owner] = nil end
  if next(db.restore) == nil then db.restore = nil end
  return failed
end

-- Restores every owner (login repair and logout). Returns how many CVars were recorded and the
-- names that still couldn't be restored.
function CVars.RestoreAll()
  local db = ns.settings
  if not db or type(db.restore) ~= "table" then return 0, {} end

  local owners, seen = {}, {}
  for _, owner in ipairs(CVars.OWNERS) do
    owners[#owners + 1] = owner
    seen[owner] = true
  end
  for owner in pairs(db.restore) do
    if not seen[owner] then owners[#owners + 1] = owner end
  end

  local count, failed = 0, {}
  for _, owner in ipairs(owners) do
    local store = Store(owner, false)
    if store then
      for _ in pairs(store) do count = count + 1 end
      for _, name in ipairs(CVars.Restore(owner)) do failed[#failed + 1] = name end
    end
  end
  return count, failed
end
