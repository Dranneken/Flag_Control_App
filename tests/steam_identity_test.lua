package.path = './?.lua;./?/init.lua;' .. package.path

local steamIdentity = require('modules/steam_identity')
local validUID = '76561190000000000'

local parsed, parseError = steamIdentity.parse(
  'other setting = true\nsteam_profile = ' .. validUID .. '\n'
)
assert(parsed == validUID and parseError == nil)

local missing, missingError = steamIdentity.parse('no profile ID is present')
assert(missing == nil and missingError == 'identity_unavailable')

local malformed, malformedError = steamIdentity.parse(
  'steam_profile = 765611980000000000\n'
)
assert(malformed == nil and malformedError == 'identity_unavailable')

local ambiguous, ambiguousError = steamIdentity.parse(
  validUID .. '\n' .. validUID .. '\n'
)
assert(ambiguous == nil and ambiguousError == 'identity_ambiguous')

local otherProfile, otherProfileError = steamIdentity.parse(
  '99999998000000000\n'
)
assert(otherProfile == nil and otherProfileError == 'identity_unavailable')

ac = {
  FolderID = { AppDataLocal = 5 },
  getFolder = function (folderID)
    assert(folderID == 5)
    return 'C:\\Users\\Test\\AppData\\Local'
  end
}

local originalOpen = io.open
local openedPath
io.open = function (path, mode)
  openedPath = path
  assert(mode == 'rb')
  return {
    read = function (_, format)
      assert(format == '*a')
      return 'steam_profile = ' .. validUID
    end,
    close = function () return true end
  }
end
local fromFile, fileError = steamIdentity.readCurrent()
io.open = originalOpen
assert(fromFile == validUID and fileError == nil)
assert(openedPath ==
  'C:\\Users\\Test\\AppData\\Local\\AcTools Content Manager\\Values.data')

print('Steam identity tests passed')
