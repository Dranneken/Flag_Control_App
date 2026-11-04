package.path = './?.lua;./?/init.lua;' .. package.path

local now = 1000
local notifications = require('modules/penalty_notifications').create({
  duration = 15,
  isLocalRecord = function (record) return record.driverSessionID == 1 end,
  now = function () return now end
})

local persisted = {
  {
    id = 'old',
    status = 'issued',
    createdAt = 980,
    type = 'warning',
    driverSessionID = 2
  }
}
notifications.update(persisted, 0)
assert(notifications.getCurrent() == nil, 'existing records should not alert on startup')

local first = {
  id = 'first',
  status = 'issued',
  createdAt = 1000,
  type = 'time',
  driverName = 'Driver One',
  driverSessionID = 1
}
local second = {
  id = 'second',
  status = 'issued',
  createdAt = 1001,
  type = 'drive_through',
  driverName = 'Driver Two',
  driverSessionID = 2
}
local third = {
  id = 'third',
  status = 'issued',
  createdAt = 1002,
  type = 'warning',
  driverName = 'Driver One',
  driverSessionID = 1
}

now = 1001
notifications.update({ persisted[1], first }, 0)
assert(notifications.getCurrent('mine').id == 'first')
notifications.update({ persisted[1], first, second, third }, 0)
assert(notifications.getCurrent('mine').id == 'first', 'mine queue should retain its current notice')
assert(notifications.getCurrent('others').id == 'second',
  'other players should have an independent current notice')
notifications.update({ persisted[1], first, second }, 15)
assert(notifications.getCurrent('mine').id == 'third',
  'the mine queue should advance independently')
assert(notifications.getCurrent('others') == nil,
  'the other players queue should expire independently')
notifications.update({ persisted[1], first, second }, 15)
assert(notifications.getCurrent('mine') == nil, 'queued notices should expire after 15 seconds')

local recommendation = {
  id = 'approved',
  status = 'recommended',
  createdAt = 900,
  type = 'warning',
  driverSessionID = 2
}
notifications.update({ persisted[1], first, second, recommendation }, 0)
recommendation.status = 'issued'
notifications.update({ persisted[1], first, second, recommendation }, 0)
assert(notifications.getCurrent('others').id == 'approved',
  'approving a recommendation should create a notice even if it is older')

print('penalty notification tests passed')
