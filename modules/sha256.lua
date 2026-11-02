local sha256 = {}
local MODULO = 4294967296
local bit = bit

local INITIAL_STATE = {
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
}

local ROUND_CONSTANTS = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local function add(...)
  local result = 0
  for index = 1, select('#', ...) do
    result = result + select(index, ...)
  end
  return result % MODULO
end

local function packWord(value)
  value = value % MODULO
  return string.char(
    math.floor(value / 16777216) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 256) % 256,
    value % 256
  )
end

local function compress(state, block)
  local schedule = {}
  for index = 1, 16 do
    local offset = (index - 1) * 4 + 1
    local b1, b2, b3, b4 = block:byte(offset, offset + 3)
    schedule[index] = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
  end

  for index = 17, 64 do
    local x = schedule[index - 15]
    local y = schedule[index - 2]
    local sigma0 = bit.bxor(bit.ror(x, 7), bit.ror(x, 18), bit.rshift(x, 3))
    local sigma1 = bit.bxor(bit.ror(y, 17), bit.ror(y, 19), bit.rshift(y, 10))
    schedule[index] = add(
      schedule[index - 16],
      sigma0,
      schedule[index - 7],
      sigma1
    )
  end

  local a, b, c, d = state[1], state[2], state[3], state[4]
  local e, f, g, h = state[5], state[6], state[7], state[8]
  for index = 1, 64 do
    local sigma1 = bit.bxor(bit.ror(e, 6), bit.ror(e, 11), bit.ror(e, 25))
    local choose = bit.bxor(bit.band(e, f), bit.band(bit.bnot(e), g))
    local first = add(h, sigma1, choose, ROUND_CONSTANTS[index], schedule[index])
    local sigma0 = bit.bxor(bit.ror(a, 2), bit.ror(a, 13), bit.ror(a, 22))
    local majority = bit.bxor(bit.band(a, b), bit.band(a, c), bit.band(b, c))
    local second = add(sigma0, majority)
    h, g, f, e = g, f, e, add(d, first)
    d, c, b, a = c, b, a, add(first, second)
  end

  return {
    add(state[1], a), add(state[2], b),
    add(state[3], c), add(state[4], d),
    add(state[5], e), add(state[6], f),
    add(state[7], g), add(state[8], h)
  }
end

local function hashWithPrefix(state, message, prefixLength)
  local messageLength = prefixLength + #message
  local bitLength = messageLength * 8
  local paddingLength = (56 - ((#message + 1) % 64)) % 64
  local padded = message .. '\128' .. string.rep('\0', paddingLength) ..
    packWord(math.floor(bitLength / MODULO)) .. packWord(bitLength % MODULO)

  local currentState = state
  for offset = 1, #padded, 64 do
    currentState = compress(currentState, padded:sub(offset, offset + 63))
  end

  local digest = {}
  for index = 1, 8 do
    digest[index] = packWord(currentState[index])
  end
  return table.concat(digest)
end

function sha256.hash(message)
  if type(message) ~= 'string' then return nil end
  return hashWithPrefix(INITIAL_STATE, message, 0)
end

function sha256.createHmac(key)
  if type(key) ~= 'string' then return nil end
  if #key > 64 then key = sha256.hash(key) end
  key = key .. string.rep('\0', 64 - #key)

  local innerPad = {}
  local outerPad = {}
  for index = 1, 64 do
    innerPad[index] = string.char(bit.bxor(key:byte(index), 0x36))
    outerPad[index] = string.char(bit.bxor(key:byte(index), 0x5c))
  end

  local innerState = compress(INITIAL_STATE, table.concat(innerPad))
  local outerState = compress(INITIAL_STATE, table.concat(outerPad))
  return function (message)
    if type(message) ~= 'string' then return nil end
    local innerDigest = hashWithPrefix(innerState, message, 64)
    return hashWithPrefix(outerState, innerDigest, 64)
  end
end

return sha256
