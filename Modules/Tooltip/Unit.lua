----------------------------------------------------------------------------------------
-- Tooltip Unit
-- Description: Unit tooltip text formatting, statusbar handling, and unit post-calls.
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
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Config = RefineUI.Config
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local select = select
local gsub = string.gsub
local find = string.find
local strlower = strlower
local IsShiftKeyDown = IsShiftKeyDown

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltip = _G.GameTooltip
local GameTooltipStatusBar = _G.GameTooltipStatusBar
local UnitRace = UnitRace
local UnitClass = UnitClass
local UnitLevel = UnitLevel
local UnitName = UnitName
local UnitPVPName = UnitPVPName
local UnitCreatureType = UnitCreatureType
local UnitClassification = UnitClassification
local UnitRealmRelationship = UnitRealmRelationship
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local UnitIsTapDenied = UnitIsTapDenied
local UnitIsAFK = UnitIsAFK
local UnitIsDND = UnitIsDND
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitEffectiveLevel = UnitEffectiveLevel
local UnitInPartyIsAI = UnitInPartyIsAI
local UnitPlayerControlled = UnitPlayerControlled
local IsInGuild = IsInGuild
local GetGuildInfo = GetGuildInfo
local GetQuestDifficultyColor = GetQuestDifficultyColor
local InCombatLockdown = InCombatLockdown
local TOOLTIP_DATA_TYPE = Enum and Enum.TooltipDataType

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TOOLTIP_UNIT_POSTCALL_KEY = "Tooltip:PostCall:Unit"
local TOOLTIP_HIDE_IN_COMBAT_HOOK_KEY = "Tooltip:GameTooltip:OnShow:HideInCombat"

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

local function IsPlayerDebuffAuraTooltip(tooltipFrame)
    if not Tooltip:IsGameTooltipFrameSafe(tooltipFrame) then
        return false
    end

    local okOwner, owner = Tooltip:SafeObjectMethodCall(tooltipFrame, "GetOwner")
    if not okOwner or not Tooltip:CanAccessObjectSafe(owner) or Tooltip:IsForbiddenFrameSafe(owner) then
        return false
    end

    local ownerUnit = Tooltip:ReadSafeString(select(1, Tooltip:SafeGetField(owner, "unit")))
    if ownerUnit and ownerUnit ~= "player" then
        return false
    end

    local auraType = Tooltip:ReadSafeString(select(1, Tooltip:SafeGetField(owner, "auraType")))
    if not auraType then
        local buttonInfo = select(1, Tooltip:SafeGetField(owner, "buttonInfo"))
        if Tooltip:CanAccessObjectSafe(buttonInfo) then
            auraType = Tooltip:ReadSafeString(select(1, Tooltip:SafeGetField(buttonInfo, "auraType")))
        end
    end

    return auraType == "Debuff" or auraType == "DeadlyDebuff"
end

----------------------------------------------------------------------------------------
-- Unit Formatting
----------------------------------------------------------------------------------------
function Tooltip:GetColor(unitToken)
    if not unitToken then
        return
    end

    local r, g, b = Tooltip:GetUnitBorderColor(unitToken)
    if not r or not g or not b then
        return
    end

    return RefineUI:RGBToHex(r, g, b), r, g, b
end

function Tooltip:ApplyStatusBarColor(unitToken, classFile, reaction)
    if not GameTooltipStatusBar or not unitToken then
        return
    end

    local r, g, b = 1, 1, 1
    local isConnected = Tooltip:ReadSafeBoolean(UnitIsConnected(unitToken))
    local isTapDenied = Tooltip:ReadSafeBoolean(UnitIsTapDenied(unitToken))
    local isGhost = Tooltip:ReadSafeBoolean(UnitIsGhost(unitToken))
    local isDead = Tooltip:ReadSafeBoolean(UnitIsDead(unitToken))
    local isPlayer = Tooltip:ReadSafeBoolean(UnitIsPlayer(unitToken))
    local isPartyAI = Tooltip:ReadSafeBoolean(UnitInPartyIsAI(unitToken))
    local isPlayerControlled = Tooltip:ReadSafeBoolean(UnitPlayerControlled(unitToken))

    if isConnected == false or isTapDenied == true or isGhost == true then
        r, g, b = 0.5, 0.5, 0.5
    elseif isDead == true then
        r, g, b = 0.5, 0, 0
    elseif isPlayer == true or isPartyAI == true or (isPlayerControlled == true and isPlayer ~= true) then
        local safeClassFile = Tooltip:IsSecretValueSafe(classFile) and nil or classFile
        local classColor = safeClassFile and Colors and Colors.Class and Colors.Class[safeClassFile]
        if classColor then
            r, g, b = classColor.r, classColor.g, classColor.b
        end
    else
        local reactionKey = Tooltip:ReadSafeNumber(reaction)
        local reactionColor = reactionKey and Colors and Colors.Reaction and Colors.Reaction[reactionKey]
        if reactionColor then
            r, g, b = reactionColor.r, reactionColor.g, reactionColor.b
        else
            local unitR, unitG, unitB = Tooltip:GetUnitBorderColor(unitToken)
            if unitR and unitG and unitB then
                r, g, b = unitR, unitG, unitB
            end
        end
    end

    GameTooltipStatusBar:SetStatusBarColor(r, g, b)
    if GameTooltipStatusBar.bg then
        if GameTooltipStatusBar.bg.border then
            GameTooltipStatusBar.bg.border:SetColorTexture(r * 0.5, g * 0.5, b * 0.5, 0.7)
        else
            GameTooltipStatusBar.bg:SetBackdropColor(r * 0.5, g * 0.5, b * 0.5, 0.7)
        end
    end
