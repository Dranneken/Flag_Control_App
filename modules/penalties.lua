local penalties = {}

local TYPES = {
  warning = true,
  time = true,
  drive_through = true,
  stop_go = true,
  disqualification = true
}

local STATUSES = {
  recommended = true,
  delayed = true,
  issued = true,
  served = true,
  cancelled = true,
  rejected = true
}

local SOURCES = {
  track_limits = true,
  collision = true,
  blue_flag = true,
  unsafe_rejoin = true,
  pit_rules = true,
  manual_incident = true
}

local POLICY_MODES = {
  off = true,
  manual = true,
  recommend_approval = true,
  recommend_delay = true,
  auto_instant = true,
  auto_delay = true
}

local DELAY_UNITS = {
  seconds = true,
  laps = true
}

local MAX_RECORDS = 100
local RECORDS_STORAGE_KEY = 'FlagControl.Penalties.v1'

local function cleanText(value, maxLength)
  if type(value) ~= 'string' then return '' end
  value = value:gsub('[%c]', ' '):gsub('^%s*(.-)%s*$', '%1')
  if #value > maxLength then return value:sub(1, maxLength) end
  return value
end

local function validInteger(value, minimum, maximum)
  return type(value) == 'number' and value == math.floor(value) and
    value >= minimum and value <= maximum
end

local function copyRecord(record)
  local copy = {}
  for key, value in pairs(record) do copy[key] = value end
  return copy
end

local function encodeText(value)
  return (value:gsub('.', function (character)
    if character:match('[A-Za-z0-9_. %-]') then return character end
    return string.format('%%%02X', character:byte())
  end))
end

