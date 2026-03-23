----------------------------------------------------------------------------------------
-- Quests Component: Edit Mode
-- Description: Objective Tracker edit mode extension settings.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Quests = RefineUI:GetModule("Quests")
if not Quests then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local floor = math.floor
local format = string.format
local tonumber = tonumber
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local OBJECTIVE_TRACKER_SCALE_DEFAULT = 1.2
local OBJECTIVE_TRACKER_SCALE_MIN = 0.5
local OBJECTIVE_TRACKER_SCALE_MAX = 2.0
local OBJECTIVE_TRACKER_SCALE_STEP = 0.05
local OBJECTIVE_TRACKER_SCALE_MULTIPLIER = 20

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local systemSettingsRegistered = false

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function EnsureQuestConfig()
    Config.Quests = Config.Quests or {}
    Config.Quests.LayoutScales = Config.Quests.LayoutScales or {}
    if type(Config.Quests.ObjectiveTrackerScale) ~= "number" then
        Config.Quests.ObjectiveTrackerScale = OBJECTIVE_TRACKER_SCALE_DEFAULT
    end
    return Config.Quests
end

local function RoundObjectiveTrackerScale(value)
    local numericValue = tonumber(value) or OBJECTIVE_TRACKER_SCALE_DEFAULT
    local steppedValue = floor((numericValue * OBJECTIVE_TRACKER_SCALE_MULTIPLIER) + 0.5) / OBJECTIVE_TRACKER_SCALE_MULTIPLIER

    if steppedValue < OBJECTIVE_TRACKER_SCALE_MIN then
        steppedValue = OBJECTIVE_TRACKER_SCALE_MIN
    elseif steppedValue > OBJECTIVE_TRACKER_SCALE_MAX then
        steppedValue = OBJECTIVE_TRACKER_SCALE_MAX
    end

    return steppedValue
end

local function GetObjectiveTrackerFrame()
    return _G.ObjectiveTrackerFrame
end

local function FormatObjectiveTrackerScale(value)
    return format("%.2f", RoundObjectiveTrackerScale(value))
end

local function GetCurrentLayoutTierKey()
    local context = RefineUI.GetLayoutContext and RefineUI:GetLayoutContext() or nil
    local tierKey = context and context.tierKey or nil
    if type(tierKey) ~= "string" or tierKey == "" then
        tierKey = RefineUI.GetLayoutTier and RefineUI:GetLayoutTier() or nil
    end
    return tierKey
end

local function GetDefaultObjectiveTrackerScale(tierKey)
    local defaults = RefineUI.GetLayoutDefaults and RefineUI:GetLayoutDefaults(tierKey) or nil
    local objectiveTrackerDefaults = defaults and defaults.objectiveTracker or nil
    local scale = tonumber(objectiveTrackerDefaults and objectiveTrackerDefaults.scale)
    if not scale or scale <= 0 then
        scale = OBJECTIVE_TRACKER_SCALE_DEFAULT
    end
    return RoundObjectiveTrackerScale(scale)
end

local function GetStoredObjectiveTrackerScale(cfg, tierKey)
    local layoutScales = cfg and cfg.LayoutScales or nil
    local scale = layoutScales and tonumber(layoutScales[tierKey]) or nil
    if scale and scale > 0 then
        return RoundObjectiveTrackerScale(scale)
    end

    local legacyScale = tonumber(cfg and cfg.ObjectiveTrackerScale)
    local defaultScale = GetDefaultObjectiveTrackerScale(tierKey)
    if legacyScale and legacyScale > 0 and legacyScale ~= OBJECTIVE_TRACKER_SCALE_DEFAULT then
        scale = legacyScale
    else
        scale = defaultScale
    end

    scale = RoundObjectiveTrackerScale(scale)
    if layoutScales and tierKey then
        layoutScales[tierKey] = scale
    end
    return scale
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function Quests:GetObjectiveTrackerScale()
    local cfg = EnsureQuestConfig()
    local tierKey = GetCurrentLayoutTierKey()
    local scale = GetStoredObjectiveTrackerScale(cfg, tierKey)
    if tierKey then
        cfg.LayoutScales[tierKey] = scale
    end
    cfg.ObjectiveTrackerScale = scale
    return scale
end

function Quests:ApplyObjectiveTrackerScale()
    local objectiveTrackerFrame = GetObjectiveTrackerFrame()
    if not objectiveTrackerFrame then
        return
    end

    objectiveTrackerFrame:SetScale(self:GetObjectiveTrackerScale())
end

function Quests:RegisterObjectiveTrackerEditModeSettings()
    if systemSettingsRegistered then
        return
    end

    local lib = RefineUI.LibEditMode
    if not lib or not lib.SettingType or type(lib.AddSystemSettings) ~= "function" then
        return
    end

    local Enum = _G.Enum
    if not Enum or not Enum.EditModeSystem or not Enum.EditModeSystem.ObjectiveTracker then
        return
    end

    local settingType = lib.SettingType
    lib:AddSystemSettings(Enum.EditModeSystem.ObjectiveTracker, {
        {
            kind = settingType.Slider,
            name = "Tracker Scale",
            default = OBJECTIVE_TRACKER_SCALE_DEFAULT,
            minValue = OBJECTIVE_TRACKER_SCALE_MIN,
            maxValue = OBJECTIVE_TRACKER_SCALE_MAX,
            valueStep = OBJECTIVE_TRACKER_SCALE_STEP,
            formatter = FormatObjectiveTrackerScale,
            get = function()
                return Quests:GetObjectiveTrackerScale()
            end,
            set = function(_, value)
                local cfg = EnsureQuestConfig()
                local tierKey = GetCurrentLayoutTierKey()
                local scale = RoundObjectiveTrackerScale(value)
                if tierKey then
                    cfg.LayoutScales[tierKey] = scale
                end
                cfg.ObjectiveTrackerScale = scale
                Quests:ApplyObjectiveTrackerScale()
            end,
        },
    })

    systemSettingsRegistered = true
end
