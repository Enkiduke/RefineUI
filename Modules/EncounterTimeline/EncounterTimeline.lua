----------------------------------------------------------------------------------------
-- EncounterTimeline for RefineUI
-- Description: Root module registration, config normalization, and shared helpers
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:RegisterModule("EncounterTimeline")

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
local max = math.max
local min = math.min
local next = next
local pcall = pcall
local select = select
local tonumber = tonumber
local tostring = tostring
local type = type
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local AUDIO_COUNTDOWN_MODE = {
    LATEST_WINS = "latest_wins",
}

local AUDIO_SOURCE_FILTER = {
    ALL = "all",
    ENCOUNTER = "encounter",
    SCRIPT = "script",
}

local AUDIO_UNKNOWN_SEVERITY_POLICY = {
    EXCLUDE = "exclude",
    INCLUDE = "include",
    AS_MEDIUM = "as_medium",
}

local SKIN_BORDER_COLOR_MODE = {
    ICON_CLASSIFICATION = "icon_classification",
    SEVERITY = "severity",
    EVENT_COLOR = "event_color",
    DEFAULT = "default",
}

local TRACK_TEXT_ANCHOR = {
    LEFT = "LEFT",
    RIGHT = "RIGHT",
}

local BIG_ICON_ORIENTATION = {
    HORIZONTAL = "HORIZONTAL",
    VERTICAL = "VERTICAL",
}

local BIG_ICON_GROW_DIRECTION = {
    RIGHT = "RIGHT",
    LEFT = "LEFT",
    UP = "UP",
    DOWN = "DOWN",
    CENTERED = "CENTERED",
}

local BIG_ICON_DEFAULT_GROW_DIRECTION_BY_ORIENTATION = {
    [BIG_ICON_ORIENTATION.HORIZONTAL] = BIG_ICON_GROW_DIRECTION.RIGHT,
    [BIG_ICON_ORIENTATION.VERTICAL] = BIG_ICON_GROW_DIRECTION.UP,
}

local AUDIO_CHANNEL_DEFAULT = "Master"
local BIG_ICON_FRAME_NAME = "RefineUI_EncounterTimeline_BigIcon"

local VALID_AUDIO_CHANNELS = {
    Master = true,
    SFX = true,
    Music = true,
    Ambience = true,
    Dialog = true,
}

local CONFIG_DEFAULTS = {
    Enable = true,
    SkinEnabled = true,
    SkinTrackView = true,
    SkinTimerView = true,
    SkinBorderColorMode = SKIN_BORDER_COLOR_MODE.ICON_CLASSIFICATION,
    TrackTextAnchor = TRACK_TEXT_ANCHOR.LEFT,
    SkinUseEventColorBorder = true,
    SkinUseIconMaskStyles = true,
    SkinDispelBorderEnable = true,
    SkinDeadlyGlowEnable = true,
    RespectUserViewMode = true,
    BigIconEnable = true,
    BigIconSize = 72,
    BigIconThresholdSeconds = 5,
    BigIconSpacing = 6,
    BigIconOrientation = BIG_ICON_ORIENTATION.HORIZONTAL,
    BigIconGrowDirection = BIG_ICON_GROW_DIRECTION.RIGHT,
    BigIconIconFallback = 134400,
    PullTimerEnable = true,
    PullTimerIconFileID = 134376,
    ReadyCheckEnable = true,
    ReadyCheckIconFileID = 134400,
    ReadyCheckFallbackDuration = 35,
    AudioCountdownEnable = true,
    AudioCountdownMode = AUDIO_COUNTDOWN_MODE.LATEST_WINS,
    AudioCountdownChannel = AUDIO_CHANNEL_DEFAULT,
    AudioCountdownVoicePrefix = "EncounterCountdown",
    AudioCountdownSeverityLow = true,
    AudioCountdownSeverityMedium = true,
    AudioCountdownSeverityHigh = true,
    AudioCountdownRoleFilterEnabled = false,
    AudioCountdownIncludeRoleless = false,
    AudioCountdownSourceFilter = AUDIO_SOURCE_FILTER.ALL,
    AudioCountdownUnknownSeverityPolicy = AUDIO_UNKNOWN_SEVERITY_POLICY.EXCLUDE,
}

