----------------------------------------------------------------------------------------
-- RefineUI EventBus
-- Description: Single-frame event consolidation for performance optimization.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local pcall = pcall
local debug = debug
local format = string.format
local issecretvalue = _G and _G.issecretvalue
local wipe = wipe

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}  -- handlers[event] = { map = {}, count = 0, ordered = {}, dirty = false }
local unitHandlers = {} -- unitHandlers[event] = { map = { [unitToken] = bucket }, count = 0 }

RefineUI.Observability = RefineUI.Observability or {
    enabled = false,
    events = {
        registered = {},
        fired = {},
        handlers = {},
    },
    hooks = {
        registered = {},
        calls = {},
    },
}

local observability = RefineUI.Observability

----------------------------------------------------------------------------------------
-- Internal
----------------------------------------------------------------------------------------
local function createBucket()
    return {
        map = {},
        count = 0,
        ordered = {},
        dirty = false,
    }
end

local function getBucket(event, create)
    local bucket = handlers[event]
    if not bucket and create then
        bucket = createBucket()
        handlers[event] = bucket
    end
    return bucket
end

local function getUnitState(event, create)
    local unitState = unitHandlers[event]
    if not unitState and create then
        unitState = {
            map = {},
            count = 0,
        }
        unitHandlers[event] = unitState
    end
    return unitState
end

local function getUnitBucket(event, unitToken, create)
    local unitState = getUnitState(event, create)
    if not unitState then
        return nil, nil
    end

    local bucket = unitState.map[unitToken]
    if not bucket and create then
        bucket = createBucket()
        unitState.map[unitToken] = bucket
    end

    return bucket, unitState
end

local function makeUnitEventKey(event, unitToken)
    return format("%s:%s", event, unitToken)
end

local function getEventListenerCount(event)
    local count = 0
    local bucket = handlers[event]
    if bucket then
        count = count + bucket.count
    end

    local unitState = unitHandlers[event]
    if unitState then
        count = count + unitState.count
    end

    return count
end

local function hasHandlers(event)
    return getEventListenerCount(event) > 0
end

local function incrementCounter(map, key)
    map[key] = (map[key] or 0) + 1
end

local function trackHandlerCount(event)
    if not observability.enabled then return end
    observability.events.handlers[event] = getEventListenerCount(event)
end

local function trackUnitHandlerCount(event, unitToken)
    if not observability.enabled then return end
    local bucket = getUnitBucket(event, unitToken, false)
    observability.events.handlers[makeUnitEventKey(event, unitToken)] = bucket and bucket.count or 0
end

local function markBucketDirty(bucket)
    if bucket then
        bucket.dirty = true
    end
end

