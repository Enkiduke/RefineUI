----------------------------------------------------------------------------------------
-- Tooltip Icons
-- Description: Prepends spell/item icons to tooltip title lines.
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
local ReadSafeString = Private.ReadSafeString

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local AddTooltipPostCall = TooltipDataProcessor.AddTooltipPostCall
local GetItemIconByID = C_Item.GetItemIconByID
local GetSpellTexture = C_Spell.GetSpellTexture
local SPELL_TOOLTIP_TYPE = Enum.TooltipDataType.Spell
local MACRO_TOOLTIP_TYPE = Enum.TooltipDataType.Macro

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TOOLTIP_TITLE_ICON_FORMAT = "|T%s:20:20:0:0:64:64:4:60:4:60|t %s"

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function SetTooltipIcon(tooltip, icon)
    icon = ReadSafeNumber(icon) or ReadSafeString(icon)
    if not icon then
        return
    end

    local title = tooltip:GetLeftLine(1)
    local text = title and ReadSafeString(title:GetText())
    if not text or text == "" or text:find("|T" .. icon, 1, true) then
        return
    end

    title:SetFormattedText(TOOLTIP_TITLE_ICON_FORMAT, icon, text)
end

local function GetDataID(data)
    return IsAccessibleTable(data) and ReadSafeNumber(data.id)
end

local function OnItemTooltip(tooltip, data)
    local itemID = GetDataID(data)
    if itemID and IsAugmentableTooltip(tooltip) then
        SetTooltipIcon(tooltip, GetItemIconByID(itemID))
    end
end

local function OnSpellTooltip(tooltip, data)
    local spellID = GetDataID(data)
    if spellID and IsAugmentableTooltip(tooltip) then
        SetTooltipIcon(tooltip, GetSpellTexture(spellID))
    end
end

local function OnMacroTooltip(tooltip, data)
    local tooltipType, tooltipID = Tooltip:GetMacroTooltipTarget(data)
    if not tooltipID or not IsAugmentableTooltip(tooltip) then
        return
    end

    if tooltipType == 0 then
        SetTooltipIcon(tooltip, GetItemIconByID(tooltipID))
    elseif tooltipType == 1 then
        SetTooltipIcon(tooltip, GetSpellTexture(tooltipID))
    end
end

-- Macro tooltips describe their item (0) or spell (1) target on the first data line.
function Tooltip:GetMacroTooltipTarget(data)
    local lines = IsAccessibleTable(data) and data.lines
    local line = IsAccessibleTable(lines) and lines[1]
    if not IsAccessibleTable(line) then
        return nil
    end
    return ReadSafeNumber(line.tooltipType), ReadSafeNumber(line.tooltipID)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipIcons()
    self:RegisterItemHandler(OnItemTooltip)
    AddTooltipPostCall(SPELL_TOOLTIP_TYPE, OnSpellTooltip)
    AddTooltipPostCall(MACRO_TOOLTIP_TYPE, OnMacroTooltip)
end
