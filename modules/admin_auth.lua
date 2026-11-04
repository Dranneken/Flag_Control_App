local adminAuth = {}

local COOLDOWN_SECONDS = 3
local KDF_STEP_BUDGET_SECONDS = 0.0015
local RESET_CONFIRM_SECONDS = 5
local DEFAULT_PASSWORD = 'adminpass'

local BLOCKED_MESSAGES = {
  allowlist_unavailable = 'The local admin allowlist is missing or could not be read.',
  empty_allowlist = 'The local admin allowlist is empty.',
  invalid_allowlist = 'The local admin allowlist contains invalid entries.',
  identity_unavailable = 'Content Manager identity data could not be verified.',
  identity_ambiguous = 'Content Manager identity data contains multiple Steam profile IDs.',
  not_allowlisted = 'This local Steam profile is not on the admin allowlist.'
}

function adminAuth.create(dependencies)
  local adminConfig = dependencies.adminConfig or require('modules/admin_config')
  local steamIdentity = dependencies.steamIdentity or require('modules/steam_identity')
  local passwordKdf = dependencies.passwordKdf or require('modules/password_kdf')
  local identityReader = dependencies.identityReader or steamIdentity.readCurrent
  local allowlistLoader = dependencies.allowlistLoader or adminConfig.load
  local getAllowlistPath = dependencies.allowlistPath or adminConfig.getPath
  local storage = dependencies.credentialStorage
  local now = dependencies.now or os.clock
  local password = ''
  local newPassword = ''
  local passwordConfirmation = ''
  local errorMessage = ''
  local noticeMessage = ''
  local blockedMessage = ''
  local cooldown = 0
  local credential = ''
  local mode = 'blocked'
  local unlocked = false
  local job
  local jobAction
  local resetConfirmUntil = 0
  local passwordChangeOpen = false
  local defaultPasswordActive = false

  local function refreshAuthorization()
    unlocked = false
    local allowlist, allowlistError = allowlistLoader()
    if type(allowlist) ~= 'table' or allowlistError then
      mode = 'blocked'
      blockedMessage = BLOCKED_MESSAGES[allowlistError] or
        BLOCKED_MESSAGES.allowlist_unavailable
      return false
    end

    local identity, identityError = identityReader()
    if identityError or not adminConfig.isSteamID64(identity) then
      mode = 'blocked'
      blockedMessage = BLOCKED_MESSAGES[identityError] or
        BLOCKED_MESSAGES.identity_unavailable
      return false
    end
    if allowlist[identity] ~= true then
      mode = 'blocked'
      blockedMessage = BLOCKED_MESSAGES.not_allowlisted
      return false
    end

    credential = storage:get() or ''
    if type(credential) ~= 'string' then
      mode = 'blocked'
      blockedMessage = 'The local admin credential could not be read.'
      return false
    end

    blockedMessage = ''
    defaultPasswordActive = credential == ''
    mode = 'login'
    return true
  end

  local function clearJob()
    job = nil
    jobAction = nil
    password = ''
  end

  local function beginJob(action, submittedPassword)
    if job or cooldown > 0 then return false end
    if not refreshAuthorization() then return false end
    if action == 'setup' and mode ~= 'setup' then return false end
    if action == 'login' and mode ~= 'login' then return false end

    if action == 'login' and defaultPasswordActive then
      password = ''
      if submittedPassword == DEFAULT_PASSWORD then
        unlocked = true
        mode = 'unlocked'
        errorMessage = ''
        noticeMessage = ''
        return true
      end
      unlocked = false
      errorMessage = 'Incorrect local admin password.'
      cooldown = COOLDOWN_SECONDS
      return false
    end

    local newJob, jobError
    if action == 'setup' then
      newJob, jobError = passwordKdf.startCreate(submittedPassword)
    else
      newJob, jobError = passwordKdf.startVerify(submittedPassword, credential)
    end
    password = ''
    if not newJob then
      if jobError == 'invalid_password_length' then
        errorMessage = 'Password must be between 9 and 128 bytes.'
      elseif jobError == 'invalid_credential' then
        errorMessage = 'Saved password data is invalid. Reset it and set up a new password.'
      else
        errorMessage = 'Password verification could not start. Admin controls remain locked.'
      end
      return false
    end

    errorMessage = ''
    job = newJob
    jobAction = action
    return true
  end

  local function update(dt)
    if cooldown > 0 then
      cooldown = math.max(0, cooldown - dt)
    end

    if resetConfirmUntil > 0 and now() > resetConfirmUntil then
      resetConfirmUntil = 0
      if errorMessage == 'Press reset again within five seconds to confirm.' then
        errorMessage = ''
      end
    end

    if not job then return end
    local action = jobAction
    local complete, stepError = job.step(KDF_STEP_BUDGET_SECONDS)
    if stepError then
      clearJob()
      unlocked = false
      passwordChangeOpen = false
      mode = 'login'
      errorMessage = 'Password processing failed. Admin controls remain locked.'
      return
    end
    if not complete then return end

    local result = job.getResult()
    clearJob()
    if action == 'setup' then
      if type(result) ~= 'string' or result == '' then
        mode = 'setup'
        errorMessage = 'Password setup failed. Admin controls remain locked.'
        return
      end
      storage:set(result)
      credential = result
      defaultPasswordActive = false
      unlocked = true
      mode = 'unlocked'
      errorMessage = ''
      noticeMessage = ''
    elseif action == 'password_change' then
      if type(result) ~= 'string' or result == '' then
        mode = 'login'
        errorMessage = 'Password change failed. Log in again to unlock admin controls.'
        passwordChangeOpen = false
        return
      end
      storage:set(result)
      credential = result
      defaultPasswordActive = false
      unlocked = true
      mode = 'unlocked'
      passwordChangeOpen = false
      newPassword = ''
      passwordConfirmation = ''
      noticeMessage = 'Password changed.'
      errorMessage = ''
    elseif result == true then
      unlocked = true
      mode = 'unlocked'
      errorMessage = ''
      noticeMessage = ''
    else
      unlocked = false
      mode = 'login'
      errorMessage = 'Incorrect local admin password.'
      cooldown = COOLDOWN_SECONDS
    end
  end

  local function beginPasswordReset()
    if job or not refreshAuthorization() or credential == '' then return false end
    if resetConfirmUntil > now() then
      storage:set('')
      credential = ''
      defaultPasswordActive = true
      resetConfirmUntil = 0
      errorMessage = 'Password reset. Sign in with adminpass.'
      noticeMessage = ''
      mode = 'login'
      return true
    end

    resetConfirmUntil = now() + RESET_CONFIRM_SECONDS
    errorMessage = 'Press reset again within five seconds to confirm.'
    return false
  end

  refreshAuthorization()

  local function beginPasswordChange()
    if not unlocked or job then return false end
    passwordChangeOpen = true
    newPassword = ''
    passwordConfirmation = ''
    errorMessage = ''
    noticeMessage = ''
    return true
  end

  local function startPasswordChange()
    if not unlocked or not passwordChangeOpen or job then return false end
    if newPassword ~= passwordConfirmation then
      errorMessage = 'New passwords do not match.'
      return false
    end

    local newJob, jobError = passwordKdf.startCreate(newPassword)
    if not newJob then
      errorMessage = jobError == 'invalid_password_length' and
        'Password must be between 9 and 128 bytes.' or
        'Password change could not start. The current password remains active.'
      return false
    end

    newPassword = ''
    passwordConfirmation = ''
    errorMessage = ''
    unlocked = false
    mode = 'password_change_pending'
    job = newJob
    jobAction = 'password_change'
    return true
  end

  local function cancelPasswordChange()
    if job then return false end
    passwordChangeOpen = false
    newPassword = ''
    passwordConfirmation = ''
    errorMessage = ''
    noticeMessage = ''
    return true
  end

  return {
    update = update,
    isUnlocked = function () return unlocked end,
    getState = function ()
      return {
        mode = mode,
        password = password,
        newPassword = newPassword,
        passwordConfirmation = passwordConfirmation,
        error = errorMessage,
        notice = noticeMessage,
        blockedMessage = blockedMessage,
        allowlistPath = getAllowlistPath(),
        cooldown = cooldown,
        pending = job ~= nil,
        progress = job and job.getProgress() or 0,
        resetArmed = resetConfirmUntil > now(),
        defaultPasswordActive = defaultPasswordActive,
        passwordChangeOpen = passwordChangeOpen
      }
    end,
    setPassword = function (value)
      password = type(value) == 'string' and value or ''
    end,
    setNewPassword = function (value)
      newPassword = type(value) == 'string' and value or ''
    end,
    setPasswordConfirmation = function (value)
      passwordConfirmation = type(value) == 'string' and value or ''
    end,
    startSetup = function () return beginJob('setup', password) end,
    startLogin = function () return beginJob('login', password) end,
    beginPasswordChange = beginPasswordChange,
    startPasswordChange = startPasswordChange,
    cancelPasswordChange = cancelPasswordChange,
    beginPasswordReset = beginPasswordReset,
    lock = function ()
      unlocked = false
      password = ''
      newPassword = ''
      passwordConfirmation = ''
      passwordChangeOpen = false
      errorMessage = ''
      noticeMessage = ''
      cooldown = 0
      resetConfirmUntil = 0
      refreshAuthorization()
    end
  }
end

return adminAuth
