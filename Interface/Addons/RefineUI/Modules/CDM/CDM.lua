----------------------------------------------------------------------------------------
-- CDM for RefineUI
-- Description: Root module registration, shared constants, and key builders.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:RegisterModule("CDM", "CDM")

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

CDM.TRACKER_BUCKETS = { "Left", "Right", "Bottom", "Radial" }
CDM.RADIAL_BUCKET = "Radial"
CDM.NOT_TRACKED_KEY = "NotTracked"
CDM.EXTERNAL_CATEGORY_KEYS = {
    TRINKETS = "Trinkets",
    RACIALS = "Racials",
    CONSUMABLES = "Consumables",
}
CDM.BUCKET_LABELS = {
    Left = "Left",
    Right = "Right",
    Bottom = "Bottom",
    Radial = "Radial",
    Trinkets = "Equipped Trinkets",
    Racials = "Racial Abilities",
    Consumables = "Combat Consumables",
    NotTracked = "Spells/Buffs (Untracked)",
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
CDM.UPDATE_TIMER_KEY = CDM:BuildKey("Refresh", "NextFrame")
CDM.STATE_REGISTRY = CDM:BuildKey("State")

function CDM:GetCooldownViewerSettingsFrame()
    return self.settingsFrame or _G[CDM.SETTINGS_FRAME_NAME]
end

function CDM:GetBlizzardCooldownViewerSettingsFrame()
    return _G.CooldownViewerSettings
end
