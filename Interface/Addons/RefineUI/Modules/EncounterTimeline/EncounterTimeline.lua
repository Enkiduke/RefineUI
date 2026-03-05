----------------------------------------------------------------------------------------
-- EncounterTimeline for RefineUI
-- Description: Root module registration, config normalization, and shared helpers
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:RegisterModule("EncounterTimeline")

-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local max = math.max
local min = math.min
local pcall = pcall
local select = select
local tonumber = tonumber
local tostring = tostring
local type = type
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue

-- Constants
----------------------------------------------------------------------------------------
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

local BIG_ICON_FRAME_NAME = "RefineUI_EncounterTimeline_BigIcon"

local CONFIG_DEFAULTS = {
    Enable = true,
    SkinEnabled = true,
    SkinTrackView = true,
    SkinTimerView = true,
    TrackTextAnchor = TRACK_TEXT_ANCHOR.LEFT,
    BigIconEnable = true,
    BigIconSize = 72,
    BigIconThresholdSeconds = 5,
    BigIconSpacing = 6,
    BigIconOrientation = BIG_ICON_ORIENTATION.HORIZONTAL,
    BigIconGrowDirection = BIG_ICON_GROW_DIRECTION.RIGHT,
    BigIconIconFallback = 134400,
}

EncounterTimeline.KEY_PREFIX = "EncounterTimeline"
EncounterTimeline.STATE_REGISTRY = EncounterTimeline.KEY_PREFIX .. ":State"
EncounterTimeline.BLIZZARD_ADDON_NAME = "Blizzard_EncounterTimeline"
EncounterTimeline.BIG_ICON_FRAME_NAME = BIG_ICON_FRAME_NAME
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

function EncounterTimeline:GetConfig()
    RefineUI.Config = RefineUI.Config or {}
    RefineUI.Config.EncounterTimeline = RefineUI.Config.EncounterTimeline or {}

    local config = RefineUI.Config.EncounterTimeline

    config.Enable = NormalizeBoolean(config.Enable, CONFIG_DEFAULTS.Enable)
    config.SkinEnabled = NormalizeBoolean(config.SkinEnabled, CONFIG_DEFAULTS.SkinEnabled)
    config.SkinTrackView = NormalizeBoolean(config.SkinTrackView, CONFIG_DEFAULTS.SkinTrackView)
    config.SkinTimerView = NormalizeBoolean(config.SkinTimerView, CONFIG_DEFAULTS.SkinTimerView)
    config.TrackTextAnchor = NormalizeTrackTextAnchor(config.TrackTextAnchor)
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
function EncounterTimeline:UpdateEventMetadataFromInfo(eventID, eventInfo)
    if not self:IsValidEventID(eventID) then
        return
    end
    if IsUnreadableValue(eventInfo) or type(eventInfo) ~= "table" then
        return
    end

    local metadata = {}
    local hasData = false

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
