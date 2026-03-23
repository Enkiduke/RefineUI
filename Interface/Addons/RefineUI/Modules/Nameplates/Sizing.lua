----------------------------------------------------------------------------------------
-- Nameplates Component: Sizing
-- Description: Nameplate size and text-scale configuration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tonumber = tonumber
local pcall = pcall
local floor = math.floor
local min = math.min
local max = math.max
local abs = math.abs

local C_NamePlate = C_NamePlate
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DEFAULT_NAMEPLATE_SCALE = 1
local DEFAULT_NAMEPLATE_WIDTH = 150
local DEFAULT_NAMEPLATE_HEIGHT = 20
local NAMEPLATE_SCALE_EPSILON = 0.001

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function SafeSetFrameDimension(frame, methodName, value)
    if not frame or type(value) ~= "number" then
        return false
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return false
    end

    local setter = frame[methodName]
    if type(setter) ~= "function" then
        return false
    end

    local ok = pcall(setter, frame, value)
    return ok == true
end

local function ClampNameplateScale(value, fallback, constants)
    local scale = tonumber(value)
    if not scale then
        scale = fallback
    end
    if scale < constants.NAMEPLATE_TEXT_SCALE_MIN then
        return constants.NAMEPLATE_TEXT_SCALE_MIN
    end
    if scale > constants.NAMEPLATE_TEXT_SCALE_MAX then
        return constants.NAMEPLATE_TEXT_SCALE_MAX
    end
    return scale
end

