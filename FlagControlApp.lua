local FLAG_NONE = 0
local FLAG_GREEN = 1
local FLAG_YELLOW = 2
local FLAG_RED = 6

local CONTROLLABLE_FLAGS = {
  [FLAG_GREEN] = true,
  [FLAG_YELLOW] = true,
  [FLAG_RED] = true
}

local function isControllableFieldFlag(flag)
  return flag == FLAG_NONE or CONTROLLABLE_FLAGS[flag] == true
end

local CMRT_YELLOW = rgbm(1, 228 / 255, 0, 1)
local CMRT_SETTINGS_TEXT = rgbm(180 / 255, 180 / 255, 180 / 255, 1)
local CMRT_MUTED_TEXT = rgbm(209 / 255, 209 / 255, 209 / 255, 0.72)
local FLAG_BLUE_COLOR = rgbm(0.2, 0.62, 1.0, 1)
local IGNORED_COLOR = rgbm(0.95, 0.65, 0.2, 1)
local DANGER_RED = rgbm(0.85, 0.2, 0.15, 1)
local SUCCESS_GREEN = rgbm(0.18, 0.65, 0.25, 1)

local fieldFlag = FLAG_NONE
local selectedFlag = FLAG_YELLOW
local blueClassRules = {}
local blueAlertActive = false
local blueAlertGroup = ''
local selectedBlueGroup = ''
local manualBlueDrivers = {}
local ignoredDrivers = {}

local cmrtOverrideState = ac.connect({
  ac.StructItem.key('app.FlagControlApp.cmrtOverride.v3'),
  active = ac.StructItem.boolean(),
  flag = ac.StructItem.int32(),
  className = ac.StructItem.string(48),
  autoBlueFilterConfigured = ac.StructItem.boolean(),
  autoBlueFilterEnabled = ac.StructItem.boolean(),
  blueIgnored = ac.StructItem.boolean(),
  manualBlueActive = ac.StructItem.boolean()
}, false, ac.SharedNamespace.Shared)

cmrtOverrideState.active = false
cmrtOverrideState.flag = FLAG_NONE
cmrtOverrideState.blueIgnored = false
cmrtOverrideState.manualBlueActive = false

local flagSenderName = 'No flag update received'
local onlinePeers = {}
local presenceTimer = 0
local lobbyMessageStatus = 'Join an online lobby to discover peers'

local function cleanString(s)
  if type(s) ~= 'string' then return '' end
  return (s:gsub('^%s*(.-)%s*$', '%1'))
end

local function classKey(className)
  return cleanString(className):lower()
end

local function getDriverKey(driverName, sessionID, carIndex)
  local name = classKey(driverName)
  local sId = sessionID ~= nil and tostring(sessionID) or ''
  local cIdx = carIndex ~= nil and tostring(carIndex) or '0'
  return sId .. ':' .. cIdx .. ':' .. name
end

local function isDriverIgnored(driverName, sessionID, carIndex)
  local key = getDriverKey(driverName, sessionID, carIndex)
  if ignoredDrivers[key] == true then return true end

  local name = classKey(driverName)
  if name ~= '' and ignoredDrivers['name:' .. name] == true then return true end

  if sessionID ~= nil and sessionID >= 0 and ignoredDrivers['s:' .. tostring(sessionID)] == true then
    return true
  end

  return false
end

local function applyBlueIgnore(driverName, sessionID, carIndex, ignored)
  local key = getDriverKey(driverName, sessionID, carIndex)
  local name = classKey(driverName)
  local sId = sessionID ~= nil and tostring(sessionID) or ''

  if ignored then
    ignoredDrivers[key] = true
    if name ~= '' then ignoredDrivers['name:' .. name] = true end
    if sId ~= '' then ignoredDrivers['s:' .. sId] = true end
  else
    ignoredDrivers[key] = nil
    if name ~= '' then ignoredDrivers['name:' .. name] = nil end
    if sId ~= '' then ignoredDrivers['s:' .. sId] = nil end
  end

  local localName = classKey(ac.getDriverName(0) or '')
  local localCar = ac.getCar(0)
  local localSessionID = localCar and localCar.sessionID or -1
  local isLocal = (carIndex == 0) or
                  (sessionID ~= nil and sessionID >= 0 and sessionID == localSessionID) or
                  (name ~= '' and name == localName)

  if isLocal then
    cmrtOverrideState.blueIgnored = ignored == true
    if ignored then
      pcall(physics.overrideRacingFlag, ac.FlagType.None)
    end
  end
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
  applyBlueIgnore(message.driverName, message.sessionID, message.carIndex, message.ignored)
