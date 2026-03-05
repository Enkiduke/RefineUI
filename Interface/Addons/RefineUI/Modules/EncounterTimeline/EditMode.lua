----------------------------------------------------------------------------------------
-- EncounterTimeline Component: EditMode
-- Description: Minimal edit mode settings for timeline text anchoring
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:GetModule("EncounterTimeline")
if not EncounterTimeline then
    return
end

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local systemSettingsRegistered = false

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function RefreshSkinsAndBigIcon()
    EncounterTimeline:RefreshTimelineSkins(true)
    EncounterTimeline:RefreshBigIconVisualState()
    EncounterTimeline:UpdateBigIconSchedulerState()
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
            RefreshSkinsAndBigIcon()
        end,
    }

    lib:AddSystemSettings(systemID, settings, subSystemID)
    systemSettingsRegistered = true
end

----------------------------------------------------------------------------------------
-- Big Icon Settings
----------------------------------------------------------------------------------------
-- Intentionally no frame-specific settings. Big icon movement still uses edit mode frame drag.
function EncounterTimeline:AttachBigIconEditModeSettings(_frame)
    return
end

