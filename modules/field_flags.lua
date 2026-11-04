local fieldFlags = {}

function fieldFlags.create(dependencies)
  local fieldFlag = dependencies.flagNone
  local flagSenderName = 'No flag update received'
  local revision = 0
  local controllableFlags = {
    [dependencies.flagGreen] = true,
    [dependencies.flagYellow] = true,
    [dependencies.flagRed] = true
  }

  local function isControllableFieldFlag(flag)
    return flag == dependencies.flagNone or controllableFlags[flag] == true
  end

  local function apply(flag, overrideActive, senderName)
    fieldFlag = flag
    dependencies.setOverrideState('active', overrideActive)
    dependencies.setOverrideState('flag', flag)
    flagSenderName = senderName or 'Lobby member'
    revision = revision + 1
  end

  local function publish(flag)
    if not dependencies.isAdminUnlocked() then return false end
    if not isControllableFieldFlag(flag) then return false end

    fieldFlag = flag
    local overrideActive = flag ~= dependencies.flagNone
    dependencies.setOverrideState('active', overrideActive)
    dependencies.setOverrideState('flag', flag)
    flagSenderName = 'You'
    revision = revision + 1
    dependencies.network().sendFlagState({
      protocol = 6,
      overrideActive = overrideActive,
      flag = flag
    }, true)
    return true
  end

  return {
    isControllableFieldFlag = isControllableFieldFlag,
    apply = apply,
    publish = publish,
    getFlag = function () return fieldFlag end,
    getSenderName = function () return flagSenderName end,
    getRevision = function () return revision end
  }
end

return fieldFlags
