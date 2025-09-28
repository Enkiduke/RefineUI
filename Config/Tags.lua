local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = ns.oUF
-- External helpers from oUF/global env
local Hex = rawget(_G, "Hex") or R.RGBToHex
local TAGS = (oUF and oUF.Tags and oUF.Tags.Methods) or rawget(_G, "_TAGS")

-- Upvalues
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local UnitLevel = UnitLevel
local UnitName = UnitName
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitClassification = UnitClassification
local UnitIsWildBattlePet = UnitIsWildBattlePet
local UnitIsBattlePetCompanion = UnitIsBattlePetCompanion
local UnitBattlePetLevel = UnitBattlePetLevel
local UnitAffectingCombat = UnitAffectingCombat
local UnitThreatSituation = UnitThreatSituation
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local string = string
local math = math
local unpack = unpack

-- Forward declarations
local IsOffTankTanking

----------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------
local function FormatColor(r, g, b)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function GetColorForNPC(npcID, threatStatus)
    if npcID == "120651" then     -- Explosives affix
        return C.nameplate.extraColor
    elseif npcID == "174773" then -- Spiteful Shade affix
        return threatStatus == 3 and C.nameplate.extraColor or C.nameplate.good_color
    end
    return nil
end

local function GetThreatColor(unit, threatStatus)
    if R.Role == "Tank" then
        if threatStatus == 3 then
            return C.nameplate.mobColorEnable and R.ColorPlate[unit.npcID] or C.nameplate.good_color
        elseif threatStatus == 0 then
            return IsOffTankTanking(unit) and C.nameplate.offtank_color or C.nameplate.bad_color
        end
    else
        if threatStatus == 3 then
            return C.nameplate.bad_color
        elseif threatStatus == 0 then
            return C.nameplate.mobColorEnable and R.ColorPlate[unit.npcID] or C.nameplate.good_color
        end
    end
    return C.nameplate.near_color
end

IsOffTankTanking = function(unit)
    if not IsInRaid() then return false end
    for i = 1, GetNumGroupMembers() do
        if UnitExists("raid" .. i) and not UnitIsUnit("raid" .. i, "player") and
            UnitGroupRolesAssigned("raid" .. i) == "TANK" then
            local isTanking = UnitDetailedThreatSituation("raid" .. i, unit)
            if isTanking then return true end
        end
    end
    return false
end

----------------------------------------------------------------------------------------
-- Tags
----------------------------------------------------------------------------------------

-- oUF.Tags.Methods["RaidIcon"] = function(unit)
--     local iconIndex = GetRaidTargetIndex(unit)  -- Get the raid icon index
--     return iconIndex and string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:25|t", iconIndex) or ""  -- Format the icon with increased size
-- end
-- oUF.Tags.Events["RaidIcon"] = "RAID_TARGET_UPDATE"



oUF.Tags.Methods["Threat"] = function()
    local _, status, percent = UnitDetailedThreatSituation("player", "target")
    if percent and percent > 0 then
        return ("%s%d%%|r"):format(Hex(GetThreatStatusColor(status)), percent)
    end
end
oUF.Tags.Events["Threat"] = "UNIT_THREAT_LIST_UPDATE"
oUF.Tags.Methods["GetNameColor"] = function(unit)
    local reaction = UnitReaction(unit, "player")
    local name = UnitName(unit)
    if not name then
        return FormatColor(0.5, 0.5, 0.5)
    end

    if UnitIsPlayer(unit) then
        return TAGS and TAGS["raidcolor"] and TAGS["raidcolor"](unit)
    elseif reaction then
        local c = R.oUF_colors.reaction[reaction]
        return FormatColor(unpack(c))
    else
        return FormatColor(0.33, 0.59, 0.33)
    end
end
-- Name tags
local function CreateNameTag(length, ellipsis)
    return function(unit)
        local name = UnitName(unit)
        if not name then
            return ""  -- Return an empty string if name is nil
        end
        name = string.upper(name)
        return R.UTF(name, length, ellipsis)
    end
end

oUF.Tags.Methods["NameArena"] = CreateNameTag(4, false)
oUF.Tags.Methods["NameShort"] = CreateNameTag(8, false)
oUF.Tags.Methods["NameMedium"] = CreateNameTag(12, false)
oUF.Tags.Methods["NameLong"] = CreateNameTag(18, true)

oUF.Tags.Events["NameArena"] = "UNIT_NAME_UPDATE"
oUF.Tags.Events["NameShort"] = "UNIT_NAME_UPDATE"
oUF.Tags.Events["NameMedium"] = "UNIT_NAME_UPDATE"
oUF.Tags.Events["NameLong"] = "UNIT_NAME_UPDATE"

oUF.Tags.Methods["NameLongAbbrev"] = function(unit)
    local name = UnitName(unit)
    if string.len(name) > 16 then
        name = string.gsub(name, "-", "")
        name = string.gsub(name, "%s?(.[\128-\191]*)%S+%s", "%1. ")
    end
    name = string.upper(name)
    return R.UTF(name, 18, false)
end
oUF.Tags.Events["NameLongAbbrev"] = "UNIT_NAME_UPDATE"

local hiddenTooltip
local function GetHiddenTooltip()
    if not hiddenTooltip then
        hiddenTooltip = CreateFrame("GameTooltip", "HiddenTitleTooltip", UIParent, "GameTooltipTemplate")
        ---@diagnostic disable-next-line: param-type-mismatch
        hiddenTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return hiddenTooltip
end

