local MODULO = 4294967296
local MASK = MODULO - 1

local function normalize(value)
  return value % MODULO
end

local function combine(left, right, operation)
  left = normalize(left)
  right = normalize(right)
  local result = 0
  local place = 1
  for _ = 1, 32 do
    local leftBit = left % 2
    local rightBit = right % 2
    if operation(leftBit, rightBit) then result = result + place end
    left = math.floor(left / 2)
    right = math.floor(right / 2)
    place = place * 2
  end
  return result
end

local bitStub = {}

function bitStub.band(left, right)
  return combine(left, right, function (a, b) return a == 1 and b == 1 end)
end

function bitStub.bor(left, right)
  return combine(left, right, function (a, b) return a == 1 or b == 1 end)
end

function bitStub.bxor(left, right, ...)
  local result = combine(left, right, function (a, b) return a ~= b end)
  for index = 1, select('#', ...) do
    result = combine(result, select(index, ...), function (a, b) return a ~= b end)
  end
  return result
end

function bitStub.bnot(value)
  return MASK - normalize(value)
end

function bitStub.rshift(value, amount)
  return math.floor(normalize(value) / (2 ^ amount))
end

function bitStub.lshift(value, amount)
  return (normalize(value) * (2 ^ amount)) % MODULO
end

function bitStub.ror(value, amount)
  value = normalize(value)
  local low = value % (2 ^ amount)
  local high = math.floor(value / (2 ^ amount))
  return high + low * (2 ^ (32 - amount))
end

return bitStub