end

function Tooltip:FormatUnitName(unitToken)
    local name, realm = UnitName(unitToken)
    if Tooltip:IsSecretValueSafe(name) then
        if _G.GameTooltipTextLeft1 then
            _G.GameTooltipTextLeft1:SetText(name)
        end
        return
    end

    name = Tooltip:ReadSafeString(name) or ""
    realm = Tooltip:ReadSafeString(realm)

    local title = Tooltip:ReadSafeString(UnitPVPName(unitToken))
    local relationship = Tooltip:ReadSafeNumber(UnitRealmRelationship(unitToken))
    local color = Tooltip:GetColor(unitToken) or "|CFFFFFFFF"
    local statusText = ""

    if title and title ~= "" then
        name = title
    end

    if realm and realm ~= "" then
        if IsShiftKeyDown() then
            name = name .. "-" .. realm
        elseif relationship == LE_REALM_RELATION_COALESCED then
            name = name .. FOREIGN_SERVER_LABEL
        elseif relationship == LE_REALM_RELATION_VIRTUAL then
            name = name .. INTERACTIVE_SERVER_LABEL
        end
    end

    if Tooltip:ReadSafeBoolean(UnitIsAFK(unitToken)) == true then
        statusText = " |CFF559655" .. CHAT_FLAG_AFK .. "|r"
    elseif Tooltip:ReadSafeBoolean(UnitIsDND(unitToken)) == true then
        statusText = " |CFF559655" .. CHAT_FLAG_DND .. "|r"
    end

    if _G.GameTooltipTextLeft1 then
        _G.GameTooltipTextLeft1:SetText(color .. name .. "|r" .. statusText)
    end
end

function Tooltip:FormatGuildInfo(unitToken)
    local guildName, guildRankName = GetGuildInfo(unitToken)
    guildName = Tooltip:ReadSafeString(guildName)
    guildRankName = Tooltip:ReadSafeString(guildRankName) or ""
    if not guildName then
        return
    end

    local playerGuild = Tooltip:ReadSafeString(GetGuildInfo("player"))
    local sameGuild = IsInGuild() and playerGuild ~= nil and playerGuild == guildName
    local formatString = sameGuild
        and "|CFFFF66CC[%s]|r |CFF00FF10[%s]|r"
        or "|CFFFFFFFF[%s]|r |CFF00FF10[%s]|r"

    if _G.GameTooltipTextLeft2 then
        _G.GameTooltipTextLeft2:SetFormattedText(formatString, guildName, guildRankName)
    end
end

