local FLAG_NONE = 0
local FLAG_GREEN = 1
local FLAG_YELLOW = 2
local FLAG_RED = 6

local FCA_YELLOW = rgbm(1, 228 / 255, 0, 1)
local FCA_SETTINGS_TEXT = rgbm(180 / 255, 180 / 255, 180 / 255, 1)
local FCA_MUTED_TEXT = rgbm(209 / 255, 209 / 255, 209 / 255, 0.72)
local FLAG_BLUE_COLOR = rgbm(0.2, 0.62, 1.0, 1)
local IGNORED_COLOR = rgbm(0.95, 0.65, 0.2, 1)
local DANGER_RED = rgbm(0.85, 0.2, 0.15, 1)
local SUCCESS_GREEN = rgbm(0.18, 0.65, 0.25, 1)

-- Admin state
local isAdminUnlocked = false         -- true once authenticated this session
local loginPassword = ''              -- ephemeral password input buffer
local loginError = ''                 -- error message shown inside the dialog
local loginCooldown = 0               -- seconds until next attempt is allowed
local adminCheckPending = false       -- waiting for ac.checkAdminPrivileges() refresh
local adminCheckTimer = 0             -- time since checkAdminPrivileges was called
local ADMIN_CHECK_TIMEOUT = 4         -- seconds to wait before treating check as failed
local wasOnlineRace = nil

local selectedFlag = FLAG_YELLOW
local selectedBlueGroup = ''

local function connectOverrideState(key)
  return ac.connect({
    ac.StructItem.key(key),
    active = ac.StructItem.boolean(),
    flag = ac.StructItem.int32(),
    className = ac.StructItem.string(48),
    autoBlueFilterConfigured = ac.StructItem.boolean(),
    autoBlueFilterEnabled = ac.StructItem.boolean(),
    blueIgnored = ac.StructItem.boolean(),
    manualBlueActive = ac.StructItem.boolean()
  }, false, ac.SharedNamespace.Shared)
end

-- Keep CMRT's existing shared-memory contract while exposing the same state
-- under an FCA-owned key for the planned custom HUD.
local cmrtOverrideState = connectOverrideState('app.FlagControlApp.cmrtOverride.v3')
local fcaOverrideState = connectOverrideState('app.FlagControlApp.fcaOverride.v3')

local function setOverrideState(field, value)
  cmrtOverrideState[field] = value
  fcaOverrideState[field] = value
end

local function getLocalClassName()
  local className = fcaOverrideState.className
  if className == nil or className == '' then
    className = cmrtOverrideState.className
  end
  return className or ''
end

setOverrideState('active', false)
setOverrideState('flag', FLAG_NONE)
setOverrideState('blueIgnored', false)
setOverrideState('manualBlueActive', false)

local onlinePeers = {}
local presenceTimer = 0
local lobbyMessageStatus = 'Join an online lobby to discover peers'

local network

local flagOptions = {
  { value = FLAG_GREEN, label = 'GREEN FLAG' },
  { value = FLAG_YELLOW, label = 'YELLOW FLAG' },
  { value = FLAG_RED, label = 'RED FLAG' }
}

local blueFlags = require('modules/blue_flags').create({
  isAdminUnlocked = function () return isAdminUnlocked end,
  setOverrideState = setOverrideState,
  network = function () return network end,
  onlinePeers = onlinePeers,
  getLocalClassName = getLocalClassName
})

local fieldFlags = require('modules/field_flags').create({
  flagNone = FLAG_NONE,
  flagGreen = FLAG_GREEN,
  flagYellow = FLAG_YELLOW,
  flagRed = FLAG_RED,
  isAdminUnlocked = function () return isAdminUnlocked end,
  setOverrideState = setOverrideState,
  network = function () return network end
})

network = require('modules/network').create({
  onlinePeers = onlinePeers,
  applyBlueIgnore = blueFlags.applyIgnore,
  applyBlueClassRule = blueFlags.applyBlueClassRule,
  applyBlueAlert = blueFlags.applyAlert,
  isControllableFieldFlag = fieldFlags.isControllableFieldFlag,
  applyFieldFlag = fieldFlags.apply
})

