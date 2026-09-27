----------------------------------------------------------------------------------------
-- Nameplates Component: Threat
-- Description: Threat role/color logic and threat display CVar management.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Colors = RefineUI.Colors

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local type = type
local pairs = pairs

local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer
local UnitCanAttack = UnitCanAttack
local UnitIsTapDenied = UnitIsTapDenied
local UnitSelectionColor = UnitSelectionColor
local UnitThreatSituation = UnitThreatSituation
local UnitThreatLeadSituation = UnitThreatLeadSituation
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetSpecialization = GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local C_CVar = C_CVar
local CVarCallbackRegistry = CVarCallbackRegistry
local Enum = Enum
local IsInInstance = IsInInstance
local UnitAffectingCombat = UnitAffectingCombat
local GetTime = GetTime
local C_NamePlate = C_NamePlate

local Private = Nameplates:GetPrivate()
local Util = Private.Util
local Runtime = Private.Runtime
local Constants = Private.Constants
local NameplateData = RefineUI.NameplateData

----------------------------------------------------------------------------------------
-- Config Helpers
----------------------------------------------------------------------------------------
function Nameplates:GetThreatConfig()
    return self:GetConfiguredNameplatesConfig().Threat
end

function Nameplates:GetThreatConfigColor(config, key, fallback)
    local color = config[key]
    if type(color) == "table" then
        return color
    end
    return fallback
end

----------------------------------------------------------------------------------------
-- Threat Role
----------------------------------------------------------------------------------------
function Nameplates:RefreshPlayerThreatRole()
    local role = UnitGroupRolesAssigned("player")
    if role == nil or role == "NONE" then
        local specIndex = GetSpecialization()
        if specIndex and specIndex > 0 then
            role = GetSpecializationRole(specIndex)
        end
    end

    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
        role = "DAMAGER"
    end

    Runtime.playerThreatRole = role
end

function Nameplates:IsPlayerTankRole()
    if Runtime.playerThreatRole == nil then
        self:RefreshPlayerThreatRole()
    end

    return Runtime.playerThreatRole == "TANK"
end

----------------------------------------------------------------------------------------
-- Threat Display CVar
----------------------------------------------------------------------------------------
local function IsThreatBitEnabled(index)
    if type(index) ~= "number" then
        return false
    end

    local currentValue = C_CVar.GetCVar(Constants.NAMEPLATE_THREAT_DISPLAY_CVAR)
    if type(currentValue) ~= "string" or currentValue == "" then
        return false
    end

    return CVarCallbackRegistry:GetCVarBitfieldIndex(Constants.NAMEPLATE_THREAT_DISPLAY_CVAR, index)
end

-- Progressive/Flash intentionally disabled; RefineUI uses Safe/Transition/Warning only.
function Nameplates:ApplyThreatDisplayCVarFromConfig()
    local threatDisplay = Enum.NamePlateThreatDisplay
    if not threatDisplay or not C_CVar.GetCVar(Constants.NAMEPLATE_THREAT_DISPLAY_CVAR) then
        return
    end

    local desiredHealthColor = self:GetThreatConfig().Enable ~= false
    if IsThreatBitEnabled(threatDisplay.Progressive) == false
        and IsThreatBitEnabled(threatDisplay.Flash) == false
        and IsThreatBitEnabled(threatDisplay.HealthBarColor) == desiredHealthColor then
        return
    end

    local mask = 0
    local healthColorBit = threatDisplay.HealthBarColor
    if desiredHealthColor and type(healthColorBit) == "number" and healthColorBit > 0 then
        mask = 2 ^ (healthColorBit - 1)
    end

    CVarCallbackRegistry:SetCVarBitfieldMask(Constants.NAMEPLATE_THREAT_DISPLAY_CVAR, mask)
    Runtime.threatHealthColorMirrored = nil
end

