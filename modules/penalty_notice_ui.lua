local penaltyNoticeUI = {}

local TYPE_LABELS = {
  warning = 'WARNING',
  time = 'TIME PENALTY',
  drive_through = 'DRIVE-THROUGH',
  stop_go = 'STOP-AND-GO',
  disqualification = 'DISQUALIFICATION'
}

local function getRequirement(record)
  if record.type == 'warning' then return 'Warning issued.' end
  if record.type == 'time' then
    return string.format('Suggested time loss: %d seconds.', record.amount)
  end
  if record.type == 'drive_through' then
    local deadline = record.serveWithinLaps > 0 and
      (' within ' .. tostring(record.serveWithinLaps) .. ' laps') or ''
    return 'Serve a drive-through' .. deadline .. '.'
  end
  if record.type == 'stop_go' then
    local deadline = record.serveWithinLaps > 0 and
      (' within ' .. tostring(record.serveWithinLaps) .. ' laps') or ''
    return string.format('Stop for %d seconds in the pit lane%s.',
      record.amount, deadline)
  end
  return 'Disqualification announced; server removal is not connected.'
end

function penaltyNoticeUI.create(dependencies)
  local colors = dependencies.colors

  local function drawRecord(record)
    if not record then
      ui.textWrapped('No active notice.')
      return
    end
    ui.textColored(
      (TYPE_LABELS[record.type] or 'PENALTY') .. ' - ' .. record.driverName,
      colors.yellow
    )
    ui.textWrapped('Cause: ' .. record.cause)
    ui.textWrapped(getRequirement(record))
    if record.details ~= '' then
      ui.textWrapped(record.details)
    end
    ui.text('Issued by ' .. record.issuer)
  end

  local function drawColumn(id, title, side, size)
    if ui.beginChild(id, size, true) then
      ui.pushStyleColor(ui.StyleColor.Text, colors.yellow)
      ui.setNextTextBold()
      ui.text(title)
      ui.popStyleColor()
      ui.separator()
      drawRecord(dependencies.getCurrent(side))
    end
    ui.endChild()
  end

  local function draw()
    ui.pushStyleColor(ui.StyleColor.Text, colors.yellow)
    ui.setNextTextBold()
    ui.header('PENALTY NOTICE')
    ui.popStyleColor()

    local availableSpace = ui.availableSpace()
    local gap = 10
    local columnSize = vec2(math.floor((availableSpace.x - gap) / 2), availableSpace.y)
    drawColumn('PenaltyNoticeMine', 'YOU', 'mine', columnSize)
    ui.sameLine(0, gap)
    drawColumn('PenaltyNoticeOthers', 'OTHER PLAYERS', 'others', columnSize)
  end

  return { draw = draw }
end

return penaltyNoticeUI
