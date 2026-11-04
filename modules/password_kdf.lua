local passwordKdf = {}

local ITERATIONS = 600000
local SALT_LENGTH = 16
local KEY_LENGTH = 32
local MIN_PASSWORD_BYTES = 9
local MAX_PASSWORD_BYTES = 128

local function isPasswordLengthValid(password)
  return type(password) == 'string' and
    #password >= MIN_PASSWORD_BYTES and
    #password <= MAX_PASSWORD_BYTES
end

local function toHex(value)
  return (value:gsub('.', function (character)
    return string.format('%02x', character:byte())
  end))
end

local function fromHex(value)
  if #value % 2 ~= 0 or value:match('^[0-9a-f]+$') == nil then
    return nil
  end
  return (value:gsub('..', function (pair)
    return string.char(tonumber(pair, 16))
  end))
end

local function parseCredential(credential)
  if type(credential) ~= 'string' or #credential > 256 then return nil end
  local algorithm, rounds, saltHex, verifierHex =
    credential:match('^([^$]+)%$(%d+)%$([0-9a-f]+)%$([0-9a-f]+)$')
  if algorithm ~= 'pbkdf2-sha256' or not rounds or not saltHex or not verifierHex or
     tonumber(rounds) ~= ITERATIONS or
     #saltHex ~= SALT_LENGTH * 2 or #verifierHex ~= KEY_LENGTH * 2 then
    return nil
  end

  local salt = fromHex(saltHex)
  local verifier = fromHex(verifierHex)
  if not salt or not verifier then return nil end
  return salt, verifier
end

local function constantTimeEqual(left, right)
  if type(left) ~= 'string' or type(right) ~= 'string' or
     #left ~= #right then
    return false
  end

  local difference = 0
  for index = 1, #left do
    difference = difference + math.abs(left:byte(index) - right:byte(index))
  end
  return difference == 0
end

local function makeJob(derivation, getResult)
  return {
    step = derivation.step,
    isComplete = derivation.isComplete,
    getProgress = derivation.getProgress,
    getResult = function ()
      local result = derivation.getResult()
      if not result then return nil end
      return getResult(result)
    end
  }
end

local function startDerivation(password, salt, pbkdf2)
  pbkdf2 = pbkdf2 or require('modules/pbkdf2')
  return pbkdf2.start(password, salt, ITERATIONS, KEY_LENGTH)
end

function passwordKdf.startCreate(password, crypto, pbkdf2)
  if not isPasswordLengthValid(password) then
    return nil, 'invalid_password_length'
  end

  if not crypto then
    local loaded, cryptoModule = pcall(require, 'modules/windows_crypto')
    if not loaded then return nil, 'crypto_unavailable' end
    crypto = cryptoModule
  end
  local randomSucceeded, salt, saltError = pcall(crypto.randomBytes, SALT_LENGTH)
  if not randomSucceeded then return nil, 'crypto_unavailable' end
  if not salt or #salt ~= SALT_LENGTH then
    return nil, saltError or 'crypto_unavailable'
  end

  local derivation, deriveError = startDerivation(password, salt, pbkdf2)
  if not derivation then return nil, deriveError or 'crypto_unavailable' end
  return makeJob(derivation, function (verifier)
    if #verifier ~= KEY_LENGTH then return nil end
    return string.format(
      'pbkdf2-sha256$%d$%s$%s',
      ITERATIONS,
      toHex(salt),
      toHex(verifier)
    )
  end)
end

function passwordKdf.startVerify(password, credential, pbkdf2)
  if not isPasswordLengthValid(password) then
    return nil, 'invalid_password_length'
  end

  local salt, expectedVerifier = parseCredential(credential)
  if not salt then return nil, 'invalid_credential' end

  local derivation, deriveError = startDerivation(password, salt, pbkdf2)
  if not derivation then return nil, deriveError or 'crypto_unavailable' end
  return makeJob(derivation, function (verifier)
    if #verifier ~= KEY_LENGTH then return nil end
    return constantTimeEqual(verifier, expectedVerifier)
  end)
end

return passwordKdf
