----------------------------------------------------------------------------------------
-- Nameplates Component: Common
-- Description: Shared secret-safe helpers for Nameplate modules.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tostring = tostring
local pcall = pcall
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local UnitIsUnit = UnitIsUnit
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local C_NamePlate = C_NamePlate

----------------------------------------------------------------------------------------
-- Shared Utility Table
----------------------------------------------------------------------------------------
RefineUI.NameplatesUtil = RefineUI.NameplatesUtil or {}
local Util = RefineUI.NameplatesUtil
Nameplates.Private = Nameplates.Private or {}
Nameplates.Private.Util = Util

local function CoreIsSecret(v)
    if RefineUI.IsSecretValue then
        return RefineUI:IsSecretValue(v)
    end
    return issecretvalue and issecretvalue(v)
end

local function CoreHasValue(v)
    if RefineUI.HasValue then
        return RefineUI:HasValue(v)
    end
    if CoreIsSecret(v) then
        return true
    end
    return v ~= nil
end

function Util.IsSecret(v)
    return CoreIsSecret(v)
end

function Util.HasValue(v)
    return CoreHasValue(v)
end

function Util.IsAccessibleValue(v)
    if CoreIsSecret(v) then
        return false
    end
    if v ~= nil and canaccessvalue and not canaccessvalue(v) then
        return false
    end
    return true
end

function Util.ReadSafeBoolean(v)
    if not Util.IsAccessibleValue(v) then
        return nil
    end
    local valueType = type(v)
    if valueType == "boolean" then
        return v
    end
    if valueType == "number" then
        return v ~= 0
    end
    return nil
end

function Util.ReadAccessibleValue(v, fallback)
    if Util.IsAccessibleValue(v) then
        return v
    end
    return fallback
end

function Util.IsUsableUnitToken(unit)
    if unit == nil then return false end
    if CoreIsSecret(unit) then return false end
    if canaccessvalue and not canaccessvalue(unit) then return false end
    if type(unit) ~= "string" then return false end
    return true
end

function Util.IsDisallowedNameplateUnitToken(unit)
    if not Util.IsUsableUnitToken(unit) then
        return true
    end

    if unit:match("^boss%d") then
        return true
    end

    return false
end

function Util.ResolveUnitToken(unit, fallbackUnit)
    if Util.IsUsableUnitToken(unit) then
        return unit
    end
    if Util.IsUsableUnitToken(fallbackUnit) then
        return fallbackUnit
    end
    return nil
end

function Util.SafeUnitIsUnit(unitA, unitB)
    if not Util.IsUsableUnitToken(unitA) or not Util.IsUsableUnitToken(unitB) then
        return false
    end
    if type(UnitIsUnit) ~= "function" then
        return false
    end
    return Util.ReadSafeBoolean(UnitIsUnit(unitA, unitB)) == true
end

function Util.IsTargetNameplateUnitFrame(unitFrame)
    if not unitFrame or type(unitFrame) ~= "table" then
        return false
    end

    if type(unitFrame.IsTarget) == "function" then
        local ok, isTarget = pcall(unitFrame.IsTarget, unitFrame)
        if ok then
            local resolvedTarget = Util.ReadSafeBoolean(isTarget)
            if resolvedTarget ~= nil then
                return resolvedTarget
            end
        end
    end

    local isTarget = Util.ReadSafeBoolean(unitFrame.isTarget)
    if isTarget ~= nil then
        return isTarget
    end

    if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
        local ok, targetNameplate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if (not ok or not targetNameplate) then
            ok, targetNameplate = pcall(C_NamePlate.GetNamePlateForUnit, "target", true)
        end
        if ok and targetNameplate and targetNameplate.UnitFrame == unitFrame then
            return true
        end
        -- If nameplate API is available and didn't match this frame, treat as non-target.
        return false
    end

    return Util.SafeUnitIsUnit("target", unitFrame.unit)
end

function Util.SafeTableIndex(tbl, key)
    if not Util.IsAccessibleValue(tbl) then
        return nil
    end

    local ok, value = pcall(function()
        return tbl[key]
    end)
    if not ok then
        return nil
    end
    return value
end

function Util.GetHookOwnerId(owner)
    if type(owner) == "table" and owner.GetName then
        local name = owner:GetName()
        if name and name ~= "" then
            return name
        end
    end
    return tostring(owner)
end

function Util.BuildHookKey(prefix, owner, method)
    local keyPrefix = prefix
    if type(keyPrefix) ~= "string" or keyPrefix == "" then
        keyPrefix = "Nameplates"
    end
    return keyPrefix .. ":" .. Util.GetHookOwnerId(owner) .. ":" .. tostring(method)
end

--- Shared Cast-Active Check ---------------------------------------------------
-- Canonical implementation: CastBars and CrowdControl delegate to this.
-- @param unit   string|nil  – nameplate unit token
-- @param castBar  StatusBar|nil – castBar frame (resolve from unitFrame before calling)
-- @return boolean
function Util.IsCastActive(unit, castBar)
    if castBar and castBar.IsShown and castBar:IsShown() then
        if Util.ReadSafeBoolean(castBar.casting) == true then return true end
        if Util.ReadSafeBoolean(castBar.channeling) == true then return true end
        if Util.ReadSafeBoolean(castBar.reverseChanneling) == true then return true end

        local barType = castBar.barType
        if Util.IsAccessibleValue(barType) and type(barType) == "string" and barType ~= "" and barType ~= "interrupted" then
            return true
        end
    end

    if Util.IsUsableUnitToken(unit) then
        local castName = UnitCastingInfo(unit)
        if Util.HasValue(castName) then
            return true
        end

        castName = UnitChannelInfo(unit)
        if Util.HasValue(castName) then
            return true
        end
    end

    return false