EncounterTimeline.KEY_PREFIX = "EncounterTimeline"
EncounterTimeline.STATE_REGISTRY = EncounterTimeline.KEY_PREFIX .. ":State"
EncounterTimeline.BLIZZARD_ADDON_NAME = "Blizzard_EncounterTimeline"
EncounterTimeline.BIG_ICON_FRAME_NAME = BIG_ICON_FRAME_NAME
EncounterTimeline.AUDIO_COUNTDOWN_MODE = AUDIO_COUNTDOWN_MODE
EncounterTimeline.AUDIO_SOURCE_FILTER = AUDIO_SOURCE_FILTER
EncounterTimeline.AUDIO_UNKNOWN_SEVERITY_POLICY = AUDIO_UNKNOWN_SEVERITY_POLICY
EncounterTimeline.SKIN_BORDER_COLOR_MODE = SKIN_BORDER_COLOR_MODE
EncounterTimeline.TRACK_TEXT_ANCHOR = TRACK_TEXT_ANCHOR
EncounterTimeline.BIG_ICON_ORIENTATION = BIG_ICON_ORIENTATION
EncounterTimeline.BIG_ICON_GROW_DIRECTION = BIG_ICON_GROW_DIRECTION

----------------------------------------------------------------------------------------
-- Key Helpers
----------------------------------------------------------------------------------------
local function IsUnreadableValue(value)
    if value == nil then
        return false
    end
    if issecretvalue and issecretvalue(value) then
        return true
    end
    if canaccessvalue and not canaccessvalue(value) then
        return true
    end
    if RefineUI.IsSecretValue and RefineUI:IsSecretValue(value) then
        return true
    end
    return false
end

local function HasAnyValue(value)
    return value ~= nil
end

function EncounterTimeline:BuildKey(...)
    local key = self.KEY_PREFIX
    for index = 1, select("#", ...) do
        key = key .. ":" .. tostring(select(index, ...))
    end
    return key
end

function EncounterTimeline:BuildFrameHookKey(frame, methodName, qualifier)
    local frameToken
    if frame and type(frame.GetName) == "function" then
        frameToken = frame:GetName()
    end
    if type(frameToken) ~= "string" or frameToken == "" then
        frameToken = tostring(frame)
    end
    return self:BuildKey("Hook", frameToken, methodName or "Unknown", qualifier or "Default")
end

function EncounterTimeline:IsNonSecretNumber(value)
    return not IsUnreadableValue(value) and type(value) == "number"
end

function EncounterTimeline:IsValidEventID(eventID)
    return self:IsNonSecretNumber(eventID) and eventID > 0
end

----------------------------------------------------------------------------------------
-- Config
----------------------------------------------------------------------------------------
local function NormalizeBoolean(value, defaultValue)
    if type(value) == "boolean" then
        return value
    end
    return defaultValue
end

local function NormalizeInteger(value, defaultValue, minValue, maxValue)
    local normalized = tonumber(value)
    if type(normalized) ~= "number" then
        normalized = defaultValue
    end

    normalized = math.floor(normalized + 0.5)
    normalized = max(minValue, normalized)
    normalized = min(maxValue, normalized)
    return normalized
end

local function NormalizeToken(value, validTokens, defaultValue)
    if type(value) == "string" and validTokens[value] == true then
        return value
    end
    return defaultValue
end

local function NormalizeAudioMode(value)
    if value == AUDIO_COUNTDOWN_MODE.LATEST_WINS then
        return value
    end
    return AUDIO_COUNTDOWN_MODE.LATEST_WINS
end

local function NormalizeAudioChannel(value)
    if type(value) == "string" and VALID_AUDIO_CHANNELS[value] then
        return value
    end
    return AUDIO_CHANNEL_DEFAULT
end