local function rebuildDispatchList(bucket)
    if not bucket or not bucket.dirty then
        return
    end

    local ordered = bucket.ordered
    if wipe then
        wipe(ordered)
    else
        for i = 1, #ordered do
            ordered[i] = nil
        end
    end

    for key, fn in pairs(bucket.map) do
        ordered[#ordered + 1] = key
        ordered[#ordered + 1] = fn
    end

    bucket.dirty = false
end

local function DispatchEventHandler(fn, event, ...)
    -- Secret-heavy events are forwarded with stable minimal args so shared
    -- payload tables (for example UNIT_AURA updateInfo) never enter addon handlers.
    if event == "UNIT_AURA" then
        local unit = ...
        return pcall(fn, event, unit)
    end
    if event == "PLAYER_TOTEM_UPDATE" then
        local slot = ...
        return pcall(fn, event, slot)
    end
    return pcall(fn, event, ...)
end

local function SafeString(v)
    if issecretvalue and issecretvalue(v) then
        return "<secret>"
    end

    local sOk, s = pcall(tostring, v)
    if sOk then
        return s
    end

    return "<unprintable>"
end

local function dispatchBucket(bucket, event, ...)
    if not bucket or bucket.count == 0 then
        return
    end

    rebuildDispatchList(bucket)

    local ordered = bucket.ordered
    for i = 1, #ordered, 2 do
        local key = ordered[i]
        local fn = ordered[i + 1]
        if bucket.map[key] == fn then
            local ok, err = DispatchEventHandler(fn, event, ...)
            if not ok then
                local handlerLabel = SafeString(key)
                if type(fn) == "function" and debug and debug.getinfo then
                    local info = debug.getinfo(fn, "Sl")
                    if info and info.short_src and info.linedefined then
                        handlerLabel = format("%s:%d", info.short_src, info.linedefined)
                    end
                end

                local errText = SafeString(err)
                print(format("|cFFFF0000[RefineUI EventBus]|r Error in handler [%s] for event [%s]: %s", handlerLabel, SafeString(event), errText))
            end
        end
    end
end

local function dispatch(_, event, ...)
    local bucket = handlers[event]
    local unitState = unitHandlers[event]
    if (not bucket or bucket.count == 0) and (not unitState or unitState.count == 0) then
        return
    end

    if observability.enabled then
        incrementCounter(observability.events.fired, event)
    end

    dispatchBucket(bucket, event, ...)

    if unitState and unitState.count > 0 then
        local unitToken = ...
        if type(unitToken) == "string" and (not issecretvalue or not issecretvalue(unitToken)) then
            local unitBucket = unitState.map[unitToken]
            if unitBucket and unitBucket.count > 0 then
                if observability.enabled then
                    incrementCounter(observability.events.fired, makeUnitEventKey(event, unitToken))
                end
                dispatchBucket(unitBucket, event, ...)
            end
        end
    end
end

eventFrame:SetScript("OnEvent", dispatch)

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

--- Register a callback for an event
-- @param event string The WoW event name
-- @param fn function The callback function(event, ...)
-- @param key string Optional key for unregistering (defaults to tostring(fn))
-- @return string The key used for registration
function RefineUI:RegisterEventCallback(event, fn, key)
    if type(fn) ~= "function" or not event then return end
    key = key or tostring(fn)

    if getEventListenerCount(event) == 0 then
        eventFrame:RegisterEvent(event)
    end

    local bucket = getBucket(event, true)
    if bucket.map[key] == nil then
        bucket.count = bucket.count + 1
    end

    bucket.map[key] = fn
    markBucketDirty(bucket)

    if observability.enabled then
        incrementCounter(observability.events.registered, event)
        trackHandlerCount(event)
    end

    return key
end

--- Register a callback for an event scoped to a specific unit token
-- @param event string The WoW event name
-- @param unitToken string The unit token to scope the callback to
-- @param fn function The callback function(event, ...)
-- @param key string Optional key for unregistering (defaults to tostring(fn))
-- @return string The key used for registration
function RefineUI:RegisterUnitEventCallback(event, unitToken, fn, key)
    if type(fn) ~= "function" or not event then return end
    if type(unitToken) ~= "string" or unitToken == "" then return end
    key = key or tostring(fn)

    if getEventListenerCount(event) == 0 then
        eventFrame:RegisterEvent(event)
    end

    local bucket, unitState = getUnitBucket(event, unitToken, true)
    if bucket.map[key] == nil then
        bucket.count = bucket.count + 1
        unitState.count = unitState.count + 1
    end

    bucket.map[key] = fn
    markBucketDirty(bucket)

    if observability.enabled then
        incrementCounter(observability.events.registered, event)
        incrementCounter(observability.events.registered, makeUnitEventKey(event, unitToken))
        trackHandlerCount(event)
        trackUnitHandlerCount(event, unitToken)
    end

    return key
end

--- Register a callback that fires once then auto-unregisters
-- @param event string The WoW event name
-- @param fn function The callback function(event, ...)
-- @param key string Optional key for unregistering
-- @return string The key used for registration
function RefineUI:OnceEvent(event, fn, key)
    if type(fn) ~= "function" or not event then return end
    key = key or (tostring(fn) .. ":once:" .. event)
    
    local wrapper
    wrapper = function(evt, ...)
        RefineUI:OffEvent(event, key)
        fn(evt, ...)
    end
    
    return RefineUI:RegisterEventCallback(event, wrapper, key)
end

--- Register for multiple events with the same callback
-- @param eventList table Array of event names
-- @param fn function The callback function(event, ...)
-- @param keyPrefix string Optional prefix for keys
function RefineUI:OnEvents(eventList, fn, keyPrefix)
    if type(eventList) ~= "table" or type(fn) ~= "function" then return end
    keyPrefix = keyPrefix or tostring(fn)
    for _, event in ipairs(eventList) do
        self:RegisterEventCallback(event, fn, keyPrefix .. ":" .. event)
    end
end

--- Register for multiple unit-scoped events with the same callback
-- @param unitToken string The unit token to scope callbacks to
-- @param eventList table Array of event names
-- @param fn function The callback function(event, ...)
-- @param keyPrefix string Optional prefix for keys
function RefineUI:OnUnitEvents(unitToken, eventList, fn, keyPrefix)
    if type(unitToken) ~= "string" or unitToken == "" then return end
    if type(eventList) ~= "table" or type(fn) ~= "function" then return end
    keyPrefix = keyPrefix or tostring(fn)
    for _, event in ipairs(eventList) do
        self:RegisterUnitEventCallback(event, unitToken, fn, keyPrefix .. ":" .. event)
    end
end

--- Unregister a callback by key
-- @param event string The WoW event name
-- @param key string The key used during registration
function RefineUI:OffEvent(event, key)
    local bucket = handlers[event]
    if not event or not bucket then return end

    if key == nil then
        handlers[event] = nil
        if getEventListenerCount(event) <= 0 then
            eventFrame:UnregisterEvent(event)
        end
        if observability.enabled then
            trackHandlerCount(event)
        end
        return
    end

    if bucket.map[key] ~= nil then
        bucket.map[key] = nil
        bucket.count = bucket.count - 1
        markBucketDirty(bucket)
    end

    if bucket.count <= 0 then
        handlers[event] = nil
        if getEventListenerCount(event) <= 0 then
            eventFrame:UnregisterEvent(event)
        end
        if observability.enabled then
            trackHandlerCount(event)
        end
        return
    end

    if observability.enabled then
        trackHandlerCount(event)
    end
end

--- Unregister a unit-scoped callback by key
-- @param event string The WoW event name
-- @param unitToken string The unit token used during registration
-- @param key string The key used during registration
function RefineUI:OffUnitEvent(event, unitToken, key)
    if type(unitToken) ~= "string" or unitToken == "" then return end

    local bucket, unitState = getUnitBucket(event, unitToken, false)
    if not event or not bucket or not unitState then return end

    if key == nil then
        unitState.count = unitState.count - bucket.count
        unitState.map[unitToken] = nil
    elseif bucket.map[key] ~= nil then
        bucket.map[key] = nil
        bucket.count = bucket.count - 1
        unitState.count = unitState.count - 1
        markBucketDirty(bucket)
    end

    if bucket.count <= 0 or key == nil then
        unitState.map[unitToken] = nil
    end

    if unitState.count <= 0 then
        unitHandlers[event] = nil
    end

    if getEventListenerCount(event) <= 0 then
        eventFrame:UnregisterEvent(event)
    end

    if observability.enabled then
        trackHandlerCount(event)
        trackUnitHandlerCount(event, unitToken)
    end
end

--- Check if an event has any handlers registered
-- @param event string The WoW event name
-- @return boolean
function RefineUI:HasEventHandlers(event)
    return hasHandlers(event)
end

local function copyTable(src)
    local dst = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            local nested = {}
            for nk, nv in pairs(v) do
                nested[nk] = nv
            end
            dst[k] = nested
        else
            dst[k] = v
        end
    end
    return dst
end

local function syncActiveHandlerSnapshot()
    observability.events.handlers = {}
    if not observability.enabled then return end

    for event, bucket in pairs(handlers) do
        observability.events.handlers[event] = bucket.count
    end

    for event, unitState in pairs(unitHandlers) do
        observability.events.handlers[event] = getEventListenerCount(event)
        for unitToken, bucket in pairs(unitState.map) do
            observability.events.handlers[makeUnitEventKey(event, unitToken)] = bucket.count
        end
    end
end

function RefineUI:SetObservabilityEnabled(enabled)
    observability.enabled = enabled and true or false
    if observability.enabled then
        syncActiveHandlerSnapshot()
    end
end

function RefineUI:IsObservabilityEnabled()
    return observability.enabled == true
end

function RefineUI:GetObservabilitySnapshot()
    return {
        enabled = observability.enabled == true,
        events = {
            registered = copyTable(observability.events.registered),
            fired = copyTable(observability.events.fired),
            handlers = copyTable(observability.events.handlers),
        },
        hooks = {
            registered = copyTable(observability.hooks.registered),
            calls = copyTable(observability.hooks.calls),
        },
    }
end

function RefineUI:ResetObservabilityCounters()
    observability.events.registered = {}
    observability.events.fired = {}
    observability.events.handlers = {}
    observability.hooks.registered = {}
    observability.hooks.calls = {}
    if observability.enabled then
        syncActiveHandlerSnapshot()
    end
end

function RefineUI:ObserveHookRegistration(key, metadata)
    if not observability.enabled or not key then return end
    if type(metadata) == "table" then
        observability.hooks.registered[key] = copyTable(metadata)
    else
        observability.hooks.registered[key] = true
    end
end

function RefineUI:ObserveHookCall(key)
    if not observability.enabled or not key then return end
    incrementCounter(observability.hooks.calls, key)
end

RefineUI:RegisterStartupCallback("Core:ObservabilityConfig", function()
    local general = RefineUI.Config and RefineUI.Config.General
    local debug = general and general.Debug
    RefineUI:SetObservabilityEnabled(debug and debug.Observability == true)
end, 40)

-- Store reference for debugging
RefineUI.EventFrame = eventFrame
