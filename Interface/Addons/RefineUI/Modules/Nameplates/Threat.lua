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
local _G = _G
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

----------------------------------------------------------------------------------------
-- Config Helpers
----------------------------------------------------------------------------------------
function Nameplates:GetThreatConfig()
    local nameplatesConfig = self:GetConfiguredNameplatesConfig()
    if not nameplatesConfig then
        return nil
    end

    local threatConfig = nameplatesConfig.Threat
    if type(threatConfig) ~= "table" then
        threatConfig = {}
        nameplatesConfig.Threat = threatConfig
    end

    if threatConfig.Enable == nil then
        threatConfig.Enable = true
    end
    if threatConfig.InstanceOnly == nil then
        threatConfig.InstanceOnly = false
    end

    return threatConfig
end

function Nameplates:GetThreatConfigColor(config, key, fallback)
    local color = config and config[key]
    if type(color) == "table" then
        return color
    end
    return fallback
end

----------------------------------------------------------------------------------------
-- Threat Role
----------------------------------------------------------------------------------------
function Nameplates:RefreshPlayerThreatRole()
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    if not runtime then
        return
    end

    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if role == nil or role == "NONE" then
        local specIndex = GetSpecialization and GetSpecialization()
        if specIndex and specIndex > 0 and GetSpecializationRole then
            role = GetSpecializationRole(specIndex)
        end
    end

    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
        role = "DAMAGER"
    end

    runtime.playerThreatRole = role
end

function Nameplates:IsPlayerTankRole()
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    if not runtime then
        return false
    end

    if runtime.playerThreatRole == nil then
        self:RefreshPlayerThreatRole()
    end

    return runtime.playerThreatRole == "TANK"
end

----------------------------------------------------------------------------------------
-- Threat Display CVar
----------------------------------------------------------------------------------------
local function IsThreatBitEnabled(index)
    local private = Nameplates:GetPrivate()
    local constants = private and private.Constants
    if not constants or type(index) ~= "number" then
        return false
    end

    if not C_CVar or type(C_CVar.GetCVar) ~= "function" then
        return false
    end

    local currentValue = C_CVar.GetCVar(constants.NAMEPLATE_THREAT_DISPLAY_CVAR)
    if type(currentValue) ~= "string" or currentValue == "" then
        return false
    end

    if not CVarCallbackRegistry or type(CVarCallbackRegistry.GetCVarBitfieldIndex) ~= "function" then
        return false
    end

    return CVarCallbackRegistry:GetCVarBitfieldIndex(constants.NAMEPLATE_THREAT_DISPLAY_CVAR, index)
end

local function BuildThreatDisplayMask(threatConfig)
    local threatDisplay = Enum and Enum.NamePlateThreatDisplay
    if not threatDisplay then
        return nil
    end

    local enableHealthColor = threatConfig == nil or threatConfig.Enable ~= false
    local mask = 0

    local function AddMaskBit(bitIndex, enabled)
        if enabled and type(bitIndex) == "number" and bitIndex > 0 then
            mask = mask + (2 ^ (bitIndex - 1))
        end
    end

    -- Progressive/Flash intentionally disabled; RefineUI uses Safe/Transition/Warning only.
    AddMaskBit(threatDisplay.Progressive, false)
    AddMaskBit(threatDisplay.Flash, false)
    AddMaskBit(threatDisplay.HealthBarColor, enableHealthColor)

    return mask
end

function Nameplates:ApplyThreatDisplayCVarFromConfig()
    local private = self:GetPrivate()
    local constants = private and private.Constants
    if not constants then
        return
    end

    if not C_CVar or type(C_CVar.GetCVar) ~= "function" then
        return
    end
    if not C_CVar.GetCVar(constants.NAMEPLATE_THREAT_DISPLAY_CVAR) then
        return
    end
    if not CVarCallbackRegistry or type(CVarCallbackRegistry.SetCVarBitfieldMask) ~= "function" then
        return
    end

    local threatDisplay = Enum and Enum.NamePlateThreatDisplay
    if not threatDisplay then
        return
    end

    local threatConfig = self:GetThreatConfig()
    local desiredMask = BuildThreatDisplayMask(threatConfig)
    if type(desiredMask) ~= "number" then
        return
    end

    local desiredProgressive = false
    local desiredFlash = false
    local desiredHealthColor = threatConfig == nil or threatConfig.Enable ~= false

    local currentProgressive = IsThreatBitEnabled(threatDisplay.Progressive)
    local currentFlash = IsThreatBitEnabled(threatDisplay.Flash)
    local currentHealthColor = IsThreatBitEnabled(threatDisplay.HealthBarColor)

    if currentProgressive == desiredProgressive and currentFlash == desiredFlash and currentHealthColor == desiredHealthColor then
        return
    end

    CVarCallbackRegistry:SetCVarBitfieldMask(constants.NAMEPLATE_THREAT_DISPLAY_CVAR, desiredMask)
