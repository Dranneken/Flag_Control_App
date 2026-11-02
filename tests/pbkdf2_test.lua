package.path = './?.lua;./?/init.lua;' .. package.path
bit = require('tests/bit_stub')

local pbkdf2 = require('modules/pbkdf2')
local function toHex(value)
  return (value:gsub('.', function (character)
    return string.format('%02x', character:byte())
  end))
end

local oneIteration = pbkdf2.start('password', 'salt', 1, 32)
assert(oneIteration.step(1))
assert(toHex(oneIteration.getResult()) ==
  '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b')

local twoIterations = pbkdf2.start('password', 'salt', 2, 32)
assert(not twoIterations.step(0))
assert(twoIterations.getProgress() > 0 and twoIterations.getProgress() < 1)
assert(twoIterations.step(1))
assert(toHex(twoIterations.getResult()) ==
  'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43')

print('PBKDF2 tests passed')
