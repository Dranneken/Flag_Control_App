package.path = './?.lua;./?/init.lua;' .. package.path

local registeredEvents = {}
local sentMessages = {}
local sentMessageCounts = {}
local driverNames = { [2] = 'Driver Two' }
local adminUnlocked = true
local currentFieldFlag = 6
local currentTime = 10
local originalClock = os.clock
os.clock = function () return currentTime end

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
      sentMessageCounts[key] = (sentMessageCounts[key] or 0) + 1
      return true
    end
  end,
  getDriverName = function (carIndex) return driverNames[carIndex] end
}

local function eventPayloadSize(layout)
  local size = 0
  for index, value in pairs(layout) do
    if index ~= 1 and type(value) == 'string' then
      if value == 'int32' then
        size = size + 4
      elseif value == 'boolean' then
        size = size + 1
      else
        local stringLength = value:match('^string:(%d+)$')
        if stringLength then size = size + tonumber(stringLength) end
      end
    end
  end
  return size
end

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
  applyPenaltyEvent = function (...)
    calls.penalty = { ... }
  end,
  getPenaltyRecords = function ()
    return {
      {
        id = '8:10:1', type = 'time', status = 'issued', source = 'collision',
        driverName = 'Driver Two', driverSessionID = 8, carIndex = 2,
        cause = 'Contact', details = 'Avoidable', issuer = 'Admin',
        issuerSessionID = 4, amount = 5, serveWithinLaps = 0,
        createdAt = 10, revision = 1, autoAfterDelay = false,
        delayValue = 0, delayUnit = 'seconds', dueAt = 0, dueLap = 0
      }
    }
  end,
  applyFieldFlag = function (...)
    calls.fieldFlag = { ... }
  end,
  isAdminUnlocked = function () return adminUnlocked end,
  getCurrentFieldFlag = function () return currentFieldFlag end,
  flagNone = 0
}

local network = require('modules/network').create(state)

for _, key in ipairs({
  'blueIgnore.v3',
  'blueClassRule.v1',
  'manualBlueAlert.v1',
  'lobbyPresence.v4',
  'fieldFlag.v6',
  'fieldFlagSyncRequest.v1',
  'penaltyFeedMeta.v1',
  'penaltyFeedText.v1'
}) do
  assert(registeredEvents['app.FlagControlApp.' .. key], 'missing event: ' .. key)
end
assert(eventPayloadSize(registeredEvents['app.FlagControlApp.penaltyFeedMeta.v1'].layout) <= 175)
assert(eventPayloadSize(registeredEvents['app.FlagControlApp.penaltyFeedText.v1'].layout) <= 175)

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
local firstPresenceSync = sentMessages['app.FlagControlApp.fieldFlag.v6']
assert(firstPresenceSync.message.flag == 6 and firstPresenceSync.message.overrideActive, 'new peers must receive the current flag snapshot')

local firstPresenceSyncCount = sentMessageCounts['app.FlagControlApp.fieldFlag.v6']
currentTime = currentTime + 2
receive('lobbyPresence.v4', { index = 2, sessionID = 8 }, {
  protocol = 4, className = 'GT3', isBlueFlag = true, blueCauseCarIndex = 1
})
assert(sentMessageCounts['app.FlagControlApp.fieldFlag.v6'] == firstPresenceSyncCount, 'regular presence heartbeats must not rebroadcast field state')

receive('manualBlueAlert.v1', { index = 2 }, {
  protocol = 1, active = true, groupName = 'GT3'
})
assert(calls.blueAlert[1] == true and calls.blueAlert[2] == 'GT3')

