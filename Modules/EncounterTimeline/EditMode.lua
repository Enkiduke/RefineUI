----------------------------------------------------------------------------------------
-- EncounterTimeline Component: EditMode
-- Description: Edit mode frame/system settings for skin, big icon, and audio options
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
local floor = math.floor
local tonumber = tonumber
local type = type

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local systemSettingsRegistered = false
local bigIconSettingsBuilt = false
local bigIconSettingsAttached = false
local bigIconSettings

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function ClampInteger(value, minimum, maximum, fallback)
    local n = tonumber(value)
    if type(n) ~= "number" then
        n = fallback
    end

    n = floor(n + 0.5)
    if n < minimum then
        n = minimum
    elseif n > maximum then
        n = maximum
    end
    return n
end

local function RefreshSkinsAndBigIcon()
    EncounterTimeline:RefreshTimelineSkins(true)
    EncounterTimeline:RefreshBigIconVisualState()
    EncounterTimeline:UpdateBigIconSchedulerState()
end

local function RefreshBigIconAndAudio()
    EncounterTimeline:ClearAllPlayedAudioState()
    EncounterTimeline:RefreshBigIconVisualState()
    EncounterTimeline:UpdateBigIconSchedulerState()
end

local function NormalizeBigIconOrientation(value)
    local orientation = EncounterTimeline.BIG_ICON_ORIENTATION or {}
    if value == orientation.VERTICAL then
        return orientation.VERTICAL
    end
    return orientation.HORIZONTAL
end

local function NormalizeBigIconGrowDirectionForOrientation(value, orientationValue)
    local orientation = NormalizeBigIconOrientation(orientationValue)
    local direction = EncounterTimeline.BIG_ICON_GROW_DIRECTION or {}

    if orientation == (EncounterTimeline.BIG_ICON_ORIENTATION and EncounterTimeline.BIG_ICON_ORIENTATION.VERTICAL) then
        if value == direction.UP or value == direction.DOWN or value == direction.CENTERED then
            return value
        end
        return direction.UP
    end

    if value == direction.LEFT or value == direction.RIGHT or value == direction.CENTERED then
        return value
    end
    return direction.RIGHT
end

local function GetBigIconGrowDirectionOptions(orientationValue)
    local direction = EncounterTimeline.BIG_ICON_GROW_DIRECTION or {}
    local orientation = NormalizeBigIconOrientation(orientationValue)
    if orientation == (EncounterTimeline.BIG_ICON_ORIENTATION and EncounterTimeline.BIG_ICON_ORIENTATION.VERTICAL) then
        return {
            { text = "Up", value = direction.UP },
            { text = "Centered", value = direction.CENTERED },
            { text = "Down", value = direction.DOWN },
        }
    end

    return {
        { text = "Left", value = direction.LEFT },
        { text = "Centered", value = direction.CENTERED },
        { text = "Right", value = direction.RIGHT },
    }
end

