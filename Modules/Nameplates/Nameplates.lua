----------------------------------------------------------------------------------------
-- Nameplates for RefineUI
-- Description: Custom styles for default Blizzard nameplates
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:RegisterModule("Nameplates")
local C = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local pairs, ipairs, unpack, select = pairs, ipairs, unpack, select
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local strfind = string.find
local strmatch = string.match
local strgsub = string.gsub
local strsub = string.sub
local type, tostring, tonumber = type, tostring, tonumber
local wipe = table.wipe

----------------------------------------------------------------------------------------
-- WoW Globals
-- Cache at file scope per DESIGN.md for performance
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UnitHealthPercent = UnitHealthPercent
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer
local UnitIsFriend = UnitIsFriend
local UnitCanAttack = UnitCanAttack
local UnitIsTapDenied = UnitIsTapDenied
local UnitSelectionColor = UnitSelectionColor
local UnitThreatSituation = UnitThreatSituation
local UnitThreatLeadSituation = UnitThreatLeadSituation
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetSpecialization = GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local C_NamePlate = C_NamePlate
local C_NamePlateManager = C_NamePlateManager
local C_CVar = C_CVar
local CVarCallbackRegistry = CVarCallbackRegistry
local Enum = Enum
local ReloadUI = ReloadUI
local CurveConstants = CurveConstants
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitCastingDuration = UnitCastingDuration
local UnitGUID = UnitGUID
local unpack = unpack
local GetCVar = GetCVar
local SetCVar = SetCVar
local IsInInstance = IsInInstance
local UnitInBattleground = UnitInBattleground
local UnitAffectingCombat = UnitAffectingCombat
local GetTime = GetTime
local C_TooltipInfo = C_TooltipInfo
local TOOLTIP_UNIT_LEVEL = TOOLTIP_UNIT_LEVEL
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local activeNameplates = {}
RefineUI.ActiveNameplates = activeNameplates

local M = RefineUI.Media.Textures
local TEX_BAR = M.HealthBar
local TEX_PORTRAIT_BORDER = M.PortraitBorder
local TEX_PORTRAIT_BG = M.PortraitBG
local TEX_MASK = M.PortraitMask

local NAMEPLATE_STATE_REGISTRY = "NameplatesState"
local NameplatesUtil = RefineUI.NameplatesUtil
local IsSecret = NameplatesUtil.IsSecret
local IsAccessibleValue = NameplatesUtil.IsAccessibleValue
local ReadSafeBoolean = NameplatesUtil.ReadSafeBoolean
local IsUsableUnitToken = NameplatesUtil.IsUsableUnitToken
local IsDisallowedNameplateUnitToken = NameplatesUtil.IsDisallowedNameplateUnitToken
local ResolveUnitToken = NameplatesUtil.ResolveUnitToken
local SafeUnitIsUnit = NameplatesUtil.SafeUnitIsUnit
local SafeTableIndex = NameplatesUtil.SafeTableIndex
local BuildHookKey = NameplatesUtil.BuildHookKey
local BuildNameplateHookKey = function(owner, method)
    return BuildHookKey("Nameplates", owner, method)
end

local NAMEPLATE_THREAT_DISPLAY_CVAR = "nameplateThreatDisplay"
local THREAT_STATUS_LOW = 0
local THREAT_STATUS_TRANSITION_LOW = 1
local THREAT_STATUS_TRANSITION_HIGH = 2
local THREAT_STATUS_AGGRO = 3
local THREAT_LEAD_STATUS_NONE = 0
local THREAT_LEAD_STATUS_YELLOW = 1
local THREAT_LEAD_STATUS_ORANGE = 2
local THREAT_LEAD_STATUS_RED = 3
local DEFAULT_THREAT_SAFE_COLOR = { 0.2, 0.8, 0.2 }
local DEFAULT_THREAT_TRANSITION_COLOR = { 1, 1, 0 }
local DEFAULT_THREAT_WARNING_COLOR = { 1, 0, 0 }
local NPC_TITLE_FONT_SIZE = 9
local NPC_TITLE_COLOR = { .9, 0.9, .9 }
local NPC_TITLE_RETRY_DELAY_SECONDS = 0.2
local NPC_TITLE_TIMER_KEY_PREFIX = "Nameplates:NPCTitleRetry:"
local TOOLTIP_LINE_TYPE_UNIT_NAME = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.UnitName) or 2
local NAMEPLATE_NAME_FONT_BASE_SIZE = 12
local NAMEPLATE_HEALTH_FONT_BASE_SIZE = 18
local NAMEPLATE_TEXT_SCALE_MIN = 0.5
local NAMEPLATE_TEXT_SCALE_MAX = 2.0

local npcTitleCacheByGUID = {}
local unitLevelPattern = nil

local playerThreatRole = nil
local nameplateSizeHooksRegistered = {
    base = false,
    unit = false,
    anchors = false,
}
local pendingNameplateSizeApply = false
local lastAppliedNameplateWidth = nil
local lastAppliedNameplateHeight = nil

local function GetNameplateState(owner, key, defaultValue)
    return RefineUI:RegistryGet(NAMEPLATE_STATE_REGISTRY, owner, key, defaultValue)
end

local function SetNameplateState(owner, key, value)
    if value == nil then
        RefineUI:RegistryClear(NAMEPLATE_STATE_REGISTRY, owner, key)
    else
        RefineUI:RegistrySet(NAMEPLATE_STATE_REGISTRY, owner, key, value)
    end
end

local function SafeGetNamePlateForUnit(unit, includeForbidden)
    if IsDisallowedNameplateUnitToken(unit) then
        return nil
    end

    local ok, nameplate
    if includeForbidden == nil then
        ok, nameplate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    else
        ok, nameplate = pcall(C_NamePlate.GetNamePlateForUnit, unit, includeForbidden)
    end

    if not ok then
        return nil
    end

    return nameplate
end

local function GetConfiguredNameplateSize()
    local width = 150
    local height = 20
    local size = C and C.Nameplates and C.Nameplates.Size
    if type(size) == "table" then
        width = tonumber(size[1]) or width
        height = tonumber(size[2]) or height
    end

    width = max(120, min(320, width))
    height = max(10, min(48, height))
    return RefineUI:Scale(width), RefineUI:Scale(height)
end

local function GetConfiguredNameplateFrameSize()
    local scaledWidth, scaledHeight = GetConfiguredNameplateSize()
    local sideInset = RefineUI:Scale(12)
    return scaledWidth + (sideInset * 2), scaledHeight
end

local function ApplyConfiguredBlizzardNameplateSize(forceApply)
    if not C_NamePlate or type(C_NamePlate.SetNamePlateSize) ~= "function" then
        return false
    end

    local targetWidth, targetHeight = GetConfiguredNameplateFrameSize()
    if not forceApply then
        local isCachedMatch = lastAppliedNameplateWidth == targetWidth and lastAppliedNameplateHeight == targetHeight
        if isCachedMatch and type(C_NamePlate.GetNamePlateSize) == "function" then
            local ok, currentWidth, currentHeight = pcall(C_NamePlate.GetNamePlateSize)
            if ok and type(currentWidth) == "number" and type(currentHeight) == "number" then
                isCachedMatch = abs(currentWidth - targetWidth) <= 0.5 and abs(currentHeight - targetHeight) <= 0.5
            end
        end
        if isCachedMatch then
            return true
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        pendingNameplateSizeApply = true
        return false
    end

    local ok = pcall(C_NamePlate.SetNamePlateSize, targetWidth, targetHeight)
    if not ok then
        pendingNameplateSizeApply = true
        return false
    end

    lastAppliedNameplateWidth = targetWidth
    lastAppliedNameplateHeight = targetHeight
    pendingNameplateSizeApply = false
    return true
