----------------------------------------------------------------------------------------
-- Nameplates Component: Visibility
-- Description: Name-only detection, raid icon anchoring, and visibility transitions.
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
local pcall = pcall

local UnitIsFriend = UnitIsFriend
local UnitCanAttack = UnitCanAttack

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local Private = Nameplates:GetPrivate()
local Util = Private.Util
local RAID_ICON_SIZE = Private.Constants.RAID_ICON_SIZE

local EMPTY_TEXT_OPTS = {
    emptyText = "",
}

local function ReadAccessibleFrameNumber(frame, methodName)
    local ok, value = pcall(frame[methodName], frame)
    if not ok or not Util.IsAccessibleValue(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

local function EnsureRaidTargetFrameSize(raidTargetFrame)
    local width = ReadAccessibleFrameNumber(raidTargetFrame, "GetWidth")
    local height = ReadAccessibleFrameNumber(raidTargetFrame, "GetHeight")
    if width ~= RAID_ICON_SIZE or height ~= RAID_ICON_SIZE then
        raidTargetFrame:SetSize(RAID_ICON_SIZE, RAID_ICON_SIZE)
    end
end

local function EvaluateNameOnlyFromUnit(unit)
    if not Util.IsUsableUnitToken(unit) then
        return true
    end

    local isFriend = Util.ReadSafeBoolean(UnitIsFriend("player", unit)) == true
    local canAttack = Util.ReadSafeBoolean(UnitCanAttack("player", unit)) == true
    return isFriend or not canAttack
end

local function IsBlizzardNameOnly(unitFrame)
    if unitFrame:IsShowOnlyName() or unitFrame.widgetsOnlyMode == true or unitFrame:IsSimplified() then
        return true
    end

    local healthContainer = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame.HealthBar
    return healthContainer ~= nil and not healthContainer:IsShown()
end

local function UpdateRaidTargetShownState(raidTargetFrame)
    if raidTargetFrame.UpdateShownState then
        raidTargetFrame:UpdateShownState()
    end
end

----------------------------------------------------------------------------------------
-- Name-Only API
----------------------------------------------------------------------------------------
function Nameplates:IsNameOnlyNameplateInternal(unitFrame, data, allowCachedState)
    if not unitFrame then
        return false
    end

    if EvaluateNameOnlyFromUnit(unitFrame.unit) then
        return true
    end

    if allowCachedState ~= false and data and data.RefineHidden == true then
        return true
    end

    return IsBlizzardNameOnly(unitFrame)
end

----------------------------------------------------------------------------------------
-- Raid Icon Anchor API
----------------------------------------------------------------------------------------
function Nameplates:ApplyPortraitRaidIconAnchor(unitFrame, data)
    local raidTargetFrame = unitFrame.RaidTargetFrame
    if not raidTargetFrame then
        return
    end

    local healthBar = unitFrame.healthBar or unitFrame.HealthBar or unitFrame.HealthBarsContainer or unitFrame
    local anchorTarget = data.HealthBorderOverlay or healthBar
    -- Blizzard only re-anchors the icon in UpdateAnchors, whose hook clears the mode.
    if data.RaidIconAnchorMode == "portrait" and data.RaidIconAnchorTarget == anchorTarget then
        return
    end

    local desiredFrameLevel = healthBar:GetFrameLevel() + 5
    if ReadAccessibleFrameNumber(raidTargetFrame, "GetFrameLevel") ~= desiredFrameLevel then
        raidTargetFrame:SetFrameLevel(desiredFrameLevel)
    end

    EnsureRaidTargetFrameSize(raidTargetFrame)

    raidTargetFrame:ClearAllPoints()
    RefineUI.Point(raidTargetFrame, "CENTER", anchorTarget, "RIGHT", 0, 0)

    data.RaidIconAnchorMode = "portrait"
    data.RaidIconAnchorTarget = anchorTarget

    UpdateRaidTargetShownState(raidTargetFrame)
end

function Nameplates:ApplyNameOnlyRaidIconAnchor(unitFrame, data)
    data = data or self:GetNameplateData(unitFrame)

    local nameAnchor = data.RefineName or unitFrame.name
    local raidTargetFrame = unitFrame.RaidTargetFrame
    if not nameAnchor or not raidTargetFrame then
        return
    end
    if data.RaidIconAnchorMode == "name" and data.RaidIconAnchorTarget == nameAnchor then
        return
    end

    if raidTargetFrame:GetParent() ~= unitFrame then
        pcall(raidTargetFrame.SetParent, raidTargetFrame, unitFrame)
    end

    EnsureRaidTargetFrameSize(raidTargetFrame)

    raidTargetFrame:ClearAllPoints()
    RefineUI.Point(raidTargetFrame, "BOTTOM", nameAnchor, "TOP", 0, 6)

    data.RaidIconAnchorMode = "name"
    data.RaidIconAnchorTarget = nameAnchor

    UpdateRaidTargetShownState(raidTargetFrame)
end

function Nameplates:ApplyRaidIconAnchor(unitFrame, data, isNameOnlyOverride)
    if not unitFrame then
        return
    end

    data = data or RefineUI.NameplateData[unitFrame]

    local isNameOnly = isNameOnlyOverride
    if isNameOnly == nil then
        isNameOnly = self:IsNameOnlyNameplateInternal(unitFrame, data)
    end

    if isNameOnly then
        self:ApplyNameOnlyRaidIconAnchor(unitFrame, data)
    elseif data then
        self:ApplyPortraitRaidIconAnchor(unitFrame, data)
    end
end

----------------------------------------------------------------------------------------
-- Visibility Pipeline
----------------------------------------------------------------------------------------
function Nameplates:UpdateVisibility(nameplate, unit)
    local unitFrame = nameplate and nameplate.UnitFrame
    local data = unitFrame and RefineUI.NameplateData[unitFrame]
    if not data then
        return
    end

    local healthContainer = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame.HealthBar
    local castBar = Util.GetNameplateCastBar(unitFrame)
    local isNameOnly = self:IsNameOnlyNameplateInternal(unitFrame, data, false)
    local wasHidden = data.RefineHidden == true

    if isNameOnly then
        if healthContainer then
            healthContainer:SetAlpha(0)
        end
        self:ApplyRaidIconAnchor(unitFrame, data, true)

        if unitFrame.selectionHighlight then
            unitFrame.selectionHighlight:SetAlpha(0)
        end

        if data.PortraitFrame then
            data.PortraitFrame:Hide()
        end

        if not wasHidden then
            -- Set before suppressing the cast bar: its hide path reads this flag.
            data.RefineHidden = true
            data.isCasting = false

            if castBar then
                self:SuppressCastBarForNameOnly(castBar)
            end

            self:UpdateNameplatePortraitModelEvents(unitFrame, unit, false)
            self:ClearDeferredPortraitRefreshQueue(unitFrame)

            if data.RefineHealth then
                RefineUI:SetFontStringValue(data.RefineHealth, nil, EMPTY_TEXT_OPTS)
                data.RefineHealth:Hide()
            end

            self:ApplyRefineTextVisibility(data, self:IsNativeNameShown(unitFrame))
            RefineUI:ClearNameplateCrowdControl(unitFrame)

            if data.PortraitFrame then
                RefineUI:UpdateDynamicPortrait(nameplate, unit, "UNIT_FACTION")
            end
        end
    else
        if healthContainer then
            healthContainer:SetAlpha(1)
        end
        self:ApplyRaidIconAnchor(unitFrame, data, false)

        if unitFrame.selectionHighlight then
            unitFrame.selectionHighlight:SetAlpha(0.25)
        end

        if data.PortraitFrame then
            data.PortraitFrame:Show()
        end

        if castBar then
            self:SetCastBarVisualAlpha(castBar, 1)
        end

        data.RefineHidden = false

        if wasHidden then
            self:UpdateNameplatePortraitModelEvents(unitFrame, unit, true)
            self:UpdateHealth(nameplate, unit)
            RefineUI:UpdateDynamicPortrait(nameplate, unit, "UNIT_FACTION")
            RefineUI:UpdateNameplateCrowdControl(unitFrame, unit)

            if castBar then
                self:RefreshCastBarForRuntimeMode(castBar)
            end
        end
    end

    if wasHidden ~= data.RefineHidden then
        RefineUI:UpdateTarget(unitFrame)
    end

    self:ApplyNpcTitleVisual(nameplate, unit)
end
