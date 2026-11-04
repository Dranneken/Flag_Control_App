local network = {}

local PENALTY_TYPE_CODES = {
  warning = 1,
  time = 2,
  drive_through = 3,
  stop_go = 4,
  disqualification = 5
}

local PENALTY_TYPE_NAMES = {
  [1] = 'warning',
  [2] = 'time',
  [3] = 'drive_through',
  [4] = 'stop_go',
  [5] = 'disqualification'
}

local PENALTY_STATUS_CODES = {
  recommended = 1,
  delayed = 2,
  issued = 3,
  served = 4,
  cancelled = 5,
  rejected = 6
}

local PENALTY_STATUS_NAMES = {
  [1] = 'recommended',
  [2] = 'delayed',
  [3] = 'issued',
  [4] = 'served',
  [5] = 'cancelled',
  [6] = 'rejected'
}

local PENALTY_SOURCE_CODES = {
  track_limits = 1,
  collision = 2,
  blue_flag = 3,
  unsafe_rejoin = 4,
  pit_rules = 5,
  manual_incident = 6
}

local PENALTY_SOURCE_NAMES = {
  [1] = 'track_limits',
  [2] = 'collision',
  [3] = 'blue_flag',
  [4] = 'unsafe_rejoin',
  [5] = 'pit_rules',
  [6] = 'manual_incident'
}

local DELAY_UNIT_CODES = { seconds = 1, laps = 2 }
local DELAY_UNIT_NAMES = { [1] = 'seconds', [2] = 'laps' }

