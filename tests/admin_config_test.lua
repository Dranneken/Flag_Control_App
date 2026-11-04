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
    read = function (_, maxBytes)
      assert(maxBytes == 16385)
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
assert(missingFile == nil and missingFileError == 'allowlist_unavailable')

local scriptConfigPath =
  'C:\\Users\\Test\\Documents\\Assetto Corsa\\cfg\\extension\\state\\lua\\apps\\FlagControlApp\\admin_steam_ids.ini'
local generatedPath =
  'C:\\Users\\Test\\Documents\\Assetto Corsa\\cfg\\extension\\state\\lua\\apps\\FlagControlApp_admin_steam_ids.ini'
local generatedContents
io.open = function (path, mode)
  if path == scriptConfigPath and mode == 'rb' then
    return nil, 'missing script config directory'
  end
  if path == generatedPath and mode == 'rb' then
    return nil, 'missing allowlist'
  end
  if path == generatedPath and mode == 'wb' then
    return {
      write = function (_, contents)
        generatedContents = contents
        return true
      end,
      close = function () return true end
    }
  end
  error('unexpected allowlist file access: ' .. path .. ' (' .. mode .. ')')
end
assert(adminConfig.getPath() == generatedPath)
local generated, generatedError = adminConfig.load()
assert(generated == nil and generatedError == 'empty_allowlist')
assert(generatedContents and generatedContents:find('Steam profile ID', 1, true))

io.open = function (path, mode)
  if path == scriptConfigPath and mode == 'rb' then
    return nil, 'missing script config directory'
  end
  if path == generatedPath and mode == 'rb' then
    return {
      read = function () return '76561190000000002\n' end,
      close = function () return true end
    }
  end
  error('unexpected allowlist file access: ' .. path .. ' (' .. mode .. ')')
end
local existingGenerated, existingGeneratedError = adminConfig.load()
assert(existingGeneratedError == nil)
assert(existingGenerated['76561190000000002'])
io.open = originalOpen

print('Admin config tests passed')
