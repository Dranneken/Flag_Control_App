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
local wasOnlineRace = false
local lobbyMessageStatus = 'Join an online lobby to discover peers'

local adminConfig = require('modules/admin_config')
local steamIdentity = require('modules/steam_identity')
local credentialStorage = ac.storage('localAdminCredential', '')
local adminAuth = require('modules/admin_auth').create({
  adminConfig = adminConfig,
  steamIdentity = steamIdentity,
  credentialStorage = credentialStorage
})

local function isAdminUnlocked()
  return adminAuth.isUnlocked()
end

local network

local blueFlags = require('modules/blue_flags').create({
  isAdminUnlocked = isAdminUnlocked,
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
  isAdminUnlocked = isAdminUnlocked,
  setOverrideState = setOverrideState,
  network = function () return network end
})

local flagNotifications = require('modules/flag_notifications').create({
  flagNone = FLAG_NONE
})

local penalties = require('modules/penalties').create({
  isAdminUnlocked = isAdminUnlocked,
  network = function () return network end,
  storageFactory = function (key, defaultValue) return ac.storage(key, defaultValue) end,
  getLocalSessionID = function ()
    local car = ac.getCar(0)
    return car and car.sessionID or -1
  end,
  getLocalDriverName = function ()
    return ac.getDriverName(0) or 'Race Control'
  end,
  getDriverLapCount = function (sessionID, carIndex)
    local sim = ac.getSim()
    for index = 0, (sim.carsCount or 0) - 1 do
      local car = ac.getCar(index)
      if car and ((sessionID >= 0 and car.sessionID == sessionID) or index == carIndex) then
        return car.sessionLapCount or car.lapCount or 0
      end
    end
    return nil
  end
})

local raceControlUI = require('modules/race_control_ui').create({
  fieldFlags = fieldFlags,
  blueFlags = blueFlags,
  colors = {
    yellow = FCA_YELLOW,
    settingsText = FCA_SETTINGS_TEXT,
    muted = FCA_MUTED_TEXT,
    blue = FLAG_BLUE_COLOR,
    ignored = IGNORED_COLOR,
    danger = DANGER_RED,
    success = SUCCESS_GREEN
  },
  flags = {
    none = FLAG_NONE,
    green = FLAG_GREEN,
    yellow = FLAG_YELLOW,
    red = FLAG_RED
  },
  onlinePeers = onlinePeers,
  getLobbyMessageStatus = function () return lobbyMessageStatus end,
  getLocalClassName = getLocalClassName
})

network = require('modules/network').create({
  onlinePeers = onlinePeers,
  applyBlueIgnore = blueFlags.applyIgnore,
  applyBlueClassRule = blueFlags.applyBlueClassRule,
  applyBlueAlert = blueFlags.applyAlert,
  isControllableFieldFlag = fieldFlags.isControllableFieldFlag,
  isAdminUnlocked = isAdminUnlocked,
  getCurrentFieldFlag = fieldFlags.getFlag,
  flagNone = FLAG_NONE,
  applyFieldFlag = fieldFlags.apply,
  applyPenaltyEvent = penalties.applyPenaltyEvent,
  applyPenaltyPolicy = penalties.applyPolicyEvent,
  getPenaltyRecords = penalties.getRecords,
  getPenaltyPolicies = penalties.getPolicies
})

local penaltyFeedUI = require('modules/penalty_feed_ui').create({
  penalties = penalties,
  isAdminUnlocked = isAdminUnlocked,
  getDrivers = function ()
    local _, allDrivers = blueFlags.collectDriverBlueStates()
    return allDrivers
  end,
  getLocalDriverName = function () return ac.getDriverName(0) or 'Race Control' end,
  colors = {
    yellow = FCA_YELLOW,
    settingsText = FCA_SETTINGS_TEXT,
    muted = FCA_MUTED_TEXT,
    danger = DANGER_RED,
    success = SUCCESS_GREEN
  }
})

