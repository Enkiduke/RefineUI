----------------------------------------------------------------------------------------
-- Tooltip Spell/Item IDs
-- Description: Displays spell/item IDs in tooltips while modifier key is held.
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
local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local type = type

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltip = _G.GameTooltip
local ItemRefTooltip = _G.ItemRefTooltip
local C_UnitAuras = _G.C_UnitAuras
local TOOLTIP_DATA_TYPE = Enum and Enum.TooltipDataType

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SPELL_ID_TEXT = "Spell ID:"
local ITEM_ID_TEXT = "Item ID:"
local SPELL_ID_COLOR_PREFIX = "|cffffffff"

local SPELL_ID_ITEM_HANDLER_KEY = "SpellID"
local SPELL_ID_POSTCALL_SPELL_KEY = "SpellID:PostCall:Spell"
local SPELL_ID_POSTCALL_MACRO_KEY = "SpellID:PostCall:Macro"
local SPELL_ID_POSTCALL_TOY_KEY = "SpellID:PostCall:Toy"

local SPELL_ID_HOOK_SET_UNIT_AURA_KEY = "Tooltip:SpellID:GameTooltip:SetUnitAura"
local SPELL_ID_HOOK_SET_UNIT_BUFF_AURA_INSTANCE_KEY = "Tooltip:SpellID:GameTooltip:SetUnitBuffByAuraInstanceID"
local SPELL_ID_HOOK_SET_UNIT_DEBUFF_AURA_INSTANCE_KEY = "Tooltip:SpellID:GameTooltip:SetUnitDebuffByAuraInstanceID"
local SPELL_ID_HOOK_SET_ITEM_REF_KEY = "Tooltip:SpellID:SetItemRef"

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function EscapePattern(value)
    return (value:gsub("([^%w])", "%%%1"))
end

local function TooltipHasIDLine(tooltip, label, id)
    local tooltipName = Tooltip:GetTooltipNameSafe(tooltip)
    if not tooltipName then
        return false
    end
    if type(tooltip.NumLines) ~= "function" then
        return false
    end

    local labelPattern = EscapePattern(label)
    local idPattern = tostring(id)
    local lineCount = tooltip:NumLines()
    for lineIndex = 1, lineCount do
        local line = _G[tooltipName .. "TextLeft" .. lineIndex]
        if line and line.GetText then
            local okText, text = pcall(line.GetText, line)
            if okText and type(text) == "string" and not Tooltip:IsSecretValueSafe(text) then
                if text:match(labelPattern .. "%s+" .. idPattern .. "%f[%D]") then
                    return true
                end
            end
        end
    end

    return false
end

local function AddIDLine(tooltip, id, isItem)
    if not IsModifierKeyDown() then
        return
    end
    if not Tooltip:IsGameTooltipFrameSafe(tooltip) then
        return
    end

    id = tonumber(id)
    if not id then
        return
    end

    local label = isItem and ITEM_ID_TEXT or SPELL_ID_TEXT
    if TooltipHasIDLine(tooltip, label, id) then
        return
    end

    tooltip:AddLine(SPELL_ID_COLOR_PREFIX .. label .. " " .. id)
    if not isItem then
        tooltip:Show()
    end
end

local function AddAuraInstanceID(tooltip, unitToken, auraInstanceID)
    if not IsModifierKeyDown() or not C_UnitAuras or type(C_UnitAuras.GetAuraDataByAuraInstanceID) ~= "function" then
        return
    end

    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unitToken, auraInstanceID)
    local spellID = aura and aura.spellId
    if spellID then
        AddIDLine(tooltip, spellID, false)
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeSpellID()
    RefineUI:HookOnce(SPELL_ID_HOOK_SET_UNIT_AURA_KEY, GameTooltip, "SetUnitAura", function(tooltip, unitToken, index, filter)
        if not IsModifierKeyDown() then
            return
        end
        if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByIndex) ~= "function" then
            return
        end

        local auraInfo = C_UnitAuras.GetAuraDataByIndex(unitToken, index, filter)
        if auraInfo and auraInfo.spellId then
            AddIDLine(tooltip, auraInfo.spellId, false)
        end
    end)

    RefineUI:HookOnce(
        SPELL_ID_HOOK_SET_UNIT_BUFF_AURA_INSTANCE_KEY,
        GameTooltip,
        "SetUnitBuffByAuraInstanceID",
        AddAuraInstanceID
    )
    RefineUI:HookOnce(
        SPELL_ID_HOOK_SET_UNIT_DEBUFF_AURA_INSTANCE_KEY,
        GameTooltip,
        "SetUnitDebuffByAuraInstanceID",
        AddAuraInstanceID
    )

    RefineUI:HookOnce(SPELL_ID_HOOK_SET_ITEM_REF_KEY, "SetItemRef", function(link)
        if type(link) ~= "string" then
            return
        end
        local spellID = tonumber(link:match("spell:(%d+)"))
        if spellID then
            AddIDLine(ItemRefTooltip, spellID, false)
        end
    end)

    Tooltip:RegisterItemHandler(SPELL_ID_ITEM_HANDLER_KEY, function(tooltip, data)
        if not IsModifierKeyDown() then
            return
        end
        if not Tooltip:IsAugmentableTooltipFrame(tooltip) then
            return
        end
        AddIDLine(tooltip, data and data.id, true)
    end)

    if TOOLTIP_DATA_TYPE and TOOLTIP_DATA_TYPE.Spell then
        Tooltip:AddTooltipPostCallOnce(SPELL_ID_POSTCALL_SPELL_KEY, TOOLTIP_DATA_TYPE.Spell, function(tooltip, data)
            if not IsModifierKeyDown() then
                return
            end
            if tooltip ~= GameTooltip then
                return
            end
            AddIDLine(tooltip, data and data.id, false)
        end)
    end

    if TOOLTIP_DATA_TYPE and TOOLTIP_DATA_TYPE.Macro then
        Tooltip:AddTooltipPostCallOnce(SPELL_ID_POSTCALL_MACRO_KEY, TOOLTIP_DATA_TYPE.Macro, function(tooltip, data)
            if not IsModifierKeyDown() then
                return
            end
            if not Tooltip:IsGameTooltipFrameSafe(tooltip) then
                return
            end
            if not Tooltip:CanAccessObjectSafe(data) then
                return
            end

            local lineData = data.lines and data.lines[1]
            local tooltipType = lineData and lineData.tooltipType
            if tooltipType == 0 then
                AddIDLine(tooltip, lineData.tooltipID, true)
            elseif tooltipType == 1 then
                AddIDLine(tooltip, lineData.tooltipID, false)
            end
        end)
    end

    if TOOLTIP_DATA_TYPE and TOOLTIP_DATA_TYPE.Toy then
        Tooltip:AddTooltipPostCallOnce(SPELL_ID_POSTCALL_TOY_KEY, TOOLTIP_DATA_TYPE.Toy, function(tooltip, data)
            if not IsModifierKeyDown() then
                return
            end
            if tooltip ~= GameTooltip then
                return
            end
            AddIDLine(tooltip, data and data.id, true)
        end)
    end
end
