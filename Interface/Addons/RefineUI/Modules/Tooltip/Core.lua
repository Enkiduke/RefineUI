----------------------------------------------------------------------------------------
-- Tooltip Core
-- Description: Shared secret-safe readers, tooltip checks, and color resolution.
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
local Config = RefineUI.Config
local Colors = RefineUI.Colors

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local type = type
local issecretvalue = issecretvalue
local canaccesstable = canaccesstable

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltip = GameTooltip
local ColorManager = ColorManager
local GetItemQualityByID = C_Item.GetItemQualityByID
local GetItemLinkByGUID = C_Item.GetItemLinkByGUID
local RequestLoadItemDataByID = C_Item.RequestLoadItemDataByID
local GetMouseFoci = GetMouseFoci
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local UnitCanAttack = UnitCanAttack
local UnitCanAssist = UnitCanAssist
local UnitTokenFromGUID = UnitTokenFromGUID
local GameTooltip_UnitColor = GameTooltip_UnitColor
local UNIT_TOOLTIP_TYPE = Enum.TooltipDataType.Unit

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local UNIT_TOOLTIP_FALLBACK_TOKENS = { "mouseover", "softenemy", "softfriend", "softinteract" }

local AUGMENTABLE_TOOLTIP_NAMES = {
    GameTooltip = true,
    ItemRefTooltip = true,
    ItemRefShoppingTooltip1 = true,
    ItemRefShoppingTooltip2 = true,
    ShoppingTooltip1 = true,
    ShoppingTooltip2 = true,
}

----------------------------------------------------------------------------------------
-- Secret-Safe Readers
----------------------------------------------------------------------------------------
local function ReadSafeBoolean(value)
    if type(value) == "boolean" and not issecretvalue(value) then
        return value
    end
end

local function ReadSafeNumber(value)
    if type(value) == "number" and not issecretvalue(value) then
        return value
    end
end

local function ReadSafeString(value)
    if type(value) == "string" and not issecretvalue(value) then
        return value
    end
end

local function IsAccessibleTable(value)
    return type(value) == "table" and canaccesstable(value)
end

----------------------------------------------------------------------------------------
-- Tooltip Checks
----------------------------------------------------------------------------------------
local function IsTooltip(frame)
    return type(frame) == "table" and not frame:IsForbidden() and frame:IsObjectType("GameTooltip")
end

-- Embedded item tooltips carry the IsEmbedded key value from their XML template.
local function IsStyledTooltip(frame)
    return IsTooltip(frame) and not frame.IsEmbedded
end

local function IsAugmentableTooltip(frame)
    return IsTooltip(frame) and AUGMENTABLE_TOOLTIP_NAMES[frame:GetName()] == true
end

Private.ReadSafeBoolean = ReadSafeBoolean
Private.ReadSafeNumber = ReadSafeNumber
Private.ReadSafeString = ReadSafeString
Private.IsAccessibleTable = IsAccessibleTable
Private.IsTooltip = IsTooltip
Private.IsStyledTooltip = IsStyledTooltip
Private.IsAugmentableTooltip = IsAugmentableTooltip

function Tooltip:ReadSafeNumber(value)
    return ReadSafeNumber(value)
end

function Tooltip:ReadSafeString(value)
    return ReadSafeString(value)
end

function Tooltip:IsAugmentableTooltipFrame(frame)
    return IsAugmentableTooltip(frame)
end

----------------------------------------------------------------------------------------
-- Item Handlers
----------------------------------------------------------------------------------------
local itemHandlers = {}