end

local function ClampNameplateTextScale(value, fallback)
    local scale = tonumber(value)
    if not scale then
        scale = fallback
    end
    if scale < NAMEPLATE_TEXT_SCALE_MIN then
        return NAMEPLATE_TEXT_SCALE_MIN
    end
    if scale > NAMEPLATE_TEXT_SCALE_MAX then
        return NAMEPLATE_TEXT_SCALE_MAX
    end
    return scale
end

local function GetConfiguredUnitNameScale()
    local cfg = C and C.Nameplates
    return ClampNameplateTextScale(cfg and cfg.UnitNameScale, 1)
end

local function GetConfiguredHealthTextScale()
    local cfg = C and C.Nameplates
    return ClampNameplateTextScale(cfg and cfg.HealthTextScale, 1)
end

local function GetScaledNameplateNameFontSize()
    return max(1, floor((NAMEPLATE_NAME_FONT_BASE_SIZE * GetConfiguredUnitNameScale()) + 0.5))
end

local function GetScaledNameplateHealthFontSize()
    return max(1, floor((NAMEPLATE_HEALTH_FONT_BASE_SIZE * GetConfiguredHealthTextScale()) + 0.5))
end

local function ApplyConfiguredNameplateHeight(unitFrame)
    if not unitFrame then
        return
    end

    local _, scaledHeight = GetConfiguredNameplateSize()

    local healthContainer = unitFrame.HealthBarsContainer
    if healthContainer and healthContainer.SetHeight then
        healthContainer:SetHeight(scaledHeight)
    end

    local health = unitFrame.healthBar or unitFrame.HealthBar
    if health and health.SetHeight then
        health:SetHeight(scaledHeight)
    end
end

local function ApplyConfiguredNameplateSize(unitFrame, _nameplate)
    if not unitFrame then
        return
    end

    local outerWidth = GetConfiguredNameplateFrameSize()
    ApplyConfiguredBlizzardNameplateSize(false)

    if unitFrame.SetWidth then
        -- Parent NamePlate:SetWidth() is protected in Blizzard secure ApplyFrameOptions flow.
        unitFrame:SetWidth(outerWidth)
    end

    ApplyConfiguredNameplateHeight(unitFrame)
end

local function EnsureConfiguredNameplateSizeHooks()
    if not nameplateSizeHooksRegistered.base and _G.NamePlateBaseMixin and _G.NamePlateBaseMixin.ApplyFrameOptions then
        local ok = RefineUI:HookOnce(
            "Nameplates:NamePlateBaseMixin:ApplyFrameOptions:ConfiguredSize",
            _G.NamePlateBaseMixin,
            "ApplyFrameOptions",
            function(nameplateFrame)
                local unitFrame = nameplateFrame and nameplateFrame.UnitFrame
                if unitFrame then
                    ApplyConfiguredNameplateSize(unitFrame, nameplateFrame)
                end
            end
        )
        nameplateSizeHooksRegistered.base = ok == true
    end

    if not nameplateSizeHooksRegistered.unit and _G.NamePlateUnitFrameMixin and _G.NamePlateUnitFrameMixin.ApplyFrameOptions then
        local ok = RefineUI:HookOnce(
            "Nameplates:NamePlateUnitFrameMixin:ApplyFrameOptions:ConfiguredSize",
            _G.NamePlateUnitFrameMixin,
            "ApplyFrameOptions",
            function(unitFrame)
                if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
                    return
                end

                local nameplate = unitFrame:GetParent()
                if nameplate and nameplate.UnitFrame == unitFrame then
                    ApplyConfiguredNameplateSize(unitFrame, nameplate)
                end
            end
        )
        nameplateSizeHooksRegistered.unit = ok == true
    end

    if not nameplateSizeHooksRegistered.anchors and _G.NamePlateUnitFrameMixin and _G.NamePlateUnitFrameMixin.UpdateAnchors then
        local ok = RefineUI:HookOnce(
            "Nameplates:NamePlateUnitFrameMixin:UpdateAnchors:ConfiguredSize",
            _G.NamePlateUnitFrameMixin,
            "UpdateAnchors",
            function(unitFrame)
                if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
                    return
                end
                ApplyConfiguredNameplateHeight(unitFrame)
            end
        )
        nameplateSizeHooksRegistered.anchors = ok == true
    end
end

local function SetNameColorIfChanged(data, r, g, b)
    if not data or not data.RefineName then
        return
    end

    if data.NameColorR == r and data.NameColorG == g and data.NameColorB == b then
        return
    end

    data.RefineName:SetTextColor(r, g, b)
    data.NameColorR = r
    data.NameColorG = g
    data.NameColorB = b
end

local function SetBarColorIfChanged(statusbar, r, g, b)
    if not statusbar or not statusbar.GetStatusBarColor or not statusbar.SetStatusBarColor then
        return
    end

    local cr, cg, cb = statusbar:GetStatusBarColor()
    if cr ~= r or cg ~= g or cb ~= b then
        statusbar:SetStatusBarColor(r, g, b)
    end
end

local function IsNpcTitleFeatureEnabled()
    return C and C.Nameplates and C.Nameplates.ShowNPCTitles ~= false
end

local function BuildNpcTitleTimerKey(unitFrame)
    return NPC_TITLE_TIMER_KEY_PREFIX .. tostring(unitFrame)
end

local function CancelNpcTitleRetry(unitFrame)
    if not unitFrame then
        return
    end
    RefineUI:CancelTimer(BuildNpcTitleTimerKey(unitFrame))
end

local function TrimTooltipLineText(text)
    if IsSecret(text) or type(text) ~= "string" or not IsAccessibleValue(text) then
        return nil
    end

    local trimmed = strmatch(text, "^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end

    return trimmed
end

local function NormalizeNpcTitleText(text)
    local normalized = TrimTooltipLineText(text)
    if not normalized then
        return nil
    end

    if strsub(normalized, 1, 1) == "<" and strsub(normalized, -1) == ">" then
        normalized = TrimTooltipLineText(strsub(normalized, 2, -2))
    end

    if normalized == "" then
        return nil
    end

    return normalized
end

local function IsEligibleNpcTitleUnit(unit, data)
    if not IsUsableUnitToken(unit) then
        return false
    end

    local isPlayerUnit = nil
    if data and data.isPlayer ~= nil then
        isPlayerUnit = data.isPlayer == true
    else
        isPlayerUnit = ReadSafeBoolean(UnitIsPlayer(unit)) == true
    end

    if isPlayerUnit then
        return false
    end

    return ReadSafeBoolean(UnitIsFriend("player", unit)) == true
end

local function EnsureNpcTitleFontString(unitFrame, data)
    if not unitFrame or not data or not data.RefineName then
        return nil
    end

    if not data.RefineNpcTitle then
        data.RefineNpcTitle = unitFrame:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.RefineNpcTitle, NPC_TITLE_FONT_SIZE, nil, "OUTLINE")
        data.RefineNpcTitle:SetTextColor(NPC_TITLE_COLOR[1], NPC_TITLE_COLOR[2], NPC_TITLE_COLOR[3])
        data.RefineNpcTitle:SetJustifyH("CENTER")
        data.RefineNpcTitle:SetJustifyV("MIDDLE")
        data.RefineNpcTitle:Hide()
    end

    if data.RefineNpcTitleAnchor ~= data.RefineName then
        data.RefineNpcTitle:ClearAllPoints()
        RefineUI.Point(data.RefineNpcTitle, "TOP", data.RefineName, "BOTTOM", 0, -1)
        data.RefineNpcTitleAnchor = data.RefineName
    end

    return data.RefineNpcTitle
end

