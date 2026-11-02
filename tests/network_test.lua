package.path = './?.lua;./?/init.lua;' .. package.path

local registeredEvents = {}
local sentMessages = {}
local driverNames = { [2] = 'Driver Two' }

ac = {
  StructItem = {
    key = function (key) return key end,
    int32 = function () return 'int32' end,
    boolean = function () return 'boolean' end,
    string = function (length) return 'string:' .. tostring(length) end
  },
  OnlineEvent = function (layout, callback)
    local key = layout[1]
    registeredEvents[key] = { layout = layout, callback = callback }
    return function (message, repeatForNewConnections)
      sentMessages[key] = {
        message = message,
        repeatForNewConnections = repeatForNewConnections
      }
      return true
    end
  end,
  getDriverName = function (carIndex) return driverNames[carIndex] end
}

local calls = {}
local state = {
  onlinePeers = {},
  isControllableFieldFlag = function (flag)
    return flag == 0 or flag == 1 or flag == 2 or flag == 6
  end,
  applyBlueIgnore = function (...)
    calls.blueIgnore = { ... }
  end,
  applyBlueClassRule = function (...)
    calls.blueClassRule = { ... }
  end,
  applyBlueAlert = function (...)
    calls.blueAlert = { ... }
  end,
  applyFieldFlag = function (...)
    calls.fieldFlag = { ... }
  end
}

local network = require('modules/network').create(state)

for _, key in ipairs({
  'blueIgnore.v3',
  'blueClassRule.v1',
  'manualBlueAlert.v1',
  'lobbyPresence.v4',
  'fieldFlag.v6'
}) do
  assert(registeredEvents['app.FlagControlApp.' .. key], 'missing event: ' .. key)
end

local function receive(key, sender, message)
  local event = registeredEvents['app.FlagControlApp.' .. key]
  assert(event, 'missing event: ' .. key)
  event.callback(sender, message)
end

receive('blueIgnore.v3', { index = 2 }, {
  protocol = 3, driverName = 'Driver Two', sessionID = 8, carIndex = 2, ignored = true
})
assert(calls.blueIgnore[1] == 'Driver Two' and calls.blueIgnore[4] == true)

local priorBlueIgnore = calls.blueIgnore
receive('blueIgnore.v3', { index = 2 }, {
  protocol = 2, driverName = 'Driver Two', sessionID = 8, carIndex = 2, ignored = false
})
assert(calls.blueIgnore == priorBlueIgnore, 'unexpected protocol must be ignored')

receive('blueClassRule.v1', { index = 2 }, {
  protocol = 1, className = 'GT3', groupName = 'GT', autoAllowed = false
})
assert(calls.blueClassRule[1] == 'GT3' and calls.blueClassRule[3] == false)

local priorBlueRule = calls.blueClassRule
receive('blueClassRule.v1', { index = 2 }, {
  protocol = 1, className = '', groupName = 'GT', autoAllowed = true
})
assert(calls.blueClassRule == priorBlueRule, 'empty class names must be ignored')

receive('lobbyPresence.v4', { index = 2, sessionID = 8 }, {
  protocol = 4, className = 'GT3', isBlueFlag = true, blueCauseCarIndex = 1
})
assert(state.onlinePeers[8].name == 'Driver Two')
assert(state.onlinePeers[8].className == 'GT3')
assert(state.onlinePeers[8].isBlueFlag == true)

receive('manualBlueAlert.v1', { index = 2 }, {
  protocol = 1, active = true, groupName = 'GT3'
})
assert(calls.blueAlert[1] == true and calls.blueAlert[2] == 'GT3')

receive('fieldFlag.v6', { index = 2 }, {
  protocol = 6, overrideActive = true, flag = 4
})
assert(calls.fieldFlag == nil, 'unsupported field flags must be ignored')

receive('fieldFlag.v6', { index = 2 }, {
  protocol = 6, overrideActive = true, flag = 2
})
assert(calls.fieldFlag[1] == 2 and calls.fieldFlag[2] == true)
assert(calls.fieldFlag[3] == 'Driver Two')

network.sendFlagState({ protocol = 6, overrideActive = true, flag = 2 }, true)
local sent = sentMessages['app.FlagControlApp.fieldFlag.v6']
assert(sent.message.flag == 2 and sent.repeatForNewConnections == true)

print('network tests passed')
