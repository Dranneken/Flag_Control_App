package.path = './?.lua;./?/init.lua;' .. package.path

local text = {}
local currentSide
local currentRecords = {}

vec2 = function (x, y) return { x = x, y = y } end

ui = {
  StyleColor = { Text = 1 },
  pushStyleColor = function () end,
  popStyleColor = function () end,
  setNextTextBold = function () end,
  header = function (value) text[#text + 1] = value end,
  text = function (value) text[#text + 1] = value end,
  textWrapped = function (value) text[#text + 1] = value end,
  textColored = function (value) text[#text + 1] = value end,
  availableSpace = function () return vec2(580, 240) end,
  beginChild = function (id) currentSide = id; return true end,
  endChild = function () end,
  sameLine = function () end,
  separator = function () end
}

local noticeUI = require('modules/penalty_notice_ui').create({
  getCurrent = function (side) return currentRecords[side] end,
  colors = { yellow = {} }
})

noticeUI.draw()
assert(text[1] == 'PENALTY NOTICE')
assert(text[2] == 'YOU' and text[3] == 'No active notice.')
assert(text[4] == 'OTHER PLAYERS' and text[5] == 'No active notice.')

currentRecords.mine = {
  type = 'time',
  driverName = 'Local Driver',
  cause = 'Track limits',
  amount = 5,
  details = 'Repeated violation',
  issuer = 'Race Control'
}
currentRecords.others = {
  type = 'warning',
  driverName = 'Driver Two',
  cause = 'Unsafe rejoin',
  amount = 0,
  details = '',
  issuer = 'Race Control'
}
text = {}
noticeUI.draw()
assert(text[1] == 'PENALTY NOTICE')
assert(text[2] == 'YOU')
assert(text[3] == 'TIME PENALTY - Local Driver')
assert(text[4] == 'Cause: Track limits')
assert(text[5] == 'Suggested time loss: 5 seconds.')
assert(text[6] == 'Repeated violation')
assert(text[7] == 'Issued by Race Control')
assert(text[8] == 'OTHER PLAYERS')
assert(text[9] == 'WARNING - Driver Two')
assert(text[10] == 'Cause: Unsafe rejoin')

print('penalty notice UI tests passed')
