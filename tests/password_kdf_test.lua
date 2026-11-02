package.path = './?.lua;./?/init.lua;' .. package.path

local expectedVerifier = string.rep('\2', 32)
local cryptoCalls = 0
local fakeCrypto = {
  randomBytes = function (length)
    cryptoCalls = cryptoCalls + 1
    assert(length == 16)
    return string.rep('\1', length)
  end
}

local fakePbkdf2 = {
  start = function (password, salt, iterations, keyLength)
    assert(salt == string.rep('\1', 16))
    assert(iterations == 600000 and keyLength == 32)
    local complete = false
    local result = password == 'correct horse battery staple' and
      expectedVerifier or string.rep('\3', 32)
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
}

local passwordKdf = require('modules/password_kdf')
local password = 'correct horse battery staple'
local createJob, createError = passwordKdf.startCreate(
  password, fakeCrypto, fakePbkdf2
)
assert(createError == nil and createJob)
assert(not createJob.isComplete())
assert(createJob.step(0))
local credential = createJob.getResult()
assert(credential:match('^pbkdf2%-sha256%$600000%$'))
assert(not credential:find(password, 1, true))
assert(cryptoCalls == 1)

local verifyJob = passwordKdf.startVerify(password, credential, fakePbkdf2)
assert(verifyJob.step(0))
assert(verifyJob.getResult() == true)

local wrongPasswordJob = passwordKdf.startVerify(
  'a different password value', credential, fakePbkdf2
)
assert(wrongPasswordJob.step(0))
assert(wrongPasswordJob.getResult() == false)

local shortPassword, shortPasswordError = passwordKdf.startCreate('short')
assert(shortPassword == nil and shortPasswordError == 'invalid_password_length')
local malformedCredential, credentialError =
  passwordKdf.startVerify(password, 'malformed', fakePbkdf2)
assert(malformedCredential == nil and credentialError == 'invalid_credential')

print('Password credential tests passed')
