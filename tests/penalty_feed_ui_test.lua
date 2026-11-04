package.path = './?.lua;./?/init.lua;' .. package.path

local issued
local selectedTab = 'Issue Penalty'
local tabNames = {}
local color = {}

rgbm = function (r, g, b, a) return { r = r, g = g, b = b, a = a } end
vec2 = function (x, y) return { x = x, y = y } end

ui = {
  StyleColor = { Text = 1 },
  TabBarFlags = { FittingPolicyScroll = 0 },
  header = function () end,
  setNextTextBold = function () end,
  pushStyleColor = function () end,
  popStyleColor = function () end,
  text = function () end,
  textWrapped = function () end,
  textColored = function () end,
  separator = function () end,
  tabBar = function (_, _, callback) callback() end,
  tabItem = function (label, callback)
    tabNames[#tabNames + 1] = label
    if label == selectedTab then callback() end
  end,
  combo = function (_, _, callback) callback() end,
  selectable = function () return false end,
  availableSpaceX = function () return 300 end,
  setNextItemWidth = function () end,
  inputText = function (label, value)
    if label == '##penalty_cause' then return 'Track limits' end
    if label == '##penalty_details' then return 'Repeated violation' end
    return value
  end,
  button = function (label) return label == 'ISSUE PENALTY' end,
  sameLine = function () end
}

local uiModule = require('modules/penalty_feed_ui')
local feed = uiModule.create({
  penalties = {
    getPolicy = function ()
      return {
        mode = 'manual',
        penaltyType = 'time',
        amount = 5,
        delayValue = 10,
        delayUnit = 'seconds'
      }
    end,
    getRecords = function () return {} end,
    issue = function (input)
      issued = input
      return { driverName = input.driverName }
    end
  },
  isAdminUnlocked = function () return true end,
  getDrivers = function ()
    return { { name = 'Driver One', sessionID = 11, carIndex = 2, racePosition = 3 } }
  end,
  getLocalDriverName = function () return 'Race Control' end,
  colors = {
    yellow = color,
    settingsText = color,
    muted = color,
    danger = color,
    success = color
  }
})

feed.draw()
assert(issued and issued.driverName == 'Driver One')
assert(issued.type == 'warning' and issued.source == 'manual_incident')
assert(issued.cause == 'Track limits' and issued.details == 'Repeated violation')
assert(#tabNames == 3 and tabNames[1] == 'Feed' and
  tabNames[2] == 'Issue Penalty' and tabNames[3] == 'Policies')
selectedTab = 'Policies'
tabNames = {}
feed.draw()
assert(#tabNames == 3)

print('penalty feed UI tests passed')
