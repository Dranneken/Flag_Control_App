local network = {}

function network.create(state)
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

    state.onlinePeers[sessionID] = {
      carIndex = sender.index,
      name = name,
      className = message.className,
      isBlueFlag = message.isBlueFlag == true,
      blueCauseCarIndex = message.blueCauseCarIndex or -1,
      lastSeen = os.clock()
    }
  end)

  local sendFlagState = ac.OnlineEvent({
    ac.StructItem.key('app.FlagControlApp.fieldFlag.v6'),
    protocol = ac.StructItem.int32(),
    overrideActive = ac.StructItem.boolean(),
    flag = ac.StructItem.int32()
  }, function (sender, message)
    if sender == nil or sender.index == 0 or message.protocol ~= 6 then return end
    if not state.isControllableFieldFlag(message.flag) then return end

    state.applyFieldFlag(message.flag, message.overrideActive, ac.getDriverName(sender.index))
  end)

  return {
    sendBlueIgnore = sendBlueIgnore,
    sendBlueClassRule = sendBlueClassRule,
    sendBlueAlert = sendBlueAlert,
    sendPresence = sendPresence,
    sendFlagState = sendFlagState
  }
end

return network