function script.update(dt)
  local sim = ac.getSim()

  -- Admin: tick cooldown timer
  if loginCooldown > 0 then
    loginCooldown = loginCooldown - dt
    if loginCooldown < 0 then loginCooldown = 0 end
  end

  -- Offline has no server admin to authenticate against. On entering an online
  -- session, discard that offline unlock unless CSP reports native admin status.
  if not sim.isOnlineRace then
    isAdminUnlocked = true
  elseif wasOnlineRace == false then
    isAdminUnlocked = sim.isAdmin == true
  end
  wasOnlineRace = sim.isOnlineRace

  -- Admin: poll ac.checkAdminPrivileges() result after a login attempt
  if adminCheckPending then
    adminCheckTimer = adminCheckTimer + dt
    if sim.isAdmin then
      isAdminUnlocked = true
      adminCheckPending = false
      loginPassword = ''
      loginError = ''
    elseif adminCheckTimer >= ADMIN_CHECK_TIMEOUT then
      adminCheckPending = false
      loginError = 'Login failed. Check your admin password and try again.'
      loginCooldown = 3
    end
  end

  local localCar = ac.getCar(0)
  local localName = ac.getDriverName(0) or ''
  local localSessionID = localCar and localCar.sessionID or -1
  local isLocalIgnored = blueFlags.isDriverIgnored(localName, localSessionID, 0)
  setOverrideState('blueIgnored', isLocalIgnored)

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
    network.sendPresence({
      protocol = 4,
      className = getLocalClassName(),
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

-- Attempt to authenticate as server admin by sending /admin <password> via chat.
-- On success: sim.isAdmin will flip to true; we poll it in script.update.
local function attemptAdminLogin(password)
  if loginCooldown > 0 then return end
  if adminCheckPending then return end
  if password == nil or password == '' then
    loginError = 'Please enter your admin password.'
    return
  end

  loginError = ''
  -- Send the /admin command silently. ac.sendChatMessage returns false if rate-limited.
  local sent = ac.sendChatMessage('/admin ' .. password)
  if not sent then
    loginError = 'Chat is rate-limited. Please wait a moment and try again.'
    loginCooldown = 2
    return
  end

  -- Immediately request CSP to refresh the isAdmin flag.
  ac.checkAdminPrivileges()
  adminCheckPending = true
  adminCheckTimer = 0
end

-- Draws the admin status badge in the app header.
local function drawAdminHeader()
  local sim = ac.getSim()
  if not isAdminUnlocked then return end

  -- Show a small green admin badge on the right side of the title row.
  ui.sameLine(ui.windowWidth() - 110)
  ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.1, 0.45, 0.15, 1))
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.14, 0.55, 0.2, 1))
  ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.14, 0.55, 0.2, 1))
  ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
  if ui.button('ADMIN MODE', vec2(100, 18)) then
    -- Allow local lockout while retaining offline access.
    if sim.isOnlineRace then
      isAdminUnlocked = false
      adminCheckPending = false
      loginError = ''
      loginPassword = ''
    end
  end
  if ui.itemHovered() and sim.isOnlineRace then
    ui.setTooltip('Click to lock race-control actions')
  end
  ui.popStyleColor(4)
end

local function drawAdminLoginPage()
  ui.newLine(3)
  ui.pushStyleColor(ui.StyleColor.Text, FCA_YELLOW)
  ui.setNextTextBold()
  ui.text('SERVER ADMIN ACCESS')
  ui.popStyleColor()
  ui.separator()

  ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
  ui.textWrapped('Log in with the server admin password to open race-control tools and broadcast flag changes to the lobby.')
  ui.popStyleColor()
  ui.newLine(2)

  ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
  ui.text('SERVER STATUS')
  ui.popStyleColor()
  ui.text(ac.getSim().isOnlineRace and 'Online session — server authentication required' or 'Offline session')
  ui.newLine(2)

  ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
  ui.text('ADMIN PASSWORD')
  ui.popStyleColor()
  ui.setNextItemWidth(ui.availableSpaceX())
  local updatedPassword, _, enterPressed = ui.inputText(
    '##adminpw',
    loginPassword,
    bit.bor(ui.InputTextFlags.Password, ui.InputTextFlags.FocusByDefault)
  )
  loginPassword = updatedPassword

  if loginError ~= '' then
    ui.newLine()
    ui.pushStyleColor(ui.StyleColor.Text, DANGER_RED)
    ui.textWrapped(loginError)
    ui.popStyleColor()
  elseif loginCooldown > 0 then
    ui.newLine()
    ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
    ui.text(string.format('Please wait %.0f seconds before trying again.', math.ceil(loginCooldown)))
    ui.popStyleColor()
  end

  ui.newLine(2)
  local canSubmit = loginCooldown <= 0 and not adminCheckPending
  if not canSubmit then
    ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.25, 0.25, 0.25, 1))
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.25, 0.25, 0.25, 1))
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.25, 0.25, 0.25, 1))
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.5, 0.5, 0.5, 1))
  end
  local buttonText = adminCheckPending and 'VERIFYING…' or 'LOG IN'
  if ui.modernButton(buttonText, vec2(ui.availableSpaceX(), 40), ui.ButtonFlags.None, ui.Icons.ArrowRight) then
    if canSubmit then attemptAdminLogin(loginPassword) end
  end
  if enterPressed and canSubmit then attemptAdminLogin(loginPassword) end
  if not canSubmit then ui.popStyleColor(4) end

  if adminCheckPending then
    ui.newLine()
    ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
    ui.text('Waiting for the server to confirm admin access…')
    ui.popStyleColor()
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

