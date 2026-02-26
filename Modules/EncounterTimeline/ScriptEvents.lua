----------------------------------------------------------------------------------------
-- EncounterTimeline Component: ScriptEvents
-- Description: Script-event creation/cancel for pull timer and ready check
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:GetModule("EncounterTimeline")
if not EncounterTimeline then
    return
end

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
local pcall = pcall
local tonumber = tonumber
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local PULL_TIMER_LABEL = "Pull Timer"
local READY_CHECK_LABEL = "Ready Check"
local SCRIPT_EVENT_SPELL_ID = 0
local DEFAULT_SCRIPT_ICON_MASK = 0

local SEVERITY_MEDIUM = (_G.Enum and _G.Enum.EncounterEventSeverity and _G.Enum.EncounterEventSeverity.Medium) or 1

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function NormalizeDuration(value, fallbackValue)
    if RefineUI:IsSecretValue(value) then
        return fallbackValue
    end

    local duration = tonumber(value)
    if type(duration) ~= "number" or duration <= 0 then
        return fallbackValue
    end

    if duration < 1 then
        duration = 1
    elseif duration > 120 then
        duration = 120
    end

    return duration
end

local function NormalizeFileID(value, fallbackValue)
    local fileID = tonumber(value)
    if type(fileID) ~= "number" or fileID <= 0 then
        return fallbackValue
    end
    return math.floor(fileID + 0.5)
end

local function GetDefaultSeverity()
    return SEVERITY_MEDIUM
end

function EncounterTimeline:CanUseScriptEventAPI()
    return C_EncounterTimeline
        and type(C_EncounterTimeline.AddScriptEvent) == "function"
        and type(C_EncounterTimeline.CancelScriptEvent) == "function"
end

function EncounterTimeline:CreateTimelineScriptEvent(label, iconFileID, duration, metadata)
    if not self:CanUseScriptEventAPI() then
        return nil
    end

    local severity = metadata and metadata.severity
    if RefineUI:IsSecretValue(severity) or type(severity) ~= "number" then
        severity = GetDefaultSeverity()
    end

    local iconMask = metadata and metadata.iconMask
    if RefineUI:IsSecretValue(iconMask) or type(iconMask) ~= "number" then
        iconMask = DEFAULT_SCRIPT_ICON_MASK
    end

    local eventRequest = {
        spellID = SCRIPT_EVENT_SPELL_ID,
        iconFileID = iconFileID,
        duration = duration,
        maxQueueDuration = 0,
        overrideName = label,
        icons = iconMask,
        severity = severity,
        paused = false,
    }

    local ok, eventID = pcall(C_EncounterTimeline.AddScriptEvent, eventRequest)
    if ok and self:IsValidEventID(eventID) then
        self:MarkScriptEvent(eventID, {
            label = label,
            sourceToken = self.AUDIO_SOURCE_FILTER.SCRIPT,
            severity = severity,
            iconMask = iconMask,
        })
        return eventID
    end

    return nil
end

function EncounterTimeline:CancelTimelineScriptEvent(eventID)
    if not self:CanUseScriptEventAPI() then
        return
    end
    if not self:IsValidEventID(eventID) then
        return
    end

    pcall(C_EncounterTimeline.CancelScriptEvent, eventID)
    self:ClearEventRuntimeState(eventID)
end

----------------------------------------------------------------------------------------
-- Ready Check
----------------------------------------------------------------------------------------
function EncounterTimeline:CancelReadyCheckTimelineEvent()
    if self.activeReadyCheckScriptEventID then
        self:CancelTimelineScriptEvent(self.activeReadyCheckScriptEventID)
        self.activeReadyCheckScriptEventID = nil
    end
end

function EncounterTimeline:HandleReadyCheckTimelineEvent(readyCheckTimeLeft)
    local config = self:GetConfig()
    if config.ReadyCheckEnable ~= true then
        self:CancelReadyCheckTimelineEvent()
        return
    end
    if not self:CanProcessVisibleTimelineEvents() then
        self:CancelReadyCheckTimelineEvent()
        return
    end

    self:CancelReadyCheckTimelineEvent()

    local fallbackDuration = NormalizeDuration(config.ReadyCheckFallbackDuration, 35)
    local duration = NormalizeDuration(readyCheckTimeLeft, fallbackDuration)
    local iconFileID = NormalizeFileID(config.ReadyCheckIconFileID, config.BigIconIconFallback)

    self.activeReadyCheckScriptEventID = self:CreateTimelineScriptEvent(READY_CHECK_LABEL, iconFileID, duration, {
        severity = SEVERITY_MEDIUM,
    })
end

function EncounterTimeline:HandleReadyCheckFinishedTimelineEvent()
    self:CancelReadyCheckTimelineEvent()
end

----------------------------------------------------------------------------------------
-- Pull Countdown
----------------------------------------------------------------------------------------
function EncounterTimeline:CancelPullTimelineEvent()
    if self.activePullScriptEventID then
        self:CancelTimelineScriptEvent(self.activePullScriptEventID)
        self.activePullScriptEventID = nil
    end
end

function EncounterTimeline:HandlePullStartTimelineEvent(timeRemaining)
    local config = self:GetConfig()
    if config.PullTimerEnable ~= true then
        self:CancelPullTimelineEvent()
        return
    end
    if not self:CanProcessVisibleTimelineEvents() then
        self:CancelPullTimelineEvent()
        return
    end

    self:CancelPullTimelineEvent()

    local duration = NormalizeDuration(timeRemaining, 10)
    local iconFileID = NormalizeFileID(config.PullTimerIconFileID, config.BigIconIconFallback)

    self.activePullScriptEventID = self:CreateTimelineScriptEvent(PULL_TIMER_LABEL, iconFileID, duration, {
        severity = SEVERITY_MEDIUM,
    })
end

function EncounterTimeline:HandlePullCancelTimelineEvent()
    self:CancelPullTimelineEvent()
end
