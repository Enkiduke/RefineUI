----------------------------------------------------------------------------------------
-- Tooltip Icons
-- Description: Prepends spell/item icons to tooltip title lines.
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
local tostring = tostring
local type = type
local pcall = pcall

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_Item = _G.C_Item
local C_Spell = _G.C_Spell
local TOOLTIP_DATA_TYPE = Enum and Enum.TooltipDataType

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TOOLTIP_ICONS_ITEM_HANDLER_KEY = "TooltipIcons"
local TOOLTIP_ICONS_POSTCALL_SPELL_KEY = "TooltipIcons:PostCall:Spell"
local TOOLTIP_ICONS_POSTCALL_MACRO_KEY = "TooltipIcons:PostCall:Macro"
local TOOLTIP_TITLE_ICON_FORMAT = "|T%s:20:20:0:0:64:64:4:60:4:60|t %s"

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function SetTooltipIcon(tooltip, icon)
    if not Tooltip:IsAugmentableTooltipFrame(tooltip) then
        return
    end
    if icon == nil then
        return
    end

    local title = Tooltip:GetCachedLine(tooltip, 1)
    if not title then
        return
    end

    local okText, text = pcall(title.GetText, title)
    if not okText then
        return
    end

    text = Tooltip:ReadSafeString(text)
    if not text or text == "" then
        return
    end

    local iconToken = nil
    local safeIconString = Tooltip:ReadSafeString(icon)
    if safeIconString then
        iconToken = "|T" .. safeIconString
    else
        local safeIconNumber = Tooltip:ReadSafeNumber(icon)
        if safeIconNumber then
            iconToken = "|T" .. tostring(safeIconNumber)
        end
    end

    if iconToken and text:find(iconToken, 1, true) then
        return
    end

    pcall(title.SetFormattedText, title, TOOLTIP_TITLE_ICON_FORMAT, icon, text)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipIcons()
    Tooltip:RegisterItemHandler(TOOLTIP_ICONS_ITEM_HANDLER_KEY, function(tooltip, data)
        if not Tooltip:IsAugmentableTooltipFrame(tooltip) then
            return
        end

        local itemID = nil
        if Tooltip:CanAccessObjectSafe(data) then
            local rawItemID, okItemID = Tooltip:SafeGetField(data, "id")
            if okItemID then
                itemID = Tooltip:ReadSafeNumber(rawItemID)
            end
        end
        local icon = C_Item and C_Item.GetItemIconByID and itemID and C_Item.GetItemIconByID(itemID)
        SetTooltipIcon(tooltip, icon)
    end)

    if TOOLTIP_DATA_TYPE and TOOLTIP_DATA_TYPE.Spell then
        Tooltip:AddTooltipPostCallOnce(TOOLTIP_ICONS_POSTCALL_SPELL_KEY, TOOLTIP_DATA_TYPE.Spell, function(tooltip, data)
            if not Tooltip:IsAugmentableTooltipFrame(tooltip) then
                return
            end

            local spellID = nil
            if Tooltip:CanAccessObjectSafe(data) then
                local rawSpellID, okSpellID = Tooltip:SafeGetField(data, "id")
                if okSpellID then
                    spellID = Tooltip:ReadSafeNumber(rawSpellID)
                end
            end
            local icon = C_Spell and C_Spell.GetSpellTexture and spellID and C_Spell.GetSpellTexture(spellID)
            SetTooltipIcon(tooltip, icon)
        end)
    end

    if TOOLTIP_DATA_TYPE and TOOLTIP_DATA_TYPE.Macro then
        Tooltip:AddTooltipPostCallOnce(TOOLTIP_ICONS_POSTCALL_MACRO_KEY, TOOLTIP_DATA_TYPE.Macro, function(tooltip, data)
            if not Tooltip:IsAugmentableTooltipFrame(tooltip) then
                return
            end
            if not Tooltip:CanAccessObjectSafe(data) then
                return
            end

            local lines, okLines = Tooltip:SafeGetField(data, "lines")
            if not okLines or type(lines) ~= "table" then
                return
            end

            local lineData, okLineData = Tooltip:SafeGetField(lines, 1)
            if not okLineData or not Tooltip:CanAccessObjectSafe(lineData) then
                return
            end

            local rawTooltipType, okTooltipType = Tooltip:SafeGetField(lineData, "tooltipType")
            local tooltipType = okTooltipType and Tooltip:ReadSafeNumber(rawTooltipType) or nil
            if not tooltipType then
                return
            end

            local rawTooltipID, okTooltipID = Tooltip:SafeGetField(lineData, "tooltipID")
            local tooltipID = okTooltipID and Tooltip:ReadSafeNumber(rawTooltipID) or nil
            if not tooltipID then
                return
            end

            local icon = nil
            if tooltipType == 0 then
                icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(tooltipID)
            elseif tooltipType == 1 then
                icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(tooltipID)
            end

            SetTooltipIcon(tooltip, icon)
        end)
    end
end
