local FLAG_NONE = 0
local FLAG_GREEN = 1
local FLAG_YELLOW = 2
local FLAG_BLUE = 3
local FLAG_BLACK = 4
local FLAG_PENALTY = 5
local FLAG_RED = 6
local FLAG_WHITE = 7
local FLAG_CHECKERED = 8
local FLAG_PITLANE = 9
local FLAG_PITBOX = 10

local CMRT_YELLOW = rgbm(1, 228 / 255, 0, 1)
local CMRT_DARK = rgbm(27 / 255, 27 / 255, 27 / 255, 1)
local CMRT_SETTINGS_TEXT = rgbm(180 / 255, 180 / 255, 180 / 255, 1)
local CMRT_MUTED_TEXT = rgbm(209 / 255, 209 / 255, 209 / 255, 0.72)

local fieldFlag = FLAG_NONE
local selectedFlag = FLAG_YELLOW
local cmrtOverrideState = ac.connect({
  ac.StructItem.key('app.FlagControlApp.cmrtOverride.v1'),
  active = ac.StructItem.boolean(),
  flag = ac.StructItem.int32()
}, false, ac.SharedNamespace.Shared)

cmrtOverrideState.active = false
cmrtOverrideState.flag = FLAG_NONE

local flagSenderName = 'No flag update received'
local onlinePeers = {}
local presenceTimer = 0
local lobbyMessageStatus = 'Join an online lobby to discover peers'

local flagOptions = {
  { value = FLAG_GREEN, label = 'GREEN FLAG' },
  { value = FLAG_YELLOW, label = 'YELLOW FLAG' },
  { value = FLAG_BLUE, label = 'BLUE FLAG' },
  { value = FLAG_BLACK, label = 'BLACK FLAG' },
  { value = FLAG_PENALTY, label = 'PENALTY' },
  { value = FLAG_RED, label = 'RED FLAG' },
  { value = FLAG_WHITE, label = 'WHITE FLAG' },
  { value = FLAG_CHECKERED, label = 'CHECKERED FLAG' },
  { value = FLAG_PITLANE, label = 'PIT LANE' },
  { value = FLAG_PITBOX, label = 'PIT BOX' }
}

local sendPresence = ac.OnlineEvent({
  ac.StructItem.key('app.FlagControlApp.lobbyPresence.v1'),
  protocol = ac.StructItem.int32()
}, function (sender, message)
  if sender == nil or sender.index == 0 or message.protocol ~= 1 then return end

  local sessionID = sender.sessionID
  if sessionID == nil then return end

  local name = ac.getDriverName(sender.index)
  if name == nil or name == '' then
    name = 'Driver ' .. tostring(sessionID)
  end

  onlinePeers[sessionID] = { name = name, lastSeen = os.clock() }
end)

local sendFlagState = ac.OnlineEvent({
  ac.StructItem.key('app.FlagControlApp.fieldFlag.v3'),
  protocol = ac.StructItem.int32(),
  overrideActive = ac.StructItem.boolean(),
  flag = ac.StructItem.int32()
}, function (sender, message)
  if sender == nil or sender.index == 0 or message.protocol ~= 3 then return end
  if message.flag < FLAG_NONE or message.flag > FLAG_PITBOX then return end

  fieldFlag = message.flag
  cmrtOverrideState.active = message.overrideActive
  cmrtOverrideState.flag = message.flag
  flagSenderName = ac.getDriverName(sender.index) or 'Lobby member'
end)

local function publishFlag(flag)
  fieldFlag = flag
  local overrideActive = flag ~= FLAG_NONE
  cmrtOverrideState.active = overrideActive
  cmrtOverrideState.flag = flag
  flagSenderName = 'You'
  sendFlagState({ protocol = 3, overrideActive = overrideActive, flag = flag }, true)
end

function script.update(dt)
  local sim = ac.getSim()
  if not sim.isOnlineRace then
    lobbyMessageStatus = 'Join an online lobby to discover peers'
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
    if not sendPresence({ protocol = 1 }) then
      lobbyMessageStatus = 'Presence message was rate-limited'
    end
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
  if flag == FLAG_BLUE then return 'BLUE FLAG' end
  if flag == FLAG_BLACK then return 'BLACK FLAG' end
  if flag == FLAG_PENALTY then return 'PENALTY' end
  if flag == FLAG_RED then return 'RED FLAG' end
  if flag == FLAG_WHITE then return 'WHITE FLAG' end
  if flag == FLAG_CHECKERED then return 'CHECKERED FLAG' end
  if flag == FLAG_PITLANE then return 'PIT LANE' end
  if flag == FLAG_PITBOX then return 'PIT BOX' end
  return 'NO ACTIVE FLAG'
end

local function getFieldFlagColor(flag)
  if flag == FLAG_GREEN then return rgbm(0.15, 0.78, 0.25, 1) end
  if flag == FLAG_YELLOW then return rgbm(1, 0.78, 0.08, 1) end
  if flag == FLAG_BLUE then return rgbm(0.12, 0.42, 0.95, 1) end
  if flag == FLAG_BLACK then return rgbm(0.12, 0.12, 0.12, 1) end
  if flag == FLAG_PENALTY then return rgbm(0.9, 0.12, 0.12, 1) end
  if flag == FLAG_RED then return rgbm(0.9, 0.12, 0.12, 1) end
  if flag == FLAG_WHITE or flag == FLAG_CHECKERED then return rgbm(1, 1, 1, 1) end
  if flag == FLAG_PITLANE or flag == FLAG_PITBOX then return rgbm(0, 0.8, 0.9, 1) end
  return rgbm(0.65, 0.65, 0.65, 1)
end

local function getFlagButtonColor(flag, selected)
  local color = getFieldFlagColor(flag)
  local brightness = selected and 1 or 0.55
  return rgbm(color.r * brightness, color.g * brightness, color.b * brightness, 1)
end

local function getFlagButtonTextColor(flag)
  if flag == FLAG_GREEN or flag == FLAG_YELLOW or flag == FLAG_WHITE or
      flag == FLAG_CHECKERED or flag == FLAG_PITLANE or flag == FLAG_PITBOX then
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
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_SETTINGS_TEXT)
  ui.text(string.format('LOBBY DRIVERS  %d', #peerNames))
  ui.popStyleColor()
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_MUTED_TEXT)
  ui.textWrapped(table.concat(peerNames, ', '))
  ui.popStyleColor()
end

function script.windowAdmin(dt)
  ui.setNextTextBold()
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_YELLOW)
  ui.header('RACE CONTROL')
  ui.popStyleColor()
  ui.separator()

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
  ui.text('Prototype only: controls are not admin-verified.')
  ui.popStyleColor()
  ui.pushStyleColor(ui.StyleColor.Text, CMRT_MUTED_TEXT)
  ui.text('App flag only; does not change AC flags.')
  ui.popStyleColor()
end