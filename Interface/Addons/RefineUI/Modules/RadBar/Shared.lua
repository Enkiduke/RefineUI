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
Private.REMOVE_ICON_ATLAS = "common-icon-redx"
Private.REMOVE_ICON_SCALE = 0.7
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
Private.SLOT_COUNT = 4
Private.RING_RADIUS = 100
Private.INNER_RADIUS = 35
Private.CENTER_SIZE = 52
Private.SLICE_SIZE = 40
Private.CONTENT_SIZE = 400
Private.ARROW_SIZE = 32
Private.ARROW_RADIUS = 50
Private.TWO_PI = math.pi * 2

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSupportedActionType(actionType)
    return _G.type(actionType) == "string" and SUPPORTED_ACTION_TYPES[actionType] or false
end

local function IsPositiveInteger(value)
    return _G.type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value)
end

local function IsNonEmptyString(value)
    return _G.type(value) == "string" and value:find("%S") ~= nil
end

local function GetSlotPrefix(index)
    return index == 0 and "center-" or "child" .. index .. "-"
end

-- Mirrors Core's GetSelection secure snippet; regression tests check boundary parity.
local function GetSelection(angle, radius, innerRadius, count)
    if radius <= innerRadius or count <= 0 then
        return 0
    end
    local sliceAngle = Private.TWO_PI / count
    return math.floor(((angle + sliceAngle / 2) % Private.TWO_PI) / sliceAngle) + 1
end

local function GetDefaultBorderColor()
    local color = Config and Config.General and Config.General.BorderColor
    if _G.type(color) == "table" then
        return color[1] or 0.3, color[2] or 0.3, color[3] or 0.3, color[4] or 1
    end
    return 0.3, 0.3, 0.3, 1
end

local function GetDefaultMainRing()
    return _G.CopyTable(RefineUI.DefaultConfig.RadBar.Rings.Main)
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

    for i in next, slices do
        if _G.type(i) ~= "number" or i < 1 or i > 4 or i ~= math.floor(i) then
            return false
        end
    end

    return true
end

----------------------------------------------------------------------------------------
-- Shared Exports
----------------------------------------------------------------------------------------
Private.IsSupportedActionType = IsSupportedActionType
Private.IsPositiveInteger = IsPositiveInteger
Private.IsNonEmptyString = IsNonEmptyString
Private.GetSlotPrefix = GetSlotPrefix
Private.GetSelection = GetSelection
Private.GetDefaultBorderColor = GetDefaultBorderColor
Private.GetDefaultMainRing = GetDefaultMainRing
Private.IsLegacyDefaultMainRing = IsLegacyDefaultMainRing
