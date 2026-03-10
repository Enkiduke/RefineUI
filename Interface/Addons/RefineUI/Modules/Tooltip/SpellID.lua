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
local SPELL_ID_RENDER_FLAG_PREFIX = "Tooltip:SpellID:"

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
local function ClaimRenderFlag(tooltip, context, key)
    key = Tooltip:ReadSafeString(key)
    if not key or key == "" then
        return false
    end

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
    local renderFlag = SPELL_ID_RENDER_FLAG_PREFIX .. label .. ":" .. tostring(id)
    if not ClaimRenderFlag(tooltip, context, renderFlag) then
        return
    end

    tooltip:AddLine(SPELL_ID_COLOR_PREFIX .. label .. " " .. id)
    if not isItem then
        tooltip:Show()
    end
end

local function GetTooltipDataID(data)
    if not Tooltip:CanAccessObjectSafe(data) then
        return nil
    end
    local rawID, okID = Tooltip:SafeGetField(data, "id")
    if not okID then
        return nil
    end
    return Tooltip:ReadSafeNumber(rawID)
end

local function AddAuraInstanceID(tooltip, unitToken, auraInstanceID)
    if not IsModifierKeyDown() or not C_UnitAuras or type(C_UnitAuras.GetAuraDataByAuraInstanceID) ~= "function" then
        return
    end

    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unitToken, auraInstanceID)
    local spellID = aura and Tooltip:ReadSafeNumber(aura.spellId)
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
            Tooltip:ResetTooltipRenderFlags(ItemRefTooltip)
            AddIDLine(ItemRefTooltip, spellID, false)
        end
    end)

    Tooltip:RegisterItemHandler(SPELL_ID_ITEM_HANDLER_KEY, function(tooltip, data, context)
        if not IsModifierKeyDown() then
            return
        end
        if not Tooltip:IsAugmentableTooltipFrame(tooltip) then
            return
        end
        AddIDLine(tooltip, data and data.id, true, context)
    end)

    if TOOLTIP_DATA_TYPE and TOOLTIP_DATA_TYPE.Spell then
        Tooltip:AddTooltipPostCallOnce(SPELL_ID_POSTCALL_SPELL_KEY, TOOLTIP_DATA_TYPE.Spell, function(tooltip, data)
            if not IsModifierKeyDown() then
                return
            end
            if tooltip ~= GameTooltip then
                return
            end
            AddIDLine(tooltip, GetTooltipDataID(data), false)
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
            AddIDLine(tooltip, GetTooltipDataID(data), true)
        end)
    end
end
