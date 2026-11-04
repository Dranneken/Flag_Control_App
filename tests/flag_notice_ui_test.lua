package.path = './?.lua;./?/init.lua;' .. package.path

local drawnText = {}
local currentPath = {}
local drawnShapes = {}
local fillColor
local fillCount = 0
local now = 0
local currentNotice = {
  flag = 1,
  senderName = 'You'
}

ui = {
  StyleColor = { Text = 1 },
  pushStyleColor = function () end,
  popStyleColor = function () end,
  setNextTextBold = function () end,
  header = function (value) drawnText[#drawnText + 1] = value end,
  textColored = function (value) drawnText[#drawnText + 1] = value end,
  textWrapped = function (value) drawnText[#drawnText + 1] = value end,
  getCursor = function () return { x = 8, y = 40 } end,
  availableSpaceX = function () return 360 end,
  drawLine = function () end,
  pathClear = function () currentPath = {} end,
  pathLineTo = function (point) currentPath[#currentPath + 1] = point end,
  pathFillConvex = function (color)
    fillColor = color
    fillCount = fillCount + 1
    drawnShapes[#drawnShapes + 1] = { points = currentPath, color = color }
  end
}

vec2 = function (x, y) return { x = x, y = y } end
rgbm = function (r, g, b, a) return { r = r, g = g, b = b, a = a } end

local colors = {
  yellow = { name = 'yellow' },
  green = { name = 'green' },
  red = { name = 'red' }
}
local noticeUI = require('modules/flag_notice_ui').create({
  getCurrent = function () return currentNotice end,
  getTime = function () return now end,
  flags = { none = 0, green = 1, yellow = 2, red = 6 },
  colors = colors
})

noticeUI.draw()
assert(fillColor == colors.green, 'the waving flag should match the active field flag')
assert(fillCount == 24, 'the cloth should use overlapping convex strips')
for _, shape in ipairs(drawnShapes) do
  assert(#shape.points == 4, 'each flag strip should have a convex four-point outline')
  assert(shape.color == colors.green, 'every flag strip should use the active flag color')
end

local topMin, topMax = math.huge, -math.huge
local bottomMin, bottomMax = math.huge, -math.huge
for _, shape in ipairs(drawnShapes) do
  local points = shape.points
  topMin = math.min(topMin, points[1].y, points[2].y)
  topMax = math.max(topMax, points[1].y, points[2].y)
  bottomMin = math.min(bottomMin, points[3].y, points[4].y)
  bottomMax = math.max(bottomMax, points[3].y, points[4].y)
end
assert(topMax - topMin > 5, 'the upper edge should have a visible wave')
assert(bottomMax - bottomMin > 5, 'the lower edge should have a visible wave')
local firstPoint = drawnShapes[1].points[2]

now = 1
fillCount = 0
drawnShapes = {}
noticeUI.draw()
assert(drawnShapes[1].points[2].y ~= firstPoint.y,
  'the flag shape should animate over time')

currentNotice = { flag = 0, senderName = 'You' }
fillCount = 0
drawnShapes = {}
noticeUI.draw()
assert(fillCount == 0, 'a cleared flag should not draw an active waving flag')

print('flag notice UI tests passed')