local function NormalizeVoicePrefix(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return CONFIG_DEFAULTS.AudioCountdownVoicePrefix
end

local function NormalizeSkinBorderColorMode(value)
    return NormalizeToken(value, {
        [SKIN_BORDER_COLOR_MODE.ICON_CLASSIFICATION] = true,
        [SKIN_BORDER_COLOR_MODE.SEVERITY] = true,
        [SKIN_BORDER_COLOR_MODE.EVENT_COLOR] = true,
        [SKIN_BORDER_COLOR_MODE.DEFAULT] = true,
    }, CONFIG_DEFAULTS.SkinBorderColorMode)
end

local function NormalizeTrackTextAnchor(value)
    return NormalizeToken(value, {
        [TRACK_TEXT_ANCHOR.LEFT] = true,
        [TRACK_TEXT_ANCHOR.RIGHT] = true,
    }, CONFIG_DEFAULTS.TrackTextAnchor)
end

local function NormalizeBigIconGrowDirection(value)
    return NormalizeToken(value, {
        [BIG_ICON_GROW_DIRECTION.RIGHT] = true,
        [BIG_ICON_GROW_DIRECTION.LEFT] = true,
        [BIG_ICON_GROW_DIRECTION.UP] = true,
        [BIG_ICON_GROW_DIRECTION.DOWN] = true,
        [BIG_ICON_GROW_DIRECTION.CENTERED] = true,
    }, CONFIG_DEFAULTS.BigIconGrowDirection)
end

local function NormalizeBigIconOrientation(value)
    return NormalizeToken(value, {
        [BIG_ICON_ORIENTATION.HORIZONTAL] = true,
        [BIG_ICON_ORIENTATION.VERTICAL] = true,
    }, CONFIG_DEFAULTS.BigIconOrientation)
end

local function NormalizeBigIconGrowDirectionForOrientation(value, orientation)
    local normalizedOrientation = NormalizeBigIconOrientation(orientation)
    local defaultDirection = BIG_ICON_DEFAULT_GROW_DIRECTION_BY_ORIENTATION[normalizedOrientation] or CONFIG_DEFAULTS.BigIconGrowDirection

    if normalizedOrientation == BIG_ICON_ORIENTATION.VERTICAL then
        return NormalizeToken(value, {
            [BIG_ICON_GROW_DIRECTION.UP] = true,
            [BIG_ICON_GROW_DIRECTION.DOWN] = true,
            [BIG_ICON_GROW_DIRECTION.CENTERED] = true,
        }, defaultDirection)
    end

    return NormalizeToken(value, {
        [BIG_ICON_GROW_DIRECTION.LEFT] = true,
        [BIG_ICON_GROW_DIRECTION.RIGHT] = true,
        [BIG_ICON_GROW_DIRECTION.CENTERED] = true,
    }, defaultDirection)
end

local function NormalizeAudioSourceFilter(value)
    return NormalizeToken(value, {
        [AUDIO_SOURCE_FILTER.ALL] = true,
        [AUDIO_SOURCE_FILTER.ENCOUNTER] = true,
        [AUDIO_SOURCE_FILTER.SCRIPT] = true,
    }, CONFIG_DEFAULTS.AudioCountdownSourceFilter)
end

local function NormalizeAudioUnknownSeverityPolicy(value)
    return NormalizeToken(value, {
        [AUDIO_UNKNOWN_SEVERITY_POLICY.EXCLUDE] = true,
        [AUDIO_UNKNOWN_SEVERITY_POLICY.INCLUDE] = true,
        [AUDIO_UNKNOWN_SEVERITY_POLICY.AS_MEDIUM] = true,
    }, CONFIG_DEFAULTS.AudioCountdownUnknownSeverityPolicy)
end

function EncounterTimeline:GetConfig()
    RefineUI.Config = RefineUI.Config or {}
    RefineUI.Config.EncounterTimeline = RefineUI.Config.EncounterTimeline or {}

    local config = RefineUI.Config.EncounterTimeline

    config.Enable = NormalizeBoolean(config.Enable, CONFIG_DEFAULTS.Enable)
    config.SkinEnabled = NormalizeBoolean(config.SkinEnabled, CONFIG_DEFAULTS.SkinEnabled)
    config.SkinTrackView = NormalizeBoolean(config.SkinTrackView, CONFIG_DEFAULTS.SkinTrackView)
    config.SkinTimerView = NormalizeBoolean(config.SkinTimerView, CONFIG_DEFAULTS.SkinTimerView)
    if type(config.SkinBorderColorMode) ~= "string" and config.SkinUseEventColorBorder == true then
        config.SkinBorderColorMode = SKIN_BORDER_COLOR_MODE.EVENT_COLOR
    end
    config.SkinBorderColorMode = NormalizeSkinBorderColorMode(config.SkinBorderColorMode)
    config.TrackTextAnchor = NormalizeTrackTextAnchor(config.TrackTextAnchor)
    config.SkinUseEventColorBorder = NormalizeBoolean(config.SkinUseEventColorBorder, CONFIG_DEFAULTS.SkinUseEventColorBorder)
    config.SkinUseIconMaskStyles = NormalizeBoolean(config.SkinUseIconMaskStyles, CONFIG_DEFAULTS.SkinUseIconMaskStyles)
    config.SkinDispelBorderEnable = NormalizeBoolean(config.SkinDispelBorderEnable, CONFIG_DEFAULTS.SkinDispelBorderEnable)
    config.SkinDeadlyGlowEnable = NormalizeBoolean(config.SkinDeadlyGlowEnable, CONFIG_DEFAULTS.SkinDeadlyGlowEnable)
    config.RespectUserViewMode = NormalizeBoolean(config.RespectUserViewMode, CONFIG_DEFAULTS.RespectUserViewMode)
    config.BigIconEnable = NormalizeBoolean(config.BigIconEnable, CONFIG_DEFAULTS.BigIconEnable)
    config.BigIconSize = NormalizeInteger(config.BigIconSize, CONFIG_DEFAULTS.BigIconSize, 32, 256)
    config.BigIconThresholdSeconds = NormalizeInteger(config.BigIconThresholdSeconds, CONFIG_DEFAULTS.BigIconThresholdSeconds, 1, 15)
    config.BigIconSpacing = NormalizeInteger(config.BigIconSpacing, CONFIG_DEFAULTS.BigIconSpacing, 0, 40)
    config.BigIconGrowDirection = NormalizeBigIconGrowDirection(config.BigIconGrowDirection)
    if type(config.BigIconOrientation) ~= "string" then
        if config.BigIconGrowDirection == BIG_ICON_GROW_DIRECTION.UP or config.BigIconGrowDirection == BIG_ICON_GROW_DIRECTION.DOWN then
            config.BigIconOrientation = BIG_ICON_ORIENTATION.VERTICAL
        else
            config.BigIconOrientation = BIG_ICON_ORIENTATION.HORIZONTAL
        end
    end
    config.BigIconOrientation = NormalizeBigIconOrientation(config.BigIconOrientation)
    config.BigIconGrowDirection = NormalizeBigIconGrowDirectionForOrientation(config.BigIconGrowDirection, config.BigIconOrientation)
    config.BigIconIconFallback = NormalizeInteger(config.BigIconIconFallback, CONFIG_DEFAULTS.BigIconIconFallback, 1, 9999999)
    config.PullTimerEnable = NormalizeBoolean(config.PullTimerEnable, CONFIG_DEFAULTS.PullTimerEnable)
    config.PullTimerIconFileID = NormalizeInteger(config.PullTimerIconFileID, CONFIG_DEFAULTS.PullTimerIconFileID, 1, 9999999)
    config.ReadyCheckEnable = NormalizeBoolean(config.ReadyCheckEnable, CONFIG_DEFAULTS.ReadyCheckEnable)
    config.ReadyCheckIconFileID = NormalizeInteger(config.ReadyCheckIconFileID, CONFIG_DEFAULTS.ReadyCheckIconFileID, 1, 9999999)
    config.ReadyCheckFallbackDuration = NormalizeInteger(config.ReadyCheckFallbackDuration, CONFIG_DEFAULTS.ReadyCheckFallbackDuration, 1, 120)
    config.AudioCountdownEnable = NormalizeBoolean(config.AudioCountdownEnable, CONFIG_DEFAULTS.AudioCountdownEnable)
    config.AudioCountdownMode = NormalizeAudioMode(config.AudioCountdownMode)
    config.AudioCountdownChannel = NormalizeAudioChannel(config.AudioCountdownChannel)
    config.AudioCountdownVoicePrefix = NormalizeVoicePrefix(config.AudioCountdownVoicePrefix)
    config.AudioCountdownSeverityLow = NormalizeBoolean(config.AudioCountdownSeverityLow, CONFIG_DEFAULTS.AudioCountdownSeverityLow)
    config.AudioCountdownSeverityMedium = NormalizeBoolean(config.AudioCountdownSeverityMedium, CONFIG_DEFAULTS.AudioCountdownSeverityMedium)
    config.AudioCountdownSeverityHigh = NormalizeBoolean(config.AudioCountdownSeverityHigh, CONFIG_DEFAULTS.AudioCountdownSeverityHigh)
    config.AudioCountdownRoleFilterEnabled = NormalizeBoolean(config.AudioCountdownRoleFilterEnabled, CONFIG_DEFAULTS.AudioCountdownRoleFilterEnabled)
    config.AudioCountdownIncludeRoleless = NormalizeBoolean(config.AudioCountdownIncludeRoleless, CONFIG_DEFAULTS.AudioCountdownIncludeRoleless)
    config.AudioCountdownSourceFilter = NormalizeAudioSourceFilter(config.AudioCountdownSourceFilter)
    config.AudioCountdownUnknownSeverityPolicy = NormalizeAudioUnknownSeverityPolicy(config.AudioCountdownUnknownSeverityPolicy)

    return config
end

function EncounterTimeline:IsEnabled()
    return self:GetConfig().Enable ~= false
end

function EncounterTimeline:IsTimelineVisible()
    local timelineFrame = _G and _G.EncounterTimeline
    if not timelineFrame or type(timelineFrame.IsShown) ~= "function" then
        return false
    end

    local ok, shown = pcall(timelineFrame.IsShown, timelineFrame)
    if not ok or IsUnreadableValue(shown) or type(shown) ~= "boolean" then
        return false
    end

    return shown
end

function EncounterTimeline:HasTimelineEvents()
    if not C_EncounterTimeline or type(C_EncounterTimeline.HasAnyEvents) ~= "function" then
        return false
    end

    local ok, hasAnyEvents = pcall(C_EncounterTimeline.HasAnyEvents)
    if not ok or IsUnreadableValue(hasAnyEvents) then
        return false
    end

    return hasAnyEvents == true
end

function EncounterTimeline:CanProcessVisibleTimelineEvents()
    if not self:IsEnabled() then
        return false
    end
    if not self:IsTimelineVisible() then
        return false
    end
    return C_EncounterTimeline ~= nil
end

----------------------------------------------------------------------------------------
-- Metadata Helpers
----------------------------------------------------------------------------------------
function EncounterTimeline:NormalizeEventSourceToken(sourceValue)
    local eventSource = _G.Enum and _G.Enum.EncounterTimelineEventSource
    if type(sourceValue) ~= "number" or not eventSource then
        return nil
    end

    if sourceValue == eventSource.Encounter then
        return AUDIO_SOURCE_FILTER.ENCOUNTER
    end
    if sourceValue == eventSource.Script then
        return AUDIO_SOURCE_FILTER.SCRIPT
    end

    return nil
end

function EncounterTimeline:UpdateEventMetadataFromInfo(eventID, eventInfo)
    if not self:IsValidEventID(eventID) then
        return
    end
    if IsUnreadableValue(eventInfo) or type(eventInfo) ~= "table" then
        return
    end

    local metadata = {}
    local hasData = false

    local sourceValue = eventInfo.source
    if not IsUnreadableValue(sourceValue) and type(sourceValue) == "number" then
        metadata.sourceEnum = sourceValue
        metadata.sourceToken = self:NormalizeEventSourceToken(sourceValue)
        hasData = true
    end

    local severity = eventInfo.severity
    if not IsUnreadableValue(severity) and type(severity) == "number" then
        metadata.severity = severity
        hasData = true
    end

    local iconMask = eventInfo.icons
    if not IsUnreadableValue(iconMask) and type(iconMask) == "number" then
        metadata.iconMask = iconMask
        hasData = true
    end

    local isApproximate = eventInfo.isApproximate
    if not IsUnreadableValue(isApproximate) and type(isApproximate) == "boolean" then
        metadata.isApproximate = isApproximate
        hasData = true
    end

    local okIcon, iconFileID = pcall(function(info)
        return info.iconFileID
    end, eventInfo)
    if okIcon and HasAnyValue(iconFileID) then
        metadata.bigIconTextureToken = iconFileID
        hasData = true
    end

    if hasData then
        self:SetEventMetadata(eventID, metadata)
    end
end

function EncounterTimeline:ResolveTimelineEventMetadata(eventID)
    if not self:IsValidEventID(eventID) then
        return nil
    end

    local metadata = self:GetEventMetadata(eventID)
    if metadata
        and metadata.sourceToken ~= nil
        and metadata.severity ~= nil
        and metadata.iconMask ~= nil then
        return metadata
    end

    if C_EncounterTimeline and type(C_EncounterTimeline.GetEventInfo) == "function" then
        local ok, eventInfo = pcall(C_EncounterTimeline.GetEventInfo, eventID)
        if ok and not IsUnreadableValue(eventInfo) and type(eventInfo) == "table" then
            self:UpdateEventMetadataFromInfo(eventID, eventInfo)
        end
    end

    local refreshed = self:GetEventMetadata(eventID)
    if refreshed and next(refreshed) ~= nil then
        return refreshed
    end

    return nil
end
