package.path = './?.lua;./?/init.lua;' .. package.path

rgbm = function (r, g, b, a)
  return { r = r, g = g, b = b, a = a }
end
vec2 = function (x, y) return { x = x, y = y } end

local tabBarName
local tabs = {}
ui = setmetatable({
  StyleColor = { Text = 1, Button = 2 },
  TabBarFlags = { FittingPolicyScroll = 1 },
  tabBar = function (name, _, callback)
    tabBarName = name
    callback()
  end,
  tabItem = function (name, callback)
    tabs[#tabs + 1] = { name = name, draw = callback }
  end,
  availableSpaceX = function () return 300 end,
  button = function () return false end,
  treeNode = function () return false end
}, {
  __index = function ()
    return function () end
  end
})

ac = {
  getDriverName = function () return 'Local Driver' end
}

local fieldFlagsDrawn = false
local blueFlagsDrawn = false
local raceControlUI = require('modules/race_control_ui').create({
  fieldFlags = {
    getFlag = function () fieldFlagsDrawn = true; return 0 end,
    getSenderName = function () return 'Local Driver' end,
    publish = function () end
  },
  blueFlags = {
    collectDriverBlueStates = function ()
      blueFlagsDrawn = true
      return {}, {}
    end
  },
  colors = {
    yellow = {}, settingsText = {}, muted = {}, blue = {},
    ignored = {}, danger = {}, success = {}
  },
  flags = { none = 0, green = 1, yellow = 2, red = 6 },
  onlinePeers = {},
  getLobbyMessageStatus = function () return 'Offline' end,
  getLocalClassName = function () return '' end
})

raceControlUI.drawTabs()
assert(tabBarName == 'FlagControlAdminTabs')
assert(#tabs == 2)
assert(tabs[1].name == 'Field Flags')
assert(tabs[2].name == 'Blue Flags')
tabs[1].draw()
tabs[2].draw()
assert(fieldFlagsDrawn)
assert(blueFlagsDrawn)

print('Race control UI module tests passed')
