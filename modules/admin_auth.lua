local adminAuth = {}

local COOLDOWN_SECONDS = 3
local KDF_STEP_BUDGET_SECONDS = 0.0015
local RESET_CONFIRM_SECONDS = 5

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
  local errorMessage = ''
  local blockedMessage = ''
  local cooldown = 0
  local credential = ''
  local mode = 'blocked'
  local unlocked = false
  local job
  local jobAction
  local resetConfirmUntil = 0

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
    mode = credential == '' and 'setup' or 'login'
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

    local newJob, jobError
    if action == 'setup' then
      newJob, jobError = passwordKdf.startCreate(submittedPassword)
    else
      newJob, jobError = passwordKdf.startVerify(submittedPassword, credential)
    end
    password = ''
    if not newJob then
      if jobError == 'invalid_password_length' then
        errorMessage = 'Password must be between 12 and 128 bytes.'
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
    local complete, stepError = job.step(KDF_STEP_BUDGET_SECONDS)
    if stepError then
      clearJob()
      unlocked = false
      mode = 'login'
      errorMessage = 'Password verification failed. Admin controls remain locked.'
      return
    end
    if not complete then return end

    local action = jobAction
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
      unlocked = true
      mode = 'unlocked'
      errorMessage = ''
    elseif result == true then
      unlocked = true
      mode = 'unlocked'
      errorMessage = ''
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
      resetConfirmUntil = 0
      errorMessage = ''
      mode = 'setup'
      return true
    end

    resetConfirmUntil = now() + RESET_CONFIRM_SECONDS
    errorMessage = 'Press reset again within five seconds to confirm.'
    return false
  end

  refreshAuthorization()

  return {
    update = update,
    isUnlocked = function () return unlocked end,
    getState = function ()
      return {
        mode = mode,
        password = password,
        error = errorMessage,
        blockedMessage = blockedMessage,
        allowlistPath = getAllowlistPath(),
        cooldown = cooldown,
        pending = job ~= nil,
        progress = job and job.getProgress() or 0,
        resetArmed = resetConfirmUntil > now()
      }
    end,
    setPassword = function (value)
      password = type(value) == 'string' and value or ''
    end,
    startSetup = function () return beginJob('setup', password) end,
    startLogin = function () return beginJob('login', password) end,
    beginPasswordReset = beginPasswordReset,
    lock = function ()
      unlocked = false
      password = ''
      errorMessage = ''
      cooldown = 0
      resetConfirmUntil = 0
      refreshAuthorization()
    end
  }
end

return adminAuth
