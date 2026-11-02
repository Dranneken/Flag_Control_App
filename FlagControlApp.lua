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

local adminUI = require('modules/ui').create({
  colors = {
    yellow = FCA_YELLOW,
    settingsText = FCA_SETTINGS_TEXT,
    muted = FCA_MUTED_TEXT,
    danger = DANGER_RED
  },
  isAdminUnlocked = function () return isAdminUnlocked end,
  getLoginState = function ()
    return {
      password = loginPassword,
      error = loginError,
      cooldown = loginCooldown,
      pending = adminCheckPending
    }
  end,
  setLoginPassword = function (password) loginPassword = password end,
  attemptAdminLogin = attemptAdminLogin,
  lockAdmin = function ()
    if ac.getSim().isOnlineRace then
      isAdminUnlocked = false
      adminCheckPending = false
      loginError = ''
      loginPassword = ''
    end
  end
})

function script.windowAdmin(dt)
  ui.setNextTextBold()
  ui.pushStyleColor(ui.StyleColor.Text, FCA_YELLOW)
  ui.header('RACE CONTROL')
  ui.popStyleColor()
  adminUI.drawAdminHeader()
  ui.separator()

  if not isAdminUnlocked then
    adminUI.drawAdminLoginPage()
    return
  end

  raceControlUI.drawTabs()
end
