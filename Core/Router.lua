----------------------------------------------------------------------------------------
--  Router: tiny event hub + pub/sub (no OnUpdate, no timers)
----------------------------------------------------------------------------------------
local ADDON, engine = ...
local R, C, L = unpack(engine)

if R.Router then return end -- idempotent

local Router                 = {}
R.Router                     = Router

-- Localize
local CreateFrame            = CreateFrame
local tostring, type, select = tostring, type, select
local pairs, wipe            = pairs, wipe
local next                   = next
local unpack                 = unpack
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local GetInstanceInfo        = GetInstanceInfo
local C_ChatInfo             = C_ChatInfo

local SafeCall = R and R.SafeCall or function(fn, ctx, ...)
  local ok, err = pcall(fn, ...)
  if not ok then (DEFAULT_CHAT_FRAME or print)(("|cffff4444Router error|r [%s] %s"):format(tostring(ctx or "?"), tostring(err))) end
end

----------------------------------------------------------------------------------------
--  State
----------------------------------------------------------------------------------------
local f                      = CreateFrame("Frame")
local events                 = {} -- events[event] = { [key] = { fn = fn, filter = filter }, ... }
local units                  = {} -- units[event]  = { [key] = { unit = unit, fn = fn, filter = filter }, ... }
local topics                 = {} -- topics[name]  = { [key] = fn, ... }
local once                   = {} -- once[name]    = { [key] = fn, ... }
local prefixRefs             = {} -- addon msg prefixes with refcounts

local topicCache             = setmetatable({}, { __index = function(t, ev)
    local s = "event:" .. ev
    rawset(t, ev, s)
    return s
end })

topics.__lastCLEU            = nil
topics.__lastInstType        = nil

----------------------------------------------------------------------------------------
--  Internals
----------------------------------------------------------------------------------------
local function normalizeKey(key, fn)
    if key == nil then
        -- Stable string key from function address; prevents dupes without allocations per callsite
        key = tostring(fn)
    elseif type(key) ~= "string" then
        key = tostring(key)
    end
    return key
end

local function hasHandlers(bucket)
    if not bucket then return false end
    for _ in pairs(bucket) do return true end
    return false
end

local function tryUnregisterFrameEvent(eventName)
    if not hasHandlers(events[eventName]) and not hasHandlers(units[eventName]) then
        f:UnregisterEvent(eventName)
    end
end

local function passFilter(rec, event, ...)
    if not rec or not rec.filter then return true end
    local flt = rec.filter
    local ft = type(flt)
    if ft == "function" then
        return flt(event, ...)
    elseif ft == "table" then
        if flt.cleu and not (event == "COMBAT_LOG_EVENT_UNFILTERED" and topics.__lastCLEU and topics.__lastCLEU.subevent == flt.cleu) then
            return false
        end
        if flt.instType and topics.__lastInstType ~= flt.instType then
            return false
        end
        if flt.unit and select(1, ...) ~= flt.unit then
            return false
        end
    end
    return true
end

----------------------------------------------------------------------------------------
--  Game Events
----------------------------------------------------------------------------------------
function Router:RegisterEvent(eventName, fn, key, filter)
    if not eventName or type(fn) ~= "function" then return end
    key = normalizeKey(key, fn)

    local bucket = events[eventName]
    if not bucket then
        bucket = {}
        events[eventName] = bucket
    end
    bucket[key] = { fn = fn, filter = filter }
    f:RegisterEvent(eventName)
    return key
end

function Router:RegisterUnitEvent(eventName, unit, fn, key, filter)
    if not eventName or type(fn) ~= "function" or not unit then return end
    key = normalizeKey(key, fn)

    local bucket = units[eventName]
    if not bucket then
        bucket = {}
        units[eventName] = bucket
    end
    bucket[key] = { unit = unit, fn = fn, filter = filter }
    f:RegisterUnitEvent(eventName, unit)
    return key
end

function Router:RegisterEventOnce(eventName, fn, key, filter)
    if not eventName or type(fn) ~= "function" then return end
    key = key or (tostring(fn) .. ":once:" .. eventName)
    local proxy
    proxy = function(...)
        self:UnregisterEvent(eventName, key)
        SafeCall(fn, "event-once:" .. eventName, ...)
    end
    return self:RegisterEvent(eventName, proxy, key, filter)
end