local function ReadLegacyScaleCandidates(cfg)
    local candidates = {}
    local size = cfg and cfg.Size
    if type(size) == "table" then
        local width = tonumber(size[1])
        if width and abs(width - DEFAULT_NAMEPLATE_WIDTH) > NAMEPLATE_SCALE_EPSILON then
            candidates[#candidates + 1] = width / DEFAULT_NAMEPLATE_WIDTH
        end

        local height = tonumber(size[2])
        if height and abs(height - DEFAULT_NAMEPLATE_HEIGHT) > NAMEPLATE_SCALE_EPSILON then
            candidates[#candidates + 1] = height / DEFAULT_NAMEPLATE_HEIGHT
        end
    end

    local unitNameScale = tonumber(cfg and cfg.UnitNameScale)
    if unitNameScale and abs(unitNameScale - DEFAULT_NAMEPLATE_SCALE) > NAMEPLATE_SCALE_EPSILON then
        candidates[#candidates + 1] = unitNameScale
    end

    local healthTextScale = tonumber(cfg and cfg.HealthTextScale)
    if healthTextScale and abs(healthTextScale - DEFAULT_NAMEPLATE_SCALE) > NAMEPLATE_SCALE_EPSILON then
        candidates[#candidates + 1] = healthTextScale
    end

    local portraitScale = tonumber(cfg and cfg.DynamicPortraitScale)
    if portraitScale and abs(portraitScale - DEFAULT_NAMEPLATE_SCALE) > NAMEPLATE_SCALE_EPSILON then
        candidates[#candidates + 1] = portraitScale
    end

    return candidates
end

----------------------------------------------------------------------------------------
-- Sizing API
----------------------------------------------------------------------------------------
function Nameplates:GetConfiguredNameplateScale()
    local private = self:GetPrivate()
    local constants = private and private.Constants
    if not constants then
        return DEFAULT_NAMEPLATE_SCALE
    end

    local cfg = self:GetConfiguredNameplatesConfig()
    local configuredScale = tonumber(cfg and cfg.Scale)
    if configuredScale then
        return ClampNameplateScale(configuredScale, DEFAULT_NAMEPLATE_SCALE, constants)
    end

    local candidates = ReadLegacyScaleCandidates(cfg)
    if #candidates == 0 then
        return DEFAULT_NAMEPLATE_SCALE
    end

    local total = 0
    for index = 1, #candidates do
        total = total + candidates[index]
    end

    return ClampNameplateScale(total / #candidates, DEFAULT_NAMEPLATE_SCALE, constants)
end

function Nameplates:GetConfiguredNameplateSize()
    local scale = self:GetConfiguredNameplateScale()
    local width = DEFAULT_NAMEPLATE_WIDTH * scale
    local height = DEFAULT_NAMEPLATE_HEIGHT * scale

    return RefineUI:Scale(width), RefineUI:Scale(height)
end

function Nameplates:GetConfiguredNameplateFrameSize()
    local scaledWidth, scaledHeight = self:GetConfiguredNameplateSize()
    local sideInset = RefineUI:Scale(12)
    return scaledWidth + (sideInset * 2), scaledHeight
end

function Nameplates:ApplyConfiguredBlizzardNameplateSize(forceApply)
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    if not runtime then
        return false
    end

    if not C_NamePlate or type(C_NamePlate.SetNamePlateSize) ~= "function" then
        return false
    end

    local targetWidth, targetHeight = self:GetConfiguredNameplateFrameSize()
    if not forceApply then
        local isCachedMatch = runtime.lastAppliedNameplateWidth == targetWidth and runtime.lastAppliedNameplateHeight == targetHeight
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
        runtime.pendingNameplateSizeApply = true
        return false
    end

    local ok = pcall(C_NamePlate.SetNamePlateSize, targetWidth, targetHeight)
    if not ok then
        runtime.pendingNameplateSizeApply = true
        return false
    end

    runtime.lastAppliedNameplateWidth = targetWidth
    runtime.lastAppliedNameplateHeight = targetHeight
    runtime.pendingNameplateSizeApply = false
    return true
end

function Nameplates:IsNameplateSizeApplyPending()
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    return runtime and runtime.pendingNameplateSizeApply == true
end

function Nameplates:GetConfiguredUnitNameScale()
    return self:GetConfiguredNameplateScale()
end

function Nameplates:GetConfiguredHealthTextScale()
    return self:GetConfiguredNameplateScale()
end

function Nameplates:GetScaledNameplateNameFontSize()
    local private = self:GetPrivate()
    local constants = private and private.Constants
    if not constants then
        return 12
    end

    return max(1, floor((constants.NAMEPLATE_NAME_FONT_BASE_SIZE * self:GetConfiguredUnitNameScale()) + 0.5))
end

function Nameplates:GetScaledNameplateHealthFontSize()
    local private = self:GetPrivate()
    local constants = private and private.Constants
    if not constants then
        return 18
    end

    return max(1, floor((constants.NAMEPLATE_HEALTH_FONT_BASE_SIZE * self:GetConfiguredHealthTextScale()) + 0.5))
end

function Nameplates:ApplyConfiguredNameplateHeight(unitFrame)
    if not unitFrame then
        return
    end

    local _, scaledHeight = self:GetConfiguredNameplateSize()

    local healthContainer = unitFrame.HealthBarsContainer
    if healthContainer then
        SafeSetFrameDimension(healthContainer, "SetHeight", scaledHeight)
    end

    local health = unitFrame.healthBar or unitFrame.HealthBar
    if health then
        SafeSetFrameDimension(health, "SetHeight", scaledHeight)
    end
end

function Nameplates:ApplyConfiguredNameplateSize(unitFrame, _nameplate)
    if not unitFrame then
        return
    end

    local outerWidth = self:GetConfiguredNameplateFrameSize()
    -- Keep the per-nameplate size pass local. The global C_NamePlate size API
    -- re-runs Blizzard ApplyFrameOptions/SetUnit for visible nameplates, which
    -- can drive castBar:SetUnit through hostile secret cast state.

    -- Parent NamePlate:SetWidth() is protected in Blizzard secure ApplyFrameOptions flow.
    SafeSetFrameDimension(unitFrame, "SetWidth", outerWidth)

    self:ApplyConfiguredNameplateHeight(unitFrame)
end

function Nameplates:EnsureConfiguredNameplateSizeHooks()
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    local registered = runtime and runtime.nameplateSizeHooksRegistered
    if not registered then
        return
    end

    if not registered.base and _G.NamePlateBaseMixin and _G.NamePlateBaseMixin.ApplyFrameOptions then
        local ok = RefineUI:HookOnce(
            "Nameplates:NamePlateBaseMixin:ApplyFrameOptions:ConfiguredSize",
            _G.NamePlateBaseMixin,
            "ApplyFrameOptions",
            function(nameplateFrame)
                local unitFrame = nameplateFrame and nameplateFrame.UnitFrame
                if unitFrame then
                    self:ApplyConfiguredNameplateSize(unitFrame, nameplateFrame)
                end
            end
        )
        registered.base = ok == true
    end

    if not registered.unit and _G.NamePlateUnitFrameMixin and _G.NamePlateUnitFrameMixin.ApplyFrameOptions then
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
                    self:ApplyConfiguredNameplateSize(unitFrame, nameplate)
                end
            end
        )
        registered.unit = ok == true
    end

    if not registered.anchors and _G.NamePlateUnitFrameMixin and _G.NamePlateUnitFrameMixin.UpdateAnchors then
        local ok = RefineUI:HookOnce(
            "Nameplates:NamePlateUnitFrameMixin:UpdateAnchors:ConfiguredSize",
            _G.NamePlateUnitFrameMixin,
            "UpdateAnchors",
            function(unitFrame)
                if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
                    return
                end
                self:ApplyConfiguredNameplateHeight(unitFrame)
            end
        )
        registered.anchors = ok == true
    end
end

----------------------------------------------------------------------------------------
-- Public API (Compatibility)
----------------------------------------------------------------------------------------
function RefineUI:ApplyNameplateSizeSettings(forceApply)
    if Nameplates and Nameplates.ApplyConfiguredBlizzardNameplateSize then
        Nameplates:ApplyConfiguredBlizzardNameplateSize(forceApply == true)
    end
end
