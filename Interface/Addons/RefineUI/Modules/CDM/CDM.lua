----------------------------------------------------------------------------------------
-- CDM for RefineUI
-- Description: Root module registration, shared constants, and key builders.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:RegisterModule("CDM")

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

CDM.TRACKER_BUCKETS = { "Left", "Right", "Bottom" }
CDM.NOT_TRACKED_KEY = "NotTracked"
CDM.BUCKET_LABELS = {
    Left = "Left",
    Right = "Right",
    Bottom = "Bottom",
    NotTracked = "Not Tracked",
}
CDM.TRACKER_FRAME_NAMES = {
    Left = "RefineUI_CDM_LeftTracker",
    Right = "RefineUI_CDM_RightTracker",
    Bottom = "RefineUI_CDM_BottomTracker",
}
CDM.TRACKER_DEFAULT_DIRECTION = {
    Left = "LEFT",
    Right = "RIGHT",
    Bottom = "LEFT",
}
CDM.SETTINGS_SECTION_TITLE = "RefineUI Aura Trackers"
CDM.UPDATE_THROTTLE_KEY = CDM:BuildKey("Refresh")
CDM.UPDATE_TIMER_KEY = CDM:BuildKey("Refresh", "NextFrame")
CDM.STATE_REGISTRY = CDM:BuildKey("State")
CDM.NATIVE_AURA_VIEWERS = {
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

function CDM:GetCooldownViewerSettingsFrame()
    return _G.CooldownViewerSettings
end
