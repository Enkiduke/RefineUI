----------------------------------------------------------------------------------------
-- CDM for RefineUI
-- Description: Root module registration, shared constants, and key builders.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:RegisterModule("CDM")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local tostring = tostring
local select = select
local type = type
local pairs = pairs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
CDM.KEY_PREFIX = "CDM"
CDM.PERF_STATE = {
    counters = {},
    timings = {},
}

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:BuildKey(...)
    local key = self.KEY_PREFIX
    for i = 1, select("#", ...) do
        key = key .. ":" .. tostring(select(i, ...))
    end
    return key
end

function CDM:ShouldUseRuntimeResolverFallback()
    return self.auraProbeInitialized ~= true
end

function CDM:IncrementPerfCounter(name, amount)
    if type(name) ~= "string" or name == "" then
        return
    end

    local counters = self.PERF_STATE and self.PERF_STATE.counters
    if type(counters) ~= "table" then
        return
    end

    local delta = type(amount) == "number" and amount or 1
    counters[name] = (counters[name] or 0) + delta
end

function CDM:RecordPerfSample(name, elapsed)
    if type(name) ~= "string" or name == "" or type(elapsed) ~= "number" then
        return
    end

    local timings = self.PERF_STATE and self.PERF_STATE.timings
    if type(timings) ~= "table" then
        return
    end

    local entry = timings[name]
    if type(entry) ~= "table" then
        entry = {
            count = 0,
            total = 0,
            max = 0,
        }
        timings[name] = entry
    end

    entry.count = entry.count + 1
    entry.total = entry.total + elapsed
    if elapsed > entry.max then
        entry.max = elapsed
    end
end

function CDM:ResetPerfState()
    local perfState = self.PERF_STATE
    if type(perfState) ~= "table" then
        return
    end

    local counters = perfState.counters
    if type(counters) == "table" then
        for key in pairs(counters) do
            counters[key] = nil
        end
    end

    local timings = perfState.timings
    if type(timings) == "table" then
        for key in pairs(timings) do
            timings[key] = nil
        end
    end
end

CDM.TRACKER_BUCKETS = { "Left", "Right", "Bottom", "Radial" }
CDM.NOT_TRACKED_KEY = "NotTracked"
CDM.BUCKET_LABELS = {
    Left = "Left",
    Right = "Right",
    Bottom = "Bottom",
    Radial = "Radial",
    NotTracked = "Not Tracked",
}
CDM.TRACKER_FRAME_NAMES = {
    Left = "RefineUI_CDM_LeftTracker",
    Right = "RefineUI_CDM_RightTracker",
    Bottom = "RefineUI_CDM_BottomTracker",
    Radial = "RefineUI_CDM_RadialTracker",
}
CDM.TRACKER_DEFAULT_DIRECTION = {
    Left = "LEFT",
    Right = "RIGHT",
    Bottom = "LEFT",
    Radial = "RIGHT",
}
CDM.BLIZZARD_CATEGORY = {
    TRACKED_BUFF = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff,
    TRACKED_BAR = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar,
    HIDDEN_AURA = (Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.HiddenAura) or -2,
}
CDM.NATIVE_AURA_VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}
CDM.SETTINGS_SECTION_TITLE = "RefineUI Aura Trackers"
CDM.SETTINGS_FRAME_NAME = "RefineUI_CDM_Settings"
CDM.UPDATE_THROTTLE_KEY = CDM:BuildKey("Refresh")
CDM.UPDATE_TIMER_KEY = CDM:BuildKey("Refresh", "NextFrame")
CDM.STATE_REGISTRY = CDM:BuildKey("State")

function CDM:GetCooldownViewerSettingsFrame()
    return self.settingsFrame or _G[CDM.SETTINGS_FRAME_NAME]
end

function CDM:GetBlizzardCooldownViewerSettingsFrame()
    return _G.CooldownViewerSettings
end
