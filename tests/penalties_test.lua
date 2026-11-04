package.path = './?.lua;./?/init.lua;' .. package.path

local adminUnlocked = true
local currentTime = 100
local currentClock = 5
local currentLap = 3
local persisted = {}
local publishedRecords = {}

local function storageFactory(key, defaultValue)
  if persisted[key] == nil then persisted[key] = defaultValue end
  return {
    get = function () return persisted[key] end,
    set = function (_, value) persisted[key] = value end
  }
end

local penaltiesModule = require('modules/penalties')
local penalties = penaltiesModule.create({
  isAdminUnlocked = function () return adminUnlocked end,
  getLocalSessionID = function () return 4 end,
  getLocalDriverName = function () return 'Race Control' end,
  getDriverLapCount = function () return currentLap end,
  now = function () return currentTime end,
  clock = function () return currentClock end,
  storageFactory = storageFactory,
  network = function ()
    return {
      sendPenaltyRecord = function (record) publishedRecords[#publishedRecords + 1] = record end
    }
  end
})

local warning, warningError = penalties.issue({
  type = 'warning',
  source = 'track_limits',
  driverName = 'Driver One',
  driverSessionID = 11,
  carIndex = 2,
  cause = 'Repeated track limits',
  details = 'Turn 4, third occurrence',
  issuer = 'Race Control'
})
assert(warning and not warningError)
assert(warning.status == 'issued' and warning.amount == 0)
assert(publishedRecords[1].id == warning.id)

local invalidPenalty, invalidError = penalties.issue({
  type = 'time',
  source = 'collision',
  driverName = 'Driver One',
  cause = 'Contact',
  amount = 0
})
assert(not invalidPenalty and invalidError == 'invalid_amount')

local savePolicy, policyError = penalties.setPolicy('collision', {
  mode = 'recommend_approval',
  penaltyType = 'time',
  amount = 10,
  delayValue = 30,
  delayUnit = 'seconds'
})
assert(savePolicy and not policyError)
assert(penalties.getPolicy('collision').mode == 'recommend_approval')

local recommendation = penalties.reportIncident({
  source = 'collision',
  driverName = 'Driver Two',
  driverSessionID = 12,
  carIndex = 3,
  cause = 'Avoidable contact'
})
assert(recommendation and recommendation.status == 'recommended')

local served, serveError = penalties.markServed(recommendation.id)
assert(not served and serveError == 'not_serviceable')
assert(penalties.approve(recommendation.id).status == 'issued')
assert(penalties.markServed(recommendation.id).status == 'served')

penalties.setPolicy('blue_flag', {
  mode = 'recommend_delay',
  penaltyType = 'time',
  amount = 5,
  delayValue = 10,
  delayUnit = 'seconds'
})
local delayedRecommendation = penalties.reportIncident({
  source = 'blue_flag',
  driverName = 'Driver Three',
  driverSessionID = 13,
  carIndex = 4,
  cause = 'Failed to yield'
})
assert(delayedRecommendation.status == 'recommended')
currentTime = currentTime + 9
penalties.update()
assert(penalties.getRecords()[1].status == 'recommended')
currentTime = currentTime + 1
penalties.update()
assert(penalties.getRecords()[1].status == 'issued')

penalties.setPolicy('pit_rules', {
  mode = 'auto_delay',
  penaltyType = 'stop_go',
  amount = 5,
  delayValue = 2,
  delayUnit = 'laps'
})
local delayedLapPenalty = penalties.reportIncident({
  source = 'pit_rules',
  driverName = 'Driver Four',
  driverSessionID = 14,
  carIndex = 5,
  cause = 'Pit-lane violation'
})
assert(delayedLapPenalty.status == 'delayed' and delayedLapPenalty.dueLap == 5)
currentLap = 4
penalties.update()
assert(penalties.getRecords()[1].status == 'delayed')
currentLap = 5
penalties.update()
assert(penalties.getRecords()[1].status == 'issued')

local beforeOff = #penalties.getRecords()
penalties.setPolicy('unsafe_rejoin', {
  mode = 'off',
  penaltyType = 'warning',
  amount = 0,
  delayValue = 0,
  delayUnit = 'seconds'
})
local disabled, disabledError = penalties.reportIncident({
  source = 'unsafe_rejoin',
  driverName = 'Driver Five',
  driverSessionID = 15,
  carIndex = 6,
  cause = 'Unsafe rejoin'
})
assert(not disabled and disabledError == 'policy_off')
assert(#penalties.getRecords() == beforeOff)

local persistedRecords = persisted['FlagControl.Penalties.v1']
assert(persistedRecords:find('Driver One', 1, true))

local restored = penaltiesModule.create({
  isAdminUnlocked = function () return false end,
  storageFactory = storageFactory
})
assert(#restored.getRecords() == #penalties.getRecords())
assert(restored.getPolicy('pit_rules').delayUnit == 'laps')
assert(restored.getRecords()[#restored.getRecords()].cause == 'Repeated track limits')

adminUnlocked = false
local locked, lockedError = penalties.issue({
  type = 'disqualification',
  source = 'manual_incident',
  driverName = 'Driver One',
  cause = 'Unsafe conduct'
})
assert(not locked and lockedError == 'admin_locked')

print('penalty tests passed')