local penaltyNotifications = require('modules/penalty_notifications').create({
  duration = 15,
  isLocalRecord = function (record)
    local localCar = ac.getCar(0)
    local localSessionID = localCar and localCar.sessionID or -1
    if localSessionID >= 0 and record.driverSessionID and record.driverSessionID >= 0 then
      return record.driverSessionID == localSessionID
    end

    local localName = string.lower(ac.getDriverName(0) or 'Race Control')
    return string.lower(record.driverName or '') == localName
  end
})

local penaltyNoticeUI = require('modules/penalty_notice_ui').create({
  getCurrent = penaltyNotifications.getCurrent,
  colors = {
    yellow = FCA_YELLOW
  }
})

local companionWindowLock = require('modules/companion_window_lock')

local flagNoticeUI = require('modules/flag_notice_ui').create({
  getCurrent = flagNotifications.getCurrent,
  flags = {
    none = FLAG_NONE,
    green = FLAG_GREEN,
    yellow = FLAG_YELLOW,
    red = FLAG_RED
  },
  colors = {
    yellow = FCA_YELLOW,
    green = SUCCESS_GREEN,
    red = DANGER_RED
  }
})

function script.update(dt)
  local sim = ac.getSim()
  adminAuth.update(dt)
  flagNotifications.update(
    fieldFlags.getRevision(),
    fieldFlags.getFlag(),
    fieldFlags.getSenderName()
  )
  penaltyNotifications.update(penalties.getRecords(), dt)
  penalties.update()
  penaltyNotifications.update(penalties.getRecords(), 0)

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
    wasOnlineRace = false
    for sessionID in pairs(onlinePeers) do
      onlinePeers[sessionID] = nil
    end
    return
  end

  if not wasOnlineRace then
    wasOnlineRace = true
    network.requestFieldFlagSync()
    network.requestPenaltySync()
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

local adminUI = require('modules/ui').create({
  colors = {
    yellow = FCA_YELLOW,
    settingsText = FCA_SETTINGS_TEXT,
    muted = FCA_MUTED_TEXT,
    danger = DANGER_RED
  },
  isAdminUnlocked = isAdminUnlocked,
  getAdminState = adminAuth.getState,
  setPassword = adminAuth.setPassword,
  setNewPassword = adminAuth.setNewPassword,
  setPasswordConfirmation = adminAuth.setPasswordConfirmation,
  startSetup = adminAuth.startSetup,
  startLogin = adminAuth.startLogin,
  beginPasswordChange = adminAuth.beginPasswordChange,
  startPasswordChange = adminAuth.startPasswordChange,
  cancelPasswordChange = adminAuth.cancelPasswordChange,
  beginPasswordReset = adminAuth.beginPasswordReset,
  lockAdmin = adminAuth.lock
})

function script.windowAdmin(dt)
  ui.setNextTextBold()
  ui.pushStyleColor(ui.StyleColor.Text, FCA_YELLOW)
  ui.header('FLAG CONTROL')
  ui.popStyleColor()
  adminUI.drawAdminHeader()
  ui.separator()

  local adminState = adminAuth.getState()
  local availableSpace = ui.availableSpace()
  local panelGap = 12
  local panelSize = vec2(math.floor((availableSpace.x - panelGap) / 2), availableSpace.y)
  if ui.beginChild('FlagControlPanel', panelSize, true) then
    if adminState.passwordChangeOpen then
      adminUI.drawPasswordChangePage()
    elseif not isAdminUnlocked() then
      adminUI.drawAdminAccessPage()
    else
      raceControlUI.drawTabs()
    end
  end
  ui.endChild()
  ui.sameLine(0, panelGap)
  if ui.beginChild('PenaltyFeedPanel', panelSize, true) then
    penaltyFeedUI.draw()
  end
  ui.endChild()
end

function script.windowPenaltyNotice(dt)
  companionWindowLock.update('Penalty Notice', 'penalty_notice')
  penaltyNoticeUI.draw()
  companionWindowLock.drawStatus('penalty_notice')
end

function script.windowFlagNotice(dt)
  companionWindowLock.update('Flag Notice', 'flag_notice')
  flagNoticeUI.draw()
  companionWindowLock.drawStatus('flag_notice')
end
