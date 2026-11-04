local penaltyNotifications = {}

local DEFAULT_DURATION = 15
local MAX_QUEUED_NOTICES = 32

local function copyRecord(record)
  local copy = {}
  for key, value in pairs(record) do copy[key] = value end
  return copy
end

function penaltyNotifications.create(dependencies)
  dependencies = dependencies or {}
  local duration = dependencies.duration or DEFAULT_DURATION
  local now = dependencies.now or os.time
  local isLocalRecord = dependencies.isLocalRecord or function () return false end
  local statuses = {}
  local queues = {
    mine = { items = {}, current = nil, remaining = 0 },
    others = { items = {}, current = nil, remaining = 0 }
  }
  local initialized = false

  local function startNext(queue)
    if queue.current or #queue.items == 0 then return end
    queue.current = table.remove(queue.items, 1)
    queue.remaining = duration
  end

  local function advance(queue, elapsed)
    while queue.current and elapsed >= queue.remaining do
      elapsed = elapsed - queue.remaining
      queue.current = nil
      queue.remaining = 0
      startNext(queue)
    end
    if queue.current then queue.remaining = queue.remaining - elapsed end
  end

  local function update(records, dt)
    local elapsed = math.max(0, dt or 0)
    advance(queues.mine, elapsed)
    advance(queues.others, elapsed)

    local currentStatuses = {}
    local newNotices = {}
    local currentTime = now()
    for _, record in ipairs(records) do
      local previousStatus = statuses[record.id]
      local newlyIssued = record.status == 'issued' and (
        previousStatus ~= nil and previousStatus ~= 'issued' or
        previousStatus == nil and record.createdAt >= currentTime - duration
      )
      if initialized and newlyIssued then
        newNotices[#newNotices + 1] = copyRecord(record)
      end
      currentStatuses[record.id] = record.status
    end
    statuses = currentStatuses
    initialized = true

    table.sort(newNotices, function (left, right)
      if left.createdAt == right.createdAt then return left.id < right.id end
      return left.createdAt < right.createdAt
    end)
    for _, record in ipairs(newNotices) do
      local queue = isLocalRecord(record) and queues.mine or queues.others
      if #queue.items < MAX_QUEUED_NOTICES then
        queue.items[#queue.items + 1] = record
      end
    end
    startNext(queues.mine)
    startNext(queues.others)
  end

  return {
    update = update,
    getCurrent = function (side)
      local queue = queues[side]
      return queue and queue.current and copyRecord(queue.current) or nil
    end
  }
end

return penaltyNotifications
