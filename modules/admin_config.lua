local adminConfig = {}

local CONFIG_FILE_NAME = 'admin_steam_ids.ini'
local SHARED_CONFIG_FILE_NAME = 'FlagControlApp_admin_steam_ids.ini'
local MAX_CONFIG_BYTES = 16384
local EMPTY_CONFIG = [[
# Add each administrator's Steam profile ID on a separate line.
# Example: 7656119XXXXXXXXXX
]]

function adminConfig.isSteamID64(value)
  return type(value) == 'string' and
    #value == 17 and
    value:match('^7656119%d%d%d%d%d%d%d%d%d%d$') ~= nil
end

function adminConfig.parse(contents)
  if type(contents) ~= 'string' or #contents > MAX_CONFIG_BYTES then
    return nil, 'invalid_allowlist'
  end

  local allowlist = {}
  for line in (contents .. '\n'):gmatch('(.-)\n') do
    line = line:gsub('\r$', ''):match('^%s*(.-)%s*$')
    if line ~= '' and line:sub(1, 1) ~= '#' then
      if not adminConfig.isSteamID64(line) or allowlist[line] then
        return nil, 'invalid_allowlist'
      end
      allowlist[line] = true
    end
  end

  if next(allowlist) == nil then return nil, 'empty_allowlist' end
  return allowlist
end

local function getScriptConfigPath()
  local folder = ac.getFolder(ac.FolderID.ScriptConfig)
  if type(folder) ~= 'string' or folder == '' then return nil end
  folder = folder:gsub('[\\/]+$', '')
  return folder .. '\\' .. CONFIG_FILE_NAME
end

local function getSharedConfigPath(scriptConfigPath)
  local scriptFolder = scriptConfigPath:match('^(.*)[\\/][^\\/]+$')
  if not scriptFolder then return nil end
  local parentFolder = scriptFolder:match('^(.*)[\\/][^\\/]+$')
  if not parentFolder or parentFolder == '' then return nil end
  return parentFolder .. '\\' .. SHARED_CONFIG_FILE_NAME
end

local function readConfig(path)
  local file = io.open(path, 'rb')
  if not file then return nil end
  local contents = file:read(MAX_CONFIG_BYTES + 1)
  local closed = file:close()
  if type(contents) ~= 'string' or not closed then
    return nil, 'allowlist_unavailable'
  end
  return contents
end

function adminConfig.getPath()
  local scriptConfigPath = getScriptConfigPath()
  if not scriptConfigPath then return nil end
  local contents, readError = readConfig(scriptConfigPath)
  if contents ~= nil or readError then return scriptConfigPath end
  return getSharedConfigPath(scriptConfigPath)
end

function adminConfig.load()
  local scriptConfigPath = getScriptConfigPath()
  if not scriptConfigPath then return nil, 'allowlist_unavailable' end

  local contents, readError = readConfig(scriptConfigPath)
  if contents ~= nil then return adminConfig.parse(contents) end
  if readError then return nil, readError end

  local path = getSharedConfigPath(scriptConfigPath)
  if not path then return nil, 'allowlist_unavailable' end
  contents, readError = readConfig(path)
  if contents ~= nil then return adminConfig.parse(contents) end
  if readError then return nil, readError end

  local file = io.open(path, 'wb')
  if not file then return nil, 'allowlist_unavailable' end
  local wrote = file:write(EMPTY_CONFIG)
  local closed = file:close()
  if wrote == nil or not closed then return nil, 'allowlist_unavailable' end

  return adminConfig.parse(EMPTY_CONFIG)
end

return adminConfig
