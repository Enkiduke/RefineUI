----------------------------------------------------------------------------------------
-- RadBar Component: Shared
-- Description: Shared constants and helper functions for RadBar components.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local RadBar = RefineUI:GetModule("RadBar")
if not RadBar then
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
local next = next

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SUPPORTED_ACTION_TYPES = {
    spell = true,
    item = true,
    macro = true,
    mount = true,
}

local LEGACY_DEFAULT_MACROS = {
    [1] = "/dance",
    [2] = "/wave",
    [3] = "/cheer",
    [4] = "/laugh",
}

----------------------------------------------------------------------------------------
-- Internal Shared State
----------------------------------------------------------------------------------------
local Private = RadBar.Private or {}
RadBar.Private = Private

Private.DEFAULT_EMPTY_ICON = 134400
Private.BIND_EMPTY_SLOT_ATLAS = "cdm-empty"
Private.BIND_EMPTY_ICON_SCALE = 1.15
Private.ICON_TEX_MIN = 0.08
Private.ICON_TEX_MAX = 0.92
Private.ICON_USABLE_R = 1
Private.ICON_USABLE_G = 1
Private.ICON_USABLE_B = 1
Private.ICON_UNUSABLE_R = 1
Private.ICON_UNUSABLE_G = 0.2
Private.ICON_UNUSABLE_B = 0.2
Private.CLICK_BINDING_ACTION = "CLICK RefineUI_RadBar:LeftButton"
Private.CORE_FRAME_NAME = "RefineUI_RadBar"

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSupportedActionType(actionType)
    return actionType and SUPPORTED_ACTION_TYPES[actionType] or false
end

local function GetDefaultBorderColor()
    local color = Config and Config.General and Config.General.BorderColor
    if _G.type(color) == "table" then
        return color[1] or 0.3, color[2] or 0.3, color[3] or 0.3, color[4] or 1
    end
    return 0.3, 0.3, 0.3, 1
end

local function CopyTable(src)
    if _G.type(src) ~= "table" then
        return src
    end

    local dest = {}
    for k, v in next, src do
        dest[k] = CopyTable(v)
    end
    return dest
end

local function GetDefaultMainRing()
    local defaults = RefineUI.DefaultConfig and RefineUI.DefaultConfig.RadBar and RefineUI.DefaultConfig.RadBar.Rings
    if defaults and defaults.Main then
        return CopyTable(defaults.Main)
    end
    return {
        Slices = {},
    }
end

local function IsLegacyDefaultMainRing(ring)
    if _G.type(ring) ~= "table" then
        return false
    end

    local center = ring.Center
    if _G.type(center) ~= "table" or center.type ~= "spell" or center.value ~= 6948 then
        return false
    end

    local slices = ring.Slices
    if _G.type(slices) ~= "table" then
        return false
    end

    for i = 1, 4 do
        local info = slices[i]
        if _G.type(info) ~= "table" or info.type ~= "macro" or info.value ~= LEGACY_DEFAULT_MACROS[i] then
            return false
        end
    end

    for i = 5, #slices do
        if slices[i] ~= nil then
            return false
        end
    end

    return true
end

----------------------------------------------------------------------------------------
-- Shared Exports
----------------------------------------------------------------------------------------
Private.IsSupportedActionType = IsSupportedActionType
Private.GetDefaultBorderColor = GetDefaultBorderColor
Private.CopyTable = CopyTable
Private.GetDefaultMainRing = GetDefaultMainRing
Private.IsLegacyDefaultMainRing = IsLegacyDefaultMainRing
