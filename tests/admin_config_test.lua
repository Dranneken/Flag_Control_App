package.path = './?.lua;./?/init.lua;' .. package.path

local adminConfig = require('modules/admin_config')

local allowed, err = adminConfig.parse([[
# One SteamID64 per line
76561190000000000

76561190000000001
]])
assert(err == nil)
assert(allowed['76561190000000000'])
assert(allowed['76561190000000001'])

local empty, emptyError = adminConfig.parse('# no administrators configured\n')
assert(empty == nil and emptyError == 'empty_allowlist')

local malformed, malformedError = adminConfig.parse('765611980000000000\n')
assert(malformed == nil and malformedError == 'invalid_allowlist')

local duplicate, duplicateError = adminConfig.parse(
  '76561190000000000\n76561190000000000\n'
)
assert(duplicate == nil and duplicateError == 'invalid_allowlist')

local invalidComment, invalidCommentError = adminConfig.parse(
  '76561190000000000 # inline comment\n'
)
assert(invalidComment == nil and invalidCommentError == 'invalid_allowlist')

ac = {
  FolderID = { ScriptConfig = 8 },
  getFolder = function (folderID)
    assert(folderID == 8)
    return 'C:\\Users\\Test\\Documents\\Assetto Corsa\\cfg\\extension\\state\\lua\\apps\\FlagControlApp'
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
      return '76561190000000000\n'
    end,
    close = function () return true end
  }
end
local loaded, loadError = adminConfig.load()
assert(loadError == nil and loaded['76561190000000000'])
assert(openedPath ==
  'C:\\Users\\Test\\Documents\\Assetto Corsa\\cfg\\extension\\state\\lua\\apps\\FlagControlApp\\admin_steam_ids.ini')

io.open = function () return nil, 'missing file' end
local missingFile, missingFileError = adminConfig.load()
io.open = originalOpen
assert(missingFile == nil and missingFileError == 'allowlist_unavailable')

print('Admin config tests passed')