receive('penaltyFeedMeta.v1', { index = 2, sessionID = 8 }, {
  protocol = 1, action = 1, id = '8:10:1', penaltyType = 2,
  status = 3, source = 2, driverSessionID = 8, carIndex = 2,
  issuerSessionID = 4, amount = 5, serveWithinLaps = 0,
  createdAt = 10, revision = 1, autoAfterDelay = false,
  delayValue = 0, delayUnit = 1, dueAt = 0, dueLap = 0
})
receive('penaltyFeedText.v1', { index = 2, sessionID = 8 }, {
  protocol = 1, id = '8:10:1', field = 1, text = 'Driver Two'
})
receive('penaltyFeedText.v1', { index = 2, sessionID = 8 }, {
  protocol = 1, id = '8:10:1', field = 2, text = 'Contact'
})
receive('penaltyFeedText.v1', { index = 2, sessionID = 8 }, {
  protocol = 1, id = '8:10:1', field = 3, text = 'Avoidable'
})
receive('penaltyFeedText.v1', { index = 2, sessionID = 8 }, {
  protocol = 1, id = '8:10:1', field = 4, text = 'Admin'
})
assert(calls.penalty[1].id == '8:10:1' and calls.penalty[1].type == 'time')
assert(calls.penalty[1].cause == 'Contact' and calls.penalty[1].issuer == 'Admin')

network.sendPenaltyRecord(state.getPenaltyRecords()[1], true)
local penaltyMessage = sentMessages['app.FlagControlApp.penaltyFeedMeta.v1']
assert(penaltyMessage.message.action == 1)
assert(penaltyMessage.message.penaltyType == 2)
assert(penaltyMessage.repeatForNewConnections == true)
assert(sentMessages['app.FlagControlApp.penaltyFeedText.v1'].message.field == 4)

network.requestPenaltySync()
local penaltySyncRequest = sentMessages['app.FlagControlApp.penaltyFeedMeta.v1']
assert(penaltySyncRequest.message.action == 2)

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

network.requestFieldFlagSync()
local request = sentMessages['app.FlagControlApp.fieldFlagSyncRequest.v1']
assert(request.message.protocol == 1)

currentTime = currentTime + 4
receive('fieldFlagSyncRequest.v1', { index = 2, sessionID = 8 }, { protocol = 1 })
local synchronized = sentMessages['app.FlagControlApp.fieldFlag.v6']
assert(synchronized.message.flag == 6 and synchronized.message.overrideActive)
assert(synchronized.repeatForNewConnections == true)

local sentMetaBeforePenaltySnapshot = sentMessageCounts['app.FlagControlApp.penaltyFeedMeta.v1']
local sentTextBeforePenaltySnapshot = sentMessageCounts['app.FlagControlApp.penaltyFeedText.v1']
receive('penaltyFeedMeta.v1', { index = 2, sessionID = 10 }, {
  protocol = 1, action = 2
})
assert(sentMessageCounts['app.FlagControlApp.penaltyFeedMeta.v1'] ==
  sentMetaBeforePenaltySnapshot + 1, 'penalty snapshot must include metadata')
assert(sentMessageCounts['app.FlagControlApp.penaltyFeedText.v1'] ==
  sentTextBeforePenaltySnapshot + 4, 'penalty snapshot must include all text fields')

local sentFlagCount = sentMessageCounts['app.FlagControlApp.fieldFlag.v6']
receive('fieldFlagSyncRequest.v1', { index = 2, sessionID = 8 }, { protocol = 1 })
assert(sentMessageCounts['app.FlagControlApp.fieldFlag.v6'] == sentFlagCount, 'repeated sync requests must be throttled')

currentFieldFlag = 2
currentTime = currentTime + 4
receive('lobbyPresence.v4', { index = 2, sessionID = 8 }, {
  protocol = 4, className = 'GT3', isBlueFlag = true, blueCauseCarIndex = 1
})
local reconnectSync = sentMessages['app.FlagControlApp.fieldFlag.v6']
assert(reconnectSync.message.flag == 2, 'presence after a missed heartbeat must refresh the current flag snapshot')

adminUnlocked = false
currentTime = currentTime + 10
receive('fieldFlagSyncRequest.v1', { index = 2, sessionID = 9 }, { protocol = 1 })
assert(sentMessages['app.FlagControlApp.fieldFlag.v6'] == reconnectSync)

adminUnlocked = true
currentFieldFlag = 0
currentTime = currentTime + 10
receive('fieldFlagSyncRequest.v1', { index = 2, sessionID = 8 }, { protocol = 1 })
local cleared = sentMessages['app.FlagControlApp.fieldFlag.v6']
assert(cleared.message.flag == 0 and not cleared.message.overrideActive, 'no active flag must be synchronized to clear stale state')

os.clock = originalClock

print('network tests passed')