end)

local function publishBlueIgnore(driverName, sessionID, carIndex, ignored)
  applyBlueIgnore(driverName, sessionID, carIndex, ignored)
  sendBlueIgnore({
    protocol = 3,
    sessionID = sessionID or -1,
    carIndex = carIndex or -1,
    ignored = ignored == true,
    driverName = driverName or ''
  }, true)
end

local function clearAllIgnores()
  local keysToRemove = {}
  for k in pairs(ignoredDrivers) do
    keysToRemove[#keysToRemove + 1] = k
  end
  for _, k in ipairs(keysToRemove) do
    ignoredDrivers[k] = nil
  end

  cmrtOverrideState.blueIgnored = false
  sendBlueIgnore({
    protocol = 3,
    sessionID = -1,
    carIndex = -1,
    ignored = false,
    driverName = '__ALL__'
  }, true)
end

local function getBlueClassRule(className)
  local key = classKey(className)
  if key == '' then return nil end

  local rule = blueClassRules[key]
  if rule then return rule end

  local storedGroup = ac.storage('FlagControl.BlueGroup.' .. key, className):get()
  local storedAutoBlue = ac.storage('FlagControl.BlueAuto.' .. key, true):get()
  rule = {
    className = className,
    groupName = storedGroup,
    autoAllowed = storedAutoBlue
  }
  blueClassRules[key] = rule
  return rule
end

local function applyBlueClassRule(className, groupName, autoAllowed)
  local key = classKey(className)
  if key == '' then return end
  groupName = type(groupName) == 'string' and groupName or ''
  autoAllowed = autoAllowed == true
  blueClassRules[key] = {
    className = className,
    groupName = groupName,
    autoAllowed = autoAllowed
  }
  ac.storage('FlagControl.BlueGroup.' .. key, groupName):set(groupName)
  ac.storage('FlagControl.BlueAuto.' .. key, autoAllowed):set(autoAllowed)
end

local sendBlueClassRule = ac.OnlineEvent({
  ac.StructItem.key('app.FlagControlApp.blueClassRule.v1'),
  protocol = ac.StructItem.int32(),
  className = ac.StructItem.string(48),
  groupName = ac.StructItem.string(48),
  autoAllowed = ac.StructItem.boolean()
}, function (sender, message)
  if sender == nil or sender.index == 0 or message.protocol ~= 1 then return end
  if message.className == '' then return end
  applyBlueClassRule(message.className, message.groupName, message.autoAllowed)
end)

local sendBlueAlert = ac.OnlineEvent({
  ac.StructItem.key('app.FlagControlApp.manualBlueAlert.v1'),
  protocol = ac.StructItem.int32(),
  active = ac.StructItem.boolean(),
  groupName = ac.StructItem.string(48)
}, function (sender, message)
  if sender == nil or sender.index == 0 or message.protocol ~= 1 then return end
  blueAlertActive = message.active
  blueAlertGroup = message.groupName
  cmrtOverrideState.manualBlueActive = message.active
end)

local function publishBlueAlert(active, groupName)
  blueAlertActive = active == true
  blueAlertGroup = groupName or ''
  cmrtOverrideState.manualBlueActive = blueAlertActive
  sendBlueAlert({ protocol = 1, active = blueAlertActive, groupName = blueAlertGroup }, true)
end

local flagOptions = {
  { value = FLAG_GREEN, label = 'GREEN FLAG' },
  { value = FLAG_YELLOW, label = 'YELLOW FLAG' },
  { value = FLAG_RED, label = 'RED FLAG' }
}

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

  onlinePeers[sessionID] = {
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
  if not isControllableFieldFlag(message.flag) then return end

  fieldFlag = message.flag
  cmrtOverrideState.active = message.overrideActive
  cmrtOverrideState.flag = message.flag
  flagSenderName = ac.getDriverName(sender.index) or 'Lobby member'
end)

local function publishFlag(flag)
  if not isControllableFieldFlag(flag) then return end
  fieldFlag = flag
  local overrideActive = flag ~= FLAG_NONE
  cmrtOverrideState.active = overrideActive
  cmrtOverrideState.flag = flag
  flagSenderName = 'You'
  sendFlagState({ protocol = 6, overrideActive = overrideActive, flag = flag }, true)
end

function script.update(dt)
  local sim = ac.getSim()

  local localCar = ac.getCar(0)
  local localName = ac.getDriverName(0) or ''
  local localSessionID = localCar and localCar.sessionID or -1
  local isLocalIgnored = isDriverIgnored(localName, localSessionID, 0)
  cmrtOverrideState.blueIgnored = isLocalIgnored

  local isLocalUnderBlue = sim.raceFlagType == ac.FlagType.FasterCar
  if isLocalIgnored and isLocalUnderBlue then
    pcall(physics.overrideRacingFlag, ac.FlagType.None)
  end

  if not sim.isOnlineRace then
    lobbyMessageStatus = 'Singleplayer / Offline Session'
    presenceTimer = 0
    for sessionID in pairs(onlinePeers) do
      onlinePeers[sessionID] = nil
    end
    return
  end

  lobbyMessageStatus = sim.directMessagingAvailable and 'Online messaging available' or 'Using AC compatibility messaging'

  presenceTimer = presenceTimer + dt
  if presenceTimer >= 2 then
    presenceTimer = 0
    sendPresence({
      protocol = 4,
      className = cmrtOverrideState.className or '',
      isBlueFlag = isLocalUnderBlue,
      blueCauseCarIndex = sim.raceFlagCause or -1
    })
  end

  local now = os.clock()
  for sessionID, peer in pairs(onlinePeers) do
    if now - peer.lastSeen > 7 then
      onlinePeers[sessionID] = nil
    end
  end
end

local function getFieldFlagLabel(flag)
  if flag == FLAG_GREEN then return 'GREEN FLAG' end
  if flag == FLAG_YELLOW then return 'YELLOW FLAG' end
  if flag == FLAG_RED then return 'RED FLAG' end
  return 'NO ACTIVE FLAG'
end

local function getFieldFlagColor(flag)
  if flag == FLAG_GREEN then return rgbm(0.15, 0.78, 0.25, 1) end
  if flag == FLAG_YELLOW then return rgbm(1, 0.78, 0.08, 1) end
  if flag == FLAG_RED then return rgbm(0.9, 0.12, 0.12, 1) end
  return rgbm(0.65, 0.65, 0.65, 1)
end

local function getFlagButtonColor(flag, selected)
  local color = getFieldFlagColor(flag)
  local brightness = selected and 1 or 0.55
  return rgbm(color.r * brightness, color.g * brightness, color.b * brightness, 1)
end

local function getFlagButtonTextColor(flag)
  if flag == FLAG_GREEN or flag == FLAG_YELLOW then
    return rgbm(0.08, 0.08, 0.08, 1)
  end
  return rgbm(1, 1, 1, 1)
end

local function getDriverClass(carIndex, sessionID)
  if carIndex == 0 and cmrtOverrideState.className ~= '' then
    return cmrtOverrideState.className
  end
  if sessionID ~= nil and onlinePeers[sessionID] and onlinePeers[sessionID].className ~= '' then
    return onlinePeers[sessionID].className
  end
  return ''
end

local function collectDriverBlueStates()
  local sim = ac.getSim()
  local trackLengthM = math.max(sim.trackLengthM or 1, 1)
  local totalCars = sim.carsCount or 0
  local allDrivers = {}
  local activeBlueDrivers = {}

  for i = 0, totalCars - 1 do
    local car = ac.getCar(i)
    if car and car.isConnected and car.isActive then
      local dName = ac.getDriverName(i)
      if not dName or dName == '' then
        dName = car:driverName()
        if not dName or dName == '' then dName = 'Car #' .. tostring(i) end
      end

      local cName = car:name()
      if not cName or cName == '' then cName = car:id() or 'Unknown Car' end

      local sID = car.sessionID
      local racePos = car.racePosition or 0
      local inPit = car.isInPitlane or car.isInPit
      local isLocal = (i == 0)
      local className = getDriverClass(i, sID)
      local key = getDriverKey(dName, sID, i)
      local isIgnored = isDriverIgnored(dName, sID, i)

      local isUnderBlue = false
      local causeText = ''
      local causeCarIndex = -1
      local gapSeconds = nil

      if isLocal then
        if sim.raceFlagType == ac.FlagType.FasterCar then
          isUnderBlue = true
          causeCarIndex = sim.raceFlagCause or -1
          if causeCarIndex >= 0 and causeCarIndex < totalCars and causeCarIndex ~= i then
            local fasterName = ac.getDriverName(causeCarIndex) or ('Car #' .. causeCarIndex)
            local fasterCar = ac.getCar(causeCarIndex)
            local fasterPos = fasterCar and fasterCar.racePosition and (' (P' .. fasterCar.racePosition .. ')') or ''
            causeText = 'Approached by ' .. fasterName .. fasterPos
          else
            causeText = 'AC Blue Flag'
          end
        end
      end

      if not isUnderBlue and sID ~= nil and onlinePeers[sID] then
        local peer = onlinePeers[sID]
        if peer.isBlueFlag then
          isUnderBlue = true
          causeCarIndex = peer.blueCauseCarIndex or -1
          if causeCarIndex >= 0 and causeCarIndex < totalCars then
            local fasterName = ac.getDriverName(causeCarIndex) or ('Car #' .. causeCarIndex)
            local fasterCar = ac.getCar(causeCarIndex)
            local fasterPos = fasterCar and fasterCar.racePosition and (' (P' .. fasterCar.racePosition .. ')') or ''
            causeText = 'Approached by ' .. fasterName .. fasterPos
          else
            causeText = 'Peer AC Blue Flag'
          end
        end
      end

      if not isUnderBlue and not inPit and trackLengthM > 100 then
        if sim.raceSessionType == ac.SessionType.Race then
          for j = 0, totalCars - 1 do
            if j ~= i then
              local otherCar = ac.getCar(j)
              if otherCar and otherCar.isConnected and otherCar.isActive and not otherCar.isInPitlane then
                local otherSpeedMs = otherCar.speedMs or 0
                if otherSpeedMs > 8 then
                  local isLapping = false
                  local otherLaps = otherCar.sessionLapCount or otherCar.lapCount or 0
                  local myLaps = car.sessionLapCount or car.lapCount or 0
                  if otherLaps > myLaps then
                    isLapping = true
                  elseif (otherCar.drivenInRace or 0) - (car.drivenInRace or 0) > trackLengthM * 0.45 then
                    isLapping = true
                  end

                  if isLapping then
                    local mySpline = car.splinePosition or 0
                    local otherSpline = otherCar.splinePosition or 0
                    local splineDelta = (mySpline - otherSpline) % 1.0
                    local distM = splineDelta * trackLengthM
                    if distM > 0 and distM <= 80 then
                      local gap = distM / math.max(otherSpeedMs, 14)
                      if gap <= 2.2 then
                        isUnderBlue = true
                        causeCarIndex = j
                        gapSeconds = gap
                        local fasterName = ac.getDriverName(j) or ('Car #' .. j)
                        local fasterPos = otherCar.racePosition and (' (P' .. otherCar.racePosition .. ')') or ''
                        causeText = string.format('Lapped by %s%s [%.1fs]', fasterName, fasterPos, gap)
                        break
                      end
                    end
                  end
                end
              end
            end
          end
        elseif (car.speedKmh or 0) < 110 and (car.lapCount or 0) == 0 then
          for j = 0, totalCars - 1 do
            if j ~= i then
              local otherCar = ac.getCar(j)
              if otherCar and otherCar.isConnected and otherCar.isActive and not otherCar.isInPitlane then
                if (otherCar.speedKmh or 0) > 130 and otherCar.isLapValid then
                  local splineDelta = ((car.splinePosition or 0) - (otherCar.splinePosition or 0)) % 1.0
                  local distM = splineDelta * trackLengthM
                  if distM > 0 and distM <= 70 then
                    local gap = distM / math.max(otherCar.speedMs or 0, 20)
                    if gap <= 2.0 then
                      isUnderBlue = true
                      causeCarIndex = j
                      gapSeconds = gap
                      local fasterName = ac.getDriverName(j) or ('Car #' .. j)
                      causeText = string.format('Fast Traffic: %s [%.1fs]', fasterName, gap)
                      break
                    end
                  end
                end
              end
            end
          end
        end
      end

      if manualBlueDrivers[key] == true or
         (blueAlertActive and className ~= '' and classKey(blueAlertGroup) == classKey(className)) then
        isUnderBlue = true
        causeText = 'Manual Race Control'
      end

      local entry = {
        carIndex = i,
        sessionID = sID,
        name = dName,
        carName = cName,
        className = className,
        racePosition = racePos,
        isLocal = isLocal,
        isUnderBlue = isUnderBlue,
        isIgnored = isIgnored,
        causeDescription = causeText ~= '' and causeText or 'Blue Flag',
        causeCarIndex = causeCarIndex,
        gapSeconds = gapSeconds,
        key = key
      }

      allDrivers[#allDrivers + 1] = entry
      if isUnderBlue or isIgnored then
        activeBlueDrivers[#activeBlueDrivers + 1] = entry
      end
    end
  end

  table.sort(allDrivers, function (a, b)
    if a.racePosition > 0 and b.racePosition > 0 then
      return a.racePosition < b.racePosition
    end
    return a.carIndex < b.carIndex
  end)

  table.sort(activeBlueDrivers, function (a, b)
    if a.isUnderBlue ~= b.isUnderBlue then
      return a.isUnderBlue and not b.isUnderBlue
    end
    if a.racePosition > 0 and b.racePosition > 0 then
      return a.racePosition < b.racePosition
    end
    return a.carIndex < b.carIndex
  end)

  return activeBlueDrivers, allDrivers
end

local function drawLobbyPeers()
  local peerNames = { (ac.getDriverName(0) or 'You') .. ' (you)' }
  for _, peer in pairs(onlinePeers) do
    peerNames[#peerNames + 1] = peer.name
  end
  table.sort(peerNames)
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_SETTINGS_TEXT)
  ui.text(string.format('LOBBY DRIVERS  %d', #peerNames))
  ui.popStyleColor()
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_MUTED_TEXT)
  ui.textWrapped(table.concat(peerNames, ', '))
  ui.popStyleColor()
end

local function drawFieldFlagsTab()
  ui.columns(2)
  ui.setColumnWidth(0, 220)

  ui.pushStyleColor(ui.StyleColor.Text, CMRT_SETTINGS_TEXT)
  ui.text('CURRENT FIELD FLAG')
  ui.popStyleColor()
  ui.textColored(getFieldFlagLabel(fieldFlag), getFieldFlagColor(fieldFlag))
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_MUTED_TEXT)
  ui.text('Last update: ' .. flagSenderName)
  ui.text('Lobby: ' .. lobbyMessageStatus)
  ui.popStyleColor()
  drawLobbyPeers()

  ui.nextColumn()

  ui.newLine(-5)
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_SETTINGS_TEXT)
  ui.text('SELECT FLAG')
  ui.popStyleColor()
  local buttonWidth = (ui.availableSpaceX() - 8) / 2
  for index, option in ipairs(flagOptions) do
    if index % 2 == 0 then
      ui.sameLine(0, 8)
    end
    local isSelected = selectedFlag == option.value
    ui.pushStyleColor(ui.StyleColor.Button, getFlagButtonColor(option.value, isSelected))
    ui.pushStyleColor(ui.StyleColor.Text, getFlagButtonTextColor(option.value))
    if ui.button(option.label, vec2(buttonWidth, 30)) then
      selectedFlag = option.value
    end
    ui.popStyleColor(2)
  end

  ui.newLine(-5)
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_SETTINGS_TEXT)
  ui.text('SELECTED: ' .. getFieldFlagLabel(selectedFlag))
  ui.popStyleColor()

  local flagDeployed = fieldFlag ~= FLAG_NONE
  ui.pushStyleColor(ui.StyleColor.Button, flagDeployed and rgbm(0.78, 0.12, 0.1, 1) or CMRT_YELLOW)
  ui.pushStyleColor(ui.StyleColor.Text, flagDeployed and rgbm(1, 1, 1, 1) or rgbm(0.08, 0.08, 0.08, 1))
  if ui.button(flagDeployed and 'UNDEPLOY FLAG' or 'DEPLOY FLAG', vec2(-0.1, 38)) then
    publishFlag(flagDeployed and FLAG_NONE or selectedFlag)
  end
  ui.popStyleColor(2)
  ui.columns(1)

  ui.separator()
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_YELLOW)
  ui.text('Field flags broadcast to all Flag Control clients in the session.')
  ui.popStyleColor()
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_MUTED_TEXT)
  ui.text('App flag only; does not alter native server flag.')
  ui.popStyleColor()
