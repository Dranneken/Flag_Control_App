local companionWindowLock = {}

local refreshInterval = 1
local windows = {}
local refreshedAt = -math.huge
local stores = {}
local initialized = {}
local locked = {}
local indicatorUntil = {}

local function refreshWindows()
  windows = {}
  for _, app in ipairs(ac.getAppWindows() or {}) do
    if app and app.name and app.title then
      local ok, window = pcall(ac.accessAppWindow, app.name)
      if ok and window then
        local valid, isValid = pcall(function () return window:valid() end)
        if valid and isValid then
          windows[app.title] = window
        end
      end
    end
  end
  refreshedAt = os.clock()
end

local function getWindow(title)
  if os.clock() - refreshedAt >= refreshInterval then
    refreshWindows()
  end
  return windows[title]
end

local function getStore(key)
  if not stores[key] then
    stores[key] = ac.storage('FlagControlWindowLock_' .. key, 0)
  end
  return stores[key]
end

function companionWindowLock.update(title, key)
  local window = getWindow(title)
  if not window then return end

  local store = getStore(key)
  if not initialized[key] then
    local ok = pcall(function () window:setPinned(store:get() == 1) end)
    if not ok then return end
    initialized[key] = true
    locked[key] = store:get() == 1
  end

  local ok, currentLock = pcall(function () return window:pinned() end)
  if not ok then return end
  locked[key] = currentLock

  if not ui.mouseClicked(ui.MouseButton.Right) then return end
  local mouse = ui.mouseLocalPos()
  local size = ui.windowSize()
  if not mouse or not size or mouse.x < 0 or mouse.y < 0 or
     mouse.x > size.x or mouse.y > size.y then
    return
  end

  local nextLock = not currentLock
  local changed = pcall(function () window:setPinned(nextLock) end)
  if not changed then return end
  locked[key] = nextLock
  store:set(nextLock and 1 or 0)
  indicatorUntil[key] = os.clock() + 1
end

function companionWindowLock.drawStatus(key)
  local untilTime = indicatorUntil[key]
  if not untilTime then return end

  local remaining = untilTime - os.clock()
  if remaining <= 0 then
    indicatorUntil[key] = nil
    return
  end

  local size = ui.windowSize()
  if not size then return end
  local alpha = math.clamp(remaining / 0.65, 0, 1)
  local isLocked = locked[key]
  local label = isLocked and 'LOCKED' or 'UNLOCKED'
  local color = isLocked and rgbm(1, 0.16, 0.12, alpha) or rgbm(0.15, 0.95, 0.30, alpha)
  local width = #label * 7 + 12
  local left = math.max(4, (size.x - width) / 2)
  ui.drawRectFilled(vec2(left, 3), vec2(left + width, 21), rgbm(0, 0, 0, alpha * 0.75))
  ui.drawTextClipped(
    label,
    vec2(left + 6, 5),
    vec2(left + width - 6, 21),
    color,
    vec2(0, 0),
    true
  )
end

return companionWindowLock
