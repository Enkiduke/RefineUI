----------------------------------------------------------------------------------------
-- EncounterTimeline for RefineUI
-- Description: Root module registration and shared constants
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:RegisterModule("EncounterTimeline", "EncounterTimeline")

EncounterTimeline.BLIZZARD_ADDON_NAME = "Blizzard_EncounterTimeline"
EncounterTimeline.BIG_ICON_FRAME_NAME = "RefineUI_EncounterTimeline_BigIcon"

function EncounterTimeline:GetConfig()
    return RefineUI.Config.EncounterTimeline
end