-- Runs on every health color update; the CVar bit is cached until CVAR_UPDATE
-- or ApplyThreatDisplayCVarFromConfig clears it.
function Nameplates:ShouldMirrorThreatHealthColor()
    if self:GetThreatConfig().Enable == false then
        return false
    end

    local mirrored = Runtime.threatHealthColorMirrored
    if mirrored == nil then
        local threatDisplay = Enum.NamePlateThreatDisplay
        mirrored = not threatDisplay or IsThreatBitEnabled(threatDisplay.HealthBarColor) == true
        Runtime.threatHealthColorMirrored = mirrored
    end
    return mirrored
end

----------------------------------------------------------------------------------------
-- Threat Colors
----------------------------------------------------------------------------------------
local function GetDefaultHealthColor(unit)
    local classPalette = Colors.Class
    local reactionPalette = Colors.Reaction

    if Util.ReadSafeBoolean(UnitIsTapDenied(unit)) == true then
        return 0.6, 0.6, 0.6
    end

    if Util.ReadSafeBoolean(UnitIsPlayer(unit)) == true then
        local _, class = UnitClass(unit)
        local classColor = class and classPalette[class]
        if classColor then
            return classColor.r, classColor.g, classColor.b
        end
    end

    local reaction = UnitReaction(unit, "player")
    if type(reaction) == "number" then
        local reactionColor = reactionPalette[reaction]
        if reactionColor then
            return reactionColor.r, reactionColor.g, reactionColor.b
        end
    end

    local r, g, b = UnitSelectionColor(unit, true)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return r, g, b
    end

    return 1, 0.25, 0.25
end

local function GetDefaultNameColor(unit)
    if Util.ReadSafeBoolean(UnitIsPlayer(unit)) == true then
        local _, class = UnitClass(unit)
        local classColor = class and Colors.Class[class]
        if classColor then
            return classColor.r, classColor.g, classColor.b
        end
        return 1, 1, 1
    end

    local reaction = UnitReaction(unit, "player")
    if type(reaction) == "number" then
        local reactionColor = Colors.Reaction[reaction]
        if reactionColor then
            return reactionColor.r, reactionColor.g, reactionColor.b
        end
    end

    return 1, 1, 1
end

function Nameplates:GetContextThreatStatus(unit, playerInCombat, inInstance)
    if not playerInCombat then
        return nil
    end

    if self:IsPlayerTankRole() then
        local leadStatus = UnitThreatLeadSituation("player", unit)
        if leadStatus == Constants.THREAT_LEAD_STATUS_NONE then
            return Constants.THREAT_STATUS_AGGRO
        end
        if leadStatus == Constants.THREAT_LEAD_STATUS_YELLOW then
            return Constants.THREAT_STATUS_TRANSITION_LOW
        end
        if leadStatus == Constants.THREAT_LEAD_STATUS_ORANGE then
            return Constants.THREAT_STATUS_TRANSITION_HIGH
        end
        if leadStatus == Constants.THREAT_LEAD_STATUS_RED then
            return Constants.THREAT_STATUS_LOW
        end
    end

    local playerStatus = UnitThreatSituation("player", unit)
    if type(playerStatus) == "number" then
        return playerStatus
    end

    return inInstance and Constants.THREAT_STATUS_LOW or nil
end

