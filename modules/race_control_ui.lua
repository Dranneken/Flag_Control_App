local raceControlUI = {}

function raceControlUI.create(dependencies)
  local fieldFlags = dependencies.fieldFlags
  local blueFlags = dependencies.blueFlags
  local colors = dependencies.colors
  local flags = dependencies.flags
  local selectedFlag = flags.yellow
  local selectedFlagExplicit = false
  local selectedBlueGroup = ''
  local flagOptions = {
    { value = flags.green, label = 'GREEN FLAG' },
    { value = flags.yellow, label = 'YELLOW FLAG' },
    { value = flags.red, label = 'RED FLAG' }
  }

  local function getFieldFlagLabel(flag)
    if flag == flags.green then return 'GREEN FLAG' end
    if flag == flags.yellow then return 'YELLOW FLAG' end
    if flag == flags.red then return 'RED FLAG' end
    return 'NO ACTIVE FLAG'
  end

  local function getFieldFlagColor(flag)
    if flag == flags.green then return rgbm(0.15, 0.78, 0.25, 1) end
    if flag == flags.yellow then return rgbm(1, 0.78, 0.08, 1) end
    if flag == flags.red then return rgbm(0.9, 0.12, 0.12, 1) end
    return rgbm(0.65, 0.65, 0.65, 1)
  end

  local function getFlagButtonColor(flag, selected)
    local color = getFieldFlagColor(flag)
    local brightness = selected and 1 or 0.55
    return rgbm(color.r * brightness, color.g * brightness, color.b * brightness, 1)
  end

  local function getFlagButtonTextColor(flag)
    if flag == flags.green or flag == flags.yellow then
      return rgbm(0.08, 0.08, 0.08, 1)
    end
    return rgbm(1, 1, 1, 1)
  end

  local function drawLobbyPeers()
    local peerNames = { (ac.getDriverName(0) or 'You') .. ' (you)' }
    for _, peer in pairs(dependencies.onlinePeers) do
      peerNames[#peerNames + 1] = peer.name
    end
    table.sort(peerNames)
    ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
    ui.text(string.format('LOBBY DRIVERS  %d', #peerNames))
    ui.popStyleColor()
    ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
    ui.textWrapped(table.concat(peerNames, ', '))
    ui.popStyleColor()
  end

  local function drawFieldFlagsTab()
    local currentFlag = fieldFlags.getFlag()
    if not selectedFlagExplicit and currentFlag ~= flags.none then
      selectedFlag = currentFlag
    end

    ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
    ui.text('CURRENT FIELD FLAG')
    ui.popStyleColor()
    ui.textColored(getFieldFlagLabel(currentFlag), getFieldFlagColor(currentFlag))
    ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
    ui.text('Last update: ' .. fieldFlags.getSenderName())
    ui.text('Lobby: ' .. dependencies.getLobbyMessageStatus())
    ui.popStyleColor()
    drawLobbyPeers()

    ui.separator()
    ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
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
        selectedFlagExplicit = true
      end
      ui.popStyleColor(2)
    end

    ui.newLine(-5)
    ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
    ui.text('SELECTED: ' .. getFieldFlagLabel(selectedFlag))
    ui.popStyleColor()

    local flagDeployed = currentFlag ~= flags.none
    local actionLabel = 'DEPLOY FLAG'
    if flagDeployed then
      actionLabel = selectedFlag == currentFlag and 'UNDEPLOY FLAG' or 'REDEPLOY FLAG'
    end
    local isUndeploy = actionLabel == 'UNDEPLOY FLAG'
    ui.pushStyleColor(ui.StyleColor.Button, isUndeploy and rgbm(0.78, 0.12, 0.1, 1) or colors.yellow)
    ui.pushStyleColor(ui.StyleColor.Text, isUndeploy and rgbm(1, 1, 1, 1) or rgbm(0.08, 0.08, 0.08, 1))
    if ui.button(actionLabel, vec2(-0.1, 38)) then
      fieldFlags.publish(isUndeploy and flags.none or selectedFlag)
    end
    ui.popStyleColor(2)

    ui.separator()
    ui.pushStyleColor(ui.StyleColor.Text, colors.yellow)
    ui.text('Field flags broadcast to all Flag Control clients in the session.')
    ui.popStyleColor()
    ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
    ui.text('App flag only; does not alter native server flag.')
    ui.popStyleColor()
  end

  local function drawDriverBlueFlagsTab()
    local activeBlueDrivers, allDrivers = blueFlags.collectDriverBlueStates()

    local ignoredCount = 0
    local activeUnignoredCount = 0
    for _, driver in ipairs(activeBlueDrivers) do
      if driver.isIgnored then
        ignoredCount = ignoredCount + 1
      else
        activeUnignoredCount = activeUnignoredCount + 1
      end
    end

    local availableWidth = ui.availableSpaceX()
    if activeUnignoredCount > 0 then
      ui.pushStyleColor(ui.StyleColor.Text, colors.blue)
      ui.text(string.format('ACTIVE BLUE FLAGS: %d', activeUnignoredCount))
      ui.popStyleColor()
    else
      ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
      ui.text('ACTIVE BLUE FLAGS: 0')
      ui.popStyleColor()
    end

    if ignoredCount > 0 then
      ui.sameLine(0, 12)
      ui.pushStyleColor(ui.StyleColor.Text, colors.ignored)
      ui.text(string.format('(%d IGNORED)', ignoredCount))
      ui.popStyleColor()
    end

    local rightButtonsWidth = 0
    if activeUnignoredCount > 0 then rightButtonsWidth = rightButtonsWidth + 140 end
    if ignoredCount > 0 then rightButtonsWidth = rightButtonsWidth + (activeUnignoredCount > 0 and 110 or 100) end

    if rightButtonsWidth > 0 then
      ui.sameLine(math.max(availableWidth - rightButtonsWidth, 200), 0)
      if activeUnignoredCount > 0 then
        ui.pushStyleColor(ui.StyleColor.Button, colors.danger)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('IGNORE ALL ACTIVE', vec2(132, 24)) then
          for _, driver in ipairs(activeBlueDrivers) do
            if not driver.isIgnored then
              blueFlags.publishIgnore(driver.name, driver.sessionID, driver.carIndex, true)
            end
          end
        end
        ui.popStyleColor(2)
      end
      if ignoredCount > 0 then
        if activeUnignoredCount > 0 then ui.sameLine(0, 8) end
        ui.pushStyleColor(ui.StyleColor.Button, colors.success)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('RESTORE ALL', vec2(96, 24)) then
          blueFlags.clearAllIgnores()
        end
        ui.popStyleColor(2)
      end
    end

    ui.separator()

    if #activeBlueDrivers == 0 then
      ui.newLine(3)
      ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
      ui.text('No drivers are currently under blue flag.')
      ui.popStyleColor()
      ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
      ui.textWrapped('Cars being lapped in a race session, receiving blue flags from AC, or alerted manually will automatically appear here with an Ignore button.')
      ui.popStyleColor()
      ui.newLine(3)
    else
      for _, driver in ipairs(activeBlueDrivers) do
        ui.separator()
        local position = driver.racePosition > 0 and
          ('P' .. tostring(driver.racePosition)) or '-'
        local driverName = driver.isLocal and (driver.name .. ' (You)') or driver.name
        if driver.isIgnored then
          ui.textColored('[IGNORED] ' .. position .. ' - ' .. driverName, colors.ignored)
        else
          ui.textColored('[BLUE] ' .. position .. ' - ' .. driverName, colors.blue)
        end

        local carLabel = driver.className ~= '' and
          (driver.carName .. ' (' .. driver.className .. ')') or driver.carName
        ui.textWrapped(carLabel)
        ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
        ui.textWrapped('Reason: ' .. driver.causeDescription)
        ui.popStyleColor()

        if driver.isIgnored then
          ui.pushStyleColor(ui.StyleColor.Button, colors.success)
          ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
          if ui.button('RESTORE##' .. driver.key, vec2(-0.1, 22)) then
            blueFlags.publishIgnore(driver.name, driver.sessionID, driver.carIndex, false)
          end
          ui.popStyleColor(2)
        else
          ui.pushStyleColor(ui.StyleColor.Button, colors.danger)
          ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
          if ui.button('IGNORE##' .. driver.key, vec2(-0.1, 22)) then
            blueFlags.publishIgnore(driver.name, driver.sessionID, driver.carIndex, true)
          end
          ui.popStyleColor(2)
        end
      end
    end

    ui.separator()

    ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
    ui.text('ALL SESSION DRIVERS (' .. tostring(#allDrivers) .. ')')
    ui.popStyleColor()
    if #allDrivers == 0 then
      ui.text('No session drivers available.')
    end
    for _, driver in ipairs(allDrivers) do
      ui.separator()
      local position = driver.racePosition > 0 and
        ('P' .. tostring(driver.racePosition)) or '-'
      local driverName = driver.isLocal and (driver.name .. ' (You)') or driver.name
      ui.textColored(position .. ' - ' .. driverName, driver.isLocal and colors.yellow or colors.settingsText)

      local carLabel = driver.className ~= '' and
        (driver.carName .. ' (' .. driver.className .. ')') or driver.carName
      ui.textWrapped(carLabel)

      if driver.isIgnored then
        ui.textColored('Ignored', colors.ignored)
      elseif driver.isUnderBlue then
        ui.textColored('Active Blue', colors.blue)
      else
        ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
        ui.text('Normal')
        ui.popStyleColor()
      end
      ui.sameLine()

      if driver.isIgnored then
        ui.pushStyleColor(ui.StyleColor.Button, colors.success)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('RESTORE##all_' .. driver.key, vec2(-0.1, 20)) then
          blueFlags.publishIgnore(driver.name, driver.sessionID, driver.carIndex, false)
        end
        ui.popStyleColor(2)
      else
        ui.pushStyleColor(ui.StyleColor.Button,
          driver.isUnderBlue and colors.danger or rgbm(0.3, 0.3, 0.3, 1))
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('IGNORE##all_' .. driver.key, vec2(-0.1, 20)) then
          blueFlags.publishIgnore(driver.name, driver.sessionID, driver.carIndex, true)
        end
        ui.popStyleColor(2)
      end
    end

    ui.separator()
    ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
    ui.text('MANUAL BLUE ALERT & CLASS OPTIONS')
    ui.popStyleColor()
    ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
    ui.textWrapped('Deploy a manual blue flag to all drivers in the selected group, or clear it.')
    ui.popStyleColor()

    local localClass = dependencies.getLocalClassName()
    if localClass ~= '' then
      ui.text('Your class tag: ' .. localClass)
    end

    local groups = {}
    local seen = {}
    for _, driver in ipairs(allDrivers) do
      local classNameKey = blueFlags.classKey(driver.className)
      if driver.className ~= '' and not seen[classNameKey] then
        seen[classNameKey] = true
        groups[#groups + 1] = driver.className
      end
    end
    table.sort(groups)

    if #groups > 0 then
      if selectedBlueGroup == '' or not seen[blueFlags.classKey(selectedBlueGroup)] then
        selectedBlueGroup = groups[1]
      end
      local comboWidth = math.min(250, ui.availableSpaceX() * 0.55)
      local buttonWidth = math.max(120, ui.availableSpaceX() - comboWidth - 10)
      ui.setNextItemWidth(comboWidth)
      ui.combo('##manual_blue_group', selectedBlueGroup, function ()
        for _, groupName in ipairs(groups) do
          if ui.selectable(groupName) then selectedBlueGroup = groupName end
        end
      end)
      ui.sameLine(0, 10)
      if ui.button(blueFlags.isBlueAlertActive() and 'CLEAR MANUAL BLUE' or
                   'DEPLOY BLUE TO GROUP', vec2(buttonWidth, 24)) then
        blueFlags.publishAlert(not blueFlags.isBlueAlertActive(), selectedBlueGroup)
      end
    else
      if ui.button(blueFlags.isBlueAlertActive() and 'CLEAR MANUAL BLUE' or
                   'DEPLOY BLUE FIELD-WIDE', vec2(math.min(220, ui.availableSpaceX()), 24)) then
        blueFlags.publishAlert(not blueFlags.isBlueAlertActive(), '')
      end
    end
  end

  local function drawTabs()
    ui.tabBar('FlagControlAdminTabs', ui.TabBarFlags.FittingPolicyScroll, function ()
      ui.tabItem('Field Flags', function ()
        drawFieldFlagsTab()
      end)
      ui.tabItem('Blue Flags', function ()
        drawDriverBlueFlagsTab()
      end)
    end)
  end

  return { drawTabs = drawTabs }
end

return raceControlUI