local function SetNpcTitleText(data, title)
    if not data or not data.RefineNpcTitle then
        return
    end

    if IsSecret(title) or type(title) ~= "string" or not IsAccessibleValue(title) then
        title = nil
    end

    if title then
        local formattedTitle = "<" .. title .. ">"
        if data.RefineNpcTitleFormatted ~= formattedTitle then
            data.RefineNpcTitle:SetText(formattedTitle)
            data.RefineNpcTitleFormatted = formattedTitle
        end
        data.RefineNpcTitle:Show()
        return
    end

    if data.RefineNpcTitleFormatted ~= "" then
        data.RefineNpcTitle:SetText("")
        data.RefineNpcTitleFormatted = ""
    end
    data.RefineNpcTitle:Hide()
end

local function BuildUnitLevelPattern()
    if unitLevelPattern ~= nil then
        return unitLevelPattern
    end

    if IsSecret(TOOLTIP_UNIT_LEVEL) or type(TOOLTIP_UNIT_LEVEL) ~= "string" or not IsAccessibleValue(TOOLTIP_UNIT_LEVEL) then
        return nil
    end

    local escaped = strgsub(TOOLTIP_UNIT_LEVEL, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    escaped = strgsub(escaped, "%%%%s", ".+")
    escaped = strgsub(escaped, "%%%%d", "%%d+")
    unitLevelPattern = "^" .. escaped
    return unitLevelPattern
end

local function IsTooltipLevelLine(text)
    local pattern = BuildUnitLevelPattern()
    if not pattern or not text then
        return false
    end

    return strfind(text, pattern) ~= nil
end

local function GetTooltipLineText(line)
    if not line or not IsAccessibleValue(line) then
        return nil
    end

    local leftText = SafeTableIndex(line, "leftText")
    local normalizedLeftText = TrimTooltipLineText(leftText)
    if normalizedLeftText then
        return normalizedLeftText
    end

    local text = SafeTableIndex(line, "text")
    return TrimTooltipLineText(text)
end

local function ExtractNpcTitleFromTooltipData(tooltipData)
    if not tooltipData or not IsAccessibleValue(tooltipData) then
        return nil
    end

    local lines = SafeTableIndex(tooltipData, "lines")
    if type(lines) ~= "table" or IsSecret(lines) or not IsAccessibleValue(lines) then
        return nil
    end

    local nameLineIndex = nil
    for i, line in ipairs(lines) do
        if SafeTableIndex(line, "type") == TOOLTIP_LINE_TYPE_UNIT_NAME then
            nameLineIndex = i
            break
        end
    end

    if not nameLineIndex then
        return nil
    end

    local candidate = nil
    for i = nameLineIndex + 1, #lines do
        local line = lines[i]
        local text = GetTooltipLineText(line)
        if text then
            if IsTooltipLevelLine(text) then
                return NormalizeNpcTitleText(candidate)
            end
            candidate = text
        end
    end

    return nil
end

local function ResolveNpcTitle(unit)
    if not IsUsableUnitToken(unit) then
        return nil, true
    end
    if not C_TooltipInfo or type(C_TooltipInfo.GetUnit) ~= "function" then
        return nil, true
    end

    local cacheGUID = nil
    local guid = UnitGUID(unit)
    if type(guid) == "string" and guid ~= "" and not IsSecret(guid) and IsAccessibleValue(guid) then
        cacheGUID = guid
        local cachedTitle = npcTitleCacheByGUID[cacheGUID]
        if cachedTitle ~= nil then
            if cachedTitle == false then
                return nil, true
            end
            return cachedTitle, true
        end
    end

    local ok, tooltipData = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok then
        return nil, true
    end
    if tooltipData == nil then
        return nil, false
    end

    local title = ExtractNpcTitleFromTooltipData(tooltipData)
    if cacheGUID then
        npcTitleCacheByGUID[cacheGUID] = title or false
    end

    return title, true
end

local function ApplyNpcTitleVisual(nameplate, unit, opts)
    if not nameplate then
        return
    end

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local data = RefineUI.NameplateData[unitFrame]
    if not data then
        data = {}
        RefineUI.NameplateData[unitFrame] = data
    end

    if not IsNpcTitleFeatureEnabled() then
        CancelNpcTitleRetry(unitFrame)
        if data.RefineNpcTitle then
            SetNpcTitleText(data, nil)
        end
        return
    end

    local resolvedUnit = ResolveUnitToken(unit, unitFrame.unit)
    if not resolvedUnit or not IsEligibleNpcTitleUnit(resolvedUnit, data) then
        CancelNpcTitleRetry(unitFrame)
        if data.RefineNpcTitle then
            SetNpcTitleText(data, nil)
        end
        return
    end

    if not EnsureNpcTitleFontString(unitFrame, data) then
        return
    end

    local guid = UnitGUID(resolvedUnit)
    local cacheGUID = nil
    if type(guid) == "string" and guid ~= "" and not IsSecret(guid) and IsAccessibleValue(guid) then
        cacheGUID = guid
    end

    if cacheGUID then
        local cachedTitle = npcTitleCacheByGUID[cacheGUID]
        if cachedTitle ~= nil then
            CancelNpcTitleRetry(unitFrame)
            SetNpcTitleText(data, cachedTitle ~= false and cachedTitle or nil)
            return
        end
    end

    opts = opts or {}
    if opts.allowResolve ~= true then
        SetNpcTitleText(data, nil)
        return
    end

    local resolvedTitle, isResolved = ResolveNpcTitle(resolvedUnit)
    if isResolved then
        CancelNpcTitleRetry(unitFrame)
        SetNpcTitleText(data, resolvedTitle)
        return
    end

    SetNpcTitleText(data, nil)

    if opts.fromRetry == true then
        return
    end

    local expectedGUID = cacheGUID
    local retryKey = BuildNpcTitleTimerKey(unitFrame)
    RefineUI:After(retryKey, NPC_TITLE_RETRY_DELAY_SECONDS, function()
        if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
            return
        end

        local retryNameplate = unitFrame:GetParent()
        if not retryNameplate or retryNameplate.UnitFrame ~= unitFrame then
            return
        end

        local retryUnit = ResolveUnitToken(unitFrame.unit)
        if not retryUnit then
            return
        end

        if expectedGUID then
            local currentGUID = UnitGUID(retryUnit)
            if IsSecret(currentGUID) or not IsAccessibleValue(currentGUID) or currentGUID ~= expectedGUID then
                return
            end
        end

        ApplyNpcTitleVisual(retryNameplate, retryUnit, { allowResolve = true, fromRetry = true })
    end)
end

local function GetThreatConfig()
    local nameplatesConfig = C and C.Nameplates
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

local function GetThreatConfigColor(config, key, fallback)
    local color = config and config[key]
    if type(color) == "table" then
        return color
    end
    return fallback
end

local function RefreshPlayerThreatRole()
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

    playerThreatRole = role
end

local function IsPlayerTankRole()
    if playerThreatRole == nil then
        RefreshPlayerThreatRole()
    end
    return playerThreatRole == "TANK"
end

local function IsThreatBitEnabled(index)
    if type(index) ~= "number" then
        return false
    end
    if not C_CVar or type(C_CVar.GetCVar) ~= "function" then
        return false
    end
    local currentValue = C_CVar.GetCVar(NAMEPLATE_THREAT_DISPLAY_CVAR)
    if type(currentValue) ~= "string" or currentValue == "" then
        return false
    end
    if not CVarCallbackRegistry or type(CVarCallbackRegistry.GetCVarBitfieldIndex) ~= "function" then
        return false
    end
    return CVarCallbackRegistry:GetCVarBitfieldIndex(NAMEPLATE_THREAT_DISPLAY_CVAR, index)
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

    -- Progressive/Flash are intentionally disabled; RefineUI uses Safe/Transition/Warning colors only.
    AddMaskBit(threatDisplay.Progressive, false)
    AddMaskBit(threatDisplay.Flash, false)
    AddMaskBit(threatDisplay.HealthBarColor, enableHealthColor)

    return mask
end

local function ApplyThreatDisplayCVarFromConfig()
    if not C_CVar or type(C_CVar.GetCVar) ~= "function" then
        return
    end
    if not C_CVar.GetCVar(NAMEPLATE_THREAT_DISPLAY_CVAR) then
        return
    end
    if not CVarCallbackRegistry or type(CVarCallbackRegistry.SetCVarBitfieldMask) ~= "function" then
        return
    end

    local threatDisplay = Enum and Enum.NamePlateThreatDisplay
    if not threatDisplay then
        return
    end

    local threatConfig = GetThreatConfig()
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

    if currentProgressive == desiredProgressive and
        currentFlash == desiredFlash and
        currentHealthColor == desiredHealthColor then
        return
    end

    CVarCallbackRegistry:SetCVarBitfieldMask(NAMEPLATE_THREAT_DISPLAY_CVAR, desiredMask)
end

local function ShouldMirrorThreatHealthColor()
    local threatConfig = GetThreatConfig()
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

local function GetDefaultHealthColor(unit)
    if not IsUsableUnitToken(unit) then
        return 1, 1, 1
    end

    local palette = RefineUI.Colors or {}
    local classPalette = palette.Class or {}
    local reactionPalette = palette.Reaction or {}

    if ReadSafeBoolean(UnitIsTapDenied(unit)) == true then
        return 0.6, 0.6, 0.6
    end

    if ReadSafeBoolean(UnitIsPlayer(unit)) == true then
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
    if not IsUsableUnitToken(unit) then
        return 1, 1, 1
    end

    local palette = RefineUI.Colors or {}
    local classPalette = palette.Class or {}
    local reactionPalette = palette.Reaction or {}

    if ReadSafeBoolean(UnitIsPlayer(unit)) == true then
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

local function GetContextThreatStatus(unit, playerInCombat)
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

    -- Tanks need lead-aware threat status to capture loss/gain transitions correctly.
    if IsPlayerTankRole() and UnitThreatLeadSituation then
        local leadStatus = UnitThreatLeadSituation("player", unit)
        if type(leadStatus) == "number" then
            -- UnitThreatLeadSituation semantics differ from UnitThreatSituation:
            -- 0/1/2 = currently highest threat with varying lead, 3 = not highest threat.
            if leadStatus == THREAT_LEAD_STATUS_NONE then
                return THREAT_STATUS_AGGRO
            end
            if leadStatus == THREAT_LEAD_STATUS_YELLOW then
                return THREAT_STATUS_TRANSITION_LOW
            end
            if leadStatus == THREAT_LEAD_STATUS_ORANGE then
                return THREAT_STATUS_TRANSITION_HIGH
            end
            if leadStatus == THREAT_LEAD_STATUS_RED then
                return THREAT_STATUS_LOW
            end
        end
    end

    local playerStatus = UnitThreatSituation("player", unit)
    if inInstance then
        if type(playerStatus) == "number" then
            return playerStatus
        end
        -- In instances, if both units are in combat but threat data is temporarily unavailable,
        -- keep threat coloring active using LOW semantics.
        return THREAT_STATUS_LOW
    end

    -- Open world: only color mobs that are in combat with the player.
    if type(playerStatus) == "number" then
        return playerStatus
    end

    return nil
end

local function ResolveThreatHealthColor(unit, data)
    if not IsUsableUnitToken(unit) then
        return nil
    end

    if ReadSafeBoolean(UnitIsPlayer(unit)) == true then
        return nil
    end

    if ReadSafeBoolean(UnitCanAttack("player", unit)) ~= true then
        return nil
    end

    local threatConfig = GetThreatConfig()
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

    if not ShouldMirrorThreatHealthColor() then
        return nil
    end

    local playerInCombat = ReadSafeBoolean(UnitAffectingCombat("player")) == true

    local unitInCombat = ReadSafeBoolean(UnitAffectingCombat(unit))
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

    local threatStatus = GetContextThreatStatus(unit, playerInCombat)
    if type(threatStatus) == "number" and data and GetTime then
        data.LastThreatStatusAt = GetTime()
    end

    -- Threat queries can briefly return nil while the game is transitioning threat ownership.
    -- Hold transition color very briefly to avoid dropping to reaction color during handoff.
    if type(threatStatus) ~= "number" and data and data.ThreatColorApplied == true and GetTime then
        local lastThreatStatusAt = data.LastThreatStatusAt
        if type(lastThreatStatusAt) == "number" and (GetTime() - lastThreatStatusAt) <= 0.25 then
            threatStatus = THREAT_STATUS_TRANSITION_HIGH
        end
    end

    if type(threatStatus) ~= "number" then
        return nil
    end

    local safeColor = GetThreatConfigColor(threatConfig, "SafeColor", DEFAULT_THREAT_SAFE_COLOR)
    local transitionColor = GetThreatConfigColor(threatConfig, "TransitionColor", DEFAULT_THREAT_TRANSITION_COLOR)
    local warningColor = GetThreatConfigColor(threatConfig, "WarningColor", DEFAULT_THREAT_WARNING_COLOR)
    local isTank = IsPlayerTankRole()

    if threatStatus == THREAT_STATUS_AGGRO then
        return isTank and safeColor or warningColor
    end

    if threatStatus == THREAT_STATUS_TRANSITION_LOW or threatStatus == THREAT_STATUS_TRANSITION_HIGH then
        return transitionColor
    end

    if threatStatus == THREAT_STATUS_LOW then
        return isTank and warningColor or safeColor
    end

    return nil
end

local function UpdateThreatColor(nameplate, unit, _forced)
    if not nameplate or not IsUsableUnitToken(unit) then
        return
    end

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local health = unitFrame.healthBar or unitFrame.HealthBar

    local data = RefineUI.NameplateData[unitFrame]
    if not data then
        return
    end
    if not data.RefineName then
        return
    end

    local threatColor = ResolveThreatHealthColor(unit, data)
    if threatColor then
        local r = threatColor[1] or 1
        local g = threatColor[2] or 1
        local b = threatColor[3] or 1
        if health then
            SetBarColorIfChanged(health, r, g, b)
        end
        SetNameColorIfChanged(data, r, g, b)
        data.ThreatColorApplied = true
        return
    end

    if health then
        local hr, hg, hb = GetDefaultHealthColor(unit)
        SetBarColorIfChanged(health, hr, hg, hb)
    end

    local nr, ng, nb = GetDefaultNameColor(unit)
    SetNameColorIfChanged(data, nr, ng, nb)
    data.ThreatColorApplied = false
end

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------

local function SkinNamePlateAura(frame)
    if not frame or GetNameplateState(frame, "AuraSkinned", false) then return end
    
    -- Strip default circular textures and masks
    if frame.Icon then
        -- Find mask texture (Blizzard uses UI-HUD-CoolDownManager-Mask)
        for i = 1, select("#", frame:GetRegions()) do
            local region = select(i, frame:GetRegions())
            if region:IsObjectType("MaskTexture") then
                region:SetAlpha(0)
            elseif region:IsObjectType("Texture") and region ~= frame.Icon then
                -- Hide overlays like UI-HUD-CoolDownManager-IconOverlay
                region:SetAlpha(0)
            end
        end
        
        -- Square icon
        frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        RefineUI.SetInside(frame.Icon, frame, 1, 1)
    end

    -- Create Border
    RefineUI.CreateBorder(frame, 6, 6, 12)
    
    -- Style Count Frame
    if frame.CountFrame and frame.CountFrame.Count then
        RefineUI.Font(frame.CountFrame.Count, 10, nil, "OUTLINE")
        frame.CountFrame.Count:ClearAllPoints()
        RefineUI.Point(frame.CountFrame.Count, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -1)
    end

    -- Style Cooldown
    if frame.Cooldown then
        frame.Cooldown:SetDrawEdge(false)
        frame.Cooldown:SetSwipeTexture(RefineUI.Media.Textures.CooldownSwipeSmall)
        frame.Cooldown:SetSwipeColor(0, 0, 0, 1)
        RefineUI.SetInside(frame.Cooldown, frame, -2, -2)
    end

    -- Spacing and Positioning is handled by RefreshList hook below
    local container = frame:GetParent()
    if container then
        SetNameplateState(container, "AuraContainerSkinned", true)
    end

    SetNameplateState(frame, "AuraSkinned", true)
end




local function NormalizeNameText(text, unit)
    if not text then return "" end
    local isPlayerUnit = false
    if IsUsableUnitToken(unit) then
        isPlayerUnit = ReadSafeBoolean(UnitIsPlayer(unit)) == true
    end
    if not IsSecret(text) and isPlayerUnit then
        text = text:gsub(" %(*.*%)", ""):gsub("%-.*", "")
    end
    return text
end

local function UpdateName(nameplate, unit)
    local unitFrame = nameplate.UnitFrame
    local name = unitFrame.name or (unitFrame.NameContainer and unitFrame.NameContainer.Name)
    local health = unitFrame.healthBar or unitFrame.HealthBar
    if not name then return end

    local data = RefineUI.NameplateData[unitFrame]
    if not data then 
        data = {} 
        RefineUI.NameplateData[unitFrame] = data
    end

    local desiredNameFontSize = GetScaledNameplateNameFontSize()

    -- Create RefineName if doesn't exist
    if not data.RefineName then
        data.RefineName = unitFrame:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.RefineName, desiredNameFontSize)
        local anchor = health or unitFrame
        RefineUI.Point(data.RefineName, "BOTTOM", anchor, health and "TOP" or "CENTER", 0, health and 4 or 0)
        data.RefineNameFontSize = desiredNameFontSize
    elseif data.RefineNameFontSize ~= desiredNameFontSize then
        RefineUI.Font(data.RefineName, desiredNameFontSize)
        data.RefineNameFontSize = desiredNameFontSize
    end

    -- Nameplates can swap name FontStrings across style states (full plate <-> name-only).
    -- Rebind hide/mirror hooks whenever the active source object changes.
    if data.NameSource ~= name then
        data.NameSource = name

        RefineUI:HookOnce(BuildNameplateHookKey(name, "SetText"), name, "SetText", function(_, txt)
            local frameData = RefineUI.NameplateData[unitFrame]
            if frameData and frameData.RefineName then
                frameData.RefineName:SetText(NormalizeNameText(txt or "", unitFrame.unit))
            end
        end)

        RefineUI:HookOnce(BuildNameplateHookKey(name, "SetAlpha"), name, "SetAlpha", function(self, alpha)
            if alpha ~= 0 then self:SetAlpha(0) end
        end)
    end

    -- Always suppress the currently active Blizzard name source.
    name:SetAlpha(0)
    
    -- Always sync text
    data.RefineName:SetText(NormalizeNameText(name:GetText() or "", unit))
    ApplyNpcTitleVisual(nameplate, unit, { allowResolve = false })
