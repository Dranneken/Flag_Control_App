package.path = './?.lua;./?/init.lua;' .. package.path

local allowedID = '76561190000000000'
local password = 'correct horse battery staple'

local function makeJob(result)
  local complete = false
  return {
    step = function ()
      complete = true
      return true
    end,
    isComplete = function () return complete end,
    getProgress = function () return complete and 1 or 0 end,
    getResult = function () return complete and result or nil end
  }
end

local function createAuth(options)
  local credential = options.credential or ''
  local identity = options.identity or allowedID
  local identityError = options.identityError
  local allowlist = options.allowlist or { [allowedID] = true }
  local allowlistError = options.allowlistError
  local clock = 0
  local auth = require('modules/admin_auth').create({
    identityReader = function () return identity, identityError end,
    allowlistLoader = function () return allowlist, allowlistError end,
    allowlistPath = function () return 'local admin_steam_ids.ini path' end,
    credentialStorage = {
      get = function () return credential end,
      set = function (_, value) credential = value end
    },
    passwordKdf = {
      startCreate = function (submittedPassword)
        assert(submittedPassword == password)
        return makeJob('credential-record')
      end,
      startVerify = function (submittedPassword)
        return makeJob(submittedPassword == password)
      end
    },
    now = function () return clock end
  })
  return auth,
    function () return credential end,
    function (value) identity = value end,
    function (value) clock = value end
end

local setupAuth, getSetupCredential = createAuth({})
assert(setupAuth.getState().mode == 'setup')
assert(not setupAuth.isUnlocked())
setupAuth.setPassword(password)
assert(setupAuth.startSetup())
assert(setupAuth.getState().pending)
assert(not setupAuth.isUnlocked())
setupAuth.update(0.016)
assert(setupAuth.isUnlocked())
assert(getSetupCredential() == 'credential-record')

local loginAuth = createAuth({ credential = 'stored-credential' })
assert(loginAuth.getState().mode == 'login')
loginAuth.setPassword('wrong password')
assert(loginAuth.startLogin())
loginAuth.update(0.016)
assert(not loginAuth.isUnlocked())
assert(loginAuth.getState().error == 'Incorrect local admin password.')
assert(loginAuth.getState().cooldown > 0)

loginAuth.update(4)
loginAuth.setPassword(password)
assert(loginAuth.startLogin())
loginAuth.update(0.016)
assert(loginAuth.isUnlocked())
loginAuth.lock()
assert(not loginAuth.isUnlocked())

local unlistedAuth = createAuth({ identity = '76561190000000001' })
assert(unlistedAuth.getState().mode == 'blocked')
assert(not unlistedAuth.startSetup())
assert(not unlistedAuth.isUnlocked())
assert(unlistedAuth.getState().identity == nil)

local unreadableAuth = createAuth({ identityError = 'identity_unavailable' })
assert(unreadableAuth.getState().mode == 'blocked')
assert(not unreadableAuth.startSetup())

local allowlistErrorAuth = createAuth({ allowlistError = 'allowlist_unavailable' })
assert(allowlistErrorAuth.getState().mode == 'blocked')
assert(not allowlistErrorAuth.startSetup())

local refreshedAuth, _, changeIdentity = createAuth({
  credential = 'stored-credential'
})
changeIdentity('76561190000000001')
refreshedAuth.setPassword(password)
assert(not refreshedAuth.startLogin())
assert(refreshedAuth.getState().mode == 'blocked')

local resetAuth, getResetCredential, _, advanceClock =
  createAuth({ credential = 'stored-credential' })
assert(not resetAuth.beginPasswordReset())
assert(resetAuth.getState().resetArmed)
assert(getResetCredential() == 'stored-credential')
advanceClock(1)
assert(resetAuth.beginPasswordReset())
assert(resetAuth.getState().mode == 'setup')
assert(getResetCredential() == '')

local deniedResetAuth = createAuth({
  identity = '76561190000000001',
  credential = 'stored-credential'
})
assert(not deniedResetAuth.beginPasswordReset())
assert(not deniedResetAuth.isUnlocked())

print('Admin auth tests passed')