end

function Nameplates:ShouldMirrorThreatHealthColor()
    local threatConfig = self:GetThreatConfig()
    if threatConfig and threatConfig.Enable == false then
        return false
    end

    local threatDisplay = Enum and Enum.NamePlateThreatDisplay
    if not threatDisplay then
        return true
    end

    if not CVarCallbackRegistry or type(CVarCallbackRegistry.GetCVarBitfieldIndex) ~= "function" then
        return true
    end

    return IsThreatBitEnabled(threatDisplay.HealthBarColor)
end

----------------------------------------------------------------------------------------
-- Threat Colors
----------------------------------------------------------------------------------------
local function GetDefaultHealthColor(unit)
    local private = Nameplates:GetPrivate()
    local util = private and private.Util
    if not util or not util.IsUsableUnitToken(unit) then
        return 1, 1, 1
    end

    local palette = Colors or {}
    local classPalette = palette.Class or {}
    local reactionPalette = palette.Reaction or {}

    if util.ReadSafeBoolean(UnitIsTapDenied(unit)) == true then
        return 0.6, 0.6, 0.6
    end

    if util.ReadSafeBoolean(UnitIsPlayer(unit)) == true then
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

    if UnitSelectionColor then
        local r, g, b = UnitSelectionColor(unit, true)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    return 1, 0.25, 0.25
end

local function GetDefaultNameColor(unit)
    local private = Nameplates:GetPrivate()
    local util = private and private.Util
    if not util or not util.IsUsableUnitToken(unit) then
        return 1, 1, 1
    end

    local palette = Colors or {}
    local classPalette = palette.Class or {}
    local reactionPalette = palette.Reaction or {}

    if util.ReadSafeBoolean(UnitIsPlayer(unit)) == true then
        local _, class = UnitClass(unit)
        local classColor = class and classPalette[class]
        if classColor then
            return classColor.r, classColor.g, classColor.b
        end
        return 1, 1, 1
    end

    local reaction = UnitReaction(unit, "player")
    if type(reaction) == "number" then
        local reactionColor = reactionPalette[reaction]
        if reactionColor then
            return reactionColor.r, reactionColor.g, reactionColor.b
        end
    end

    return 1, 1, 1
end

function Nameplates:GetContextThreatStatus(unit, playerInCombat)
    local private = self:GetPrivate()
    local constants = private and private.Constants
    if not constants then
        return nil
    end

    if not UnitThreatSituation then
        return nil
    end

    if not playerInCombat then
        return nil
    end

    local inInstance = false
    if IsInInstance then
        inInstance = IsInInstance() == true
    end

    if self:IsPlayerTankRole() and UnitThreatLeadSituation then
        local leadStatus = UnitThreatLeadSituation("player", unit)
        if type(leadStatus) == "number" then
            if leadStatus == constants.THREAT_LEAD_STATUS_NONE then
                return constants.THREAT_STATUS_AGGRO
            end
            if leadStatus == constants.THREAT_LEAD_STATUS_YELLOW then
                return constants.THREAT_STATUS_TRANSITION_LOW
            end
            if leadStatus == constants.THREAT_LEAD_STATUS_ORANGE then
                return constants.THREAT_STATUS_TRANSITION_HIGH
            end
            if leadStatus == constants.THREAT_LEAD_STATUS_RED then
                return constants.THREAT_STATUS_LOW
            end
        end
    end

    local playerStatus = UnitThreatSituation("player", unit)
    if inInstance then
        if type(playerStatus) == "number" then
            return playerStatus
        end
        return constants.THREAT_STATUS_LOW
    end

    if type(playerStatus) == "number" then
        return playerStatus
    end

    return nil
end