end

local function drawDriverBlueFlagsTab()
  local activeBlueDrivers, allDrivers = collectDriverBlueStates()

  local ignoredCount = 0
  local activeUnignoredCount = 0
  for _, d in ipairs(activeBlueDrivers) do
    if d.isIgnored then
      ignoredCount = ignoredCount + 1
    else
      activeUnignoredCount = activeUnignoredCount + 1
    end
  end

  local availW = ui.availableSpaceX()
  if activeUnignoredCount > 0 then
    ui.pushStyleColor(ui.StyleColor.Text, FLAG_BLUE_COLOR)
    ui.text(string.format('ACTIVE BLUE FLAGS: %d', activeUnignoredCount))
    ui.popStyleColor()
  else
    ui.pushStyleColor(ui.StyleColor.Text, CMRT_SETTINGS_TEXT)
    ui.text('ACTIVE BLUE FLAGS: 0')
    ui.popStyleColor()
  end

  if ignoredCount > 0 then
    ui.sameLine(0, 12)
    ui.pushStyleColor(ui.StyleColor.Text, IGNORED_COLOR)
    ui.text(string.format('(%d IGNORED)', ignoredCount))
    ui.popStyleColor()
  end

  local rightButtonsWidth = 0
  if activeUnignoredCount > 0 then rightButtonsWidth = rightButtonsWidth + 140 end
  if ignoredCount > 0 then rightButtonsWidth = rightButtonsWidth + (activeUnignoredCount > 0 and 110 or 100) end

  if rightButtonsWidth > 0 then
    ui.sameLine(math.max(availW - rightButtonsWidth, 200), 0)
    if activeUnignoredCount > 0 then
      ui.pushStyleColor(ui.StyleColor.Button, DANGER_RED)
      ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
      if ui.button('IGNORE ALL ACTIVE', vec2(132, 24)) then
        for _, d in ipairs(activeBlueDrivers) do
          if not d.isIgnored then
            publishBlueIgnore(d.name, d.sessionID, d.carIndex, true)
          end
        end
      end
      ui.popStyleColor(2)
    end
    if ignoredCount > 0 then
      if activeUnignoredCount > 0 then ui.sameLine(0, 8) end
      ui.pushStyleColor(ui.StyleColor.Button, SUCCESS_GREEN)
      ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
      if ui.button('RESTORE ALL', vec2(96, 24)) then
        clearAllIgnores()
      end
      ui.popStyleColor(2)
    end
  end

  ui.separator()

  if #activeBlueDrivers == 0 then
    ui.newLine(3)
    ui.pushStyleColor(ui.StyleColor.Text, CMRT_SETTINGS_TEXT)
    ui.text('No drivers are currently under blue flag.')
    ui.popStyleColor()
    ui.pushStyleColor(ui.StyleColor.Text, CMRT_MUTED_TEXT)
    ui.textWrapped('Cars being lapped in a race session, receiving blue flags from AC, or alerted manually will automatically appear here with an Ignore button.')
    ui.popStyleColor()
    ui.newLine(3)
  else
    ui.columns(6, 'BlueFlagDriversTable', true)
    ui.setColumnWidth(0, 85)
    ui.setColumnWidth(1, 46)
    ui.setColumnWidth(2, 145)
    ui.setColumnWidth(3, 140)
    ui.setColumnWidth(4, 185)

    ui.pushStyleColor(ui.StyleColor.Text, CMRT_SETTINGS_TEXT)
    ui.text('STATUS')
    ui.nextColumn()
    ui.text('POS')
    ui.nextColumn()
    ui.text('DRIVER')
    ui.nextColumn()
    ui.text('CAR / CLASS')
    ui.nextColumn()
    ui.text('APPROACHING / REASON')
    ui.nextColumn()
    ui.text('ACTION')
    ui.popStyleColor()
    ui.nextColumn()

    for _, d in ipairs(activeBlueDrivers) do
      if d.isIgnored then
        ui.textColored('[IGNORED]', IGNORED_COLOR)
      else
        ui.textColored('[BLUE]', FLAG_BLUE_COLOR)
      end
      ui.nextColumn()

      ui.text(d.racePosition > 0 and ('P' .. tostring(d.racePosition)) or '-')
      ui.nextColumn()

      if d.isLocal then
        ui.textColored(d.name .. ' (You)', CMRT_YELLOW)
      else
        ui.text(d.name)
      end
      ui.nextColumn()

      local carLabel = d.className ~= '' and (d.carName .. ' (' .. d.className .. ')') or d.carName
      ui.text(carLabel)
      ui.nextColumn()

      ui.pushStyleColor(ui.StyleColor.Text, CMRT_MUTED_TEXT)
      ui.text(d.causeDescription)
      ui.popStyleColor()
      ui.nextColumn()

      if d.isIgnored then
        ui.pushStyleColor(ui.StyleColor.Button, SUCCESS_GREEN)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('RESTORE##' .. d.key, vec2(ui.availableSpaceX(), 22)) then
          publishBlueIgnore(d.name, d.sessionID, d.carIndex, false)
        end
        ui.popStyleColor(2)
      else
        ui.pushStyleColor(ui.StyleColor.Button, DANGER_RED)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('IGNORE##' .. d.key, vec2(ui.availableSpaceX(), 22)) then
          publishBlueIgnore(d.name, d.sessionID, d.carIndex, true)
        end
        ui.popStyleColor(2)
      end
      ui.nextColumn()
    end
    ui.columns(1)
  end

  ui.separator()

  if ui.treeNode('All Session Drivers (' .. tostring(#allDrivers) .. ')###all_drivers_node') then
    ui.columns(5, 'AllDriversTable', true)
    ui.setColumnWidth(0, 46)
    ui.setColumnWidth(1, 175)
    ui.setColumnWidth(2, 175)
    ui.setColumnWidth(3, 110)

    ui.pushStyleColor(ui.StyleColor.Text, CMRT_SETTINGS_TEXT)
    ui.text('POS')
    ui.nextColumn()
    ui.text('DRIVER')
    ui.nextColumn()
    ui.text('CAR / CLASS')
    ui.nextColumn()
    ui.text('BLUE STATE')
    ui.nextColumn()
    ui.text('ACTION')
    ui.popStyleColor()
    ui.nextColumn()

    for _, d in ipairs(allDrivers) do
      ui.text(d.racePosition > 0 and ('P' .. tostring(d.racePosition)) or '-')
      ui.nextColumn()

      if d.isLocal then
        ui.textColored(d.name .. ' (You)', CMRT_YELLOW)
      else
        ui.text(d.name)
      end
      ui.nextColumn()

      local carLabel = d.className ~= '' and (d.carName .. ' (' .. d.className .. ')') or d.carName
      ui.text(carLabel)
      ui.nextColumn()

      if d.isIgnored then
        ui.textColored('Ignored', IGNORED_COLOR)
      elseif d.isUnderBlue then
        ui.textColored('Active Blue', FLAG_BLUE_COLOR)
      else
        ui.pushStyleColor(ui.StyleColor.Text, CMRT_MUTED_TEXT)
        ui.text('Normal')
        ui.popStyleColor()
      end
      ui.nextColumn()

      if d.isIgnored then
        ui.pushStyleColor(ui.StyleColor.Button, SUCCESS_GREEN)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('RESTORE##all_' .. d.key, vec2(ui.availableSpaceX(), 20)) then
          publishBlueIgnore(d.name, d.sessionID, d.carIndex, false)
        end
        ui.popStyleColor(2)
      else
        ui.pushStyleColor(ui.StyleColor.Button, d.isUnderBlue and DANGER_RED or rgbm(0.3, 0.3, 0.3, 1))
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('IGNORE##all_' .. d.key, vec2(ui.availableSpaceX(), 20)) then
          publishBlueIgnore(d.name, d.sessionID, d.carIndex, true)
        end
        ui.popStyleColor(2)
      end
      ui.nextColumn()
    end
    ui.columns(1)
    ui.treePop()
  end

  if ui.treeNode('Manual Blue Alert & Class Options###manual_blue_node') then
    ui.pushStyleColor(ui.StyleColor.Text, CMRT_MUTED_TEXT)
    ui.textWrapped('Deploy a manual blue flag to all drivers in the selected group, or clear it.')
    ui.popStyleColor()

    local localClass = cmrtOverrideState.className or ''
    if localClass ~= '' then
      ui.text('Your class tag: ' .. localClass)
    end

    local groups = {}
    local seen = {}
    for _, d in ipairs(allDrivers) do
      if d.className ~= '' and not seen[classKey(d.className)] then
        seen[classKey(d.className)] = true
        groups[#groups + 1] = d.className
      end
    end
    table.sort(groups)

    if #groups > 0 then
      if selectedBlueGroup == '' or not seen[classKey(selectedBlueGroup)] then
        selectedBlueGroup = groups[1]
      end
      ui.setNextItemWidth(250)
      ui.combo('##manual_blue_group', selectedBlueGroup, function ()
        for _, g in ipairs(groups) do
          if ui.selectable(g) then selectedBlueGroup = g end
        end
      end)
      ui.sameLine(0, 10)
      if ui.button(blueAlertActive and 'CLEAR MANUAL BLUE' or 'DEPLOY BLUE TO GROUP', vec2(200, 24)) then
        publishBlueAlert(not blueAlertActive, selectedBlueGroup)
      end
    else
      if ui.button(blueAlertActive and 'CLEAR MANUAL BLUE' or 'DEPLOY BLUE FIELD-WIDE', vec2(220, 24)) then
        publishBlueAlert(not blueAlertActive, '')
      end
    end
    ui.treePop()
  end
end

function script.windowAdmin(dt)
  ui.setNextTextBold()
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_YELLOW)
  ui.header('RACE CONTROL')
  ui.popStyleColor()
  ui.separator()

  ui.tabBar('FlagControlAdminTabs', ui.TabBarFlags.FittingPolicyScroll, function ()
    ui.tabItem('Field Flags', function ()
      drawFieldFlagsTab()
    end)
    ui.tabItem('Blue Flags', function ()
      drawDriverBlueFlagsTab()
    end)
  end)
end