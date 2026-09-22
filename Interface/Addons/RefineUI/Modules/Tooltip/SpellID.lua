----------------------------------------------------------------------------------------
-- Tooltip Spell/Item IDs
-- Description: Displays spell/item IDs in tooltips while a modifier key is held.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
if not Tooltip then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local TOOLTIP_DATA_TYPE = Enum and Enum.TooltipDataType

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SPELL_ID_TEXT = "Spell ID:"
local ITEM_ID_TEXT = "Item ID:"
local SPELL_ID_COLOR_PREFIX = "|cffffffff"
local SPELL_ID_RENDER_FLAG = "Tooltip:SpellID:Spell"
local ITEM_ID_RENDER_FLAG = "Tooltip:SpellID:Item"

local SPELL_ID_ITEM_HANDLER_KEY = "SpellID"
local SPELL_ID_POSTCALL_SPELL_KEY = "SpellID:PostCall:Spell"
local SPELL_ID_POSTCALL_UNIT_AURA_KEY = "SpellID:PostCall:UnitAura"
local SPELL_ID_POSTCALL_MACRO_KEY = "SpellID:PostCall:Macro"
local SPELL_ID_POSTCALL_TOY_KEY = "SpellID:PostCall:Toy"
local SPELL_ID_MODIFIER_EVENT_KEY = "Tooltip:SpellID:MODIFIER_STATE_CHANGED"

local TOOLTIP_ID_FRAME_NAMES = {
    "GameTooltip",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function ClaimRenderFlag(tooltip, context, key)
    local flags = context and context.flags
    if type(flags) == "table" then
        if flags[key] then
            return false
        end

        flags[key] = true
        return true
    end

    if Tooltip:HasTooltipRenderFlag(tooltip, key) then
        return false
    end

    Tooltip:SetTooltipRenderFlag(tooltip, key)
    return true
end

local function AddIDLine(tooltip, id, isItem, context)
    if not IsModifierKeyDown() or not Tooltip:IsAugmentableTooltipFrame(tooltip) then
        return
    end

    id = Tooltip:ReadSafeNumber(id)
    if not id then
        return
    end

    local label = isItem and ITEM_ID_TEXT or SPELL_ID_TEXT
    local renderFlag = isItem and ITEM_ID_RENDER_FLAG or SPELL_ID_RENDER_FLAG
    if not ClaimRenderFlag(tooltip, context, renderFlag) then
        return
    end

    tooltip:AddLine(SPELL_ID_COLOR_PREFIX .. label .. " " .. id)
end

local function GetTooltipDataID(data)
    if not Tooltip:CanAccessObjectSafe(data) then
        return nil
    end

    local rawID, okID = Tooltip:SafeGetField(data, "id")
    return okID and Tooltip:ReadSafeNumber(rawID) or nil
end

local function GetNestedTooltipID(data)
    if not Tooltip:CanAccessObjectSafe(data) then
        return nil, nil
    end

    local lines, okLines = Tooltip:SafeGetField(data, "lines")
    if not okLines or type(lines) ~= "table" then
        return nil, nil
    end

    local lineData, okLineData = Tooltip:SafeGetField(lines, 1)
    if not okLineData or not Tooltip:CanAccessObjectSafe(lineData) then
        return nil, nil
    end

    local rawTooltipType, okTooltipType = Tooltip:SafeGetField(lineData, "tooltipType")
    local rawTooltipID, okTooltipID = Tooltip:SafeGetField(lineData, "tooltipID")
    if not okTooltipType or not okTooltipID then
        return nil, nil
    end

    return Tooltip:ReadSafeNumber(rawTooltipType), Tooltip:ReadSafeNumber(rawTooltipID)
end

local function RegisterDataIDPostCall(key, dataType, isItem)
    if not dataType then
        return
    end

    Tooltip:AddTooltipPostCallOnce(key, dataType, function(tooltip, data)
        AddIDLine(tooltip, GetTooltipDataID(data), isItem)
    end)
end

local function RefreshVisibleIDTooltips()
    for index = 1, #TOOLTIP_ID_FRAME_NAMES do
        local tooltip = _G[TOOLTIP_ID_FRAME_NAMES[index]]
        if tooltip and Tooltip:IsAugmentableTooltipFrame(tooltip) then
            local okShown, isShown = Tooltip:SafeObjectMethodCall(tooltip, "IsShown")
            if okShown and isShown == true then
                local refreshQueued = Tooltip:SafeObjectMethodCall(tooltip, "RefreshDataNextUpdate")
                if not refreshQueued then
                    Tooltip:SafeObjectMethodCall(tooltip, "RebuildFromTooltipInfo")
                end
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeSpellID()
    Tooltip:RegisterItemHandler(SPELL_ID_ITEM_HANDLER_KEY, function(tooltip, data, context)
        AddIDLine(tooltip, GetTooltipDataID(data), true, context)
    end)

    if TOOLTIP_DATA_TYPE then
        RegisterDataIDPostCall(SPELL_ID_POSTCALL_SPELL_KEY, TOOLTIP_DATA_TYPE.Spell, false)
        RegisterDataIDPostCall(SPELL_ID_POSTCALL_UNIT_AURA_KEY, TOOLTIP_DATA_TYPE.UnitAura, false)
        RegisterDataIDPostCall(SPELL_ID_POSTCALL_TOY_KEY, TOOLTIP_DATA_TYPE.Toy, true)

        if TOOLTIP_DATA_TYPE.Macro then
            Tooltip:AddTooltipPostCallOnce(SPELL_ID_POSTCALL_MACRO_KEY, TOOLTIP_DATA_TYPE.Macro, function(tooltip, data)
                local tooltipType, tooltipID = GetNestedTooltipID(data)
                if tooltipType == 0 then
                    AddIDLine(tooltip, tooltipID, true)
                elseif tooltipType == 1 then
                    AddIDLine(tooltip, tooltipID, false)
                end
            end)
        end
    end

    local modifierWasDown = IsModifierKeyDown()
    RefineUI:RegisterEventCallback("MODIFIER_STATE_CHANGED", function()
        local modifierIsDown = IsModifierKeyDown()
        if modifierIsDown == modifierWasDown then
            return
        end

        modifierWasDown = modifierIsDown
        RefreshVisibleIDTooltips()
    end, SPELL_ID_MODIFIER_EVENT_KEY)
end
