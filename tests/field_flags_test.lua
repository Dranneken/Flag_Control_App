package.path = './?.lua;./?/init.lua;' .. package.path

local adminUnlocked = true
local sent
local overrideState = {}
local network = {
  sendFlagState = function (message, repeatForNewConnections)
    sent = { message = message, repeatForNewConnections = repeatForNewConnections }
  end
}

local fieldFlags = require('modules/field_flags').create({
  flagNone = 0,
  flagGreen = 1,
  flagYellow = 2,
  flagRed = 6,
  isAdminUnlocked = function () return adminUnlocked end,
  setOverrideState = function (key, value) overrideState[key] = value end,
  network = function () return network end
})

assert(fieldFlags.getFlag() == 0)
assert(fieldFlags.getSenderName() == 'No flag update received')
assert(fieldFlags.getRevision() == 0)
assert(fieldFlags.isControllableFieldFlag(0))
assert(fieldFlags.isControllableFieldFlag(1))
assert(fieldFlags.isControllableFieldFlag(2))
assert(fieldFlags.isControllableFieldFlag(6))
assert(not fieldFlags.isControllableFieldFlag(4))

fieldFlags.publish(2)
assert(fieldFlags.getFlag() == 2 and fieldFlags.getSenderName() == 'You')
assert(fieldFlags.getRevision() == 1)
assert(overrideState.active == true and overrideState.flag == 2)
assert(sent.message.flag == 2 and sent.message.overrideActive == true)
assert(sent.repeatForNewConnections == true)

sent = nil
fieldFlags.publish(4)
assert(sent == nil, 'unsupported field flags must not be published')

adminUnlocked = false
fieldFlags.publish(6)
assert(sent == nil, 'locked users must not publish field flags')

fieldFlags.apply(1, true, 'Other Admin')
assert(fieldFlags.getFlag() == 1 and fieldFlags.getSenderName() == 'Other Admin')
assert(fieldFlags.getRevision() == 2)
assert(overrideState.active == true and overrideState.flag == 1)

fieldFlags.apply(0, false, nil)
assert(fieldFlags.getFlag() == 0 and fieldFlags.getSenderName() == 'Lobby member')
assert(fieldFlags.getRevision() == 3)
assert(overrideState.active == false and overrideState.flag == 0)

print('field flag tests passed')