function Nameplates:ResolveThreatHealthColor(unit, data)
    local private = self:GetPrivate()
    local constants = private and private.Constants
    local util = private and private.Util
    if not constants or not util then
        return nil
    end

    if not util.IsUsableUnitToken(unit) then
        return nil
    end

    if util.ReadSafeBoolean(UnitIsPlayer(unit)) == true then
        return nil
    end

    if util.ReadSafeBoolean(UnitCanAttack("player", unit)) ~= true then
        return nil
    end

    local threatConfig = self:GetThreatConfig()
    if threatConfig and threatConfig.Enable == false then
        return nil
    end

    if threatConfig and threatConfig.InstanceOnly == true then
        local inInstance = false
        if IsInInstance then
            inInstance = IsInInstance() == true
        end
        if not inInstance then
            return nil
        end
    end

    if not self:ShouldMirrorThreatHealthColor() then
        return nil
    end

    local playerInCombat = util.ReadSafeBoolean(UnitAffectingCombat("player")) == true

    local unitInCombat = util.ReadSafeBoolean(UnitAffectingCombat(unit))
    if unitInCombat == nil and data then
        unitInCombat = data.inCombat
    end
    unitInCombat = unitInCombat == true
    if data then
        data.inCombat = unitInCombat
    end

    if not unitInCombat then
        return nil
    end

    local threatStatus = self:GetContextThreatStatus(unit, playerInCombat)
    if type(threatStatus) == "number" and data and GetTime then
        data.LastThreatStatusAt = GetTime()
    end

    if type(threatStatus) ~= "number" and data and data.ThreatColorApplied == true and GetTime then
        local lastThreatStatusAt = data.LastThreatStatusAt
        if type(lastThreatStatusAt) == "number" and (GetTime() - lastThreatStatusAt) <= 0.25 then
            threatStatus = constants.THREAT_STATUS_TRANSITION_HIGH
        end
    end

    if type(threatStatus) ~= "number" then
        return nil
    end

    local safeColor = self:GetThreatConfigColor(threatConfig, "SafeColor", constants.DEFAULT_THREAT_SAFE_COLOR)
    local transitionColor = self:GetThreatConfigColor(threatConfig, "TransitionColor", constants.DEFAULT_THREAT_TRANSITION_COLOR)
    local warningColor = self:GetThreatConfigColor(threatConfig, "WarningColor", constants.DEFAULT_THREAT_WARNING_COLOR)
    local isTank = self:IsPlayerTankRole()

    if threatStatus == constants.THREAT_STATUS_AGGRO then
        return isTank and safeColor or warningColor
    end

    if threatStatus == constants.THREAT_STATUS_TRANSITION_LOW or threatStatus == constants.THREAT_STATUS_TRANSITION_HIGH then
        return transitionColor
    end

    if threatStatus == constants.THREAT_STATUS_LOW then
        return isTank and warningColor or safeColor
    end

    return nil
end

function Nameplates:UpdateThreatColor(nameplate, unit, _forced)
    local private = self:GetPrivate()
    local util = private and private.Util
    if not nameplate or not util or not util.IsUsableUnitToken(unit) then
        return
    end

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local health = unitFrame.healthBar or unitFrame.HealthBar
    local data = RefineUI.NameplateData[unitFrame]
    if not data or not data.RefineName then
        return
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
        local hr, hg, hb = GetDefaultHealthColor(unit)
        self:SetBarColorIfChanged(health, hr, hg, hb)
    end

    local nr, ng, nb = GetDefaultNameColor(unit)
    self:SetNameColorIfChanged(data, nr, ng, nb)
    data.ThreatColorApplied = false
end

----------------------------------------------------------------------------------------
-- Refresh API
----------------------------------------------------------------------------------------
function Nameplates:RequestBlizzardHealthColorUpdate(unitFrame, fallbackNameplate, fallbackUnit)
    local updateHealthColor = _G.CompactUnitFrame_UpdateHealthColor
    if unitFrame and type(updateHealthColor) == "function" then
        updateHealthColor(unitFrame)
        return
    end

    if fallbackNameplate and fallbackUnit then
        self:UpdateThreatColor(fallbackNameplate, fallbackUnit, true)
    end
end

function Nameplates:RefreshAllThreatColors(_forced)
    local private = self:GetPrivate()
    local activeNameplates = private and private.ActiveNameplates or {}
    local util = private and private.Util

    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            local unitFrame = nameplate and nameplate.UnitFrame
            local unit = unitFrame and util and util.ResolveUnitToken(unitFrame.unit)
            if unit then
                self:RequestBlizzardHealthColorUpdate(unitFrame, nameplate, unit)
            end
        end
        return
    end

    for nameplate, unit in pairs(activeNameplates) do
        local unitFrame = nameplate and nameplate.UnitFrame
        local resolvedUnit = util and util.ResolveUnitToken(unit, unitFrame and unitFrame.unit)
        if resolvedUnit then
            self:RequestBlizzardHealthColorUpdate(unitFrame, nameplate, resolvedUnit)
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
function RefineUI:RefreshNameplateThreatColors(forced)
    Nameplates:ApplyThreatDisplayCVarFromConfig()
    Nameplates:RefreshAllThreatColors(forced == true)
end

function RefineUI:ApplyNameplateThreatDisplaySettings()
    RefineUI:RefreshNameplateThreatColors(true)
end
