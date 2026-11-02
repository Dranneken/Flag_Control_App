package.path = './?.lua;./?/init.lua;' .. package.path
bit = require('tests/bit_stub')

local sha256 = require('modules/sha256')
local function toHex(value)
  return (value:gsub('.', function (character)
    return string.format('%02x', character:byte())
  end))
end

assert(toHex(sha256.hash('abc')) ==
  'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')

local hmac = sha256.createHmac('key')
assert(toHex(hmac('The quick brown fox jumps over the lazy dog')) ==
  'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8')

local longKey = string.rep(string.char(170), 131)
local longKeyHmac = sha256.createHmac(longKey)
assert(toHex(longKeyHmac(
  'Test Using Larger Than Block-Size Key - Hash Key First'
)) == '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54')

print('SHA-256 tests passed')
