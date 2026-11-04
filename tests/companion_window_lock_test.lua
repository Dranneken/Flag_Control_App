package.path = './?.lua;./?/init.lua;' .. package.path

local storedValues = {
  FlagControlWindowLock_flag_notice = 1
}
local windows = {}
local clicked = false
local mouse = { x = 20, y = 20 }
local statusDrawn = false

for _, title in ipairs({ 'Flag Notice', 'Penalty Notice' }) do
  local window = { isPinned = false }
  function window:valid() return true end
  function window:setPinned(value) self.isPinned = value end
  function window:pinned() return self.isPinned end
  windows[title] = window
end

ac = {
  getAppWindows = function ()
    return {
      { name = 'flag_notice', title = 'Flag Notice' },
      { name = 'penalty_notice', title = 'Penalty Notice' }
    }
  end,
  accessAppWindow = function (name)
    if name == 'flag_notice' then return windows['Flag Notice'] end
    if name == 'penalty_notice' then return windows['Penalty Notice'] end
  end,
  storage = function (key, defaultValue)
    if storedValues[key] == nil then storedValues[key] = defaultValue end
    return {
      get = function () return storedValues[key] end,
      set = function (_, value) storedValues[key] = value end
    }
  end
}

ui = {
  MouseButton = { Right = 1 },
  mouseClicked = function () return clicked end,
  mouseLocalPos = function () return mouse end,
  windowSize = function () return { x = 300, y = 200 } end,
  drawRectFilled = function () statusDrawn = true end,
  drawTextClipped = function () statusDrawn = true end
}

vec2 = function (x, y) return { x = x, y = y } end
rgbm = function (r, g, b, a) return { r = r, g = g, b = b, a = a } end
math.clamp = function (value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local windowLock = require('modules/companion_window_lock')
windowLock.update('Flag Notice', 'flag_notice')
assert(windows['Flag Notice'].isPinned, 'saved lock state should be restored')

clicked = true
windowLock.update('Flag Notice', 'flag_notice')
assert(not windows['Flag Notice'].isPinned, 'right-click should unlock the window')
assert(storedValues.FlagControlWindowLock_flag_notice == 0,
  'unlocking should persist its state')
windowLock.drawStatus('flag_notice')
assert(statusDrawn, 'lock changes should show the temporary status indicator')

mouse = { x = 301, y = 20 }
windowLock.update('Flag Notice', 'flag_notice')
assert(not windows['Flag Notice'].isPinned,
  'right-clicks outside the window should not change its lock state')

clicked = false
mouse = { x = 20, y = 20 }
windowLock.update('Penalty Notice', 'penalty_notice')
assert(not windows['Penalty Notice'].isPinned,
  'companion windows should maintain separate pin states')
clicked = true
windowLock.update('Flag Notice', 'flag_notice')
assert(windows['Flag Notice'].isPinned, 'right-click should pin the window')
assert(storedValues.FlagControlWindowLock_flag_notice == 1,
  'pinning should persist its state')

print('companion window lock tests passed')
