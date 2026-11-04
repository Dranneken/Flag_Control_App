package.path = './?.lua;./?/init.lua;' .. package.path

rgbm = function (r, g, b, a)
  return { r = r, g = g, b = b, a = a }
end
vec2 = function (x, y) return { x = x, y = y } end

local tabBarName
local tabs = {}
local columnCalls = 0
local treeNodeCalls = 0
local visibleText = {}
local buttonLabels = {}
local clickedButton
local activeFieldFlag = 0
local publishedFlags = {}
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
  columns = function () columnCalls = columnCalls + 1 end,
  text = function (value) visibleText[#visibleText + 1] = value end,
  textColored = function (value) visibleText[#visibleText + 1] = value end,
  textWrapped = function (value) visibleText[#visibleText + 1] = value end,
  availableSpaceX = function () return 300 end,
  button = function (label)
    buttonLabels[#buttonLabels + 1] = label
    if clickedButton == label then
      clickedButton = nil
      return true
    end
    return false
  end,
  treeNode = function (label)
    treeNodeCalls = treeNodeCalls + 1
    return label ~= nil
  end
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
    getFlag = function () fieldFlagsDrawn = true; return activeFieldFlag end,
    getSenderName = function () return 'Local Driver' end,
    publish = function (flag)
      publishedFlags[#publishedFlags + 1] = flag
      activeFieldFlag = flag
    end
  },
  blueFlags = {
    collectDriverBlueStates = function ()
      blueFlagsDrawn = true
      return {}, {
        {
          key = '11:0',
          racePosition = 1,
          isLocal = true,
          name = 'Local Driver',
          className = 'GT3',
          carName = 'Test Car',
          isIgnored = false,
          isUnderBlue = false,
          sessionID = 11,
          carIndex = 0
        }
      }
    end,
    classKey = function (className) return className:lower() end,
    isBlueAlertActive = function () return false end,
    publishAlert = function () end
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
assert(buttonLabels[#buttonLabels] == 'DEPLOY FLAG')
clickedButton = 'DEPLOY FLAG'
tabs[1].draw()
assert(activeFieldFlag == 2, 'deploy should publish the selected flag')

clickedButton = 'RED FLAG'
tabs[1].draw()
assert(buttonLabels[#buttonLabels] == 'REDEPLOY FLAG',
  'selecting a different flag while deployed should offer redeploy')

clickedButton = 'REDEPLOY FLAG'
tabs[1].draw()
assert(activeFieldFlag == 6, 'redeploy should publish the new flag directly')
assert(publishedFlags[1] == 2 and publishedFlags[2] == 6,
  'redeploy should not publish an intermediate no-flag state')
tabs[1].draw()
assert(buttonLabels[#buttonLabels] == 'UNDEPLOY FLAG',
  'the selected active flag should still offer undeploy')

visibleText = {}
tabs[2].draw()
assert(fieldFlagsDrawn)
assert(blueFlagsDrawn)
assert(columnCalls == 0, 'race-control tab content must not change the outer panel columns')
assert(treeNodeCalls == 0, 'Blue Flags sections must not use collapsing tree nodes')
local allDriversHeadingVisible = false
local manualAlertHeadingVisible = false
for _, value in ipairs(visibleText) do
  if value == 'ALL SESSION DRIVERS (1)' then allDriversHeadingVisible = true end
  if value == 'MANUAL BLUE ALERT & CLASS OPTIONS' then manualAlertHeadingVisible = true end
end
assert(allDriversHeadingVisible, 'all session drivers section should always be visible')
assert(manualAlertHeadingVisible, 'manual blue alert section should always be visible')

print('Race control UI module tests passed')
