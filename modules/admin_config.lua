local adminConfig = {}

local CONFIG_FILE_NAME = 'admin_steam_ids.ini'
local MAX_CONFIG_BYTES = 16384

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

function adminConfig.getPath()
  local folder = ac.getFolder(ac.FolderID.ScriptConfig)
  if type(folder) ~= 'string' or folder == '' then return nil end
  folder = folder:gsub('[\\/]+$', '')
  return folder .. '\\' .. CONFIG_FILE_NAME
end

function adminConfig.load()
  local path = adminConfig.getPath()
  if not path then return nil, 'allowlist_unavailable' end

  local file = io.open(path, 'rb')
  if not file then return nil, 'allowlist_unavailable' end
  local contents = file:read('*a')
  local closed = file:close()
  if type(contents) ~= 'string' or not closed then
    return nil, 'allowlist_unavailable'
  end
  return adminConfig.parse(contents)
end

return adminConfig