-- Handlers run in registration order from the item post-call, before line styling.
function Tooltip:RegisterItemHandler(handler)
    itemHandlers[#itemHandlers + 1] = handler
end

function Tooltip:DispatchItemHandlers(tooltip, data)
    if not IsAccessibleTable(data) then
        return
    end
    for index = 1, #itemHandlers do
        itemHandlers[index](tooltip, data)
    end
end

----------------------------------------------------------------------------------------
-- Colors
----------------------------------------------------------------------------------------
function Tooltip:GetDefaultTooltipBorderColor()
    local color = Config.General.BorderColor
    return color[1], color[2], color[3], color[4] or 1
end

function Tooltip:GetItemQualityBorderColor(quality)
    if not quality then
        return nil
    end

    local colorData = ColorManager.GetColorDataForItemQuality(quality)
    local color = colorData and colorData.color
    if color then
        local r, g, b = color:GetRGB()
        return r, g, b, 1
    end

    color = Colors.Quality[quality]
    if color then
        return color.r, color.g, color.b, 1
    end
end

local function GetItemQuality(item)
    if not item then
        return nil
    end

    local quality = ReadSafeNumber(GetItemQualityByID(item))
    if not quality then
        RequestLoadItemDataByID(item)
    end
    return quality
end

function Tooltip:ResolveTooltipItemQuality(tooltip, data)
    if IsAccessibleTable(data) then
        local quality = ReadSafeNumber(data.quality)
            or GetItemQuality(ReadSafeString(data.hyperlink))
        if quality then
            return quality
        end

        local guid = ReadSafeString(data.guid)
        quality = guid and GetItemQuality(ReadSafeString(GetItemLinkByGUID(guid)))
            or GetItemQuality(ReadSafeNumber(data.id))
        if quality then
            return quality
        end
    end

    local _, itemLink, itemID = tooltip:GetItem()
    return GetItemQuality(ReadSafeString(itemLink)) or GetItemQuality(ReadSafeNumber(itemID))
end

function Tooltip:GetUnitBorderColor(unitToken)
    if ReadSafeBoolean(UnitIsDead(unitToken)) or ReadSafeBoolean(UnitIsGhost(unitToken)) then
        return self:GetDefaultTooltipBorderColor()
    end

    local color
    if ReadSafeBoolean(UnitIsPlayer(unitToken)) and not ReadSafeBoolean(UnitHasVehicleUI(unitToken)) then
        local _, classFile = UnitClass(unitToken)
        classFile = ReadSafeString(classFile)
        color = classFile and Colors.Class[classFile]
    end
    if not color then
        local reaction = ReadSafeNumber(UnitReaction(unitToken, "player"))
        color = reaction and Colors.Reaction[reaction]
    end
    if color then
        return color.r, color.g, color.b, 1
    end

    local r, g, b = GameTooltip_UnitColor(unitToken)
    r, g, b = ReadSafeNumber(r), ReadSafeNumber(g), ReadSafeNumber(b)
    if r and g and b then
        return r, g, b, 1
    end

    local reactionIndex
    if ReadSafeBoolean(UnitCanAttack("player", unitToken)) then
        reactionIndex = ReadSafeBoolean(UnitCanAttack(unitToken, "player")) and 2 or 4
    elseif ReadSafeBoolean(UnitCanAssist("player", unitToken)) then
        reactionIndex = 5
    end
    color = reactionIndex and Colors.Reaction[reactionIndex]
    if color then
        return color.r, color.g, color.b, 1
    end
end

----------------------------------------------------------------------------------------
-- Unit Resolution
----------------------------------------------------------------------------------------
local function ValidateUnitToken(token)
    token = ReadSafeString(token)
    if token and token ~= "" and ReadSafeBoolean(UnitExists(token)) then
        return token
    end
end

local function ResolveUnitTokenFromData(data)
    local unitToken = ValidateUnitToken(data.unitToken)
    if unitToken then
        return unitToken
    end

    local guid = ReadSafeString(data.guid)
    return guid and ValidateUnitToken(UnitTokenFromGUID(guid))
end

local function ResolveMouseFocusUnit()
    local foci = GetMouseFoci()
    local focus = foci and foci[1]
    if type(focus) ~= "table" or focus:IsForbidden() or not focus.GetAttribute then
        return nil
    end
    return ValidateUnitToken(focus:GetAttribute("unit"))
end

function Tooltip:ResolveTooltipUnitToken(tooltip, data)
    local _, unitToken = tooltip:GetUnit()
    unitToken = ValidateUnitToken(unitToken)
    if unitToken then
        return unitToken
    end

    -- SharedTooltipTemplate frames lack the tooltip data mixin.
    if not tooltip.GetPrimaryTooltipData then
        return nil
    end

    data = data or tooltip:GetPrimaryTooltipData()
    if not IsAccessibleTable(data) then
        return nil
    end

    unitToken = ResolveUnitTokenFromData(data)
    if unitToken then
        return unitToken
    end

    if tooltip ~= GameTooltip then
        return nil
    end
    if ReadSafeNumber(data.type) ~= UNIT_TOOLTIP_TYPE and not tooltip:IsTooltipType(UNIT_TOOLTIP_TYPE) then
        return nil
    end

    unitToken = ResolveMouseFocusUnit()
    if unitToken then
        return unitToken
    end

    for index = 1, #UNIT_TOOLTIP_FALLBACK_TOKENS do
        unitToken = ValidateUnitToken(UNIT_TOOLTIP_FALLBACK_TOKENS[index])
        if unitToken then
            return unitToken
        end
    end
end

-- Secret units have no readable token; fall back to the name line color.
function Tooltip:GetUnitBorderColorFromTooltipData(data)
    if not IsAccessibleTable(data) then
        return nil
    end

    local lines = data.lines
    if not IsAccessibleTable(lines) then
        return nil
    end

    for index = 1, #lines do
        local line = lines[index]
        if IsAccessibleTable(line) then
            local unitToken = ValidateUnitToken(line.unitToken)
            if unitToken then
                return self:GetUnitBorderColor(unitToken)
            end

            local color = line.leftColor
            if IsAccessibleTable(color) then
                local r, g, b = ReadSafeNumber(color.r), ReadSafeNumber(color.g), ReadSafeNumber(color.b)
                if r and g and b then
                    return r, g, b, 1
                end
            end
        end
    end
end
