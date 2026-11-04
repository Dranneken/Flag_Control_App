local penaltyFeedUI = {}

local TYPE_OPTIONS = {
  { value = 'warning', label = 'Warning' },
  { value = 'time', label = 'Time penalty' },
  { value = 'drive_through', label = 'Drive-through' },
  { value = 'stop_go', label = 'Stop-and-go' },
  { value = 'disqualification', label = 'Disqualification' }
}

local SOURCE_OPTIONS = {
  { value = 'manual_incident', label = 'Steward-entered incident' },
  { value = 'track_limits', label = 'Track limits' },
  { value = 'collision', label = 'Collision / contact' },
  { value = 'blue_flag', label = 'Blue-flag non-compliance' },
  { value = 'unsafe_rejoin', label = 'Unsafe rejoin' },
  { value = 'pit_rules', label = 'Pit-lane / race procedure' }
}

local MODE_OPTIONS = {
  { value = 'off', label = 'Off' },
  { value = 'manual', label = 'Manual' },
  { value = 'recommend_approval', label = 'Recommend; wait for approval' },
  { value = 'recommend_delay', label = 'Recommend; issue after delay' },
  { value = 'auto_instant', label = 'Auto-issue immediately' },
  { value = 'auto_delay', label = 'Auto-issue after delay' }
}

local DELAY_UNIT_OPTIONS = {
  { value = 'seconds', label = 'seconds' },
  { value = 'laps', label = 'laps' }
}

local function optionLabel(options, value)
  for _, option in ipairs(options) do
    if option.value == value then return option.label end
  end
  return ''
end

local function makeDriverKey(driver)
  return tostring(driver.sessionID or -1) .. ':' ..
    tostring(driver.carIndex or -1) .. ':' .. (driver.name or '')
end

local function makePolicyDraft(policy)
  return {
    mode = policy.mode,
    penaltyType = policy.penaltyType,
    amount = tostring(policy.amount),
    delayValue = tostring(policy.delayValue),
    delayUnit = policy.delayUnit
  }
end