local function GetNPCTitle(unit)
    if UnitIsPlayer(unit) or not UnitExists(unit) then return "" end
    
    local title = ""
    
    -- Use the reusable hidden tooltip
    local tooltip = GetHiddenTooltip()
    ---@diagnostic disable-next-line: param-type-mismatch
    tooltip:SetUnit(unit)
    
    -- Check the second line of the tooltip
    local secondLine = _G["HiddenTitleTooltipTextLeft2"]
    if secondLine then
        local text = secondLine:GetText()
        if text and not text:match("%d") and not UnitIsPlayer(unit) then
            title = "<" .. text .. ">"
        end
    end
    
    -- Clear the tooltip
    ---@diagnostic disable-next-line: param-type-mismatch
    tooltip:ClearLines()
    
    return title
end

oUF.Tags.Methods['NPCTitle'] = function(unit)
    return GetNPCTitle(unit)
end
oUF.Tags.Events['NPCTitle'] = 'UNIT_NAME_UPDATE'

oUF.Tags.Methods["LFD"] = function(unit)
    local role = UnitGroupRolesAssigned(unit)
    if role == "TANK" then
        return "|cff0070DE[T]|r"
    elseif role == "HEALER" then
        return "|cff00CC12[H]|r"
    elseif role == "DAMAGER" then
        return "|cffFF3030[D]|r"
    end
end
oUF.Tags.Events["LFD"] = "PLAYER_ROLES_ASSIGNED GROUP_ROSTER_UPDATE"

oUF.Tags.Methods["AltPower"] = function(unit)
    local min = UnitPower(unit, ALTERNATE_POWER_INDEX)
    local max = UnitPowerMax(unit, ALTERNATE_POWER_INDEX)
    if max > 0 and not UnitIsDeadOrGhost(unit) then
        return ("%s%%"):format(math.floor(min / max * 100 + 0.5))
    end
end
oUF.Tags.Events["AltPower"] = "UNIT_POWER_UPDATE"
oUF.Tags.Methods["NameplateNameColor"] = function(unit)
    local reaction = UnitReaction(unit, "player")
    local threatStatus = UnitThreatSituation("player", unit)
    local c

    if UnitAffectingCombat("player") and UnitAffectingCombat(unit) then
        local npcID = unit.npcID
        if npcID == "120651" then
            c = C.nameplate.extraColor
            return FormatColor(c[1], c[2], c[3])
        elseif npcID == "174773" then
            if threatStatus == 3 then
                c = C.nameplate.extraColor
            else
                c = C.nameplate.goodColor
            end
            return FormatColor(c[1], c[2], c[3])
        end

        if C.nameplate.enhanceThreat then
            if threatStatus == 3 then
                if R.Role == "Tank" then
                    if C.nameplate.mobColorEnable and R.ColorPlate[npcID] then
                        c = R.ColorPlate[npcID]
                    else
                        c = C.nameplate.goodColor
                    end
                else
                    c = C.nameplate.badColor
                end
                return FormatColor(c[1], c[2], c[3])
            elseif threatStatus == 2 or threatStatus == 1 then
                c = C.nameplate.nearColor
                return FormatColor(c[1], c[2], c[3])
            elseif threatStatus == 0 then
                if R.Role == "Tank" then
                    if IsOffTankTanking(unit) then
                        c = C.nameplate.offtankColor
                    else
                        c = C.nameplate.badColor
                    end
                else
                    if C.nameplate.mobColorEnable and R.ColorPlate[npcID] then
                        c = R.ColorPlate[npcID]
                    else
                        c = C.nameplate.goodColor
                    end
                end
                return FormatColor(c[1], c[2], c[3])
            end
        end

        if reaction then
             c = R.oUF_colors.reaction[reaction]
             return FormatColor(c[1], c[2], c[3])
        end

    elseif not UnitIsUnit("player", unit) and UnitIsPlayer(unit) and (reaction and reaction >= 5) then
        if C.nameplate.onlyName then
            return TAGS and TAGS["raidcolor"] and TAGS["raidcolor"](unit)
        else
            c = R.oUF_colors.power["MANA"]
            return FormatColor(c[1], c[2], c[3])
        end
    elseif UnitIsPlayer(unit) then
        return TAGS and TAGS["raidcolor"] and TAGS["raidcolor"](unit)
    elseif UnitIsDeadOrGhost(unit) then
        return FormatColor(0.6, 0.6, 0.6)
    elseif reaction then
        c = R.oUF_colors.reaction[reaction]
        return FormatColor(c[1], c[2], c[3])
    end

    return FormatColor(0.33, 0.59, 0.33)
end
oUF.Tags.Events["NameplateNameColor"] =
    "UNIT_POWER_UPDATE UNIT_FLAGS UNIT_THREAT_SITUATION_UPDATE UNIT_THREAT_LIST_UPDATE"

oUF.Tags.Methods["NameplateHealth"] = function(unit)
    local hp = UnitHealth(unit)
    local maxhp = UnitHealthMax(unit)
    if maxhp == 0 then
        return 0
    else
        return math.floor(hp / maxhp * 100 + .5)
    end
end
oUF.Tags.Events["NameplateHealth"] = "UNIT_HEALTH UNIT_MAXHEALTH NAME_PLATE_UNIT_ADDED"

oUF.Tags.Methods["GroupHealthText"] = function(unit)
    if not UnitExists(unit) then return "" end
    if not UnitIsConnected(unit) then return L_UF_OFFLINE end
    if UnitIsDead(unit) then return L_UF_DEAD end
    if UnitIsGhost(unit) then return L_UF_GHOST end
    local hp = UnitHealth(unit)
    local maxhp = UnitHealthMax(unit)
    if maxhp and maxhp > 0 then
        return string.format("%d", math.floor(hp / maxhp * 100 + 0.5))
    end
    return ""
end
oUF.Tags.Events["GroupHealthText"] = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS PLAYER_ENTERING_WORLD"