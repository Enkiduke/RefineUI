----------------------------------------------------------------------------------------
-- Tooltip Spell/Item IDs
-- Description: Displays spell/item IDs in tooltips while a modifier key is held.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
local Private = Tooltip.Private

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local IsAugmentableTooltip = Private.IsAugmentableTooltip
local IsAccessibleTable = Private.IsAccessibleTable
local ReadSafeNumber = Private.ReadSafeNumber

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local IsModifierKeyDown = IsModifierKeyDown
local AddTooltipPostCall = TooltipDataProcessor.AddTooltipPostCall
local TOOLTIP_DATA_TYPE = Enum.TooltipDataType

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SPELL_ID_PREFIX = "|cffffffffSpell ID: "
local ITEM_ID_PREFIX = "|cffffffffItem ID: "

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
local function AddIDLine(tooltip, id, prefix)
    if id and IsModifierKeyDown() and IsAugmentableTooltip(tooltip) then
        tooltip:AddLine(prefix .. id)
    end
end

local function GetDataID(data)
    return IsAccessibleTable(data) and ReadSafeNumber(data.id)
end

local function OnItemData(tooltip, data)
    AddIDLine(tooltip, GetDataID(data), ITEM_ID_PREFIX)
end

local function OnSpellData(tooltip, data)
    AddIDLine(tooltip, GetDataID(data), SPELL_ID_PREFIX)
end

local function OnMacroData(tooltip, data)
    local tooltipType, tooltipID = Tooltip:GetMacroTooltipTarget(data)
    if tooltipType == 0 then
        AddIDLine(tooltip, tooltipID, ITEM_ID_PREFIX)
    elseif tooltipType == 1 then
        AddIDLine(tooltip, tooltipID, SPELL_ID_PREFIX)
    end
end

local function RefreshVisibleIDTooltips()
    for index = 1, #TOOLTIP_ID_FRAME_NAMES do
        local tooltip = _G[TOOLTIP_ID_FRAME_NAMES[index]]
        if tooltip and tooltip:IsShown() then
            -- Shopping tooltips only carry TooltipDataHandlerMixin.
            if tooltip.RefreshDataNextUpdate then
                tooltip:RefreshDataNextUpdate()
            else
                tooltip:RebuildFromTooltipInfo()
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeSpellID()
    self:RegisterItemHandler(OnItemData)
    AddTooltipPostCall(TOOLTIP_DATA_TYPE.Spell, OnSpellData)
    AddTooltipPostCall(TOOLTIP_DATA_TYPE.UnitAura, OnSpellData)
    AddTooltipPostCall(TOOLTIP_DATA_TYPE.Toy, OnItemData)
    AddTooltipPostCall(TOOLTIP_DATA_TYPE.Macro, OnMacroData)

    local modifierWasDown = IsModifierKeyDown()
    RefineUI:RegisterEventCallback("MODIFIER_STATE_CHANGED", function()
        local modifierIsDown = IsModifierKeyDown()
        if modifierIsDown == modifierWasDown then
            return
        end

        modifierWasDown = modifierIsDown
        RefreshVisibleIDTooltips()
    end, "Tooltip:SpellID:MODIFIER_STATE_CHANGED")
end
