local raceControlUI = {}

function raceControlUI.create(dependencies)
  local fieldFlags = dependencies.fieldFlags
  local blueFlags = dependencies.blueFlags
  local colors = dependencies.colors
  local flags = dependencies.flags
  local selectedFlag = flags.yellow
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
    ui.columns(2)
    ui.setColumnWidth(0, 220)

    ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
    ui.text('CURRENT FIELD FLAG')
    ui.popStyleColor()
    ui.textColored(getFieldFlagLabel(fieldFlags.getFlag()), getFieldFlagColor(fieldFlags.getFlag()))
    ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
    ui.text('Last update: ' .. fieldFlags.getSenderName())
    ui.text('Lobby: ' .. dependencies.getLobbyMessageStatus())
    ui.popStyleColor()
    drawLobbyPeers()

    ui.nextColumn()

    ui.newLine(-5)
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
      end
      ui.popStyleColor(2)
    end

    ui.newLine(-5)
    ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
    ui.text('SELECTED: ' .. getFieldFlagLabel(selectedFlag))
    ui.popStyleColor()

    local flagDeployed = fieldFlags.getFlag() ~= flags.none
    ui.pushStyleColor(ui.StyleColor.Button, flagDeployed and rgbm(0.78, 0.12, 0.1, 1) or colors.yellow)
    ui.pushStyleColor(ui.StyleColor.Text, flagDeployed and rgbm(1, 1, 1, 1) or rgbm(0.08, 0.08, 0.08, 1))
    if ui.button(flagDeployed and 'UNDEPLOY FLAG' or 'DEPLOY FLAG', vec2(-0.1, 38)) then
      fieldFlags.publish(flagDeployed and flags.none or selectedFlag)
    end
    ui.popStyleColor(2)
    ui.columns(1)

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
      ui.columns(6, 'BlueFlagDriversTable', true)
      ui.setColumnWidth(0, 85)
      ui.setColumnWidth(1, 46)
      ui.setColumnWidth(2, 145)
      ui.setColumnWidth(3, 140)
      ui.setColumnWidth(4, 185)

      ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
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

      for _, driver in ipairs(activeBlueDrivers) do
        if driver.isIgnored then
          ui.textColored('[IGNORED]', colors.ignored)
        else
          ui.textColored('[BLUE]', colors.blue)
        end
        ui.nextColumn()

        ui.text(driver.racePosition > 0 and ('P' .. tostring(driver.racePosition)) or '-')
        ui.nextColumn()

        if driver.isLocal then
          ui.textColored(driver.name .. ' (You)', colors.yellow)
        else
          ui.text(driver.name)
        end
        ui.nextColumn()

        local carLabel = driver.className ~= '' and
                         (driver.carName .. ' (' .. driver.className .. ')') or driver.carName
        ui.text(carLabel)
        ui.nextColumn()

        ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
        ui.text(driver.causeDescription)
        ui.popStyleColor()
        ui.nextColumn()

        if driver.isIgnored then
          ui.pushStyleColor(ui.StyleColor.Button, colors.success)
          ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
          if ui.button('RESTORE##' .. driver.key, vec2(ui.availableSpaceX(), 22)) then
            blueFlags.publishIgnore(driver.name, driver.sessionID, driver.carIndex, false)
          end
          ui.popStyleColor(2)
        else
          ui.pushStyleColor(ui.StyleColor.Button, colors.danger)
          ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
          if ui.button('IGNORE##' .. driver.key, vec2(ui.availableSpaceX(), 22)) then
            blueFlags.publishIgnore(driver.name, driver.sessionID, driver.carIndex, true)
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

      ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
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

      for _, driver in ipairs(allDrivers) do
        ui.text(driver.racePosition > 0 and ('P' .. tostring(driver.racePosition)) or '-')
        ui.nextColumn()

        if driver.isLocal then
          ui.textColored(driver.name .. ' (You)', colors.yellow)
        else
          ui.text(driver.name)
        end
        ui.nextColumn()

        local carLabel = driver.className ~= '' and
                         (driver.carName .. ' (' .. driver.className .. ')') or driver.carName
        ui.text(carLabel)
        ui.nextColumn()

        if driver.isIgnored then
          ui.textColored('Ignored', colors.ignored)
        elseif driver.isUnderBlue then
          ui.textColored('Active Blue', colors.blue)
        else
          ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
          ui.text('Normal')
          ui.popStyleColor()
        end
        ui.nextColumn()

        if driver.isIgnored then
          ui.pushStyleColor(ui.StyleColor.Button, colors.success)
          ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
          if ui.button('RESTORE##all_' .. driver.key, vec2(ui.availableSpaceX(), 20)) then
            blueFlags.publishIgnore(driver.name, driver.sessionID, driver.carIndex, false)
          end
          ui.popStyleColor(2)
        else
          ui.pushStyleColor(ui.StyleColor.Button,
            driver.isUnderBlue and colors.danger or rgbm(0.3, 0.3, 0.3, 1))
          ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
          if ui.button('IGNORE##all_' .. driver.key, vec2(ui.availableSpaceX(), 20)) then
            blueFlags.publishIgnore(driver.name, driver.sessionID, driver.carIndex, true)
          end
          ui.popStyleColor(2)
        end
        ui.nextColumn()
      end
      ui.columns(1)
      ui.treePop()
    end

    if ui.treeNode('Manual Blue Alert & Class Options###manual_blue_node') then
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
        ui.setNextItemWidth(250)
        ui.combo('##manual_blue_group', selectedBlueGroup, function ()
          for _, groupName in ipairs(groups) do
            if ui.selectable(groupName) then selectedBlueGroup = groupName end
          end
        end)
        ui.sameLine(0, 10)
        if ui.button(blueFlags.isBlueAlertActive() and 'CLEAR MANUAL BLUE' or
                     'DEPLOY BLUE TO GROUP', vec2(200, 24)) then
          blueFlags.publishAlert(not blueFlags.isBlueAlertActive(), selectedBlueGroup)
        end
      else
        if ui.button(blueFlags.isBlueAlertActive() and 'CLEAR MANUAL BLUE' or
                     'DEPLOY BLUE FIELD-WIDE', vec2(220, 24)) then
          blueFlags.publishAlert(not blueFlags.isBlueAlertActive(), '')
        end
      end
      ui.treePop()
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