function network.create(state)
  local sendFlagState
  local sendPenaltyMeta
  local sendPenaltyText
  local lastSyncResponseAt = {}
  local lastPenaltySyncResponseAt = {}
  local pendingPenaltyMeta = {}
  local pendingPenaltyText = {}
  local pendingPenaltyCount = 0
  local syncResponseCooldown = 3

  local function sendCurrentFieldFlag(sessionID, now)
    if not state.isAdminUnlocked() then return false end
    if sessionID == nil then return false end

    local lastResponseAt = lastSyncResponseAt[sessionID]
    if lastResponseAt ~= nil and now - lastResponseAt < syncResponseCooldown then return false end

    local flag = state.getCurrentFieldFlag()
    if not state.isControllableFieldFlag(flag) then return false end

    lastSyncResponseAt[sessionID] = now
    sendFlagState({
      protocol = 6,
      overrideActive = flag ~= state.flagNone,
      flag = flag
    }, true)
    return true
  end

  local function sendPenaltyRecord(record, repeatForNewConnections)
    if not sendPenaltyMeta or not sendPenaltyText then return false end
    local penaltyType = PENALTY_TYPE_CODES[record.type]
    local status = PENALTY_STATUS_CODES[record.status]
    local source = PENALTY_SOURCE_CODES[record.source]
    local delayUnit = DELAY_UNIT_CODES[record.delayUnit]
    if not penaltyType or not status or not source or not delayUnit then return false end

    sendPenaltyMeta({
      protocol = 1,
      action = 1,
      id = record.id,
      penaltyType = penaltyType,
      status = status,
      source = source,
      driverSessionID = record.driverSessionID,
      carIndex = record.carIndex,
      issuerSessionID = record.issuerSessionID,
      amount = record.amount,
      serveWithinLaps = record.serveWithinLaps,
      createdAt = record.createdAt,
      revision = record.revision,
      autoAfterDelay = record.autoAfterDelay,
      delayValue = record.delayValue,
      delayUnit = delayUnit,
      dueAt = record.dueAt,
      dueLap = record.dueLap
    }, repeatForNewConnections == true)

    local textFields = {
      record.driverName,
      record.cause,
      record.details,
      record.issuer
    }
    for index, value in ipairs(textFields) do
      sendPenaltyText({
        protocol = 1,
        id = record.id,
        field = index,
        text = value
      }, repeatForNewConnections == true)
    end
    return true
  end

  local function sendPenaltySnapshot(sessionID, now)
    if not state.isAdminUnlocked() or sessionID == nil then return false end
    local lastResponseAt = lastPenaltySyncResponseAt[sessionID]
    if lastResponseAt ~= nil and now - lastResponseAt < syncResponseCooldown then return false end

    lastPenaltySyncResponseAt[sessionID] = now
    for _, record in ipairs(state.getPenaltyRecords()) do
      sendPenaltyRecord(record, true)
    end
    return true
  end

  local sendBlueIgnore = ac.OnlineEvent({
    ac.StructItem.key('app.FlagControlApp.blueIgnore.v3'),
    protocol = ac.StructItem.int32(),
    sessionID = ac.StructItem.int32(),
    carIndex = ac.StructItem.int32(),
    ignored = ac.StructItem.boolean(),
    driverName = ac.StructItem.string(48)
  }, function (sender, message)
    if sender == nil or sender.index == 0 or message.protocol ~= 3 then return end
    state.applyBlueIgnore(message.driverName, message.sessionID, message.carIndex, message.ignored)
  end)

  local sendBlueClassRule = ac.OnlineEvent({
    ac.StructItem.key('app.FlagControlApp.blueClassRule.v1'),
    protocol = ac.StructItem.int32(),
    className = ac.StructItem.string(48),
    groupName = ac.StructItem.string(48),
    autoAllowed = ac.StructItem.boolean()
  }, function (sender, message)
    if sender == nil or sender.index == 0 or message.protocol ~= 1 then return end
    if message.className == '' then return end
    state.applyBlueClassRule(message.className, message.groupName, message.autoAllowed)
  end)

  local sendBlueAlert = ac.OnlineEvent({
    ac.StructItem.key('app.FlagControlApp.manualBlueAlert.v1'),
    protocol = ac.StructItem.int32(),
    active = ac.StructItem.boolean(),
    groupName = ac.StructItem.string(48)
  }, function (sender, message)
    if sender == nil or sender.index == 0 or message.protocol ~= 1 then return end
    state.applyBlueAlert(message.active, message.groupName)
  end)

  local sendPresence = ac.OnlineEvent({
    ac.StructItem.key('app.FlagControlApp.lobbyPresence.v4'),
    protocol = ac.StructItem.int32(),
    className = ac.StructItem.string(48),
    isBlueFlag = ac.StructItem.boolean(),
    blueCauseCarIndex = ac.StructItem.int32()
  }, function (sender, message)
    if sender == nil or sender.index == 0 or message.protocol ~= 4 then return end

    local sessionID = sender.sessionID
    if sessionID == nil then return end

    local name = ac.getDriverName(sender.index)
    if name == nil or name == '' then
      name = 'Driver ' .. tostring(sessionID)
    end

    local now = os.clock()
    local previousPeer = state.onlinePeers[sessionID]
    local isNewOrReconnected = previousPeer == nil or now - previousPeer.lastSeen > syncResponseCooldown

    state.onlinePeers[sessionID] = {
      carIndex = sender.index,
      name = name,
      className = message.className,
      isBlueFlag = message.isBlueFlag == true,
      blueCauseCarIndex = message.blueCauseCarIndex or -1,
      lastSeen = now
    }

    if isNewOrReconnected then
      sendCurrentFieldFlag(sessionID, now)
      sendPenaltySnapshot(sessionID, now)
    end
  end)

  sendFlagState = ac.OnlineEvent({
    ac.StructItem.key('app.FlagControlApp.fieldFlag.v6'),
    protocol = ac.StructItem.int32(),
    overrideActive = ac.StructItem.boolean(),
    flag = ac.StructItem.int32()
  }, function (sender, message)
    if sender == nil or sender.index == 0 or message.protocol ~= 6 then return end
    if not state.isControllableFieldFlag(message.flag) then return end

    state.applyFieldFlag(message.flag, message.overrideActive, ac.getDriverName(sender.index))
  end)

  local sendFieldFlagSyncRequest = ac.OnlineEvent({
    ac.StructItem.key('app.FlagControlApp.fieldFlagSyncRequest.v1'),
    protocol = ac.StructItem.int32()
  }, function (sender, message)
    if sender == nil or sender.index == 0 or message.protocol ~= 1 then return end
    if not state.isAdminUnlocked() then return end

    local sessionID = sender.sessionID
    if sessionID == nil then return end

    sendCurrentFieldFlag(sessionID, os.clock())
  end)

  local function applyPendingPenalty(id)
    local record = pendingPenaltyMeta[id]
    local text = pendingPenaltyText[id]
    if not record or not text or text[1] == nil or text[2] == nil or
       text[3] == nil or text[4] == nil then
      return
    end
    record.driverName = text[1]
    record.cause = text[2]
    record.details = text[3]
    record.issuer = text[4]
    state.applyPenaltyEvent(record)
    pendingPenaltyMeta[id] = nil
    pendingPenaltyText[id] = nil
    pendingPenaltyCount = math.max(0, pendingPenaltyCount - 1)
  end

  sendPenaltyMeta = ac.OnlineEvent({
    ac.StructItem.key('app.FlagControlApp.penaltyFeedMeta.v1'),
    protocol = ac.StructItem.int32(),
    action = ac.StructItem.int32(),
    id = ac.StructItem.string(32),
    penaltyType = ac.StructItem.int32(),
    status = ac.StructItem.int32(),
    source = ac.StructItem.int32(),
    driverSessionID = ac.StructItem.int32(),
    carIndex = ac.StructItem.int32(),
    issuerSessionID = ac.StructItem.int32(),
    amount = ac.StructItem.int32(),
    serveWithinLaps = ac.StructItem.int32(),
    createdAt = ac.StructItem.int32(),
    revision = ac.StructItem.int32(),
    autoAfterDelay = ac.StructItem.boolean(),
    delayValue = ac.StructItem.int32(),
    delayUnit = ac.StructItem.int32(),
    dueAt = ac.StructItem.int32(),
    dueLap = ac.StructItem.int32()
  }, function (sender, message)
    if sender == nil or sender.index == 0 or message.protocol ~= 1 then return end

    if message.action == 1 then
      local id = message.id
      local penaltyType = PENALTY_TYPE_NAMES[message.penaltyType]
      local status = PENALTY_STATUS_NAMES[message.status]
      local source = PENALTY_SOURCE_NAMES[message.source]
      local delayUnit = DELAY_UNIT_NAMES[message.delayUnit]
      if type(id) ~= 'string' or id == '' or not penaltyType or not status or
         not source or not delayUnit then
        return
      end
      if not pendingPenaltyMeta[id] and not pendingPenaltyText[id] then
        if pendingPenaltyCount >= 64 then return end
        pendingPenaltyCount = pendingPenaltyCount + 1
      end
      pendingPenaltyMeta[id] = {
        id = message.id,
        type = penaltyType,
        status = status,
        source = source,
        driverSessionID = message.driverSessionID,
        carIndex = message.carIndex,
        issuerSessionID = message.issuerSessionID,
        amount = message.amount,
        serveWithinLaps = message.serveWithinLaps,
        createdAt = message.createdAt,
        revision = message.revision,
        autoAfterDelay = message.autoAfterDelay,
        delayValue = message.delayValue,
        delayUnit = delayUnit,
        dueAt = message.dueAt,
        dueLap = message.dueLap
      }
      applyPendingPenalty(id)
    elseif message.action == 2 then
      local sessionID = sender.sessionID
      if sessionID ~= nil and state.isAdminUnlocked() then
        local now = os.clock()
        local lastResponseAt = lastPenaltySyncResponseAt[sessionID]
        if lastResponseAt == nil or now - lastResponseAt >= syncResponseCooldown then
          sendPenaltySnapshot(sessionID, now)
        end
      end
    end
  end)

  sendPenaltyText = ac.OnlineEvent({
    ac.StructItem.key('app.FlagControlApp.penaltyFeedText.v1'),
    protocol = ac.StructItem.int32(),
    id = ac.StructItem.string(32),
    field = ac.StructItem.int32(),
    text = ac.StructItem.string(120)
  }, function (sender, message)
    if sender == nil or sender.index == 0 or message.protocol ~= 1 then return end
    if type(message.id) ~= 'string' or message.id == '' or
       message.field < 1 or message.field > 4 or
       type(message.text) ~= 'string' then
      return
    end
    if not pendingPenaltyMeta[message.id] and not pendingPenaltyText[message.id] then
      if pendingPenaltyCount >= 64 then return end
      pendingPenaltyCount = pendingPenaltyCount + 1
    end
    pendingPenaltyText[message.id] = pendingPenaltyText[message.id] or {}
    pendingPenaltyText[message.id][message.field] = message.text
    applyPendingPenalty(message.id)
  end)

  return {
    sendBlueIgnore = sendBlueIgnore,
    sendBlueClassRule = sendBlueClassRule,
    sendBlueAlert = sendBlueAlert,
    sendPresence = sendPresence,
    sendFlagState = sendFlagState,
    sendPenaltyRecord = sendPenaltyRecord,
    requestFieldFlagSync = function ()
      return sendFieldFlagSyncRequest({ protocol = 1 }, false)
    end,
    requestPenaltySync = function ()
      return sendPenaltyMeta({
        protocol = 1,
        action = 2,
        id = '',
        penaltyType = 0,
        status = 0,
        source = 0,
        driverSessionID = -1,
        carIndex = -1,
        issuerSessionID = -1,
        amount = 0,
        serveWithinLaps = 0,
        createdAt = 0,
        revision = 0,
        autoAfterDelay = false,
        delayValue = 0,
        delayUnit = 1,
        dueAt = 0,
        dueLap = 0
      }, false)
    end
  }
end

return network