end

local function UpdateHealth(nameplate, unit)
    if not nameplate or not unit then return end

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then return end

    local health = unitFrame.healthBar or unitFrame.HealthBar
    if not health then return end
    
    local data = RefineUI.NameplateData[unitFrame]
    if not data then return end -- Should exist by now

    local desiredHealthFontSize = GetScaledNameplateHealthFontSize()

    -- Optimization: Skip update if hidden
    if data.RefineHidden then return end
    
    if not data.RefineHealth then
        -- Parent to border to ensure it shows OVER the border
        local parent = (data.HealthBorderOverlay and data.HealthBorderOverlay.border) or health
        data.RefineHealth = parent:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.RefineHealth, desiredHealthFontSize, nil, "OUTLINE")
        RefineUI.Point(data.RefineHealth, "CENTER", health, "CENTER", 0, -2)
        data.RefineHealthFontSize = desiredHealthFontSize
    elseif data.RefineHealthFontSize ~= desiredHealthFontSize then
        RefineUI.Font(data.RefineHealth, desiredHealthFontSize, nil, "OUTLINE")
        data.RefineHealthFontSize = desiredHealthFontSize
    end

    -- Force RefineUI Texture
    if health.SetStatusBarTexture then
        health:SetStatusBarTexture(TEX_BAR)
        health:SetStatusBarDesaturated(true)
    end
    
    
    -- Use UnitHealthPercent from UnitFrames.lua method - Do NOT compare output (Secret Value)
    local percent = UnitHealthPercent(unit, true, RefineUI.GetPercentCurve())
    
    if IsSecret(percent) then
        data.RefineHealth:SetText(percent)
    else
        data.RefineHealth:SetFormattedText("%.0f", percent)
    end