local function decodeText(value)
  return (value:gsub('%%(%x%x)', function (hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function serializeRecord(record)
  local fields = {
    record.id,
    record.type,
    record.status,
    record.source,
    record.driverName,
    tostring(record.driverSessionID),
    tostring(record.carIndex),
    record.cause,
    record.details,
    record.issuer,
    tostring(record.issuerSessionID),
    tostring(record.amount),
    tostring(record.serveWithinLaps),
    tostring(record.createdAt),
    tostring(record.revision),
    record.autoAfterDelay and '1' or '0',
    tostring(record.delayValue),
    record.delayUnit,
    tostring(record.dueAt),
    tostring(record.dueLap)
  }
  for index, value in ipairs(fields) do
    if index == 1 or index == 5 or index == 8 or index == 9 or index == 10 then
      fields[index] = encodeText(value)
    end
  end
  return table.concat(fields, '|')
end

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do
    fields[#fields + 1] = field
  end
  return fields
end

local function deserializeRecord(line)
  local fields = splitFields(line)
  if #fields ~= 20 then return nil end

  local record = {
    id = decodeText(fields[1]),
    type = fields[2],
    status = fields[3],
    source = fields[4],
    driverName = decodeText(fields[5]),
    driverSessionID = tonumber(fields[6]),
    carIndex = tonumber(fields[7]),
    cause = decodeText(fields[8]),
    details = decodeText(fields[9]),
    issuer = decodeText(fields[10]),
    issuerSessionID = tonumber(fields[11]),
    amount = tonumber(fields[12]),
    serveWithinLaps = tonumber(fields[13]),
    createdAt = tonumber(fields[14]),
    revision = tonumber(fields[15]),
    autoAfterDelay = fields[16] == '1',
    delayValue = tonumber(fields[17]),
    delayUnit = fields[18],
    dueAt = tonumber(fields[19]),
    dueLap = tonumber(fields[20])
  }

  if not record.id or #record.id > 32 or not TYPES[record.type] or
     not STATUSES[record.status] or not SOURCES[record.source] or
     type(record.driverName) ~= 'string' or #record.driverName == 0 or
     not validInteger(record.driverSessionID, -1, 2147483647) or
     not validInteger(record.carIndex, -1, 255) or
     type(record.cause) ~= 'string' or #record.cause == 0 or
     type(record.details) ~= 'string' or type(record.issuer) ~= 'string' or
     not validInteger(record.issuerSessionID, -1, 2147483647) or
     not validInteger(record.amount, 0, 3600) or
     not validInteger(record.serveWithinLaps, 0, 999) or
     not validInteger(record.createdAt, 0, 2147483647) or
     not validInteger(record.revision, 1, 2147483647) or
     not validInteger(record.delayValue, 0, 999999) or
     not DELAY_UNITS[record.delayUnit] or
     not validInteger(record.dueAt, 0, 2147483647) or
     not validInteger(record.dueLap, 0, 999999) then
    return nil
  end
  return record
end

local function defaultPolicy()
  return {
    mode = 'manual',
    penaltyType = 'time',
    amount = 5,
    delayValue = 10,
    delayUnit = 'seconds',
    revision = 1
  }
end

function penalties.create(dependencies)
  dependencies = dependencies or {}
  local isAdminUnlocked = dependencies.isAdminUnlocked or function () return false end
  local getLocalSessionID = dependencies.getLocalSessionID or function () return -1 end
  local getDriverLapCount = dependencies.getDriverLapCount or function () return nil end
  local now = dependencies.now or os.time
  local clock = dependencies.clock or os.clock
  local getNetwork = dependencies.network or function () return nil end
  local storageFactory = dependencies.storageFactory
  local records = {}
  local recordOrder = {}
  local policies = {}
  local nextID = 0
  local recordStorage = storageFactory and storageFactory(RECORDS_STORAGE_KEY, '') or nil

  local function persistRecords()
    if not recordStorage then return end
    local rows = {}
    for _, id in ipairs(recordOrder) do
      local record = records[id]
      if record then rows[#rows + 1] = serializeRecord(record) end
    end
    recordStorage:set(table.concat(rows, '\n'))
  end

  local function insertRecord(record)
    local current = records[record.id]
    if current and current.revision >= record.revision then return false end
    if not current then
      recordOrder[#recordOrder + 1] = record.id
      if #recordOrder > MAX_RECORDS then
        local removedID = table.remove(recordOrder, 1)
        records[removedID] = nil
      end
    end
    records[record.id] = copyRecord(record)
    persistRecords()
    return true
  end

  local function publishRecord(record)
    local network = getNetwork()
    if network and network.sendPenaltyRecord then
      network.sendPenaltyRecord(copyRecord(record), true)
    end
  end

  local function persistPolicy(source, policy)
    if not storageFactory then return end
    local storage = storageFactory('FlagControl.PenaltyPolicy.' .. source, '')
    storage:set(table.concat({
      policy.mode,
      policy.penaltyType,
      tostring(policy.amount),
      tostring(policy.delayValue),
      policy.delayUnit,
      tostring(policy.revision)
    }, '|'))
  end

  local function loadPolicy(source)
    local policy = defaultPolicy()
    if storageFactory then
      local value = storageFactory('FlagControl.PenaltyPolicy.' .. source, ''):get()
      if type(value) == 'string' then
        local fields = splitFields(value)
        if #fields == 6 and POLICY_MODES[fields[1]] and TYPES[fields[2]] and
           validInteger(tonumber(fields[3]), 0, 3600) and
           validInteger(tonumber(fields[4]), 0, 999999) and
           DELAY_UNITS[fields[5]] and
           validInteger(tonumber(fields[6]), 1, 2147483647) then
          policy = {
            mode = fields[1],
            penaltyType = fields[2],
            amount = tonumber(fields[3]),
            delayValue = tonumber(fields[4]),
            delayUnit = fields[5],
            revision = tonumber(fields[6])
          }
        end
      end
    end
    policies[source] = policy
  end

  for source in pairs(SOURCES) do loadPolicy(source) end

  local function nextRecordID()
    nextID = nextID + 1
    return string.format('%d:%d:%d', getLocalSessionID(), now(), nextID)
  end

  local function getRecord(id)
    local record = records[id]
    return record and copyRecord(record) or nil
  end

  local function makeRecord(input, status, policy)
    if type(input) ~= 'table' or not TYPES[input.type] or
       not SOURCES[input.source] then
      return nil, 'invalid_penalty'
    end

    local driverName = cleanText(input.driverName, 48)
    local cause = cleanText(input.cause, 96)
    if driverName == '' or cause == '' then return nil, 'missing_driver_or_cause' end

    local amount = input.amount or 0
    if not validInteger(amount, 0, 3600) then return nil, 'invalid_amount' end
    if (input.type == 'time' or input.type == 'stop_go') and amount < 1 then
      return nil, 'invalid_amount'
    end

    local driverSessionID = input.driverSessionID or -1
    local carIndex = input.carIndex or -1
    local serveWithinLaps = input.serveWithinLaps or 0
    if not validInteger(driverSessionID, -1, 2147483647) or
       not validInteger(carIndex, -1, 255) or
       not validInteger(serveWithinLaps, 0, 999) then
      return nil, 'invalid_driver'
    end

    local delayValue = 0
    local delayUnit = 'seconds'
    local dueAt = 0
    local dueLap = 0
    local autoAfterDelay = false
    if policy and (policy.mode == 'recommend_delay' or policy.mode == 'auto_delay') then
      delayValue = policy.delayValue
      delayUnit = policy.delayUnit
      autoAfterDelay = true
      if delayUnit == 'seconds' then
        dueAt = now() + delayValue
      else
        local currentLap = getDriverLapCount(driverSessionID, carIndex)
        if not validInteger(currentLap, 0, 999999) then
          return nil, 'lap_delay_unavailable'
        end
        dueLap = currentLap + delayValue
      end
    end

    return {
      id = nextRecordID(),
      type = input.type,
      status = status,
      source = input.source,
      driverName = driverName,
      driverSessionID = driverSessionID,
      carIndex = carIndex,
      cause = cause,
      details = cleanText(input.details, 96),
      issuer = cleanText(input.issuer or dependencies.getLocalDriverName and dependencies.getLocalDriverName() or '', 48),
      issuerSessionID = getLocalSessionID(),
      amount = amount,
      serveWithinLaps = serveWithinLaps,
      createdAt = now(),
      revision = 1,
      autoAfterDelay = autoAfterDelay,
      delayValue = delayValue,
      delayUnit = delayUnit,
      dueAt = dueAt,
      dueLap = dueLap
    }
  end

  local function saveAndPublish(record)
    insertRecord(record)
    publishRecord(record)
    return copyRecord(record)
  end

  local function issue(input)
    if not isAdminUnlocked() then return nil, 'admin_locked' end
    local record, reason = makeRecord(input, 'issued')
    if not record then return nil, reason end
    return saveAndPublish(record)
  end

  local function reportIncident(input)
    if not isAdminUnlocked() then return nil, 'admin_locked' end
    if type(input) ~= 'table' or not SOURCES[input.source] then
      return nil, 'invalid_incident'
    end
    local policy = policies[input.source] or defaultPolicy()
    if policy.mode == 'off' then return nil, 'policy_off' end
    if policy.mode == 'manual' then return nil, 'manual_required' end

    local status = 'recommended'
    if policy.mode == 'auto_instant' then
      status = 'issued'
    elseif policy.mode == 'auto_delay' then
      status = 'delayed'
    end

    local record, reason = makeRecord({
      type = policy.penaltyType,
      source = input.source,
      driverName = input.driverName,
      driverSessionID = input.driverSessionID,
      carIndex = input.carIndex,
      cause = input.cause,
      details = input.details,
      amount = policy.amount,
      serveWithinLaps = input.serveWithinLaps or 0
    }, status, policy)
    if not record then return nil, reason end
    if policy.mode == 'recommend_approval' then
      record.autoAfterDelay = false
    end
    return saveAndPublish(record)
  end

  local function changeStatus(id, status)
    if not isAdminUnlocked() then return nil, 'admin_locked' end
    if not STATUSES[status] then return nil, 'invalid_status' end
    local record = records[id]
    if not record then return nil, 'unknown_penalty' end

    if status == 'issued' and record.status ~= 'recommended' then
      return nil, 'not_recommendation'
    end
    if status == 'rejected' and record.status ~= 'recommended' then
      return nil, 'not_recommendation'
    end
    if status == 'served' and
       (record.status ~= 'issued' or
        (record.type ~= 'time' and record.type ~= 'drive_through' and record.type ~= 'stop_go')) then
      return nil, 'not_serviceable'
    end
    if status == 'cancelled' and
       (record.status == 'served' or record.status == 'cancelled' or record.status == 'rejected') then
      return nil, 'already_closed'
    end

    local updated = copyRecord(record)
    updated.status = status
    updated.revision = updated.revision + 1
    updated.autoAfterDelay = false
    return saveAndPublish(updated)
  end

  local function setPolicy(source, input)
    if not isAdminUnlocked() then return false, 'admin_locked' end
    if not SOURCES[source] or type(input) ~= 'table' or
       not POLICY_MODES[input.mode] or not TYPES[input.penaltyType] or
       not validInteger(input.amount, 0, 3600) or
       not validInteger(input.delayValue, 0, 999999) or
       not DELAY_UNITS[input.delayUnit] then
      return false, 'invalid_policy'
    end
    if (input.penaltyType == 'time' or input.penaltyType == 'stop_go') and input.amount < 1 then
      return false, 'invalid_policy'
    end

    local current = policies[source] or defaultPolicy()
    local policy = {
      mode = input.mode,
      penaltyType = input.penaltyType,
      amount = input.amount,
      delayValue = input.delayValue,
      delayUnit = input.delayUnit,
      revision = current.revision + 1,
      source = source
    }
    policies[source] = policy
    persistPolicy(source, policy)
    return true
  end

  local function applyPenaltyEvent(record)
    if type(record) ~= 'table' then return false end
    local validated = deserializeRecord(serializeRecord(record))
    if not validated then return false end
    return insertRecord(validated)
  end

  local function applyPolicyEvent(source, policy)
    if not SOURCES[source] or type(policy) ~= 'table' or
       not POLICY_MODES[policy.mode] or not TYPES[policy.penaltyType] or
       not validInteger(policy.amount, 0, 3600) or
       not validInteger(policy.delayValue, 0, 999999) or
       not DELAY_UNITS[policy.delayUnit] or
       not validInteger(policy.revision, 1, 2147483647) then
      return false
    end
    local current = policies[source]
    if current and current.revision >= policy.revision then return false end
    policies[source] = {
      mode = policy.mode,
      penaltyType = policy.penaltyType,
      amount = policy.amount,
      delayValue = policy.delayValue,
      delayUnit = policy.delayUnit,
      revision = policy.revision
    }
    persistPolicy(source, policies[source])
    return true
  end

  local function update()
    if not isAdminUnlocked() then return end
    local localSessionID = getLocalSessionID()
    local currentTime = now()
    for _, id in ipairs(recordOrder) do
      local record = records[id]
      if record and record.issuerSessionID == localSessionID and
         record.autoAfterDelay and
         (record.status == 'recommended' or record.status == 'delayed') then
        local delayComplete = false
        if record.delayUnit == 'seconds' then
          delayComplete = currentTime >= record.dueAt
        else
          local currentLap = getDriverLapCount(record.driverSessionID, record.carIndex)
          delayComplete = validInteger(currentLap, 0, 999999) and currentLap >= record.dueLap
        end
        if delayComplete then
          local updated = copyRecord(record)
          updated.status = 'issued'
          updated.autoAfterDelay = false
          updated.revision = updated.revision + 1
          saveAndPublish(updated)
        end
      end
    end
  end

  local function getRecords()
    local result = {}
    for index = #recordOrder, 1, -1 do
      local record = records[recordOrder[index]]
      if record then result[#result + 1] = copyRecord(record) end
    end
    return result
  end

  local function getPolicies()
    local result = {}
    for source in pairs(SOURCES) do
      local policy = copyRecord(policies[source] or defaultPolicy())
      policy.source = source
      result[#result + 1] = policy
    end
    table.sort(result, function (left, right) return left.source < right.source end)
    return result
  end

  local function getPolicy(source)
    return copyRecord(policies[source] or defaultPolicy())
  end

  local savedRecords = recordStorage and recordStorage:get() or nil
  if type(savedRecords) == 'string' then
    for line in (savedRecords .. '\n'):gmatch('(.-)\n') do
      if line ~= '' then
        local record = deserializeRecord(line)
        if record then insertRecord(record) end
      end
    end
  end

  return {
    issue = issue,
    reportIncident = reportIncident,
    approve = function (id) return changeStatus(id, 'issued') end,
    reject = function (id) return changeStatus(id, 'rejected') end,
    cancel = function (id) return changeStatus(id, 'cancelled') end,
    markServed = function (id) return changeStatus(id, 'served') end,
    setPolicy = setPolicy,
    applyPenaltyEvent = applyPenaltyEvent,
    applyPolicyEvent = applyPolicyEvent,
    getRecords = getRecords,
    getPolicies = getPolicies,
    getPolicy = getPolicy,
    update = update,
    types = TYPES,
    statuses = STATUSES,
    sources = SOURCES,
    policyModes = POLICY_MODES,
    delayUnits = DELAY_UNITS
  }
end

return penalties
