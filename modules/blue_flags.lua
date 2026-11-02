local blueFlags = {}

function blueFlags.create(dependencies)
  local blueClassRules = {}
  local blueAlertActive = false
  local blueAlertGroup = ''
  local manualBlueDrivers = {}
  local ignoredDrivers = {}

  local function cleanString(value)
    if type(value) ~= 'string' then return '' end
    return (value:gsub('^%s*(.-)%s*$', '%1'))
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

  local function applyIgnore(driverName, sessionID, carIndex, ignored)
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
      dependencies.setOverrideState('blueIgnored', ignored == true)
      if ignored then
        pcall(physics.overrideRacingFlag, ac.FlagType.None)
      end
    end
  end

  local function publishIgnore(driverName, sessionID, carIndex, ignored)
    if not dependencies.isAdminUnlocked() then return false end
    applyIgnore(driverName, sessionID, carIndex, ignored)
    dependencies.network().sendBlueIgnore({
      protocol = 3,
      sessionID = sessionID or -1,
      carIndex = carIndex or -1,
      ignored = ignored == true,
      driverName = driverName or ''
    }, true)
    return true
  end

  local function clearAllIgnores()
    if not dependencies.isAdminUnlocked() then return false end
    local keysToRemove = {}
    for key in pairs(ignoredDrivers) do
      keysToRemove[#keysToRemove + 1] = key
    end
    for _, key in ipairs(keysToRemove) do
      ignoredDrivers[key] = nil
    end

    dependencies.setOverrideState('blueIgnored', false)
    dependencies.network().sendBlueIgnore({
      protocol = 3,
      sessionID = -1,
      carIndex = -1,
      ignored = false,
      driverName = '__ALL__'
    }, true)
    return true
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

  local function applyAlert(active, groupName)
    blueAlertActive = active == true
    blueAlertGroup = groupName or ''
    dependencies.setOverrideState('manualBlueActive', blueAlertActive)
  end

  local function publishAlert(active, groupName)
    if not dependencies.isAdminUnlocked() then return false end
    applyAlert(active, groupName)
    dependencies.network().sendBlueAlert({
      protocol = 1,
      active = blueAlertActive,
      groupName = blueAlertGroup
    }, true)
    return true
  end

  local function isManualBlueForClass(driverKey, className)
    return manualBlueDrivers[driverKey] == true or
           (blueAlertActive and className ~= '' and classKey(blueAlertGroup) == classKey(className))
  end

  local function getDriverClass(carIndex, sessionID)
    if carIndex == 0 then
      local localClass = dependencies.getLocalClassName()
      if localClass ~= '' then return localClass end
    end
    local peer = sessionID ~= nil and dependencies.onlinePeers[sessionID] or nil
    if sessionID ~= nil and peer and peer.className ~= '' then
      return peer.className
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
        local driverName = ac.getDriverName(i)
        if not driverName or driverName == '' then
          driverName = car:driverName()
          if not driverName or driverName == '' then driverName = 'Car #' .. tostring(i) end
        end

        local carName = car:name()
        if not carName or carName == '' then carName = car:id() or 'Unknown Car' end

        local sessionID = car.sessionID
        local racePosition = car.racePosition or 0
        local inPit = car.isInPitlane or car.isInPit
        local isLocal = (i == 0)
        local className = getDriverClass(i, sessionID)
        local key = getDriverKey(driverName, sessionID, i)
        local isIgnored = isDriverIgnored(driverName, sessionID, i)

        local isUnderBlue = false
        local causeText = ''
        local causeCarIndex = -1
        local gapSeconds = nil

        if isLocal and sim.raceFlagType == ac.FlagType.FasterCar then
          isUnderBlue = true
          causeCarIndex = sim.raceFlagCause or -1
          if causeCarIndex >= 0 and causeCarIndex < totalCars and causeCarIndex ~= i then
            local fasterName = ac.getDriverName(causeCarIndex) or ('Car #' .. causeCarIndex)
            local fasterCar = ac.getCar(causeCarIndex)
            local fasterPosition = fasterCar and fasterCar.racePosition and
                                   (' (P' .. fasterCar.racePosition .. ')') or ''
            causeText = 'Approached by ' .. fasterName .. fasterPosition
          else
            causeText = 'AC Blue Flag'
          end
        end

        local peer = sessionID ~= nil and dependencies.onlinePeers[sessionID] or nil
        if not isUnderBlue and sessionID ~= nil and peer and peer.isBlueFlag then
          isUnderBlue = true
          causeCarIndex = peer.blueCauseCarIndex or -1
          if causeCarIndex >= 0 and causeCarIndex < totalCars then
            local fasterName = ac.getDriverName(causeCarIndex) or ('Car #' .. causeCarIndex)
            local fasterCar = ac.getCar(causeCarIndex)
            local fasterPosition = fasterCar and fasterCar.racePosition and
                                   (' (P' .. fasterCar.racePosition .. ')') or ''
            causeText = 'Approached by ' .. fasterName .. fasterPosition
          else
            causeText = 'Peer AC Blue Flag'
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
                      local distanceM = splineDelta * trackLengthM
                      if distanceM > 0 and distanceM <= 80 then
                        local gap = distanceM / math.max(otherSpeedMs, 14)
                        if gap <= 2.2 then
                          isUnderBlue = true
                          causeCarIndex = j
                          gapSeconds = gap
                          local fasterName = ac.getDriverName(j) or ('Car #' .. j)
                          local fasterPosition = otherCar.racePosition and
                                                 (' (P' .. otherCar.racePosition .. ')') or ''
                          causeText = string.format('Lapped by %s%s [%.1fs]', fasterName, fasterPosition, gap)
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
                    local distanceM = splineDelta * trackLengthM
                    if distanceM > 0 and distanceM <= 70 then
                      local gap = distanceM / math.max(otherCar.speedMs or 0, 20)
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

        if isManualBlueForClass(key, className) then
          isUnderBlue = true
          causeText = 'Manual Race Control'
        end

        local entry = {
          carIndex = i,
          sessionID = sessionID,
          name = driverName,
          carName = carName,
          className = className,
          racePosition = racePosition,
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

  return {
    classKey = classKey,
    getDriverKey = getDriverKey,
    isDriverIgnored = isDriverIgnored,
    applyIgnore = applyIgnore,
    publishIgnore = publishIgnore,
    clearAllIgnores = clearAllIgnores,
    getBlueClassRule = getBlueClassRule,
    applyBlueClassRule = applyBlueClassRule,
    applyAlert = applyAlert,
    publishAlert = publishAlert,
    collectDriverBlueStates = collectDriverBlueStates,
    isBlueAlertActive = function () return blueAlertActive end,
    isManualBlueForClass = isManualBlueForClass
  }
end

return blueFlags