function Tooltip:ProcessTooltipLines(tooltipFrame, unitToken, numLines, isPlayer, className, classFile, race, creatureType, classification, level)
    local classColor = (classFile and not Tooltip:IsSecretValueSafe(classFile)) and Colors and Colors.Class and Colors.Class[classFile] or nil
    local safeLevel = Tooltip:ReadSafeNumber(level) or -1
    local diffColor = GetQuestDifficultyColor(safeLevel)
    local levelColor = (safeLevel == -1 or classification == "worldboss") and { r = 1, g = 0, b = 0 } or diffColor

    local safeClassName = Tooltip:ReadSafeString(className)
    local lowerClassName = safeClassName and strlower(safeClassName)

    for lineIndex = 2, numLines do
        local line = Tooltip:GetCachedLine(tooltipFrame, lineIndex)
        if not line then
            break
        end

        local text = line:GetText()
        if not text or Tooltip:IsSecretValueSafe(text) or type(text) ~= "string" then
            break
        end

        local lowerText = strlower(text)
        if isPlayer
            and lowerClassName
            and find(lowerText, lowerClassName)
            and not find(lowerText, "alliance")
            and not find(lowerText, "horde")
        then
            local specText = gsub(text, safeClassName, ""):trim()
            if classColor then
                line:SetFormattedText(
                    "|cFFFFFFFF%s |cff%02x%02x%02x%s|r",
                    specText,
                    classColor[1] * 255,
                    classColor[2] * 255,
                    classColor[3] * 255,
                    safeClassName
                )
            end
        end

        if find(lowerText, LEVEL1) or find(lowerText, LEVEL2) then
            if isPlayer then
                line:SetFormattedText(
                    "Level |cff%02x%02x%02x%s|r %s",
                    diffColor.r * 255,
                    diffColor.g * 255,
                    diffColor.b * 255,
                    safeLevel > 0 and safeLevel or "??",
                    race or ""
                )
            else
                local classText = CLASSIFICATION_TEXT[classification] or ""
                line:SetFormattedText(
                    "Level |cff%02x%02x%02x%s|r %s%s",
                    levelColor.r * 255,
                    levelColor.g * 255,
                    levelColor.b * 255,
                    safeLevel > 0 and safeLevel or "??",
                    classText,
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

function Tooltip:OnTooltipSetUnit(tooltipFrame, data)
    if not Tooltip:IsGameTooltipFrameSafe(tooltipFrame) then
        return
    end

    local unitToken = Tooltip:ResolveTooltipUnitToken(tooltipFrame, data)
    if unitToken then
        Tooltip:ApplyUnitBorderColor(tooltipFrame, unitToken)
    elseif Tooltip.ApplyUnitBorderColorFromData then
        if not Tooltip:ApplyUnitBorderColorFromData(tooltipFrame, data) then
            Tooltip:ResetTooltipBorderColor(tooltipFrame)
        end
    else
        Tooltip:ResetTooltipBorderColor(tooltipFrame)
    end

    if tooltipFrame ~= GameTooltip or not unitToken or not UnitExists(unitToken) then
        return
    end

    local numLines = tooltipFrame:NumLines()
    local isPlayer = Tooltip:ReadSafeBoolean(UnitIsPlayer(unitToken)) == true
    local className, classFile = UnitClass(unitToken)
    if Tooltip:IsSecretValueSafe(className) then
        className = nil
    end
    if Tooltip:IsSecretValueSafe(classFile) then
        classFile = nil
    end
    local race = Tooltip:ReadSafeString(UnitRace(unitToken))
    local level = (UnitEffectiveLevel or UnitLevel)(unitToken)
    if Tooltip:IsSecretValueSafe(level) or type(level) ~= "number" then
        level = -1
    end
    local creatureType = Tooltip:ReadSafeString(UnitCreatureType(unitToken))
    local classification = Tooltip:ReadSafeString(UnitClassification(unitToken))
    local reaction = Tooltip:ReadSafeNumber(UnitReaction(unitToken, "player"))

    Tooltip:FormatUnitName(unitToken)
    Tooltip:FormatGuildInfo(unitToken)
    Tooltip:ProcessTooltipLines(
        tooltipFrame,
        unitToken,
        numLines,
        isPlayer,
        className,
        classFile,
        race,
        creatureType,
        classification,
        level
    )
    Tooltip:ApplyStatusBarColor(unitToken, classFile, reaction)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipUnit()
    if TOOLTIP_DATA_TYPE and TOOLTIP_DATA_TYPE.Unit then
        Tooltip:AddTooltipPostCallOnce(TOOLTIP_UNIT_POSTCALL_KEY, TOOLTIP_DATA_TYPE.Unit, function(tt, data)
            Tooltip:OnTooltipSetUnit(tt, data)
        end)
    end

    if Config.Tooltip and Config.Tooltip.HideInCombat then
        RefineUI:HookScriptOnce(TOOLTIP_HIDE_IN_COMBAT_HOOK_KEY, GameTooltip, "OnShow", function(tt)
            if InCombatLockdown() then
                if Config.Auras and Config.Auras.AllowDebuffTooltipsInCombat and IsPlayerDebuffAuraTooltip(tt) then
                    return
                end
                tt:Hide()
            end
        end)
    end
end
