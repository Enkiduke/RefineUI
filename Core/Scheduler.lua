----------------------------------------------------------------------------------------
-- RefineUI Scheduler
-- Description: Shared update scheduler using a single OnUpdate frame.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local pairs = pairs
local type = type
local tostring = tostring
local pcall = pcall
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local schedulerFrame = CreateFrame("Frame")
schedulerFrame:Hide()

local jobs = {} -- jobs[key] = { key, fn, interval, elapsed, enabled, combatOnly, oocOnly, predicate, safe, disableOnError }

local function hasEnabledJobs()
    for _, job in pairs(jobs) do
        if job.enabled then
            return true
        end
    end
    return false
end

local function setFrameActiveIfNeeded()
    if hasEnabledJobs() then
        schedulerFrame:Show()
    else
        schedulerFrame:Hide()
    end
end

local function canRunJob(job, inCombat)
    if not job or not job.enabled then
        return false
    end
    if job.combatOnly and not inCombat then
        return false
    end
    if job.oocOnly and inCombat then
        return false
    end
    if job.predicate and not job.predicate() then
        return false
    end
    return true
end

local function runJob(job, elapsed)
    if job.safe == false then
        job.fn(elapsed, job.key, job)
        return
    end

    local ok, err = pcall(job.fn, elapsed, job.key, job)
    if not ok then
        print("|cFFFF0000[RefineUI Scheduler]|r Error in job [" .. tostring(job.key) .. "]:", err)
        if job.disableOnError then
            job.enabled = false
        end
    end
end

schedulerFrame:SetScript("OnUpdate", function(_, elapsed)
    local inCombat = InCombatLockdown()

    for _, job in pairs(jobs) do
        if canRunJob(job, inCombat) then
            local interval = job.interval or 0
            if interval <= 0 then
                runJob(job, elapsed)
            else
                job.elapsed = (job.elapsed or 0) + elapsed
                if job.elapsed >= interval then
                    job.elapsed = 0
                    runJob(job, elapsed)
                end
            end
        end
    end

    if not hasEnabledJobs() then
        schedulerFrame:Hide()
    end
end)

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

-- Register or replace an update job.
-- opts:
--   enabled (bool, default true)
--   combatOnly (bool)
--   oocOnly (bool)
--   predicate (fn -> bool)
--   safe (bool, default true)
--   disableOnError (bool, default true)
function RefineUI:RegisterUpdateJob(key, interval, fn, opts)
    if type(key) ~= "string" or key == "" then
        return false, "invalid_key"
    end
    if type(fn) ~= "function" then
        return false, "invalid_callback"
    end

    opts = opts or {}
    local existing = jobs[key]
    local job = existing or {}

    job.key = key
    job.fn = fn
    job.interval = (type(interval) == "number" and interval >= 0) and interval or 0
    job.elapsed = 0
    job.enabled = (opts.enabled == nil) and true or (opts.enabled and true or false)
    job.combatOnly = opts.combatOnly and true or false
    job.oocOnly = opts.oocOnly and true or false
    job.predicate = (type(opts.predicate) == "function") and opts.predicate or nil
    job.safe = (opts.safe == nil) and true or (opts.safe and true or false)
    job.disableOnError = (opts.disableOnError == nil) and true or (opts.disableOnError and true or false)

    jobs[key] = job
    setFrameActiveIfNeeded()
    return true
end

function RefineUI:UnregisterUpdateJob(key)
    if type(key) ~= "string" or key == "" then
        return false, "invalid_key"
    end
    jobs[key] = nil
    setFrameActiveIfNeeded()
    return true
end

function RefineUI:IsUpdateJobRegistered(key)
    if type(key) ~= "string" or key == "" then
        return false
    end
    return jobs[key] ~= nil
end

function RefineUI:SetUpdateJobEnabled(key, enabled, resetElapsed)
    local job = jobs[key]
    if not job then
        return false, "job_missing"
    end

    job.enabled = enabled and true or false
    if resetElapsed == nil or resetElapsed == true then
        job.elapsed = 0
    end
    setFrameActiveIfNeeded()
    return true
end

function RefineUI:SetUpdateJobInterval(key, interval)
    local job = jobs[key]
    if not job then
        return false, "job_missing"
    end
    if type(interval) ~= "number" or interval < 0 then
        return false, "invalid_interval"
    end
    job.interval = interval
    return true
end

function RefineUI:RunUpdateJobNow(key)
    local job = jobs[key]
    if not job then
        return false, "job_missing"
    end
    runJob(job, 0)
    return true
end

RefineUI.SchedulerFrame = schedulerFrame
