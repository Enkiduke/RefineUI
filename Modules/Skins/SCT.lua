----------------------------------------------------------------------------------------
-- Skins Component: SCT
-- Description: Updates Blizzard SCT scale.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:SCT"
local SCT_CVAR_NAME = "WorldTextScale_v2"
local SCT_CVAR_VALUE = 0.1

local EVENT_KEY = {
    ADDON_LOADED = COMPONENT_KEY .. ":ADDON_LOADED",
}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function SkinSCT()
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar(SCT_CVAR_NAME, SCT_CVAR_VALUE)
    else
        SetCVar(SCT_CVAR_NAME, SCT_CVAR_VALUE)
    end
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupSCT()
    SkinSCT()
    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
        if addon == "Blizzard_CombatText" then
            SkinSCT()
        end
    end, EVENT_KEY.ADDON_LOADED)
end
