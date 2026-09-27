----------------------------------------------------------------------------------------
-- Tooltip Unit
-- Description: Unit tooltip text formatting and hide-in-combat handling.
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
local ReadSafeBoolean = Private.ReadSafeBoolean
local ReadSafeNumber = Private.ReadSafeNumber
local ReadSafeString = Private.ReadSafeString
local IsAccessibleTable = Private.IsAccessibleTable

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local gsub = string.gsub
local find = string.find
local strlower = strlower
local issecretvalue = issecretvalue
local IsShiftKeyDown = IsShiftKeyDown

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltip = _G.GameTooltip
local AddTooltipPostCall = TooltipDataProcessor.AddTooltipPostCall
local UnitRace = UnitRace
local UnitClass = UnitClass
local UnitName = UnitName
local UnitPVPName = UnitPVPName
local UnitCreatureType = UnitCreatureType
local UnitClassification = UnitClassification
local UnitRealmRelationship = UnitRealmRelationship
local UnitIsPlayer = UnitIsPlayer
local UnitIsAFK = UnitIsAFK
local UnitIsDND = UnitIsDND
local UnitEffectiveLevel = UnitEffectiveLevel
local IsInGuild = IsInGuild
local GetGuildInfo = GetGuildInfo
local GetQuestDifficultyColor = GetQuestDifficultyColor
local InCombatLockdown = InCombatLockdown
local UNIT_TOOLTIP_TYPE = Enum.TooltipDataType.Unit

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local BOSS = _G.BOSS
local ELITE = _G.ELITE
local FOREIGN_SERVER_LABEL = _G.FOREIGN_SERVER_LABEL
local INTERACTIVE_SERVER_LABEL = _G.INTERACTIVE_SERVER_LABEL
local LE_REALM_RELATION_COALESCED = _G.LE_REALM_RELATION_COALESCED
local LE_REALM_RELATION_VIRTUAL = _G.LE_REALM_RELATION_VIRTUAL

local LEVEL1 = strlower(_G.TOOLTIP_UNIT_LEVEL:gsub("%s?%%s%s?%-?", ""))
local LEVEL2 = strlower(
    (_G.TOOLTIP_UNIT_LEVEL_RACE or _G.TOOLTIP_UNIT_LEVEL_CLASS)
        :gsub("^%%2$s%s?(.-)%s?%%1$s", "%1")
        :gsub("^%-?г?о?%s?", "")
        :gsub("%s?%%s%s?%-?", "")
)

local CLASSIFICATION_TEXT = {
    worldboss = "|CFFFF0000" .. BOSS .. "|r ",
    rareelite = "|CFFFF66CCRare|r |cffFFFF00" .. ELITE .. "|r ",
    elite = "|CFFFFFF00" .. ELITE .. "|r ",
    rare = "|CFFFF66CCRare|r ",
}

local BOSS_LEVEL_COLOR = { r = 1, g = 0, b = 0 }

----------------------------------------------------------------------------------------
-- Hide In Combat
----------------------------------------------------------------------------------------
local function IsPlayerDebuffAuraTooltip(tooltipFrame)
    local owner = tooltipFrame:GetOwner()
    if type(owner) ~= "table" or owner:IsForbidden() then
        return false
    end

    local ownerUnit = ReadSafeString(owner.unit)
    if ownerUnit and ownerUnit ~= "player" then
        return false
    end

    local auraType = ReadSafeString(owner.auraType)
    if not auraType and IsAccessibleTable(owner.buttonInfo) then
        auraType = ReadSafeString(owner.buttonInfo.auraType)
    end

    return auraType == "Debuff" or auraType == "DeadlyDebuff"
end

function Tooltip:MaybeHideInCombat(tooltipFrame)
    if not Config.Tooltip.HideInCombat or not InCombatLockdown() then
        return false
    end

    local itemRefTooltip = _G.ItemRefTooltip
    if tooltipFrame ~= GameTooltip and tooltipFrame ~= itemRefTooltip then
        return false
    end
    if Config.Auras.AllowDebuffTooltipsInCombat and IsPlayerDebuffAuraTooltip(tooltipFrame) then
        return false
    end

    tooltipFrame:Hide()
    if tooltipFrame == itemRefTooltip then
        _G.ItemRefShoppingTooltip1:Hide()
        _G.ItemRefShoppingTooltip2:Hide()
    end
    return true
end

local function HideInCombatOnShow(frame)
    Tooltip:MaybeHideInCombat(frame)
end