function penaltyFeedUI.create(dependencies)
  local penalties = dependencies.penalties
  local colors = dependencies.colors
  local selectedDriverKey = ''
  local selectedType = 'warning'
  local selectedSource = 'manual_incident'
  local cause = ''
  local details = ''
  local amountText = '5'
  local deadlineText = '0'
  local formMessage = ''
  local policyMessage = ''
  local policyDrafts = {}

  for _, source in ipairs(SOURCE_OPTIONS) do
    policyDrafts[source.value] = makePolicyDraft(penalties.getPolicy(source.value))
  end

  local function findSelectedDriver(drivers)
    for _, driver in ipairs(drivers) do
      if makeDriverKey(driver) == selectedDriverKey then return driver end
    end
    if #drivers > 0 then
      selectedDriverKey = makeDriverKey(drivers[1])
      return drivers[1]
    end
    selectedDriverKey = ''
    return nil
  end

  local function drawSelector(id, options, value, onSelected)
    ui.combo(id, optionLabel(options, value), function ()
      for _, option in ipairs(options) do
        if ui.selectable(option.label) then onSelected(option.value) end
      end
    end)
  end

  local function drawDriverSelector(drivers)
    local selected = findSelectedDriver(drivers)
    local label = selected and (selected.name .. ' (P' ..
      tostring(selected.racePosition or '-') .. ')') or 'No drivers found'
    ui.combo('##penalty_driver', label, function ()
      for _, driver in ipairs(drivers) do
        local driverLabel = driver.name .. ' (P' ..
          tostring(driver.racePosition or '-') .. ')'
        if ui.selectable(driverLabel) then
          selectedDriverKey = makeDriverKey(driver)
        end
      end
    end)
    return selected
  end

  local function drawAssignment()
    ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
    ui.textWrapped('Stewards can assign a penalty to an active lobby driver. The feed records the requirement and status; pit-service and disqualification enforcement remain steward/server actions.')
    ui.popStyleColor()

    if not dependencies.isAdminUnlocked() then
      ui.textColored('Unlock local Admin Mode to issue or manage penalties.', colors.danger)
      return
    end

    local drivers = dependencies.getDrivers()
    local selectedDriver = drawDriverSelector(drivers)
    ui.setNextItemWidth(ui.availableSpaceX())
    drawSelector('##penalty_type', TYPE_OPTIONS, selectedType, function (value)
      selectedType = value
    end)
    ui.setNextItemWidth(ui.availableSpaceX())
    drawSelector('##penalty_source', SOURCE_OPTIONS, selectedSource, function (value)
      selectedSource = value
    end)

    ui.text('Cause / warned action')
    local updatedCause = ui.inputText('##penalty_cause', cause, 0)
    if type(updatedCause) == 'string' then cause = updatedCause end
    ui.text('Steward note')
    local updatedDetails = ui.inputText('##penalty_details', details, 0)
    if type(updatedDetails) == 'string' then details = updatedDetails end

    if selectedType == 'time' or selectedType == 'stop_go' then
      ui.text(selectedType == 'time' and 'Suggested time loss (seconds)' or
        'Stop duration (seconds)')
      local updatedAmount = ui.inputText('##penalty_amount', amountText, 0)
      if type(updatedAmount) == 'string' then amountText = updatedAmount end
    end
    if selectedType == 'drive_through' or selectedType == 'stop_go' then
      ui.text('Serve within laps (0 = no deadline)')
      local updatedDeadline = ui.inputText('##penalty_deadline', deadlineText, 0)
      if type(updatedDeadline) == 'string' then deadlineText = updatedDeadline end
    end

    if selectedType == 'disqualification' then
      ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
      ui.textWrapped('This records and broadcasts a DQ. Kicking through server admin credentials is deferred to a trusted server-side integration; never store those credentials in this client app.')
      ui.popStyleColor()
    end

    if ui.button('ISSUE PENALTY', vec2(-0.1, 32)) then
      if not selectedDriver then
        formMessage = 'Select an active driver.'
      else
        local amount = tonumber(amountText)
        if selectedType ~= 'time' and selectedType ~= 'stop_go' then amount = 0 end
        local deadline = tonumber(deadlineText)
        if selectedType ~= 'drive_through' and selectedType ~= 'stop_go' then deadline = 0 end
        if amount == nil or deadline == nil then
          formMessage = 'Enter a whole number for time and lap values.'
        else
          local record, reason = penalties.issue({
            type = selectedType,
            source = selectedSource,
            driverName = selectedDriver.name,
            driverSessionID = selectedDriver.sessionID or -1,
            carIndex = selectedDriver.carIndex or -1,
            cause = cause,
            details = details,
            amount = math.floor(amount),
            serveWithinLaps = math.floor(deadline),
            issuer = dependencies.getLocalDriverName()
          })
          if record then
            formMessage = 'Penalty issued to ' .. record.driverName .. '.'
            cause = ''
            details = ''
          else
            formMessage = reason == 'admin_locked' and
              'Admin Mode is locked.' or
              'Could not issue penalty: ' .. tostring(reason)
          end
        end
      end
    end
    if formMessage ~= '' then
      ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
      ui.textWrapped(formMessage)
      ui.popStyleColor()
    end
  end

  local function getRequirement(record)
    if record.type == 'warning' then return 'Action: ' .. record.cause end
    if record.type == 'time' then
      return string.format('Add %d seconds; cause: %s', record.amount, record.cause)
    end
    if record.type == 'drive_through' then
      local deadline = record.serveWithinLaps > 0 and
        (' within ' .. tostring(record.serveWithinLaps) .. ' laps') or ''
      return 'Pass through pit lane' .. deadline .. '; ' .. record.cause
    end
    if record.type == 'stop_go' then
      local deadline = record.serveWithinLaps > 0 and
        (' within ' .. tostring(record.serveWithinLaps) .. ' laps') or ''
      return string.format('Stop for %d seconds in pit lane%s; %s',
        record.amount, deadline, record.cause)
    end
    return 'Disqualified; server removal is not connected'
  end

  local function drawPenaltyActions(record)
    if not dependencies.isAdminUnlocked() then return end
    local id = record.id
    if record.status == 'recommended' then
      if ui.button('APPROVE##' .. id, vec2(92, 22)) then penalties.approve(id) end
      ui.sameLine()
      if ui.button('REJECT##' .. id, vec2(82, 22)) then penalties.reject(id) end
      ui.sameLine()
    end
    if record.status == 'issued' and
       (record.type == 'time' or record.type == 'drive_through' or record.type == 'stop_go') then
      if ui.button('MARK SERVED##' .. id, vec2(130, 22)) then penalties.markServed(id) end
      ui.sameLine()
    end
    if record.status ~= 'served' and record.status ~= 'cancelled' and
       record.status ~= 'rejected' then
      if ui.button('CANCEL##' .. id, vec2(76, 22)) then penalties.cancel(id) end
    end
  end

  local function drawFeed()
    local records = penalties.getRecords()
    if #records == 0 then
      ui.text('No penalties have been issued in this session.')
      return
    end

    for _, record in ipairs(records) do
      ui.separator()
      ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
      ui.text(string.upper(record.type:gsub('_', ' ')) .. ' - ' .. record.driverName)
      ui.popStyleColor()
      ui.textColored(string.upper(record.status), record.status == 'served' and
        colors.success or (record.status == 'cancelled' or record.status == 'rejected') and
        colors.muted or colors.yellow)
      ui.textWrapped(getRequirement(record))
      if record.details ~= '' then
        ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
        ui.textWrapped(record.details)
        ui.popStyleColor()
      end
      ui.text('Issued by ' .. record.issuer)
      if record.status == 'recommended' and record.autoAfterDelay then
        ui.text('Recommendation will issue after the configured delay unless cancelled.')
      elseif record.status == 'delayed' then
        ui.text('Automatic issue is waiting for its configured delay.')
      end
      drawPenaltyActions(record)
    end
  end

  local function drawPolicy(source)
    local draft = policyDrafts[source.value]
    ui.separator()
    ui.pushStyleColor(ui.StyleColor.Text, colors.settingsText)
    ui.text(source.label)
    ui.popStyleColor()

    drawSelector('##mode_' .. source.value, MODE_OPTIONS, draft.mode, function (value)
      draft.mode = value
    end)
    drawSelector('##type_' .. source.value, TYPE_OPTIONS, draft.penaltyType, function (value)
      draft.penaltyType = value
    end)

    ui.text('Penalty amount (seconds for time / stop-and-go)')
    local amount = ui.inputText('##amount_' .. source.value, draft.amount, 0)
    if type(amount) == 'string' then draft.amount = amount end
    ui.text('Issue delay')
    local delay = ui.inputText('##delay_' .. source.value, draft.delayValue, 0)
    if type(delay) == 'string' then draft.delayValue = delay end
    drawSelector('##unit_' .. source.value, DELAY_UNIT_OPTIONS, draft.delayUnit, function (value)
      draft.delayUnit = value
    end)

    if ui.button('SAVE RULE##' .. source.value, vec2(120, 24)) then
      local saved, reason = penalties.setPolicy(source.value, {
        mode = draft.mode,
        penaltyType = draft.penaltyType,
        amount = tonumber(draft.amount),
        delayValue = tonumber(draft.delayValue),
        delayUnit = draft.delayUnit
      })
      if saved then
        policyMessage = source.label .. ' rule saved.'
      else
        policyMessage = 'Could not save rule: ' .. tostring(reason)
      end
    end
  end

  local function drawPolicies()
    ui.pushStyleColor(ui.StyleColor.Text, colors.yellow)
    ui.setNextTextBold()
    ui.header('PENALTY POLICIES')
    ui.popStyleColor()
    if not dependencies.isAdminUnlocked() then
      ui.textColored('Unlock local Admin Mode to edit penalty policies.', colors.danger)
      return
    end
    ui.pushStyleColor(ui.StyleColor.Text, colors.muted)
    ui.textWrapped('Modes: Off disables the source; Manual leaves issuing to the steward; Recommend modes create reviewable records; Auto modes issue records automatically. Delay can be measured in seconds or driver laps.')
    ui.textWrapped('Automatic incident sources are not connected in this client-only release. Policy settings are ready for a trusted server event source; no automatic violations are inferred from unreliable client heuristics.')
    ui.popStyleColor()

    for _, source in ipairs(SOURCE_OPTIONS) do drawPolicy(source) end
    if policyMessage ~= '' then
      ui.textWrapped(policyMessage)
    end
  end

  local function draw()
    ui.pushStyleColor(ui.StyleColor.Text, colors.yellow)
    ui.setNextTextBold()
    ui.header('PENALTY FEED')
    ui.popStyleColor()
    ui.textWrapped('Client-side penalty feed. Server-enforced penalties and DQ kick actions require a trusted server integration.')
    ui.separator()
    ui.tabBar('FlagControlPenaltyTabs', ui.TabBarFlags.FittingPolicyScroll, function ()
      ui.tabItem('Feed', drawFeed)
      ui.tabItem('Issue Penalty', drawAssignment)
      ui.tabItem('Policies', drawPolicies)
    end)
  end

  return { draw = draw }
end

return penaltyFeedUI
