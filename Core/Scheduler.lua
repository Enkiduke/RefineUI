----------------------------------------------------------------------------------------
--  Scheduler: zero-idle timers, debounce, throttle (no permanent OnUpdate)
----------------------------------------------------------------------------------------
local ADDON, engine = ...
local R, C, L = unpack(engine)

if R.Scheduler then return end -- idempotent

local Scheduler                           = {}
R.Scheduler                               = Scheduler

-- Locals
local C_Timer                             = C_Timer
local NewTimer                            = C_Timer and C_Timer.NewTimer
local NewTicker                           = C_Timer and C_Timer.NewTicker
local GetTimePreciseSec                   = GetTimePreciseSec or GetTime
local tostring, type, select, pairs, wipe = tostring, type, select, pairs, wipe

-- SafeCall shim
local function SafeCall(fn, ctx, ...)
    if R.SafeCall then return R.SafeCall(fn, ctx, ...) end
    local ok, err = pcall(fn, ...)
    if not ok then (DEFAULT_CHAT_FRAME or print)("|cffff4444Scheduler error|r " .. tostring(err)) end
end

----------------------------------------------------------------------------------------
--  State
----------------------------------------------------------------------------------------
-- We retain handles so we can cancel by key or handle later.
local timers    = {} -- one-shot timers: [key] = timer
local tickers   = {} -- repeating tickers: [key] = ticker
local debounces = {} -- debounce records: [key] = { timer=..., fn=..., wait=... }
local throttles = {} -- throttle records: [key] = { last=sec, pending=false, timer=nil, fn=..., interval=..., argsTable={...} }

----------------------------------------------------------------------------------------
--  Basics
----------------------------------------------------------------------------------------
function Scheduler.Now()
    return GetTimePreciseSec()
end

-- One-shot after N seconds. Returns a handle (C_Timer timer).
-- key is optional; when provided, any existing timer with that key is canceled first.
function Scheduler.After(sec, fn, key)
    if not NewTimer or type(fn) ~= "function" or not sec or sec < 0 then return nil end
    if key then Scheduler.Cancel(key) end
    local handle
    handle = NewTimer(sec, function()
        -- Drop key->handle mapping before calling fn, so fn can reschedule safely.
        if key then timers[key] = nil end
        SafeCall(fn, "Scheduler.After")
    end)
    if key then timers[key] = handle end
    return handle
end

-- Repeating every N seconds. Returns a ticker handle. Cancel via handle:Cancel() or Scheduler.Cancel(key).
function Scheduler.Every(sec, fn, key)
    if not NewTicker or type(fn) ~= "function" or not sec or sec <= 0 then return nil end
    if key then Scheduler.Cancel(key) end
    local ticker = NewTicker(sec, function() SafeCall(fn, "Scheduler.Every") end)
    if key then tickers[key] = ticker end
    return ticker
end

-- Cancel by key or handle
function Scheduler.Cancel(keyOrHandle)
    if not keyOrHandle then return end
    -- If it looks like a C_Timer object, try to Cancel() it directly.
    if type(keyOrHandle) == "table" and keyOrHandle.Cancel then
        pcall(keyOrHandle.Cancel, keyOrHandle)
        -- Also scrub from our maps in case it’s stored there.
        for k, h in pairs(timers) do if h == keyOrHandle then timers[k] = nil end end
        for k, h in pairs(tickers) do if h == keyOrHandle then tickers[k] = nil end end
        for k, rec in pairs(debounces) do if rec.timer == keyOrHandle then debounces[k] = nil end end
        for k, rec in pairs(throttles) do if rec.timer == keyOrHandle then
                rec.timer = nil; rec.pending = false
            end end
        return
    end

    local key = tostring(keyOrHandle)

    -- one-shots
    local t = timers[key]
    if t then
        pcall(t.Cancel, t); timers[key] = nil
    end

    -- repeating
    local tk = tickers[key]
    if tk then
        pcall(tk.Cancel, tk); tickers[key] = nil
    end

    -- debounce
    local d = debounces[key]
    if d and d.timer then pcall(d.timer.Cancel, d.timer) end
    debounces[key] = nil

    -- throttle
    local th = throttles[key]
    if th and th.timer then pcall(th.timer.Cancel, th.timer) end
    if th then
        th.timer = nil; th.pending = false
    end
end

