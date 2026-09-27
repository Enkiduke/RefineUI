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
local type = type
local tonumber = tonumber
local pcall = pcall
local floor = math.floor
local max = math.max
local abs = math.abs

local C_NamePlate = C_NamePlate
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local Private = Nameplates:GetPrivate()
local Constants = Private.Constants
local Runtime = Private.Runtime

local DEFAULT_NAMEPLATE_SCALE = 1
local DEFAULT_NAMEPLATE_WIDTH = 150
local DEFAULT_NAMEPLATE_HEIGHT = 20

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function SafeSetFrameDimension(frame, methodName, value)
    if frame:IsForbidden() then
        return
    end
    pcall(frame[methodName], frame, value)
end

----------------------------------------------------------------------------------------
-- Sizing API
----------------------------------------------------------------------------------------
function Nameplates:GetConfiguredNameplateScale()
    local scale = tonumber(self:GetConfiguredNameplatesConfig().Scale) or DEFAULT_NAMEPLATE_SCALE
    if scale < Constants.NAMEPLATE_TEXT_SCALE_MIN then
        return Constants.NAMEPLATE_TEXT_SCALE_MIN
    end
    if scale > Constants.NAMEPLATE_TEXT_SCALE_MAX then
        return Constants.NAMEPLATE_TEXT_SCALE_MAX
    end
    return scale
end

function Nameplates:GetConfiguredNameplateSize()
    local scale = self:GetConfiguredNameplateScale()
    return RefineUI:Scale(DEFAULT_NAMEPLATE_WIDTH * scale), RefineUI:Scale(DEFAULT_NAMEPLATE_HEIGHT * scale)
end

function Nameplates:GetConfiguredNameplateFrameSize()
    local scaledWidth, scaledHeight = self:GetConfiguredNameplateSize()
    local sideInset = RefineUI:Scale(12)
    return scaledWidth + (sideInset * 2), scaledHeight
end

function Nameplates:ApplyConfiguredBlizzardNameplateSize(forceApply)
    local targetWidth, targetHeight = self:GetConfiguredNameplateFrameSize()
    if not forceApply
        and Runtime.lastAppliedNameplateWidth == targetWidth
        and Runtime.lastAppliedNameplateHeight == targetHeight then
        local ok, currentWidth, currentHeight = pcall(C_NamePlate.GetNamePlateSize)
        if not ok or type(currentWidth) ~= "number" or type(currentHeight) ~= "number"
            or (abs(currentWidth - targetWidth) <= 0.5 and abs(currentHeight - targetHeight) <= 0.5) then
            return true
        end
    end

    if InCombatLockdown() or not pcall(C_NamePlate.SetNamePlateSize, targetWidth, targetHeight) then
        Runtime.pendingNameplateSizeApply = true
        return false
    end

    Runtime.lastAppliedNameplateWidth = targetWidth
    Runtime.lastAppliedNameplateHeight = targetHeight
    Runtime.pendingNameplateSizeApply = false
    return true
end

function Nameplates:IsNameplateSizeApplyPending()
    return Runtime.pendingNameplateSizeApply == true
end

function Nameplates:GetScaledNameplateNameFontSize()
    return max(1, floor((Constants.NAMEPLATE_NAME_FONT_BASE_SIZE * self:GetConfiguredNameplateScale()) + 0.5))
end

function Nameplates:GetScaledNameplateHealthFontSize()
    return max(1, floor((Constants.NAMEPLATE_HEALTH_FONT_BASE_SIZE * self:GetConfiguredNameplateScale()) + 0.5))
end

function Nameplates:ApplyConfiguredNameplateHeight(unitFrame)
    local _, scaledHeight = self:GetConfiguredNameplateSize()

    if unitFrame.HealthBarsContainer then
        SafeSetFrameDimension(unitFrame.HealthBarsContainer, "SetHeight", scaledHeight)
    end

    local health = unitFrame.healthBar or unitFrame.HealthBar
    if health then
        SafeSetFrameDimension(health, "SetHeight", scaledHeight)
    end
end

-- Keep the per-nameplate size pass local. The global C_NamePlate size API re-runs
-- Blizzard ApplyFrameOptions/SetUnit for visible nameplates, which can drive
-- castBar:SetUnit through hostile secret cast state. Parent NamePlate:SetWidth() is
-- protected in Blizzard's secure ApplyFrameOptions flow, so only the unit frame is sized.
function Nameplates:ApplyConfiguredNameplateSize(unitFrame)
    SafeSetFrameDimension(unitFrame, "SetWidth", (self:GetConfiguredNameplateFrameSize()))
    self:ApplyConfiguredNameplateHeight(unitFrame)
end

----------------------------------------------------------------------------------------
-- Public API (Compatibility)
----------------------------------------------------------------------------------------
function RefineUI:ApplyNameplateSizeSettings(forceApply)
    Nameplates:ApplyConfiguredBlizzardNameplateSize(forceApply == true)
end
