local flagNoticeUI = {}

local FLAG_WIDTH = 76
local FLAG_HEIGHT = 38
local FLAG_SEGMENTS = 24
local FLAG_WAVE_AMPLITUDE = 6
local FLAG_WAVE_LENGTH = math.pi * 2
local FLAG_STRIP_OVERLAP = 1.5

local function getFlagDetails(flag, flags)
  if flag == flags.green then return 'GREEN FLAG', 'Field flag deployed.' end
  if flag == flags.yellow then return 'YELLOW FLAG', 'Field flag deployed.' end
  if flag == flags.red then return 'RED FLAG', 'Field flag deployed.' end
  return 'FIELD FLAG CLEARED', 'There is no active field flag.'
end

local function getFlagColor(flag, flags, colors)
  if flag == flags.green then return colors.green end
  if flag == flags.red then return colors.red end
  return colors.yellow
end

local function drawWavingFlag(color, now)
  local origin = ui.getCursor()
  local poleX = origin.x + math.max(0, ui.availableSpaceX() - FLAG_WIDTH - 12)
  local topY = origin.y + 1
  local clothStartX = poleX + 4
  local phase = now * 4

  ui.drawLine(
    vec2(poleX, topY - 2),
    vec2(poleX, topY + FLAG_HEIGHT + 13),
    rgbm(0.72, 0.74, 0.77, 1),
    3
  )

  local function getEdgePoint(progress, bottom)
    local wave = math.sin(phase - progress * FLAG_WAVE_LENGTH) *
      FLAG_WAVE_AMPLITUDE * progress
    local xOffset = bottom and -wave * 0.25 or wave * 0.25
    local yOffset = bottom and FLAG_HEIGHT or 0
    return vec2(
      clothStartX + FLAG_WIDTH * progress + xOffset,
      topY + yOffset + wave
    )
  end

  local overlapProgress = FLAG_STRIP_OVERLAP / FLAG_WIDTH
  for index = 0, FLAG_SEGMENTS - 1 do
    local start = math.max(0, index / FLAG_SEGMENTS - overlapProgress)
    local finish = math.min(1, (index + 1) / FLAG_SEGMENTS + overlapProgress)
    ui.pathClear()
    ui.pathLineTo(getEdgePoint(start, false))
    ui.pathLineTo(getEdgePoint(finish, false))
    ui.pathLineTo(getEdgePoint(finish, true))
    ui.pathLineTo(getEdgePoint(start, true))
    ui.pathFillConvex(color)
  end
end

function flagNoticeUI.create(dependencies)
  local getTime = dependencies.getTime or os.clock

  local function draw()
    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.yellow)
    ui.setNextTextBold()
    ui.header('FLAG NOTICE')
    ui.popStyleColor()

    local notice = dependencies.getCurrent()
    if not notice then
      ui.textWrapped('No active field flag.')
      return
    end

    local flags = dependencies.flags
    local colors = dependencies.colors
    local title, description = getFlagDetails(notice.flag, flags)
    if notice.flag ~= flags.none then
      drawWavingFlag(getFlagColor(notice.flag, flags, colors), getTime())
    end
    ui.textColored(title, getFlagColor(notice.flag, flags, colors))
    ui.textWrapped(description)
    ui.textWrapped('Updated by ' .. notice.senderName)
  end

  return { draw = draw }
end

return flagNoticeUI
