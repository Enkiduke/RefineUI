----------------------------------------------------------------------------------------
-- RefineUI Utilities
-- Description: Core helper functions (Math, Strings, Timers, Animations).
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local floor, ceil = math.floor, math.ceil
local format = string.format
local C_Timer = C_Timer
local print = print
local next = next
local type = type
local tostring = tostring
local setmetatable = setmetatable
local hooksecurefunc = hooksecurefunc

----------------------------------------------------------------------------------------
-- Messaging API
----------------------------------------------------------------------------------------
local PRIMARY_COLOR = "|cffffd200" -- RefineUI Gold

local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue

function RefineUI:Print(msg, ...)
    -- Safety Check: Secret Values
    if issecretvalue and issecretvalue(msg) then return end
    local count = select("#", ...)
    for i = 1, count do
        if issecretvalue and issecretvalue(select(i, ...)) then return end
    end

    -- Formatting
    if count > 0 then
        local success, formatted = pcall(format, msg, ...)
        if success then
            msg = formatted
        else
            return -- Format failed (unsafe args?)
        end
    end

    local icon = "|TInterface\\GossipFrame\\WorkOrderGossipIcon.blp:12:12:0:0|t"
    if RefineUI.Media and RefineUI.Media.Logo then
        icon = format("|T%s:12:12:0:0|t", RefineUI.Media.Logo)
    end
    
    local prefix, body = msg:match("^(.-:)(.*)$")
    if prefix and body then
        print(format("%s |cffffd200%s|r|cffffffff%s|r", icon, prefix, body))
    else
        print(format("%s |cffffd200%s|r", icon, msg))
    end
end

function RefineUI:Error(...)
    print(PRIMARY_COLOR .. "Refine|rUI Error:|r", ...)
end

----------------------------------------------------------------------------------------
-- Secret Helpers
----------------------------------------------------------------------------------------

function RefineUI:IsSecretValue(v)
    return issecretvalue and issecretvalue(v)
end

function RefineUI:HasValue(v)
    if self:IsSecretValue(v) then
        return true
    end
    return v ~= nil
end

-- Strictly apply values to FontStrings while preserving secret values.
-- opts:
--   format:       string format (e.g. "%.1f")
--   duration:     DurationObject for SetTimerDuration
--   emptyText:    text for nil non-secret values (default "")
function RefineUI:SetFontStringValue(fontString, value, opts)
    if not fontString then return false end
    opts = opts or {}

    local emptyText = opts.emptyText
    if emptyText == nil then emptyText = "" end

    if opts.duration and fontString.SetTimerDuration then
        local ok = pcall(fontString.SetTimerDuration, fontString, opts.duration)
        if ok then return true end
    end

    if opts.format and value ~= nil and fontString.SetFormattedText then
        local ok = pcall(fontString.SetFormattedText, fontString, opts.format, value)
        if ok then return true end
    end

    if not self:IsSecretValue(value) and value == nil then
        local ok = pcall(fontString.SetText, fontString, emptyText)
        return ok
    end

    local ok = pcall(fontString.SetText, fontString, value)
    if ok then return true end

    return false
end

----------------------------------------------------------------------------------------
-- Timer Utilities
----------------------------------------------------------------------------------------

-- Debounce: delays execution until calls stop for 'delay' seconds
local debounces = {}
function RefineUI:Debounce(key, delay, fn)
    if debounces[key] then debounces[key]:Cancel() end
    debounces[key] = C_Timer.NewTimer(delay, function()
        debounces[key] = nil
        fn()
    end)
end

function RefineUI:CancelDebounce(key)
    if debounces[key] then
        debounces[key]:Cancel()
        debounces[key] = nil
    end
end

-- Throttle: executes at most once per 'interval' seconds (leading edge)
local throttles = {}
function RefineUI:Throttle(key, interval, fn)
    if type(fn) ~= "function" then return end
    if throttles[key] then return end

    interval = (type(interval) == "number" and interval > 0) and interval or 0
    if interval > 0 then
        throttles[key] = C_Timer.NewTimer(interval, function()
            throttles[key] = nil
        end)
    else
        throttles[key] = true
    end

    fn()

    if interval == 0 then
        throttles[key] = nil
    end
end

function RefineUI:CancelThrottle(key)
    local handle = throttles[key]
    if handle and type(handle) == "table" and handle.Cancel then
        handle:Cancel()
    end
    throttles[key] = nil
