local pbkdf2 = {}
local sha256 = require('modules/sha256')
local MAX_ITERATIONS = 10000000
local MAX_KEY_LENGTH = 32

local function xorStrings(left, right)
  local result = {}
  for index = 1, #left do
    result[index] = string.char(bit.band(bit.bxor(left:byte(index), right:byte(index)), 255))
  end
  return table.concat(result)
end

function pbkdf2.start(password, salt, iterations, keyLength)
  if type(password) ~= 'string' or type(salt) ~= 'string' or
     #salt == 0 or type(iterations) ~= 'number' or iterations < 1 or
     iterations > MAX_ITERATIONS or iterations ~= math.floor(iterations) or
     type(keyLength) ~= 'number' or keyLength < 1 or
     keyLength > MAX_KEY_LENGTH or keyLength ~= math.floor(keyLength) then
    return nil, 'invalid_input'
  end

  local hmac = sha256.createHmac(password)
  local completedIterations = 0
  local currentU
  local accumulator
  local result

  local function step(timeBudgetSeconds)
    if result then return true end
    if type(timeBudgetSeconds) ~= 'number' or timeBudgetSeconds < 0 then
      return false, 'invalid_time_budget'
    end

    local startedAt = os.clock()
    repeat
      if completedIterations == 0 then
        currentU = hmac(salt .. '\0\0\0\1')
        accumulator = currentU
      else
        currentU = hmac(currentU)
        accumulator = xorStrings(accumulator, currentU)
      end
      completedIterations = completedIterations + 1

      if completedIterations == iterations then
        result = accumulator:sub(1, keyLength)
        return true
      end
    until os.clock() - startedAt >= timeBudgetSeconds

    return false
  end

  return {
    step = step,
    isComplete = function () return result ~= nil end,
    getProgress = function () return completedIterations / iterations end,
    getResult = function () return result end
  }
end

return pbkdf2