local function drawLobbyPeers()
  local peerNames = { (ac.getDriverName(0) or 'You') .. ' (you)' }
  for _, peer in pairs(onlinePeers) do
    peerNames[#peerNames + 1] = peer.name
  end
  table.sort(peerNames)
  ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
  ui.text(string.format('LOBBY DRIVERS  %d', #peerNames))
  ui.popStyleColor()
  ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
  ui.textWrapped(table.concat(peerNames, ', '))
  ui.popStyleColor()
end

local function drawFieldFlagsTab()
  ui.columns(2)
  ui.setColumnWidth(0, 220)

  ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
  ui.text('CURRENT FIELD FLAG')
  ui.popStyleColor()
  ui.textColored(getFieldFlagLabel(fieldFlags.getFlag()), getFieldFlagColor(fieldFlags.getFlag()))
  ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
  ui.text('Last update: ' .. fieldFlags.getSenderName())
  ui.text('Lobby: ' .. lobbyMessageStatus)
  ui.popStyleColor()
  drawLobbyPeers()

  ui.nextColumn()

  ui.newLine(-5)
  ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
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
  ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
  ui.text('SELECTED: ' .. getFieldFlagLabel(selectedFlag))
  ui.popStyleColor()

  local flagDeployed = fieldFlags.getFlag() ~= FLAG_NONE
  ui.pushStyleColor(ui.StyleColor.Button, flagDeployed and rgbm(0.78, 0.12, 0.1, 1) or FCA_YELLOW)
  ui.pushStyleColor(ui.StyleColor.Text, flagDeployed and rgbm(1, 1, 1, 1) or rgbm(0.08, 0.08, 0.08, 1))
  if ui.button(flagDeployed and 'UNDEPLOY FLAG' or 'DEPLOY FLAG', vec2(-0.1, 38)) then
    fieldFlags.publish(flagDeployed and FLAG_NONE or selectedFlag)
  end
  ui.popStyleColor(2)
  ui.columns(1)

  ui.separator()
  ui.pushStyleColor(ui.StyleColor.Text, FCA_YELLOW)
  ui.text('Field flags broadcast to all Flag Control clients in the session.')
  ui.popStyleColor()
  ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
  ui.text('App flag only; does not alter native server flag.')
  ui.popStyleColor()
end

local function drawDriverBlueFlagsTab()
  local activeBlueDrivers, allDrivers = blueFlags.collectDriverBlueStates()

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
    ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
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
            blueFlags.publishIgnore(d.name, d.sessionID, d.carIndex, true)
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
        blueFlags.clearAllIgnores()
      end
      ui.popStyleColor(2)
    end
  end

  ui.separator()

  if #activeBlueDrivers == 0 then
    ui.newLine(3)
    ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
    ui.text('No drivers are currently under blue flag.')
    ui.popStyleColor()
    ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
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

    ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
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
        ui.textColored(d.name .. ' (You)', FCA_YELLOW)
      else
        ui.text(d.name)
      end
      ui.nextColumn()

      local carLabel = d.className ~= '' and (d.carName .. ' (' .. d.className .. ')') or d.carName
      ui.text(carLabel)
      ui.nextColumn()

      ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
      ui.text(d.causeDescription)
      ui.popStyleColor()
      ui.nextColumn()

      if d.isIgnored then
        ui.pushStyleColor(ui.StyleColor.Button, SUCCESS_GREEN)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('RESTORE##' .. d.key, vec2(ui.availableSpaceX(), 22)) then
          blueFlags.publishIgnore(d.name, d.sessionID, d.carIndex, false)
        end
        ui.popStyleColor(2)
      else
        ui.pushStyleColor(ui.StyleColor.Button, DANGER_RED)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('IGNORE##' .. d.key, vec2(ui.availableSpaceX(), 22)) then
          blueFlags.publishIgnore(d.name, d.sessionID, d.carIndex, true)
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

    ui.pushStyleColor(ui.StyleColor.Text, FCA_SETTINGS_TEXT)
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
        ui.textColored(d.name .. ' (You)', FCA_YELLOW)
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
        ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
        ui.text('Normal')
        ui.popStyleColor()
      end
      ui.nextColumn()

      if d.isIgnored then
        ui.pushStyleColor(ui.StyleColor.Button, SUCCESS_GREEN)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('RESTORE##all_' .. d.key, vec2(ui.availableSpaceX(), 20)) then
          blueFlags.publishIgnore(d.name, d.sessionID, d.carIndex, false)
        end
        ui.popStyleColor(2)
      else
        ui.pushStyleColor(ui.StyleColor.Button, d.isUnderBlue and DANGER_RED or rgbm(0.3, 0.3, 0.3, 1))
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
        if ui.button('IGNORE##all_' .. d.key, vec2(ui.availableSpaceX(), 20)) then
          blueFlags.publishIgnore(d.name, d.sessionID, d.carIndex, true)
        end
        ui.popStyleColor(2)
      end
      ui.nextColumn()
    end
    ui.columns(1)
    ui.treePop()
  end

  if ui.treeNode('Manual Blue Alert & Class Options###manual_blue_node') then
    ui.pushStyleColor(ui.StyleColor.Text, FCA_MUTED_TEXT)
    ui.textWrapped('Deploy a manual blue flag to all drivers in the selected group, or clear it.')
    ui.popStyleColor()

    local localClass = getLocalClassName()
    if localClass ~= '' then
      ui.text('Your class tag: ' .. localClass)
    end

    local groups = {}
    local seen = {}
    for _, d in ipairs(allDrivers) do
      if d.className ~= '' and not seen[blueFlags.classKey(d.className)] then
        seen[blueFlags.classKey(d.className)] = true
        groups[#groups + 1] = d.className
      end
    end
    table.sort(groups)

    if #groups > 0 then
      if selectedBlueGroup == '' or not seen[blueFlags.classKey(selectedBlueGroup)] then
        selectedBlueGroup = groups[1]
      end
      ui.setNextItemWidth(250)
      ui.combo('##manual_blue_group', selectedBlueGroup, function ()
        for _, g in ipairs(groups) do
          if ui.selectable(g) then selectedBlueGroup = g end
        end
      end)
      ui.sameLine(0, 10)
      if ui.button(blueFlags.isBlueAlertActive() and 'CLEAR MANUAL BLUE' or 'DEPLOY BLUE TO GROUP', vec2(200, 24)) then
        blueFlags.publishAlert(not blueFlags.isBlueAlertActive(), selectedBlueGroup)
      end
    else
      if ui.button(blueFlags.isBlueAlertActive() and 'CLEAR MANUAL BLUE' or 'DEPLOY BLUE FIELD-WIDE', vec2(220, 24)) then
        blueFlags.publishAlert(not blueFlags.isBlueAlertActive(), '')
      end
    end
    ui.treePop()
  end
end

function script.windowAdmin(dt)
  ui.setNextTextBold()
  ui.pushStyleColor(ui.StyleColor.Text, FCA_YELLOW)
  ui.header('RACE CONTROL')
  ui.popStyleColor()
  drawAdminHeader()
  ui.separator()

  if not isAdminUnlocked then
    drawAdminLoginPage()
    return
  end

  ui.tabBar('FlagControlAdminTabs', ui.TabBarFlags.FittingPolicyScroll, function ()
    ui.tabItem('Field Flags', function ()
      drawFieldFlagsTab()
    end)
    ui.tabItem('Blue Flags', function ()
      drawDriverBlueFlagsTab()
    end)
  end)
end