end

-- Cancellable one-shot timer: RefineUI:After(key, delay, fn)
-- Cancels any existing timer with the same key before scheduling
local timers = {}
function RefineUI:After(key, delay, fn)
    if timers[key] then timers[key]:Cancel() end
    timers[key] = C_Timer.NewTimer(delay, function()
        timers[key] = nil
        fn()
    end)
end

function RefineUI:CancelTimer(key)
    if timers[key] then
        timers[key]:Cancel()
        timers[key] = nil
    end
end

----------------------------------------------------------------------------------------
-- Math / Formatting
----------------------------------------------------------------------------------------

function RefineUI:ShortValue(v)
    if issecretvalue and issecretvalue(v) then
        return v
    end
    if v >= 1e6 then
        return format("%.1fm", v / 1e6)
    elseif v >= 1e3 then
        return format("%.1fk", v / 1e3)
    else
        return v
    end
end

function RefineUI:FormatTime(s)
    if s >= 86400 then
        return format("%dd", ceil(s / 86400))
    elseif s >= 3600 then
        return format("%dh", ceil(s / 3600))
    elseif s >= 60 then
        return format("%dm", ceil(s / 60))
    elseif s <= 10 then
        return format("%.1f", s)
    end
    return floor(s)
end

function RefineUI:RGBToHex(r, g, b)
    r = r <= 1 and r >= 0 and r or 1
    g = g <= 1 and g >= 0 and g or 1
    b = b <= 1 and b >= 0 and b or 1
    return format("|cff%02x%02x%02x", r*255, g*255, b*255)
end

----------------------------------------------------------------------------------------
-- Frame Fading (Animations)
----------------------------------------------------------------------------------------
local UIFrameFadeIn = UIFrameFadeIn
local UIFrameFadeOut = UIFrameFadeOut

function RefineUI:FadeIn(frame, duration, alpha)
    if not frame then return end
    alpha = alpha or 1
    if frame:GetAlpha() >= alpha then return end
    UIFrameFadeIn(frame, duration or 0.4, frame:GetAlpha(), alpha)
end

function RefineUI:FadeOut(frame, duration, alpha)
    if not frame then return end
    alpha = alpha or 0
    if frame:GetAlpha() <= alpha then return end
    UIFrameFadeOut(frame, duration or 0.4, frame:GetAlpha(), alpha)
end

----------------------------------------------------------------------------------------
-- Frame Helpers
----------------------------------------------------------------------------------------
function RefineUI.SetXYPoint(frame, xOffset, yOffset)
    if not frame then return end
    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
    if not point then return end
    frame:SetPoint(point, relativeTo, relativePoint, xOffset or xOfs, yOffset or yOfs)
end

----------------------------------------------------------------------------------------
-- Secure Data Registry (Weak-Key External State)
----------------------------------------------------------------------------------------
RefineUI._dataRegistries = RefineUI._dataRegistries or {}

local VALID_WEAK_MODES = {
    k = true,
    v = true,
    kv = true,
    vk = true,
}

local function isValidRegistryName(name)
    return type(name) == "string" and name ~= ""
end

function RefineUI:CreateDataRegistry(name, weakMode)
    if not isValidRegistryName(name) then return nil end

    local registry = self._dataRegistries[name]
    if registry then
        return registry
    end

    weakMode = weakMode or "k"
    if weakMode ~= "" and not VALID_WEAK_MODES[weakMode] then
        weakMode = "k"
    end

    registry = setmetatable({}, { __mode = weakMode })
    self._dataRegistries[name] = registry
    return registry
end

function RefineUI:GetDataRegistry(name)
    if not isValidRegistryName(name) then return nil end
    return self._dataRegistries[name]
end

function RefineUI:RegistryGet(name, owner, key, defaultValue)
    if not isValidRegistryName(name) or owner == nil then
        return defaultValue
    end

    local registry = self._dataRegistries[name]
    if not registry then
        return defaultValue
    end

    local ownerData = registry[owner]
    if ownerData == nil then
        return defaultValue
    end

    if key == nil then
        return ownerData
    end

    local value = ownerData[key]
    if value == nil then
        return defaultValue
    end

    return value
end

