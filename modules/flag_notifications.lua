local flagNotifications = {}

local function copyNotice(notice)
  if not notice then return nil end
  return {
    flag = notice.flag,
    senderName = notice.senderName
  }
end

function flagNotifications.create(dependencies)
  dependencies = dependencies or {}
  local flagNone = dependencies.flagNone
  local initialized = false
  local observedRevision
  local observedFlag = flagNone
  local current = nil
  local function update(revision, flag, senderName)
    if not initialized then
      initialized = true
      observedRevision = revision
      observedFlag = flag
      if flag ~= flagNone then
        current = {
          flag = flag,
          senderName = senderName or 'Lobby member'
        }
      end
      return
    end

    if revision == observedRevision then return end
    if flag ~= flagNone or observedFlag ~= flagNone then
      current = {
        flag = flag,
        senderName = senderName or 'Lobby member'
      }
    end
    observedRevision = revision
    observedFlag = flag
  end

  return {
    update = update,
    getCurrent = function () return copyNotice(current) end
  }
end

return flagNotifications