end



local function StyleNameplate(nameplate, unit)
	if not nameplate or nameplate:IsForbidden() then return end
	
    local unitFrame = nameplate.UnitFrame
    if not unitFrame then return end
    unit = ResolveUnitToken(unit, unitFrame.unit)
    if not unit then return end

    local data = RefineUI.NameplateData[unitFrame]
    if not data then 
        data = {} 
        RefineUI.NameplateData[unitFrame] = data
    end

    local health = unitFrame.healthBar or unitFrame.HealthBar
    if not health then return end

    ApplyConfiguredNameplateSize(unitFrame, nameplate)

    -- Reapply custom size whenever Blizzard reapplies nameplate frame options.
    -- Hook per unit frame so load order of global mixins cannot skip this path.
    if not data.SizeReapplyHooked and type(unitFrame.ApplyFrameOptions) == "function" then
        local hookKey = BuildNameplateHookKey(unitFrame, "ApplyFrameOptions:ConfiguredSize")
        local ok = RefineUI:HookOnce(hookKey, unitFrame, "ApplyFrameOptions", function(self)
            local parent = self.GetParent and self:GetParent() or nil
            if parent and parent.UnitFrame == self then
                ApplyConfiguredNameplateSize(self, parent)
            else
                ApplyConfiguredNameplateSize(self)
            end
        end)
        data.SizeReapplyHooked = ok == true
    end

    -- Cache isPlayer and inCombat as plain booleans.
    local isPlayer = nil
    local inCombat = nil
    if IsUsableUnitToken(unit) then
        isPlayer = ReadSafeBoolean(UnitIsPlayer(unit))
        inCombat = ReadSafeBoolean(UnitAffectingCombat(unit))
    end
    data.isPlayer = isPlayer == true
    data.inCombat = inCombat == true

    -- Hide Blizzard Classification (Elite/Rare stars)
    if unitFrame.ClassificationFrame then
        unitFrame.ClassificationFrame:SetAlpha(0)
    end

    -- Store ref locally to avoid table lookups in closures if possible, but data is safer
    if not data.EventFrame then
        data.EventFrame = CreateFrame("Frame", nil, unitFrame)
        data.EventFrame:SetScript("OnEvent", function(self, event, unit)
            local parentUnit = unitFrame.unit
            local isSame = SafeUnitIsUnit(parentUnit, unit)

            if isSame then
                if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                    UpdateHealth(nameplate, parentUnit)
                elseif event == "UNIT_AURA" then
                    if RefineUI.UpdateNameplateCrowdControl then
                        RefineUI:UpdateNameplateCrowdControl(unitFrame, parentUnit, event)
                    end
                elseif event == "UNIT_PORTRAIT_UPDATE" or
                    event == "UNIT_MODEL_CHANGED" then
                    RefineUI:UpdateDynamicPortrait(nameplate, parentUnit, event)
                end
            end
        end)
    end
    
    if not data.RefineBorder then
        -- Create isolated overlay for border to prevent direct modification of health frame properties
        local borderOverlay = CreateFrame("Frame", nil, health)
        RefineUI.SetInside(borderOverlay, health, 0, 0)
        RefineUI.CreateBorder(borderOverlay, 6, 6, 12)
        data.RefineBorder = borderOverlay.border
        data.HealthBorderOverlay = borderOverlay
    end

    -- Apply RefineUI Texture to the health bar (Always, to handle reuse)
    if health then
        -- SetStatusBarTexture is generally safe on secure frames (doesn't taint execution path usually)
        health:SetStatusBarTexture(TEX_BAR)
        health:SetStatusBarDesaturated(true)

        -- Health Bar Background
        if not data.HealthBackground then
            data.HealthBackground = health:CreateTexture(nil, "BACKGROUND")
            RefineUI.SetInside(data.HealthBackground, health, 0, 0)
            data.HealthBackground:SetTexture(TEX_BAR)
            data.HealthBackground:SetVertexColor(0.25, 0.25, 0.25, 1)
        end
    end

    if health then
        RefineUI:HookOnce(BuildNameplateHookKey(health, "SetStatusBarTexture"), health, "SetStatusBarTexture", function(self, tex)
            if data.SettingTexture then return end
            if (not IsAccessibleValue(tex)) or tex ~= TEX_BAR then
                data.SettingTexture = true
                self:SetStatusBarTexture(TEX_BAR)
                self:SetStatusBarDesaturated(true)
                data.SettingTexture = false
            end
        end)
    end

    if unitFrame.castBar then
        RefineUI:StyleNameplateCastBar(unitFrame.castBar)
        unitFrame.castBar:UpdateUnitEvents(unit)
    elseif unitFrame.CastBar then
        RefineUI:StyleNameplateCastBar(unitFrame.CastBar)
        unitFrame.CastBar:UpdateUnitEvents(unit)
    end

    -- Portrait Elements are created lazily in UpdateDynamicPortrait
    -- to avoid creating frames for hidden friendly nameplates.

    -- Update/Re-register for the current unit
    -- Update/Re-register for the current unit
    if data.EventFrame then
        -- Always re-register events for the new unit (RegisterUnitEvent handles unregistering old unit automatically)
        if IsUsableUnitToken(unit) then
            data.EventFrame:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", unit)
            data.EventFrame:RegisterUnitEvent("UNIT_MODEL_CHANGED", unit)
            
            data.EventFrame:RegisterUnitEvent("UNIT_HEALTH", unit)
            data.EventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
            data.EventFrame:RegisterUnitEvent("UNIT_AURA", unit)
        end
    end

    -- Target Features
    RefineUI:CreateTargetArrows(unitFrame)

    UpdateName(nameplate, unit)
    UpdateHealth(nameplate, unit)
end

local function UpdateVisibility(nameplate, unit)
    local unitFrame = nameplate.UnitFrame
    if not unitFrame then return end

    local data = RefineUI.NameplateData[unitFrame]
    if not data then return end -- If styled, data exists

    -- Use standard Blizzard frame reference if possible
    local healthContainer = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame.HealthBar
    -- local healthContainer check removed to allow visibility handling for names-only plates
    
    -- Safe UnitIsFriend & UnitCanAttack
    local isFriend = false
    local canAttack = false
    if IsUsableUnitToken(unit) then
        local friendValue = ReadSafeBoolean(UnitIsFriend("player", unit))
        if friendValue ~= nil then
            isFriend = friendValue
        end

        local attackValue = ReadSafeBoolean(UnitCanAttack("player", unit))
        if attackValue ~= nil then
            canAttack = attackValue
        end
    end

    -- RefineUI Rule: Check "Can Attack" instead of just "Is Friendly"
    -- This ensures Hostile Unattackable NPCs (e.g. Blood Knights) also get Name Only style
    if isFriend or not canAttack then
        -- Friendly/Unattackable: Hide bars, show name only
        if healthContainer then
            healthContainer:SetAlpha(0)
        end
        
        if unitFrame.selectionHighlight then
            unitFrame.selectionHighlight:SetAlpha(0)
        end
        
        if data.PortraitFrame then
            data.PortraitFrame:Hide()
        end
        
        local castBar = unitFrame.castBar or unitFrame.CastBar
        if castBar then
            castBar:SetAlpha(0)
            castBar:Hide()
        end

        if RefineUI.ClearNameplateCrowdControl then
            RefineUI:ClearNameplateCrowdControl(unitFrame, true)
        end
        
        -- Flag for optimization
        data.RefineHidden = true
    else
        -- Hostile/Neutral: Show bars
        if healthContainer then
            healthContainer:SetAlpha(1)
        end
        
        if unitFrame.selectionHighlight then
            unitFrame.selectionHighlight:SetAlpha(0.25)
        end

        if data.PortraitFrame then
            data.PortraitFrame:Show()
        end

        local castBar = unitFrame.castBar or unitFrame.CastBar
        if castBar and castBar:IsShown() then
            castBar:SetAlpha(1)
        end

        data.RefineHidden = false

        if RefineUI.UpdateNameplateCrowdControl then
            RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, "UNIT_FACTION")
        end
    end

    ApplyNpcTitleVisual(nameplate, unit, { allowResolve = false })