function Router:RegisterUnitEventOnce(eventName, unit, fn, key, filter)
    if not eventName or type(fn) ~= "function" or not unit then return end
    key = key or (tostring(fn) .. ":once:" .. eventName .. ":" .. tostring(unit))
    local proxy
    proxy = function(...)
        self:UnregisterEvent(eventName, key)
        SafeCall(fn, "unit-once:" .. eventName, ...)
    end
    return self:RegisterUnitEvent(eventName, unit, proxy, key, filter)
end

function Router:UnregisterEvent(eventName, keyOrFn)
    if not eventName then return end
    local key = normalizeKey(keyOrFn, keyOrFn)
    local b1 = events[eventName]; if b1 then b1[key] = nil end

    local b2 = units[eventName]; if b2 then b2[key] = nil end

    tryUnregisterFrameEvent(eventName)
end

function Router:UnregisterAll(eventName)
    if eventName then
        events[eventName] = nil
        units[eventName]  = nil
        f:UnregisterEvent(eventName)
    else
        for ev in pairs(events) do f:UnregisterEvent(ev) end
        wipe(events); wipe(units)
    end
end

function Router:OffAll(prefix)
    if not prefix then return end
    local prefixLen = #prefix

    local function scrubEventBucket(bucket)
        if not bucket then return end
        for ev, map in pairs(bucket) do
            for key in pairs(map) do
                if type(key) == "string" and key:sub(1, prefixLen) == prefix then
                    map[key] = nil
                end
            end
            if not next(map) then
                bucket[ev] = nil
                tryUnregisterFrameEvent(ev)
            end
        end
    end

    scrubEventBucket(events)
    scrubEventBucket(units)

    for name, map in pairs(topics) do
        if type(map) == "table" then
            for key in pairs(map) do
                if type(key) == "string" and key:sub(1, prefixLen) == prefix then
                    map[key] = nil
                end
            end
            if not next(map) then
                topics[name] = nil
            end
        end
    end

    local onceBucket = once
    for name, map in pairs(onceBucket) do
        for key in pairs(map) do
            if type(key) == "string" and key:sub(1, prefixLen) == prefix then
                map[key] = nil
            end
        end
        if not next(map) then
            onceBucket[name] = nil
        end
    end
end

----------------------------------------------------------------------------------------
--  Addon Messages (optional, lightweight)
----------------------------------------------------------------------------------------
function Router:RegisterAddonPrefix(prefix)
    if not C_ChatInfo or not prefix then return end
    if prefixRefs[prefix] then
        prefixRefs[prefix] = prefixRefs[prefix] + 1
    else
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
        prefixRefs[prefix] = 1
    end
    f:RegisterEvent("CHAT_MSG_ADDON")
end

-- channel: "WHISPER","GUILD","RAID","PARTY","INSTANCE_CHAT","SAY","YELL"
-- target: required for WHISPER
function Router:SendAddon(prefix, message, channel, target)
    if not C_ChatInfo or not prefix or not prefixRefs[prefix] then return end
    C_ChatInfo.SendAddonMessage(prefix, tostring(message or ""), channel or "WHISPER", target)
end

function Router:UnregisterAddonPrefix(prefix)
    if not prefix or not prefixRefs[prefix] then return end
    prefixRefs[prefix] = prefixRefs[prefix] - 1
    if prefixRefs[prefix] <= 0 then
        prefixRefs[prefix] = nil
    end
    if not next(prefixRefs) then
        f:UnregisterEvent("CHAT_MSG_ADDON")
    end
end

-- Subscribe to addon prefix as a topic: "addon:<PREFIX>"
-- e.g., Router:On("addon:REFINE", fn)
local function dispatchAddon(prefix, msg, channel, sender, ...)
    local name = "addon:" .. prefix
    -- Normal topic handlers
    local bucket = topics[name]
    if bucket then
        for k, fn in pairs(bucket) do
            SafeCall(fn, "topic:" .. name, prefix, msg, channel, sender, ...)
        end
    end
    -- Once-handlers
    local ob = once[name]
    if ob then
        for k, fn in pairs(ob) do
            SafeCall(fn, "topic-once:" .. name, prefix, msg, channel, sender, ...)
            ob[k] = nil
        end
        if not hasHandlers(ob) then once[name] = nil end
    end
end

----------------------------------------------------------------------------------------
--  Pub/Sub Topics
----------------------------------------------------------------------------------------
function Router:On(name, fn, key)
    if type(fn) ~= "function" or not name then return end
    key = normalizeKey(key, fn)
    local bucket = topics[name]
    if not bucket then
        bucket = {}; topics[name] = bucket
    end
    bucket[key] = fn
    return key
end