----------------------------------------------------------------------------------------
-- System Settings
----------------------------------------------------------------------------------------
function EncounterTimeline:RegisterEncounterTimelineEditModeSettings()
    if systemSettingsRegistered then
        return
    end

    local lib = RefineUI.LibEditMode
    if not lib or not lib.SettingType or type(lib.AddSystemSettings) ~= "function" then
        return
    end

    local Enum = _G.Enum
    if not Enum or not Enum.EditModeSystem or not Enum.EditModeEncounterEventsSystemIndices then
        return
    end

    local systemID = Enum.EditModeSystem.EncounterEvents
    local subSystemID = Enum.EditModeEncounterEventsSystemIndices.Timeline
    if not systemID or not subSystemID then
        return
    end

    local settingType = lib.SettingType
    local settings = {}

    local function AddDivider(label)
        if not settingType.Divider then
            return
        end
        settings[#settings + 1] = {
            kind = settingType.Divider,
            name = label,
        }
    end

    AddDivider("RefineUI Skin")

    settings[#settings + 1] = {
        kind = settingType.Dropdown,
        name = "Border Color Mode",
        default = EncounterTimeline.SKIN_BORDER_COLOR_MODE.ICON_CLASSIFICATION,
        values = {
            { text = "Icon Classification", value = EncounterTimeline.SKIN_BORDER_COLOR_MODE.ICON_CLASSIFICATION },
            { text = "Severity", value = EncounterTimeline.SKIN_BORDER_COLOR_MODE.SEVERITY },
            { text = "Event Color", value = EncounterTimeline.SKIN_BORDER_COLOR_MODE.EVENT_COLOR },
            { text = "Default Border", value = EncounterTimeline.SKIN_BORDER_COLOR_MODE.DEFAULT },
        },
        get = function()
            return EncounterTimeline:GetConfig().SkinBorderColorMode
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().SkinBorderColorMode = value
            RefreshSkinsAndBigIcon()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Dropdown,
        name = "Track Text Anchor",
        default = EncounterTimeline.TRACK_TEXT_ANCHOR.LEFT,
        values = {
            { text = "Left", value = EncounterTimeline.TRACK_TEXT_ANCHOR.LEFT },
            { text = "Right", value = EncounterTimeline.TRACK_TEXT_ANCHOR.RIGHT },
        },
        get = function()
            return EncounterTimeline:GetConfig().TrackTextAnchor
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().TrackTextAnchor = value
            EncounterTimeline:RefreshTimelineSkins(true)
        end,
    }

    AddDivider("RefineUI Audio")

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Enable Countdown Audio",
        default = true,
        get = function()
            return EncounterTimeline:GetConfig().AudioCountdownEnable == true
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().AudioCountdownEnable = value and true or false
            RefreshBigIconAndAudio()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Minor Warnings",
        default = true,
        get = function()
            return EncounterTimeline:GetConfig().AudioCountdownSeverityLow == true
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().AudioCountdownSeverityLow = value and true or false
            RefreshBigIconAndAudio()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Medium Warnings",
        default = true,
        get = function()
            return EncounterTimeline:GetConfig().AudioCountdownSeverityMedium == true
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().AudioCountdownSeverityMedium = value and true or false
            RefreshBigIconAndAudio()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Critical Warnings",
        default = true,
        get = function()
            return EncounterTimeline:GetConfig().AudioCountdownSeverityHigh == true
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().AudioCountdownSeverityHigh = value and true or false
            RefreshBigIconAndAudio()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Role-Only Events",
        default = false,
        get = function()
            return EncounterTimeline:GetConfig().AudioCountdownRoleFilterEnabled == true
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().AudioCountdownRoleFilterEnabled = value and true or false
            RefreshBigIconAndAudio()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Include Roleless",
        default = false,
        get = function()
            return EncounterTimeline:GetConfig().AudioCountdownIncludeRoleless == true
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().AudioCountdownIncludeRoleless = value and true or false
            RefreshBigIconAndAudio()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Dropdown,
        name = "Source Filter",
        default = EncounterTimeline.AUDIO_SOURCE_FILTER.ALL,
        values = {
            { text = "All Sources", value = EncounterTimeline.AUDIO_SOURCE_FILTER.ALL },
            { text = "Encounter Only", value = EncounterTimeline.AUDIO_SOURCE_FILTER.ENCOUNTER },
            { text = "Script Only", value = EncounterTimeline.AUDIO_SOURCE_FILTER.SCRIPT },
        },
        get = function()
            return EncounterTimeline:GetConfig().AudioCountdownSourceFilter
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().AudioCountdownSourceFilter = value
            RefreshBigIconAndAudio()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Dropdown,
        name = "Unknown Severity",
        default = EncounterTimeline.AUDIO_UNKNOWN_SEVERITY_POLICY.EXCLUDE,
        values = {
            { text = "Exclude", value = EncounterTimeline.AUDIO_UNKNOWN_SEVERITY_POLICY.EXCLUDE },
            { text = "Include", value = EncounterTimeline.AUDIO_UNKNOWN_SEVERITY_POLICY.INCLUDE },
            { text = "Treat as Medium", value = EncounterTimeline.AUDIO_UNKNOWN_SEVERITY_POLICY.AS_MEDIUM },
        },
        get = function()
            return EncounterTimeline:GetConfig().AudioCountdownUnknownSeverityPolicy
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().AudioCountdownUnknownSeverityPolicy = value
            RefreshBigIconAndAudio()
        end,
    }

    lib:AddSystemSettings(systemID, settings, subSystemID)
    systemSettingsRegistered = true
end