end

local function OnNameplateAdded(event, unit)
    local safeUnit = ResolveUnitToken(unit)
    if not safeUnit then return end

    EnsureConfiguredNameplateSizeHooks()

    local nameplate = SafeGetNamePlateForUnit(safeUnit)
    if nameplate then
        -- Update Cached State
        if nameplate.UnitFrame then
            -- Safe UnitIsPlayer
            local data = RefineUI.NameplateData[nameplate.UnitFrame]
            if not data then data = {} RefineUI.NameplateData[nameplate.UnitFrame] = data end

            if IsUsableUnitToken(safeUnit) then
                data.isPlayer = ReadSafeBoolean(UnitIsPlayer(safeUnit)) == true
            end
            local cb = nameplate.UnitFrame.castBar or nameplate.UnitFrame.CastBar
            if cb and cb.UpdateUnitEvents then
                cb:UpdateUnitEvents(safeUnit)
            end
        end

        activeNameplates[nameplate] = safeUnit
        StyleNameplate(nameplate, safeUnit)
        UpdateVisibility(nameplate, safeUnit)
        ApplyNpcTitleVisual(nameplate, safeUnit, { allowResolve = true })
        if RefineUI.UpdateNameplateCrowdControl then
            RefineUI:UpdateNameplateCrowdControl(nameplate.UnitFrame, safeUnit, event)
        end
        
        -- Force portrait update for new/reused nameplate
        if nameplate.UnitFrame then
             local data = RefineUI.NameplateData[nameplate.UnitFrame]
             if data then
                data.lastPortraitGUID = nil
                data.lastPortraitMode = nil
                data.wasCasting = false
                data.blockingCast = false
             end
        end
        RefineUI:UpdateDynamicPortrait(nameplate, safeUnit)
        if nameplate.UnitFrame then RefineUI:UpdateTarget(nameplate.UnitFrame) end
    end
end