----------------------------------------------------------------------------------------
-- Unit Formatting
----------------------------------------------------------------------------------------
local function FormatUnitName(unitToken)
    local nameLine = GameTooltip:GetLeftLine(1)
    local name, realm = UnitName(unitToken)
    if issecretvalue(name) then
        nameLine:SetText(name)
        return
    end

    name = ReadSafeString(name) or ""
    realm = ReadSafeString(realm)

    local title = ReadSafeString(UnitPVPName(unitToken))
    if title and title ~= "" then
        name = title
    end

    if realm and realm ~= "" then
        local relationship = ReadSafeNumber(UnitRealmRelationship(unitToken))
        if IsShiftKeyDown() then
            name = name .. "-" .. realm
        elseif relationship == LE_REALM_RELATION_COALESCED then
            name = name .. FOREIGN_SERVER_LABEL
        elseif relationship == LE_REALM_RELATION_VIRTUAL then
            name = name .. INTERACTIVE_SERVER_LABEL
        end
    end

    local statusText = ""
    if ReadSafeBoolean(UnitIsAFK(unitToken)) then
        statusText = " |CFF559655" .. CHAT_FLAG_AFK .. "|r"
    elseif ReadSafeBoolean(UnitIsDND(unitToken)) then
        statusText = " |CFF559655" .. CHAT_FLAG_DND .. "|r"
    end

    local r, g, b = Tooltip:GetUnitBorderColor(unitToken)
    local color = r and RefineUI:RGBToHex(r, g, b) or "|CFFFFFFFF"
    nameLine:SetText(color .. name .. "|r" .. statusText)
end

local function FormatGuildInfo(unitToken)
    local guildLine = GameTooltip:GetLeftLine(2)
    local guildName, guildRankName = GetGuildInfo(unitToken)
    guildName = ReadSafeString(guildName)
    if not guildLine or not guildName then
        return
    end

    local sameGuild = IsInGuild() and ReadSafeString(GetGuildInfo("player")) == guildName
    local formatString = sameGuild
        and "|CFFFF66CC[%s]|r |CFF00FF10[%s]|r"
        or "|CFFFFFFFF[%s]|r |CFF00FF10[%s]|r"

    guildLine:SetFormattedText(formatString, guildName, ReadSafeString(guildRankName) or "")
end

local function FormatUnitLines(unitToken)
    local isPlayer = ReadSafeBoolean(UnitIsPlayer(unitToken))
    local className, classFile = UnitClass(unitToken)
    className = ReadSafeString(className)
    classFile = ReadSafeString(classFile)
    local classColor = classFile and Colors.Class[classFile]
    local lowerClassName = className and strlower(className)
    local race = ReadSafeString(UnitRace(unitToken))
    local creatureType = ReadSafeString(UnitCreatureType(unitToken))
    local classification = ReadSafeString(UnitClassification(unitToken))
    local level = ReadSafeNumber(UnitEffectiveLevel(unitToken)) or -1
    local diffColor = GetQuestDifficultyColor(level)
    local levelColor = (level == -1 or classification == "worldboss") and BOSS_LEVEL_COLOR or diffColor
    local levelText = level > 0 and level or "??"

    for lineIndex = 2, GameTooltip:NumLines() do
        local line = GameTooltip:GetLeftLine(lineIndex)
        local text = line and ReadSafeString(line:GetText())
        if not text then
            break
        end

        local lowerText = strlower(text)
        if isPlayer
            and classColor
            and lowerClassName
            and find(lowerText, lowerClassName)
            and not find(lowerText, "alliance")
            and not find(lowerText, "horde")
        then
            line:SetFormattedText(
                "|cFFFFFFFF%s |cff%02x%02x%02x%s|r",
                gsub(text, className, ""):trim(),
                classColor.r * 255,
                classColor.g * 255,
                classColor.b * 255,
                className
            )
        end

        if find(lowerText, LEVEL1) or find(lowerText, LEVEL2) then
            if isPlayer then
                line:SetFormattedText(
                    "Level |cff%02x%02x%02x%s|r %s",
                    diffColor.r * 255,
                    diffColor.g * 255,
                    diffColor.b * 255,
                    levelText,
                    race or ""
                )
            else
                line:SetFormattedText(
                    "Level |cff%02x%02x%02x%s|r %s%s",
                    levelColor.r * 255,
                    levelColor.g * 255,
                    levelColor.b * 255,
                    levelText,
                    CLASSIFICATION_TEXT[classification] or "",
                    creatureType or ""
                )
            end
        end

        if text == creatureType or text == _G.FACTION_HORDE or text == _G.FACTION_ALLIANCE or text == _G.PVP then
            line:SetText("")
            line:Hide()
        end
    end
end

-- Border color is applied by the AllTypes post-call in Style.lua, which runs first.
local function OnUnitTooltipData(tooltipFrame, data)
    if Tooltip:MaybeHideInCombat(tooltipFrame) or tooltipFrame ~= GameTooltip then
        return
    end

    local unitToken = Tooltip:ResolveTooltipUnitToken(tooltipFrame, data)
    if not unitToken then
        return
    end

    FormatUnitName(unitToken)
    FormatGuildInfo(unitToken)
    FormatUnitLines(unitToken)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipUnit()
    AddTooltipPostCall(UNIT_TOOLTIP_TYPE, OnUnitTooltipData)

    if Config.Tooltip.HideInCombat then
        RefineUI:HookScriptOnce("Tooltip:HideInCombat:GameTooltip:OnShow", GameTooltip, "OnShow", HideInCombatOnShow)
        RefineUI:HookScriptOnce("Tooltip:HideInCombat:ItemRefTooltip:OnShow", _G.ItemRefTooltip, "OnShow", HideInCombatOnShow)
    end
end