function RefineUI:RegistrySet(name, owner, key, value)
    if not isValidRegistryName(name) or owner == nil then
        return nil
    end

    local registry = self:CreateDataRegistry(name)
    if not registry then return nil end

    if key == nil then
        registry[owner] = value
        return value
    end

    local ownerData = registry[owner]
    if type(ownerData) ~= "table" then
        ownerData = {}
        registry[owner] = ownerData
    end

    ownerData[key] = value
    return value
end

function RefineUI:RegistryClear(name, owner, key)
    if not isValidRegistryName(name) or owner == nil then return nil end

    local registry = self._dataRegistries[name]
    if not registry then return nil end

    if key == nil then
        registry[owner] = nil
        return nil
    end

    local ownerData = registry[owner]
    if type(ownerData) ~= "table" then return nil end

    ownerData[key] = nil
    if next(ownerData) == nil then
        registry[owner] = nil
    end
    return nil
end

----------------------------------------------------------------------------------------
-- Hook Guards
----------------------------------------------------------------------------------------
RefineUI._hookRegistry = RefineUI._hookRegistry or {}

local function describeTarget(target)
    if type(target) == "string" then
        return target
    end
    if type(target) == "table" then
        -- Mixin tables can define GetName() that assumes frame instance fields.
        -- Only call GetName() on actual frame objects, and always pcall it.
        local getObjectType = target.GetObjectType
        local getName = target.GetName
        if type(getObjectType) == "function" and type(getName) == "function" then
            local okType, objectType = pcall(getObjectType, target)
            if okType and type(objectType) == "string" and objectType ~= "" then
                local okName, name = pcall(getName, target)
                if okName
                    and type(name) == "string"
                    and name ~= ""
                    and (not issecretvalue or not issecretvalue(name))
                    and (not canaccessvalue or canaccessvalue(name))
                then
                    return name
                end
            end
        end
    end
    return tostring(target)
end

local function observeHookRegistration(key, metadata)
    if RefineUI.ObserveHookRegistration then
        RefineUI:ObserveHookRegistration(key, metadata)
    end
end

local function observeHookCall(key)
    if RefineUI.ObserveHookCall then
        RefineUI:ObserveHookCall(key)
    end
end

local function wrapObservedHook(key, fn)
    return function(...)
        observeHookCall(key)
        return fn(...)
    end
end

function RefineUI:HookOnce(key, target, methodOrFn, fn)
    if type(key) ~= "string" or key == "" then
        return false, "invalid_key"
    end
    if self._hookRegistry[key] then
        return false, "already_hooked"
    end

    local wrapped
    local ok

    if type(target) == "string" then
        if type(methodOrFn) ~= "function" then
            return false, "invalid_callback"
        end
        if type(_G[target]) ~= "function" then
            return false, "target_missing"
        end

        wrapped = wrapObservedHook(key, methodOrFn)
        ok = pcall(hooksecurefunc, target, wrapped)
        if not ok then
            return false, "hook_failed"
        end

        self._hookRegistry[key] = true
        observeHookRegistration(key, {
            kind = "secure_global",
            target = target,
        })
        return true
    end

    if target == nil then
        return false, "target_missing"
    end
    if type(methodOrFn) ~= "string" or methodOrFn == "" then
        return false, "invalid_method"
    end
    if type(fn) ~= "function" then
        return false, "invalid_callback"
    end
    if type(target[methodOrFn]) ~= "function" then
        return false, "method_missing"
    end

    wrapped = wrapObservedHook(key, fn)
    ok = pcall(hooksecurefunc, target, methodOrFn, wrapped)
    if not ok then
        return false, "hook_failed"
    end

    self._hookRegistry[key] = true
    observeHookRegistration(key, {
        kind = "secure_method",
        target = describeTarget(target),
        method = methodOrFn,
    })
    return true
end

function RefineUI:HookScriptOnce(key, target, script, fn)
    if type(key) ~= "string" or key == "" then
        return false, "invalid_key"
    end
    if self._hookRegistry[key] then
        return false, "already_hooked"
    end
    if target == nil then
        return false, "target_missing"
    end
    if type(target.HookScript) ~= "function" then
        return false, "hookscript_missing"
    end
    if type(script) ~= "string" or script == "" then
        return false, "invalid_script"
    end
    if type(fn) ~= "function" then
        return false, "invalid_callback"
    end

    local wrapped = wrapObservedHook(key, fn)
    local ok = pcall(target.HookScript, target, script, wrapped)
    if not ok then
        return false, "hook_failed"
    end

    self._hookRegistry[key] = true
    observeHookRegistration(key, {
        kind = "script",
        target = describeTarget(target),
        script = script,
    })
    return true