local function OnNameplateRemoved(event, unit)
    if not IsUsableUnitToken(unit) then return end
    local removedUnitFrame = nil
    for np, u in pairs(activeNameplates) do
        if IsUsableUnitToken(u) and u == unit then
            activeNameplates[np] = nil
            removedUnitFrame = np and np.UnitFrame or nil
            break
        end
    end

    if removedUnitFrame then
        CancelNpcTitleRetry(removedUnitFrame)

        local removedData = RefineUI.NameplateData[removedUnitFrame]
        if removedData then
            if removedData.RefineNpcTitle then
                SetNpcTitleText(removedData, nil)
            end
            removedData.RefineNpcTitleAnchor = nil
            removedData.RefineNpcTitleFormatted = nil
        end

        if RefineUI.ClearNameplateCrowdControl then
            RefineUI:ClearNameplateCrowdControl(removedUnitFrame, true)
        end
    end
end

----------------------------------------------------------------------------------------
-- CVar Management
----------------------------------------------------------------------------------------
local lastState = {
    inCombat = nil,
    inGroupContent = nil,
    showPetNames = nil,
}
local RefreshAllThreatColors

local function SetCVarIfChanged(cvar, value)
    local desired = tostring(value)
    local current = GetCVar(cvar)
    if current ~= desired then
        SetCVar(cvar, desired)
    end
end

local function EnsureSimplifiedNameplatesDisabled()
    if not C_NamePlateManager or not C_NamePlateManager.SetNamePlateSimplified then return end

    local nameplateType = Enum and Enum.NamePlateType
    if not nameplateType then return end

    -- Guard with pcall so API signature drift never breaks the module.
    pcall(C_NamePlateManager.SetNamePlateSimplified, nameplateType.Friendly, false)
    pcall(C_NamePlateManager.SetNamePlateSimplified, nameplateType.Enemy, false)
end

local function UpdateNameplateCVars(forceApply)
    EnsureSimplifiedNameplatesDisabled()
    ApplyThreatDisplayCVarFromConfig()

    local inCombat = ReadSafeBoolean(UnitAffectingCombat("player"))
    if inCombat == nil then
        inCombat = false
    end
    local inInstance, instanceType = IsInInstance()
    local inBattleground = ReadSafeBoolean(UnitInBattleground("player"))
    if inBattleground == nil then
        inBattleground = false
    end
    local inGroupContent = (instanceType == 'party' or instanceType == 'raid' or instanceType == 'pvp' or instanceType == 'arena') or inBattleground
    local showPetNames = C and C.Nameplates and C.Nameplates.ShowPetNames == true

    -- Check if state changed
    if (not forceApply) and
        lastState.inCombat == inCombat and
        lastState.inGroupContent == inGroupContent and
        lastState.showPetNames == showPetNames then
        return
    end

    -- Update State
    lastState.inCombat = inCombat
    lastState.inGroupContent = inGroupContent
    lastState.showPetNames = showPetNames

    -- Unified Logic: 
    -- Hide ALL friendly plates in Combat OR in Group Content (clutter reduction)
    local showFriends = (not inGroupContent and not inCombat) and 1 or 0
    local showNPCs = (not inGroupContent and not inCombat) and 1 or 0
    local showFriendlyPlayerPets = (showFriends == 1 and showPetNames) and 1 or 0
    local showEnemyPlayerPets = showPetNames and 1 or 0

    SetCVarIfChanged("nameplateShowFriends", showFriends)
    SetCVarIfChanged("nameplateShowFriendlyPlayers", showFriends)
    SetCVarIfChanged("nameplateShowFriendlyPlayerPets", showFriendlyPlayerPets)
    SetCVarIfChanged("nameplateShowFriendlyPlayerMinions", showFriends)
    SetCVarIfChanged("nameplateShowFriendlyPlayerGuardians", showFriends)
    SetCVarIfChanged("nameplateShowFriendlyPlayerTotems", showFriends)
    SetCVarIfChanged("nameplateShowEnemyPets", showEnemyPlayerPets)
    
    SetCVarIfChanged("nameplateShowFriendlyNpcs", showNPCs)
end

local function HandleNameplateUnitStateEvent(event, unit)
    if IsDisallowedNameplateUnitToken(unit) then
        return
    end

    local nameplate = SafeGetNamePlateForUnit(unit)
    if not nameplate then
        return
    end

    UpdateVisibility(nameplate, unit)
    UpdateHealth(nameplate, unit)

    if RefineUI.UpdateNameplateCrowdControl then
        RefineUI:UpdateNameplateCrowdControl(nameplate.UnitFrame, unit, event)
    end
end

local function HandleNameplateTargetChanged()
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            local unitFrame = nameplate and nameplate.UnitFrame
            if unitFrame then
                RefineUI:UpdateTarget(unitFrame)
            end
        end
        return
    end

    for nameplate in pairs(activeNameplates) do
        local unitFrame = nameplate and nameplate.UnitFrame
        if unitFrame then
            RefineUI:UpdateTarget(unitFrame)
        end
    end
end

local function HandleNameplateCVarEvent(event)
    UpdateNameplateCVars(event == "PLAYER_ENTERING_WORLD")
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" or pendingNameplateSizeApply then
        ApplyConfiguredBlizzardNameplateSize(true)
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
            for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
                local unitFrame = nameplate and nameplate.UnitFrame
                if unitFrame then
                    CancelNpcTitleRetry(unitFrame)
                end
            end
        end
        wipe(npcTitleCacheByGUID)
        wipe(activeNameplates)
    end
end

