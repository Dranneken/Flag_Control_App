local adminConfig = require('modules/admin_config')
local steamIdentity = {}

local CONTENT_MANAGER_VALUES_PATH = '\\AcTools Content Manager\\Values.data'
local MAX_VALUES_BYTES = 1048576

function steamIdentity.parse(contents)
  if type(contents) ~= 'string' or #contents > MAX_VALUES_BYTES then
    return nil, 'identity_unavailable'
  end

  local found
  for candidate in contents:gmatch('%d+') do
    if #candidate >= 17 then
      if not adminConfig.isSteamID64(candidate) then
        return nil, 'identity_unavailable'
      end
      if found then return nil, 'identity_ambiguous' end
      found = candidate
    end
  end

  if not found then return nil, 'identity_unavailable' end
  return found
end

function steamIdentity.getPath()
  local folder = ac.getFolder(ac.FolderID.AppDataLocal)
  if type(folder) ~= 'string' or folder == '' then return nil end
  folder = folder:gsub('[\\/]+$', '')
  return folder .. CONTENT_MANAGER_VALUES_PATH
end

function steamIdentity.readCurrent()
  local path = steamIdentity.getPath()
  if not path then return nil, 'identity_unavailable' end

  local file = io.open(path, 'rb')
  if not file then return nil, 'identity_unavailable' end
  local contents = file:read('*a')
  local closed = file:close()
  if type(contents) ~= 'string' or not closed then
    return nil, 'identity_unavailable'
  end
  return steamIdentity.parse(contents)
end

return steamIdentity
