package.path = './?.lua;./?/init.lua;' .. package.path

local stored = {}
local cars = {
  [0] = {
    sessionID = 5, isConnected = true, isActive = true, racePosition = 1,
    sessionLapCount = 2, drivenInRace = 2000, speedMs = 0,
    name = function () return 'Car Zero' end,
    id = function () return 'car_zero' end,
    driverName = function () return 'Local Driver' end
  },
  [1] = {
    sessionID = 9, isConnected = true, isActive = true, racePosition = 2,
    sessionLapCount = 2, drivenInRace = 2100, speedMs = 0,
    name = function () return 'Car One' end,
    id = function () return 'car_one' end,
    driverName = function () return 'Other Driver' end
  }
}
local sim = {
  carsCount = 2,
  trackLengthM = 1000,
  raceFlagType = 0,
  raceSessionType = 2
}
ac = {
  storage = function (key, defaultValue)
    if stored[key] == nil then stored[key] = defaultValue end
    return {
      get = function () return stored[key] end,
      set = function (_, value) stored[key] = value end
    }
  end,
  getDriverName = function (index)
    return index == 0 and 'Local Driver' or 'Other Driver'
  end,
  getCar = function (index) return cars[index] end,
  getSim = function () return sim end,
  FlagType = { None = 0, FasterCar = 1 },
  SessionType = { Race = 2 }
}

physics = {
  lastOverride = nil,
  overrideRacingFlag = function (flag) physics.lastOverride = flag end
}

local adminUnlocked = true
local sentIgnore, sentAlert
local overrideState = {}
local onlinePeers = {
  [9] = {
    className = 'GT4',
    isBlueFlag = true,
    blueCauseCarIndex = 0
  }
}
local network = {
  sendBlueIgnore = function (message, repeatForNewConnections)
    sentIgnore = { message = message, repeatForNewConnections = repeatForNewConnections }
  end,
  sendBlueAlert = function (message, repeatForNewConnections)
    sentAlert = { message = message, repeatForNewConnections = repeatForNewConnections }
  end
}

local blueFlags = require('modules/blue_flags').create({
  isAdminUnlocked = function () return adminUnlocked end,
  setOverrideState = function (key, value) overrideState[key] = value end,
  network = function () return network end,
  onlinePeers = onlinePeers,
  getLocalClassName = function () return 'GT3' end
})

assert(blueFlags.classKey('  GT3  ') == 'gt3')
assert(blueFlags.isDriverIgnored('Local Driver', 5, 0) == false)

blueFlags.applyIgnore('Local Driver', 5, 0, true)
assert(blueFlags.isDriverIgnored('Local Driver', 5, 0))
assert(overrideState.blueIgnored == true)
assert(physics.lastOverride == ac.FlagType.None)

blueFlags.publishIgnore('Other Driver', 9, 2, true)
assert(sentIgnore.message.driverName == 'Other Driver')
assert(sentIgnore.message.ignored == true)
assert(sentIgnore.repeatForNewConnections == true)

adminUnlocked = false
sentIgnore = nil
blueFlags.publishIgnore('Other Driver', 9, 2, false)
assert(sentIgnore == nil, 'locked users must not publish ignores')
adminUnlocked = true

blueFlags.applyBlueClassRule(' GT3 ', 'Pro', false)
local rule = blueFlags.getBlueClassRule('gt3')
assert(rule.className == ' GT3 ')
assert(rule.groupName == 'Pro' and rule.autoAllowed == false)

blueFlags.applyAlert(true, 'GT3')
assert(blueFlags.isManualBlueForClass('driver-key', 'gt3'))
assert(overrideState.manualBlueActive == true)

blueFlags.publishAlert(false, '')
assert(blueFlags.isBlueAlertActive() == false)
assert(sentAlert.message.active == false)
assert(sentAlert.repeatForNewConnections == true)

blueFlags.applyIgnore('Local Driver', 5, 0, false)
assert(not blueFlags.isDriverIgnored('Local Driver', 5, 0))
assert(overrideState.blueIgnored == false)

local activeBlueDrivers, allDrivers = blueFlags.collectDriverBlueStates()
assert(#allDrivers == 2)
assert(#activeBlueDrivers == 1)
assert(activeBlueDrivers[1].name == 'Other Driver')
assert(activeBlueDrivers[1].className == 'GT4')
assert(activeBlueDrivers[1].causeDescription == 'Approached by Local Driver (P1)')

print('blue flag tests passed')