local function HandleThreatRoleEvent(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
        return
    end

    RefreshPlayerThreatRole()
end

local function RequestBlizzardHealthColorUpdate(unitFrame, fallbackNameplate, fallbackUnit)
    local updateHealthColor = _G.CompactUnitFrame_UpdateHealthColor
    if unitFrame and type(updateHealthColor) == "function" then
        updateHealthColor(unitFrame)
        return
    end

    if fallbackNameplate and fallbackUnit then
        UpdateThreatColor(fallbackNameplate, fallbackUnit, true)
    end
end

RefreshAllThreatColors = function(_forced)
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            local unitFrame = nameplate and nameplate.UnitFrame
            local unit = unitFrame and ResolveUnitToken(unitFrame.unit)
            if unit then
                RequestBlizzardHealthColorUpdate(unitFrame, nameplate, unit)
            end
        end
        return
    end

    for nameplate, unit in pairs(activeNameplates) do
        local unitFrame = nameplate and nameplate.UnitFrame
        local resolvedUnit = ResolveUnitToken(unit, unitFrame and unitFrame.unit)
        if resolvedUnit then
            RequestBlizzardHealthColorUpdate(unitFrame, nameplate, resolvedUnit)
        end
    end
end

function RefineUI:RefreshAllNameplateNpcTitles(_reason)
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            if nameplate and nameplate.UnitFrame then
                ApplyNpcTitleVisual(nameplate, nameplate.UnitFrame.unit, { allowResolve = true })
            end
        end
        return
    end

    for nameplate, unit in pairs(activeNameplates) do
        if nameplate and nameplate.UnitFrame then
            ApplyNpcTitleVisual(nameplate, unit, { allowResolve = true })
        end
    end
end

function RefineUI:RefreshAllNameplateTextScales(_reason)
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            local unitFrame = nameplate and nameplate.UnitFrame
            local unit = unitFrame and ResolveUnitToken(unitFrame.unit)
            if unit then
                UpdateName(nameplate, unit)
                UpdateHealth(nameplate, unit)
            end
        end
        return
    end

    for nameplate, unit in pairs(activeNameplates) do
        local unitFrame = nameplate and nameplate.UnitFrame
        local resolvedUnit = ResolveUnitToken(unit, unitFrame and unitFrame.unit)
        if resolvedUnit then
            UpdateName(nameplate, resolvedUnit)
            UpdateHealth(nameplate, resolvedUnit)
        end
    end
end

function RefineUI:ApplyNameplateCVarSettings()
    UpdateNameplateCVars(true)
end

function RefineUI:ApplyNameplateSizeSettings(forceApply)
    ApplyConfiguredBlizzardNameplateSize(forceApply == true)
end

function RefineUI:RefreshNameplateThreatColors(forced)
    ApplyThreatDisplayCVarFromConfig()
    RefreshAllThreatColors(forced == true)
end

function RefineUI:ApplyNameplateThreatDisplaySettings()
    RefineUI:RefreshNameplateThreatColors(true)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Nameplates:OnEnable()
    EnsureSimplifiedNameplatesDisabled()
    RefreshPlayerThreatRole()
    EnsureConfiguredNameplateSizeHooks()
    ApplyConfiguredBlizzardNameplateSize(true)
    if type(RefineUI.RefreshNameplateCastColors) == "function" then
        RefineUI:RefreshNameplateCastColors(false)
    end

    -- Restore Alpha behavior from RefineUI_OLD (mitigates X-ray effect on overlapping frames)
    if C.Nameplates.Alpha then
        SetCVar("nameplateMinAlpha", C.Nameplates.Alpha)
    end
    SetCVar("nameplateMaxAlpha", 1.0)
    ApplyThreatDisplayCVarFromConfig()

    RefineUI:RegisterEventCallback("NAME_PLATE_UNIT_ADDED", OnNameplateAdded, "Nameplates:UnitAdded")
    RefineUI:RegisterEventCallback("NAME_PLATE_UNIT_REMOVED", OnNameplateRemoved, "Nameplates:UnitRemoved")
    RefineUI:OnEvents({ "UNIT_FACTION", "UNIT_FLAGS" }, HandleNameplateUnitStateEvent, "Nameplates:UnitState")
    RefineUI:RegisterEventCallback("PLAYER_TARGET_CHANGED", HandleNameplateTargetChanged, "Nameplates:TargetChanged")
    RefineUI:OnEvents(
        { "PLAYER_ENTERING_WORLD", "PLAYER_ROLES_ASSIGNED", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "GROUP_ROSTER_UPDATE" },
        HandleThreatRoleEvent,
        "Nameplates:ThreatRole"
    )
    
    -- Register CVar Automation Events
    RefineUI:OnEvents(
        { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" },
        HandleNameplateCVarEvent,
        "Nameplates:CVarState"
    )

    -- Initial Update
    UpdateNameplateCVars()
    
    -- Style existing plates
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unit = nameplate.UnitFrame and nameplate.UnitFrame.unit
        if unit then
            activeNameplates[nameplate] = unit
            StyleNameplate(nameplate, unit)
            UpdateVisibility(nameplate, unit)
            ApplyNpcTitleVisual(nameplate, unit, { allowResolve = true })
            if RefineUI.UpdateNameplateCrowdControl then
                RefineUI:UpdateNameplateCrowdControl(nameplate.UnitFrame, unit, "OnEnable")
            end
            RefineUI:UpdateDynamicPortrait(nameplate, unit)
            if nameplate.UnitFrame then
                RefineUI:UpdateTarget(nameplate.UnitFrame)
            end
        end
    end

    -- Hook CompactUnitFrame_UpdateName to keep RefineName synced on plate reuse
    RefineUI:HookOnce("Nameplates:CompactUnitFrame_UpdateName", "CompactUnitFrame_UpdateName", function(frame)
        if frame:IsForbidden() then return end
        if not IsUsableUnitToken(frame.unit) then return end
        if not frame.unit:find("nameplate") then return end
        
        local nameplate = frame:GetParent()
        if nameplate and nameplate.UnitFrame == frame then
             UpdateName(nameplate, frame.unit)
        end
    end)

    -- Hook CompactUnitFrame_UpdateHealthColor to force texture and mirror Blizzard threat color
    RefineUI:HookOnce("Nameplates:CompactUnitFrame_UpdateHealthColor", "CompactUnitFrame_UpdateHealthColor", function(frame)
        if frame:IsForbidden() then return end
        if not IsUsableUnitToken(frame.unit) then return end
        if not frame.unit:find("nameplate") then return end
        
        local health = frame.healthBar or frame.HealthBar
        if health then
            health:SetStatusBarTexture(TEX_BAR)
            health:SetStatusBarDesaturated(true)
        end

        local nameplate = frame:GetParent()
        if nameplate and nameplate.UnitFrame == frame then
            UpdateThreatColor(nameplate, frame.unit, false)
        end
    end)

    RefineUI:RefreshNameplateThreatColors(true)

    -- Hook Aura Updates
    if _G.NamePlateAuraItemMixin and _G.NamePlateAuraItemMixin.SetAura then
        RefineUI:HookOnce("Nameplates:NamePlateAuraItemMixin:SetAura", _G.NamePlateAuraItemMixin, "SetAura", function(self, aura)
            if self:IsForbidden() then return end
            
            SkinNamePlateAura(self)
            
            -- Color border based on aura type (Midnight SECRET-safe)
            if self.border then
                local isHelpful = SafeTableIndex(aura, "isHelpful")
                if IsSecret(isHelpful) then
                    -- Use CurveUtil to evaluate color without branching (binary fallback)
                    local c = RefineUI.Config.General.BorderColor
                    local buffColor = CreateColor(c[1], c[2], c[3], c[4] or 1)
                    local debuffColor = CreateColor(0.8, 0.1, 0.1, 1)
                    local finalColor = C_CurveUtil.EvaluateColorFromBoolean(isHelpful, buffColor, debuffColor)
                    self.border:SetBackdropBorderColor(finalColor:GetRGBA())
                else
                    if isHelpful then
                        local color = RefineUI.Config.General.BorderColor
                        self.border:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
                    else
                        -- Debuff: color by type if available, otherwise red
                        local r, g, b = 0.8, 0.1, 0.1
                        local dispelName = SafeTableIndex(aura, "dispelName")
                        if dispelName and _G.DebuffTypeColor then
                            local color = _G.DebuffTypeColor[dispelName]
                            if color then r, g, b = color.r, color.g, color.b end
                        end
                        self.border:SetBackdropBorderColor(r, g, b)
                    end
                end
            end
        end)
    end

    -- Manual Aura Layout Hook
    -- This overrides both Blizzard and BBP positioning by directly moving the icons
    if _G.NamePlateAurasMixin and _G.NamePlateAurasMixin.RefreshList then
        RefineUI:HookOnce("Nameplates:NamePlateAurasMixin:RefreshList", _G.NamePlateAurasMixin, "RefreshList", function(self)
            if self:IsForbidden() then return end
            
            -- Find the health bar to anchor to
            local unitFrame = self:GetParent()
            if unitFrame and not unitFrame.unit then unitFrame = unitFrame:GetParent() end
            local health = unitFrame and (unitFrame.healthBar or unitFrame.HealthBar)
            if not health then return end

            local idx = 0
            local spacing = RefineUI:Scale(12)
            local yOffset = 24 -- A sane default, user previously set 140 for testing
            
            -- Handle BBP's custom naming if it exists
            local itemWidth = 20
            local scaledSpacing = RefineUI:Scale(12)
            local scaledY = RefineUI:Scale(24)
            
            for auraFrame in self.auraItemFramePool:EnumerateActive() do
                if auraFrame:IsShown() then
                    auraFrame:ClearAllPoints()
                    -- Anchor manually with custom spacing
                    RefineUI.Point(auraFrame, "BOTTOMLEFT", health, "TOPLEFT", idx * (itemWidth + scaledSpacing), scaledY)
                    idx = idx + 1
                end
            end
        end)
    end

    if self.RegisterEditModeFrame then
        self:RegisterEditModeFrame()
    end
    if self.RegisterEditModeCallbacks then
        self:RegisterEditModeCallbacks()
    end
end
