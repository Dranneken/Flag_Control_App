package.path = './?.lua;./?/init.lua;' .. package.path

local notifications = require('modules/flag_notifications').create({
  flagNone = 0
})

notifications.update(0, 0, 'No flag update received', 0)
assert(notifications.getCurrent() == nil, 'initial state must not create a notice')

notifications.update(1, 2, 'You')
local notice = notifications.getCurrent()
assert(notice and notice.flag == 2 and notice.senderName == 'You')

for _ = 1, 100 do
  notifications.update(1, 2, 'You')
end
assert(notifications.getCurrent() ~= nil, 'a deployed flag should remain visible')

notifications.update(2, 0, 'Other Admin')
notice = notifications.getCurrent()
assert(notice and notice.flag == 0 and notice.senderName == 'Other Admin',
  'clearing an active flag should replace it with a persistent clear notice')

notifications.update(3, 0, 'Other Admin')
notice = notifications.getCurrent()
assert(notice and notice.flag == 0 and notice.senderName == 'Other Admin',
  'a clear notice should remain visible until the next flag update')

local restored = require('modules/flag_notifications').create({ flagNone = 0 })
restored.update(1, 6, 'Lobby Admin')
notice = restored.getCurrent()
assert(notice and notice.flag == 6 and notice.senderName == 'Lobby Admin',
  'an active flag received during initialization should be shown')

print('flag notification tests passed')
