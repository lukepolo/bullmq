--[[
  Completely obliterates a queue and all of its contents
  
  Input:
    KEYS[1] meta
    KEYS[2] base

    ARGV[1] count
    ARGV[2] force
    ARGV[3] timestamp
]]

-- This command completely destroys a queue including all of its jobs, current or past 
-- leaving no trace of its existence. Since this script needs to iterate to find all the job
-- keys, consider that this call may be slow for very large queues.

-- The queue needs to be "paused" or it will return an error
-- If the queue has currently active jobs then the script by default will return error,
-- however this behaviour can be overrided using the 'force' option.
local maxCount = tonumber(ARGV[1])
local baseKey = KEYS[2]

local rcall = redis.call

--- @include "includes/removeJobs"

local function removeLockKeys(keys)
  for i, key in ipairs(keys) do
    rcall("DEL", baseKey .. key .. ':lock')
  end
end

-- 1) Check if paused, if not return with error.
if rcall("HEXISTS", KEYS[1], "paused") ~= 1 then
  return -1 -- Error, NotPaused
end

-- 2) Check if there are active jobs, if there are and not "force" return error.
local activeKey = baseKey .. 'active'
local activeJobs = getListItems(activeKey, maxCount)
if (#activeJobs > 0) then
  if(ARGV[2] == "") then 
    return -2 -- Error, ExistActiveJobs
  end
end

removeLockKeys(activeJobs)
maxCount = removeJobs(activeJobs, true, baseKey, maxCount, ARGV[3])
rcall("LTRIM", activeKey, #activeJobs, -1)
if(maxCount <= 0) then
  return 1
end

local delayedKey = baseKey .. 'delayed'
maxCount = removeZSetJobs(delayedKey, true, baseKey, maxCount, ARGV[3])
if(maxCount <= 0) then
  return 1
end

local completedKey = baseKey .. 'completed'
maxCount = removeZSetJobs(completedKey, true, baseKey, maxCount, ARGV[3])
if(maxCount <= 0) then
  return 1
end

local waitKey = baseKey .. 'paused'
maxCount = removeListJobs(waitKey, true, baseKey, maxCount, ARGV[3])
if(maxCount <= 0) then
  return 1
end

local waitingChildrenKey = baseKey .. 'waiting-children'
maxCount = removeZSetJobs(waitingChildrenKey, true, baseKey, maxCount, ARGV[3])
if(maxCount <= 0) then
  return 1
end

local failedKey = baseKey .. 'failed'
maxCount = removeZSetJobs(failedKey, true, baseKey, maxCount, ARGV[3])
if(maxCount <= 0) then
  return 1
end

if(maxCount > 0) then
  rcall("DEL", baseKey .. 'priority')
  rcall("DEL", baseKey .. 'events')
  rcall("DEL", baseKey .. 'delay')
  rcall("DEL", baseKey .. 'stalled-check')
  rcall("DEL", baseKey .. 'stalled')
  rcall("DEL", baseKey .. 'id')
  rcall("DEL", baseKey .. 'meta')
  rcall("DEL", baseKey .. 'repeat')
  return 0
else
  return 1
end