function Scheduler.CancelAll()
    for k, t in pairs(timers) do if t.Cancel then pcall(t.Cancel, t) end end
    for k, t in pairs(tickers) do if t.Cancel then pcall(t.Cancel, t) end end
    for k, r in pairs(debounces) do if r.timer and r.timer.Cancel then pcall(r.timer.Cancel, r.timer) end end
    for k, r in pairs(throttles) do if r.timer and r.timer.Cancel then pcall(r.timer.Cancel, r.timer) end end
    wipe(timers); wipe(tickers); wipe(debounces); wipe(throttles)
end

----------------------------------------------------------------------------------------
--  Debounce: run once after quiet period (trailing edge)
----------------------------------------------------------------------------------------
-- Debounce(key, wait, fn, ...latestArgs)
-- Resets a one-shot timer on every call; when it finally fires, it calls fn(latestArgs).
function Scheduler.Debounce(key, wait, fn, ...)
    if type(fn) ~= "function" or not key or not wait or wait < 0 then return end
    local skey = tostring(key)
    local rec = debounces[skey]
    if rec and rec.timer then pcall(rec.timer.Cancel, rec.timer) end

    -- Capture latest args without allocating per call: stash into rec.args
    rec = rec or { fn = fn, wait = wait, args = {} }
    rec.fn, rec.wait = fn, wait
    wipe(rec.args)
    local n = select("#", ...)
    for i = 1, n do rec.args[i] = select(i, ...) end

    rec.timer = Scheduler.After(wait, function()
        debounces[skey] = nil
        SafeCall(rec.fn, "Scheduler.Debounce", unpack(rec.args, 1, #rec.args))
    end)
    debounces[skey] = rec
end

----------------------------------------------------------------------------------------
--  Throttle: at most once per interval; optional trailing call with latest args
----------------------------------------------------------------------------------------
-- Throttle(key, interval, fn, ...args)
-- If called after ≥ interval since last run → call immediately.
-- Otherwise schedule a trailing run with the latest args (if not already pending).
-- Returns: true if ran immediately, false if scheduled or ignored.
function Scheduler.Throttle(key, interval, fn, ...)
    if type(fn) ~= "function" or not key or not interval or interval <= 0 then return false end
    local skey = tostring(key)
    local now = Scheduler.Now()
    local rec = throttles[skey]

    if not rec then
        rec = { last = 0, pending = false, timer = nil, fn = fn, interval = interval, args = {} }
        throttles[skey] = rec
    end
    rec.fn, rec.interval = fn, interval

    -- If allowed, run now.
    if (now - (rec.last or 0)) >= interval then
        rec.last = now
        SafeCall(fn, "Scheduler.Throttle.immediate", ...)
        return true
    end

    -- Otherwise, queue a trailing call if not already pending.
    if not rec.pending then
        rec.pending = true
        wipe(rec.args)
        local n = select("#", ...)
        for i = 1, n do rec.args[i] = select(i, ...) end
        local delay = interval - (now - (rec.last or 0))
        rec.timer = Scheduler.After(delay, function()
            rec.pending = false
            rec.last = Scheduler.Now()
            SafeCall(rec.fn, "Scheduler.Throttle.trailing", unpack(rec.args, 1, #rec.args))
            rec.timer = nil
        end)
    else
        -- Update latest args for the already-scheduled trailing call.
        wipe(rec.args)
        local n = select("#", ...)
        for i = 1, n do rec.args[i] = select(i, ...) end
    end
    return false
end

----------------------------------------------------------------------------------------
--  Integration helpers (optional sugar)
----------------------------------------------------------------------------------------
-- Router bucket helper (if you decide to use it later):
-- Example usage:
--   local key = "MyMod:SPELLS_CHANGED"
--   R.Router:RegisterEvent("SPELLS_CHANGED", function()
--     R.Scheduler.Debounce(key, 0.1, RebuildSpells)
--   end, key)
--
-- We intentionally do NOT implement RegisterBucket here to keep Scheduler pure.

----------------------------------------------------------------------------------------
--  Diagnostics (hooked by /refine diag if you want)
----------------------------------------------------------------------------------------
function Scheduler.__stats()
    local ct, ck, cd, ch = 0, 0, 0, 0
    for _ in pairs(timers) do ct = ct + 1 end
    for _ in pairs(tickers) do ck = ck + 1 end
    for _ in pairs(debounces) do cd = cd + 1 end
    for _ in pairs(throttles) do ch = ch + 1 end
    return { timers = ct, tickers = ck, debounces = cd, throttles = ch }
end