end

function RefineUI:IsHookRegistered(key)
    if type(key) ~= "string" or key == "" then
        return false
    end
    return self._hookRegistry[key] == true
end

function RefineUI:ResetHookRegistration(key)
    if type(key) ~= "string" or key == "" then return end
    self._hookRegistry[key] = nil
end

----------------------------------------------------------------------------------------
-- Curve constants (Shim)
----------------------------------------------------------------------------------------
RefineUI.ScaleTo100 = 1.0
if CurveConstants and CurveConstants.ScaleTo100 then
    RefineUI.ScaleTo100 = CurveConstants.ScaleTo100
end

function RefineUI.GetPercentCurve()
    if RefineUI.PercentCurve then return RefineUI.PercentCurve end

    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step) -- No interpolation between points

    -- Create 101 points from 0 to 100
    for i = 0, 100 do
        curve:AddPoint(i / 100, i)
    end
    
    RefineUI.PercentCurve = curve
    return curve
end


function RefineUI.GetLinearCurve()
    if RefineUI.LinearCurve then return RefineUI.LinearCurve end

    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    -- Create point from 0 to 3600 (1 hour support)
    curve:AddPoint(0, 0)
    curve:AddPoint(3600, 3600)
    
    RefineUI.LinearCurve = curve
    return curve
end

function RefineUI.GetUnitCurve()
    if RefineUI.UnitCurve then return RefineUI.UnitCurve end

    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    curve:AddPoint(0, 0)
    curve:AddPoint(1, 1)
    
    RefineUI.UnitCurve = curve
    return curve
end

function RefineUI.GetCastAlphaCurve()
    if RefineUI.CastAlphaCurve then return RefineUI.CastAlphaCurve end

    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    -- X = Seconds Remaining, Y = Alpha
    -- Fades in from 0.6 to 1.0 over the last 3.0 seconds of the cast
    curve:AddPoint(0.0, 1.0) -- 0s remaining: Full Alpha
    curve:AddPoint(3.0, 0.6) -- 3s remaining: Default Alpha (0.6)
    curve:AddPoint(3600, 0.6) -- Beyond 3s: Stay at Default Alpha
    
    RefineUI.CastAlphaCurve = curve
    return curve
end

function RefineUI.GetLinearPercentCurve()
    if RefineUI.LinearPercentCurve then return RefineUI.LinearPercentCurve end

    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    curve:AddPoint(0, 0)
    curve:AddPoint(1, 100)
    
    RefineUI.LinearPercentCurve = curve
    return curve
end

----------------------------------------------------------------------------------------
-- Chat Commands
----------------------------------------------------------------------------------------
function RefineUI:RegisterChatCommand(command, func)
    local name = command:upper()
    _G["SLASH_"..name.."1"] = "/"..command:lower()
    SlashCmdList[name] = func
end

RefineUI.ChatCommands = {}

function RefineUI:HandleChatCommand(msg)
    if not msg or msg == "" then
        RefineUI:Print("Options not yet implemented.")
        return
    end
    
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    if command then
        command = command:lower()
        if RefineUI.ChatCommands[command] then
            RefineUI.ChatCommands[command](rest)
            return
        end
    end
    
    RefineUI:Print("Unknown command: %s", msg)
end

function RefineUI:LoadCommands()
    self:RegisterChatCommand("rl", ReloadUI)
    self:RegisterChatCommand("refineui", function(msg) RefineUI:HandleChatCommand(msg) end)
    self:RegisterChatCommand("refine", function(msg) RefineUI:HandleChatCommand(msg) end)
    
    self.ChatCommands["reset"] = function() RefineUI:ResetProfile() end
    self:RegisterChatCommand("rreset", self.ChatCommands["reset"])

    if self.LoadDebugCommands then
        self:LoadDebugCommands()
    end
end

RefineUI:RegisterStartupCallback("Core:Commands", function()
    RefineUI:LoadCommands()
end, 90)

----------------------------------------------------------------------------------------
-- Utils
----------------------------------------------------------------------------------------
function RefineUI:Dump(val)
    if DevTools_Dump then
        DevTools_Dump(val)
    else
        print(val)
    end
end
