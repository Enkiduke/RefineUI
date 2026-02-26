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

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}  -- handlers[event] = { [key] = fn, ... }

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
local function hasHandlers(event)
    local bucket = handlers[event]
    if not bucket then return false end
    for _ in pairs(bucket) do return true end
    return false
end

local function countHandlers(event)
    local bucket = handlers[event]
    if not bucket then return 0 end
    local count = 0
    for _ in pairs(bucket) do
        count = count + 1
    end
    return count
end

local function incrementCounter(map, key)
    map[key] = (map[key] or 0) + 1
end

local function trackHandlerCount(event)
    if not observability.enabled then return end
    observability.events.handlers[event] = countHandlers(event)
end

local function dispatch(_, event, ...)
    local bucket = handlers[event]
    if not bucket then return end

    if observability.enabled then
        incrementCounter(observability.events.fired, event)
    end

    for key, fn in pairs(bucket) do
        local ok, err = pcall(fn, event, ...)
        if not ok then
            -- Secret-safe error reporting with source hints.
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

    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end

    handlers[event][key] = fn

    if observability.enabled then
        incrementCounter(observability.events.registered, event)
        trackHandlerCount(event)
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

--- Unregister a callback by key
-- @param event string The WoW event name
-- @param key string The key used during registration
function RefineUI:OffEvent(event, key)
    if not event or not handlers[event] then return end
    if key == nil then
        handlers[event] = nil
        eventFrame:UnregisterEvent(event)
        if observability.enabled then
            observability.events.handlers[event] = 0
        end
        return
    end
    handlers[event][key] = nil

    if not hasHandlers(event) then
        handlers[event] = nil
        eventFrame:UnregisterEvent(event)
        if observability.enabled then
            observability.events.handlers[event] = 0
        end
        return
    end

    if observability.enabled then
        trackHandlerCount(event)
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

    for event in pairs(handlers) do
        observability.events.handlers[event] = countHandlers(event)
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