end

--- Cast-Bar-Only Check (no unit API fallback) ---------------------------------
-- For CrowdControl HideWhileCasting: avoids false positives from stale/secret
-- UnitCastingInfo during interrupt transitions.
-- @param castBar  StatusBar|nil
-- @return boolean
function Util.IsCastBarActive(castBar)
    if not castBar or not castBar.IsShown or not castBar:IsShown() then
        return false
    end

    if Util.ReadSafeBoolean(castBar.casting) == true then return true end
    if Util.ReadSafeBoolean(castBar.channeling) == true then return true end
    if Util.ReadSafeBoolean(castBar.reverseChanneling) == true then return true end

    local barType = castBar.barType
    if Util.IsAccessibleValue(barType) and type(barType) == "string" and barType ~= "" and barType ~= "interrupted" then
        return true
    end

    return false
end

function Util.GetNameplateFromUnitFrame(unitFrame)
    if not unitFrame or type(unitFrame) ~= "table" then
        return nil
    end
    if type(unitFrame.GetParent) ~= "function" then
        return nil
    end

    local ok, parent = pcall(unitFrame.GetParent, unitFrame)
    if not ok or not parent then
        return nil
    end
    if parent.UnitFrame ~= unitFrame then
        return nil
    end

    return parent
end

local function IsComparableVisualSignature(signature)
    return type(signature) == "string" and signature ~= ""
end

local function AreComparableVisualSignaturesEqual(left, right)
    if not IsComparableVisualSignature(left) or not IsComparableVisualSignature(right) then
        return false
    end
    return left == right
end

-- Centralized cross-module visual refresh entry point for nameplate unit frames.
-- opts:
--   refreshCrowdControl: bool -> refresh CC model/state, suppressing CC-local portrait/border refresh
--   refreshBorders:      bool -> refresh border colors
--   refreshPortrait:     bool -> refresh dynamic portrait
--   forceCastCheck:      bool|nil -> forwarded to UpdateBorderColors
function RefineUI:RefreshNameplateVisualState(unitFrame, unit, event, opts)
    if not unitFrame then
        return
    end

    opts = opts or {}
    local resolvedUnit = Util.ResolveUnitToken(unit, unitFrame.unit)
    local data = self.NameplateData and self.NameplateData[unitFrame] or nil
    -- When portrait and borders refresh together, let the shared orchestrator own
    -- the final border pass so portrait updates do not immediately recompute it again.
    local suppressPortraitBorderRefresh = opts.refreshPortrait == true and opts.refreshBorders == true
    local suppressData = suppressPortraitBorderRefresh and data or nil
    local crowdControlSignatureBefore = data and data.CrowdControlVisualSignature or nil
    local refreshCrowdControl = opts.refreshCrowdControl == true
    local refreshPortrait = opts.refreshPortrait == true
    local refreshBorders = opts.refreshBorders == true

    if refreshCrowdControl and self.UpdateNameplateCrowdControl then
        -- Suppress CC-local portrait/border fan-out; caller owns visual orchestration.
        self:UpdateNameplateCrowdControl(unitFrame, resolvedUnit, event, true)
    end

    local crowdControlSignatureAfter = data and data.CrowdControlVisualSignature or nil
    local crowdControlChanged = not AreComparableVisualSignaturesEqual(crowdControlSignatureBefore, crowdControlSignatureAfter)

    if refreshPortrait and self.UpdateDynamicPortrait then
        local portraitData = suppressData or data
        if not (portraitData and portraitData.RefineHidden == true) then
            local comparablePortraitSignature = self.GetPredictedNameplatePortraitVisualSignature
                and self:GetPredictedNameplatePortraitVisualSignature(unitFrame, resolvedUnit, event)
                or nil
            local shouldSkipPortraitRefresh = (not crowdControlChanged)
                and data ~= nil
                and AreComparableVisualSignaturesEqual(comparablePortraitSignature, data.PortraitVisualSignature)

            if not shouldSkipPortraitRefresh then
                local portraitUnit = resolvedUnit
                if not Util.IsUsableUnitToken(portraitUnit) then
                    portraitUnit = unitFrame.unit
                end
                if Util.IsUsableUnitToken(portraitUnit) then
                    local nameplate = Util.GetNameplateFromUnitFrame(unitFrame)
                    if nameplate then
                        if suppressData then
                            suppressData.SuppressPortraitBorderRefresh = true
                        end
                        self:UpdateDynamicPortrait(nameplate, portraitUnit, event)
                        if suppressData then
                            suppressData.SuppressPortraitBorderRefresh = nil
                        end
                    end
                end
            end
        end
    end

    if refreshBorders and self.UpdateBorderColors then
        local comparableBorderSignature = self.GetPredictedNameplateBorderVisualSignature
            and self:GetPredictedNameplateBorderVisualSignature(unitFrame, opts.forceCastCheck)
            or nil
        local shouldSkipBorderRefresh = (not crowdControlChanged)
            and data ~= nil
            and AreComparableVisualSignaturesEqual(comparableBorderSignature, data.BorderVisualSignature)

        if not shouldSkipBorderRefresh then
            self:UpdateBorderColors(unitFrame, opts.forceCastCheck)
        end
    end
end