function Nameplates:ResolveThreatHealthColor(unit, data)
    if Util.ReadSafeBoolean(UnitIsPlayer(unit)) == true then
        return nil
    end

    if Util.ReadSafeBoolean(UnitCanAttack("player", unit)) ~= true then
        return nil
    end

    local threatConfig = self:GetThreatConfig()
    if not self:ShouldMirrorThreatHealthColor() then
        return nil
    end

    local inInstance = IsInInstance() == true
    if threatConfig.InstanceOnly == true and not inInstance then
        return nil
    end

    local unitInCombat = Util.ReadSafeBoolean(UnitAffectingCombat(unit))
    if unitInCombat == nil then
        unitInCombat = data.inCombat
    end
    unitInCombat = unitInCombat == true
    data.inCombat = unitInCombat

    if not unitInCombat then
        return nil
    end

    local playerInCombat = Util.ReadSafeBoolean(UnitAffectingCombat("player")) == true
    local threatStatus = self:GetContextThreatStatus(unit, playerInCombat, inInstance)
    if type(threatStatus) == "number" then
        data.LastThreatStatusAt = GetTime()
    elseif data.ThreatColorApplied == true then
        local lastThreatStatusAt = data.LastThreatStatusAt
        if type(lastThreatStatusAt) == "number" and (GetTime() - lastThreatStatusAt) <= 0.25 then
            threatStatus = Constants.THREAT_STATUS_TRANSITION_HIGH
        end
    end

    if type(threatStatus) ~= "number" then
        return nil
    end

    local isTank = self:IsPlayerTankRole()

    if threatStatus == Constants.THREAT_STATUS_AGGRO then
        return isTank
            and self:GetThreatConfigColor(threatConfig, "SafeColor", Constants.DEFAULT_THREAT_SAFE_COLOR)
            or self:GetThreatConfigColor(threatConfig, "WarningColor", Constants.DEFAULT_THREAT_WARNING_COLOR)
    end

    if threatStatus == Constants.THREAT_STATUS_TRANSITION_LOW or threatStatus == Constants.THREAT_STATUS_TRANSITION_HIGH then
        return self:GetThreatConfigColor(threatConfig, "TransitionColor", Constants.DEFAULT_THREAT_TRANSITION_COLOR)
    end

    if threatStatus == Constants.THREAT_STATUS_LOW then
        return isTank
            and self:GetThreatConfigColor(threatConfig, "WarningColor", Constants.DEFAULT_THREAT_WARNING_COLOR)
            or self:GetThreatConfigColor(threatConfig, "SafeColor", Constants.DEFAULT_THREAT_SAFE_COLOR)
    end

    return nil
end

function Nameplates:UpdateThreatColor(nameplate, unit)
    local unitFrame = nameplate.UnitFrame
    local data = unitFrame and NameplateData[unitFrame]
    if not data or not data.RefineName or not Util.IsUsableUnitToken(unit) then
        return
    end

    local health = unitFrame.healthBar or unitFrame.HealthBar
    if data.RefineHidden == true then
        health = nil
    end

    local threatColor = self:ResolveThreatHealthColor(unit, data)
    if threatColor then
        local r = threatColor[1] or 1
        local g = threatColor[2] or 1
        local b = threatColor[3] or 1

        if health then
            self:SetBarColorIfChanged(health, r, g, b)
        end
        self:SetNameColorIfChanged(data, r, g, b)
        data.ThreatColorApplied = true
        return
    end

    if health then
        self:SetBarColorIfChanged(health, GetDefaultHealthColor(unit))
    end

    self:SetNameColorIfChanged(data, GetDefaultNameColor(unit))
    data.ThreatColorApplied = false
end

----------------------------------------------------------------------------------------
-- Refresh API
----------------------------------------------------------------------------------------
-- Blizzard's color pass runs first; the UpdateHealthColor hook then applies RefineUI colors.
function Nameplates:RefreshAllThreatColors()
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unitFrame = nameplate.UnitFrame
        if unitFrame and Util.ResolveUnitToken(unitFrame.unit) then
            CompactUnitFrame_UpdateHealthColor(unitFrame)
        end
    end
end

function Nameplates:HandleThreatRoleEvent(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
        return
    end

    self:RefreshPlayerThreatRole()
end

----------------------------------------------------------------------------------------
-- Public API (Compatibility)
----------------------------------------------------------------------------------------
function RefineUI:RefreshNameplateThreatColors()
    Nameplates:ApplyThreatDisplayCVarFromConfig()
    Nameplates:RefreshAllThreatColors()
end

function RefineUI:ApplyNameplateThreatDisplaySettings()
    RefineUI:RefreshNameplateThreatColors()
end