----------------------------------------------------------------------------------------
-- Big Icon Frame Settings
----------------------------------------------------------------------------------------
function EncounterTimeline:BuildBigIconEditModeSettings()
    if bigIconSettingsBuilt then
        return
    end
    if not RefineUI.LibEditMode or not RefineUI.LibEditMode.SettingType then
        return
    end

    local settingType = RefineUI.LibEditMode.SettingType
    local settings = {}

    local function AddDivider(label)
        if not settingType.Divider then
            return
        end
        settings[#settings + 1] = {
            kind = settingType.Divider,
            name = label,
        }
    end

    AddDivider("Big Icon")

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Icon Size",
        default = 72,
        minValue = 32,
        maxValue = 256,
        valueStep = 1,
        get = function()
            return EncounterTimeline:GetConfig().BigIconSize
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().BigIconSize = ClampInteger(value, 32, 256, 72)
            EncounterTimeline:RefreshBigIconVisualState()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Show Under (sec)",
        default = 5,
        minValue = 1,
        maxValue = 15,
        valueStep = 1,
        get = function()
            return EncounterTimeline:GetConfig().BigIconThresholdSeconds
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().BigIconThresholdSeconds = ClampInteger(value, 1, 15, 5)
            RefreshBigIconAndAudio()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Dropdown,
        name = "Orientation",
        default = EncounterTimeline.BIG_ICON_ORIENTATION.HORIZONTAL,
        values = {
            { text = "Horizontal", value = EncounterTimeline.BIG_ICON_ORIENTATION.HORIZONTAL },
            { text = "Vertical", value = EncounterTimeline.BIG_ICON_ORIENTATION.VERTICAL },
        },
        get = function()
            return NormalizeBigIconOrientation(EncounterTimeline:GetConfig().BigIconOrientation)
        end,
        set = function(_, value)
            local config = EncounterTimeline:GetConfig()
            local orientation = NormalizeBigIconOrientation(value)
            config.BigIconOrientation = orientation
            config.BigIconGrowDirection = NormalizeBigIconGrowDirectionForOrientation(config.BigIconGrowDirection, orientation)
            EncounterTimeline:RefreshBigIconVisualState()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Dropdown,
        name = "Grow Direction",
        default = EncounterTimeline.BIG_ICON_GROW_DIRECTION.RIGHT,
        generator = function(_, rootDescription)
            local config = EncounterTimeline:GetConfig()
            local orientation = NormalizeBigIconOrientation(config.BigIconOrientation)
            local currentDirection = NormalizeBigIconGrowDirectionForOrientation(config.BigIconGrowDirection, orientation)
            local options = GetBigIconGrowDirectionOptions(orientation)

            for index = 1, #options do
                local option = options[index]
                rootDescription:CreateRadio(
                    option.text,
                    function(data)
                        return currentDirection == data.value
                    end,
                    function(data)
                        local activeConfig = EncounterTimeline:GetConfig()
                        local activeOrientation = NormalizeBigIconOrientation(activeConfig.BigIconOrientation)
                        activeConfig.BigIconGrowDirection = NormalizeBigIconGrowDirectionForOrientation(data.value, activeOrientation)
                        EncounterTimeline:RefreshBigIconVisualState()
                    end,
                    { value = option.value }
                )
            end
        end,
        get = function()
            local config = EncounterTimeline:GetConfig()
            local orientation = NormalizeBigIconOrientation(config.BigIconOrientation)
            return NormalizeBigIconGrowDirectionForOrientation(config.BigIconGrowDirection, orientation)
        end,
        set = function(_, value)
            local config = EncounterTimeline:GetConfig()
            local orientation = NormalizeBigIconOrientation(config.BigIconOrientation)
            config.BigIconGrowDirection = NormalizeBigIconGrowDirectionForOrientation(value, orientation)
            EncounterTimeline:RefreshBigIconVisualState()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Icon Spacing",
        default = 6,
        minValue = 0,
        maxValue = 40,
        valueStep = 1,
        get = function()
            return EncounterTimeline:GetConfig().BigIconSpacing
        end,
        set = function(_, value)
            EncounterTimeline:GetConfig().BigIconSpacing = ClampInteger(value, 0, 40, 6)
            EncounterTimeline:RefreshBigIconVisualState()
        end,
    }

    bigIconSettings = settings
    bigIconSettingsBuilt = true
end

function EncounterTimeline:AttachBigIconEditModeSettings(frame)
    if bigIconSettingsAttached then
        return
    end
    if not frame then
        return
    end

    local lib = RefineUI.LibEditMode
    if not lib or type(lib.AddFrameSettings) ~= "function" then
        return
    end

    self:BuildBigIconEditModeSettings()
    if type(bigIconSettings) ~= "table" then
        return
    end

    lib:AddFrameSettings(frame, bigIconSettings)
    bigIconSettingsAttached = true
end