function Router:Once(name, fn, key)
    if type(fn) ~= "function" or not name then return end
    key = normalizeKey(key, fn)
    local bucket = once[name]
    if not bucket then
        bucket = {}; once[name] = bucket
    end
    bucket[key] = fn
    return key
end

function Router:Off(name, keyOrFn)
    if not name then return end
    local key = normalizeKey(keyOrFn, keyOrFn)
    local b1 = topics[name]; if b1 then b1[key] = nil end
    local b2 = once[name]; if b2 then b2[key] = nil end
end

function Router:Send(name, ...)
    if not name then return end
    -- Normal handlers
    local bucket = topics[name]
    if bucket then
        for k, fn in pairs(bucket) do
            SafeCall(fn, "topic:" .. name, ...)
        end
    end
    -- Once-handlers
    local ob = once[name]
    if ob then
        for k, fn in pairs(ob) do
            SafeCall(fn, "topic-once:" .. name, ...)
            ob[k] = nil
        end
        if not hasHandlers(ob) then once[name] = nil end
    end
end

----------------------------------------------------------------------------------------
--  Frame script (single dispatch point)
----------------------------------------------------------------------------------------
f:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefixRefs[prefix] then
            dispatchAddon(prefix, msg, channel, sender, select(5, ...))
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" and GetInstanceInfo then
        local _, instType = GetInstanceInfo()
        topics.__lastInstType = instType
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" and CombatLogGetCurrentEventInfo then
        local info = topics.__lastCLEU
        if not info then
            info = { payload = {} }
            topics.__lastCLEU = info
        end
        local payload = info.payload
        payload[1], payload[2], payload[3], payload[4], payload[5], payload[6], payload[7],
        payload[8], payload[9], payload[10], payload[11], payload[12], payload[13], payload[14],
        payload[15], payload[16], payload[17], payload[18], payload[19], payload[20], payload[21],
        payload[22], payload[23], payload[24], payload[25], payload[26], payload[27], payload[28] = CombatLogGetCurrentEventInfo()

        local count = 28
        while count > 0 and payload[count] == nil do
            count = count - 1
        end
        info.count = count

        info.timestamp   = payload[1]
        info.subevent    = payload[2]
        info.hideCaster  = payload[3]
        info.srcGUID     = payload[4]
        info.srcName     = payload[5]
        info.srcFlags    = payload[6]
        info.srcRaidFlags= payload[7]
        info.dstGUID     = payload[8]
        info.dstName     = payload[9]
        info.dstFlags    = payload[10]
        info.dstRaidFlags= payload[11]
        Router:Send("cleu", info)
        Router:Send("cleu:" .. (info.subevent or "?"), info)
    end

    if event == "UNIT_AURA" then
        local unit, updateInfo = ...
        Router:Send("unit_aura", unit, updateInfo)
        Router:Send("unit_aura:unit:" .. tostring(unit), unit, updateInfo)
    end

    -- Unit-specific handlers (run first for determinism)
    local ub = units[event]
    if ub then
        local unitFired = select(1, ...)
        for k, rec in pairs(ub) do
            if rec and rec.fn and rec.unit == unitFired and passFilter(rec, event, ...) then
                SafeCall(rec.fn, "unit:" .. event, ...)
            end
        end
    end

    -- Generic event handlers
    local eb = events[event]
    if eb then
        for k, rec in pairs(eb) do
            if rec and rec.fn and passFilter(rec, event, ...) then
                SafeCall(rec.fn, "event:" .. event, ...)
            end
        end
    end

    -- Optional: publish event as a topic for passive listeners
    -- e.g., topic "event:PLAYER_ENTERING_WORLD"
    Router:Send(topicCache[event], ...)
end)

----------------------------------------------------------------------------------------
--  Quality-of-life helpers
----------------------------------------------------------------------------------------
-- Convenience: bind multiple events to the same handler
function Router:RegisterEvents(list, fn, keyPrefix)
    if type(list) ~= "table" or type(fn) ~= "function" then return end
    for _, ev in pairs(list) do
        self:RegisterEvent(ev, fn, (keyPrefix or tostring(fn)) .. ":" .. ev)
    end
end

-- Convenience: unregister multiple
function Router:UnregisterEvents(list, fnOrKeyPrefix)
    if type(list) ~= "table" then return end
    for _, ev in pairs(list) do
        self:UnregisterEvent(ev, fnOrKeyPrefix and (fnOrKeyPrefix .. ":" .. ev) or fnOrKeyPrefix)
    end
end

----------------------------------------------------------------------------------------
--  Ready signal
----------------------------------------------------------------------------------------
-- Allow consumers to wait on the router if needed
Router.ready = true
R.Router = Router