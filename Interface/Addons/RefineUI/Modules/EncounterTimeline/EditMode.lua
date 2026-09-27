----------------------------------------------------------------------------------------
-- EncounterTimeline Component: EditMode
-- Description: Minimal edit mode settings for timeline text anchoring
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:GetModule("EncounterTimeline")

----------------------------------------------------------------------------------------
-- System Settings
----------------------------------------------------------------------------------------
function EncounterTimeline:RegisterEditModeSettings()
    local lib = RefineUI.LibEditMode
    lib:AddSystemSettings(Enum.EditModeSystem.EncounterEvents, {
        {
            kind = lib.SettingType.Dropdown,
            name = "Track Text Anchor",
            default = "RIGHT",
            values = {
                { text = "Left", value = "LEFT" },
                { text = "Right", value = "RIGHT" },
            },
            get = function()
                return EncounterTimeline:GetConfig().TrackTextAnchor
            end,
            set = function(_, value)
                EncounterTimeline:GetConfig().TrackTextAnchor = value
                EncounterTimeline:RefreshTrackTextAnchor()
            end,
        },
    }, Enum.EditModeEncounterEventsSystemIndices.Timeline)
end
