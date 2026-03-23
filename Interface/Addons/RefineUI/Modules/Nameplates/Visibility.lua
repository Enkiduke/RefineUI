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
local setmetatable = setmetatable

local UnitIsFriend = UnitIsFriend
local UnitCanAttack = UnitCanAttack

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local EMPTY_TEXT_OPTS = {
    emptyText = "",
}

local function GetUtil()
    local private = Nameplates:GetPrivate()
    return private and private.Util
end

local function ReadAccessibleFrameNumber(frame, methodName)
    if not frame or type(methodName) ~= "string" then
        return nil
    end

    local method = frame[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, value = pcall(method, frame)
    if not ok then
        return nil
    end

    local util = GetUtil()
    if util and (not util.IsAccessibleValue(value) or type(value) ~= "number") then
        return nil
    end

    if type(value) ~= "number" then
        return nil
    end

    return value
end

local function EnsureRaidTargetFrameSize(raidTargetFrame, raidIconSize)
    if not raidTargetFrame or type(raidIconSize) ~= "number" then
        return
    end

    local width = ReadAccessibleFrameNumber(raidTargetFrame, "GetWidth")
    local height = ReadAccessibleFrameNumber(raidTargetFrame, "GetHeight")
    if width ~= raidIconSize or height ~= raidIconSize then
        raidTargetFrame:SetSize(raidIconSize, raidIconSize)
    end
end

local function GetRaidTargetFrame(unitFrame)
    if not unitFrame then
        return nil
    end

    return unitFrame.RaidTargetFrame or unitFrame.raidTargetFrame
end

local function EvaluateNameOnlyFromUnit(unit)
    local util = GetUtil()
    if not util or not util.IsUsableUnitToken(unit) then
        -- Match original behavior for unavailable tokens.
        return true
    end

    local isFriend = false
    local canAttack = false

    local friendValue = util.ReadSafeBoolean(UnitIsFriend("player", unit))
    if friendValue ~= nil then
        isFriend = friendValue
    end

    local attackValue = util.ReadSafeBoolean(UnitCanAttack("player", unit))
    if attackValue ~= nil then
        canAttack = attackValue
    end

    return isFriend or not canAttack
end

local function GetBlizzardNameOnlyState(unitFrame, util)
    if not unitFrame or not util then
        return nil
    end

    if type(unitFrame.IsShowOnlyName) == "function" then
        local ok, isShowOnlyName = pcall(unitFrame.IsShowOnlyName, unitFrame)
        if ok then
            local resolvedShowOnlyName = util.ReadSafeBoolean(isShowOnlyName)
            if resolvedShowOnlyName ~= nil then
                return resolvedShowOnlyName
            end
        end
    end

    local showOnlyName = util.ReadSafeBoolean(unitFrame.showOnlyName)
    if showOnlyName ~= nil then
        return showOnlyName
    end

    local widgetsOnlyMode = util.ReadSafeBoolean(unitFrame.widgetsOnlyMode)
    if widgetsOnlyMode == true then
        return true
    end

    if type(unitFrame.IsSimplified) == "function" then
        local ok, isSimplified = pcall(unitFrame.IsSimplified, unitFrame)
        if ok and util.ReadSafeBoolean(isSimplified) == true then
            return true
        end
    end

    if util.ReadSafeBoolean(unitFrame.isSimplified) == true then
        return true
    end

    local optionTable = unitFrame.optionTable
    if util.ReadSafeBoolean(util.SafeTableIndex(optionTable, "nameOnly")) == true then
        return true
    end
    if util.ReadSafeBoolean(util.SafeTableIndex(optionTable, "showOnlyName")) == true then
        return true
    end

    local healthContainer = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame.HealthBar
    if healthContainer and healthContainer.IsShown and not healthContainer:IsShown() then
        return true
    end

    return nil
end

local function ResolveNameOnlyRaidAnchor(unitFrame, data)
    if data and data.RefineName then
        return data.RefineName
    end

    if unitFrame then
        local name = unitFrame.name or (unitFrame.NameContainer and unitFrame.NameContainer.Name)
        if name then
            return name
        end
    end

    return nil
end

----------------------------------------------------------------------------------------
-- Name-Only API
----------------------------------------------------------------------------------------
function Nameplates:IsNameOnlyNameplateInternal(unitFrame, data, allowCachedState)
    if not unitFrame then
        return false
    end

    local util = GetUtil()
    if not util then
        return false
    end

    local nameOnlyByUnit = EvaluateNameOnlyFromUnit(unitFrame.unit)
    if nameOnlyByUnit then
        return true
    end

    if allowCachedState ~= false and data and data.RefineHidden == true then
        return true
    end

    local nameOnlyState = GetBlizzardNameOnlyState(unitFrame, util)
    if nameOnlyState == true then
        return true
    end

    return false
end

function RefineUI:IsNameOnlyNameplate(unitFrame, data, allowCachedState)
    return Nameplates:IsNameOnlyNameplateInternal(unitFrame, data, allowCachedState)
end

function Nameplates:IsRuntimeSuppressedNameplate(unitFrame, data)
    if not unitFrame then
        return false
    end

    if not data then
        data = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame] or nil
    end

    return data and data.RefineHidden == true or false
end

function RefineUI:IsRuntimeSuppressedNameplate(unitFrame, data)
    return Nameplates:IsRuntimeSuppressedNameplate(unitFrame, data)
end

----------------------------------------------------------------------------------------
-- Raid Icon Anchor API
----------------------------------------------------------------------------------------
function Nameplates:ApplyPortraitRaidIconAnchor(unitFrame, data)
    if not unitFrame or not data then
        return
    end

    local raidTargetFrame = GetRaidTargetFrame(unitFrame)
    if not raidTargetFrame or not raidTargetFrame.ClearAllPoints or not raidTargetFrame.SetPoint then
        return
    end

    local private = self:GetPrivate()
    local constants = private and private.Constants
    local healthContainer = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame.HealthBar or unitFrame
    local healthBar = unitFrame.healthBar or unitFrame.HealthBar or healthContainer
    local anchorTarget = data.HealthBorderOverlay or healthBar or healthContainer
    local raidIconSize = (constants and constants.RAID_ICON_SIZE) or 28

    if raidTargetFrame.SetFrameLevel and healthBar and healthBar.GetFrameLevel then
        local desiredFrameLevel = healthBar:GetFrameLevel() + 5
        local currentFrameLevel = ReadAccessibleFrameNumber(raidTargetFrame, "GetFrameLevel")
        if currentFrameLevel ~= desiredFrameLevel then
            raidTargetFrame:SetFrameLevel(desiredFrameLevel)
        end
    end

    EnsureRaidTargetFrameSize(raidTargetFrame, raidIconSize)

    if anchorTarget then
        raidTargetFrame:ClearAllPoints()
        RefineUI.Point(raidTargetFrame, "CENTER", anchorTarget, "RIGHT", 0, 0)
    end

    data.RaidIconAnchorMode = "portrait"
    data.RaidIconAnchorTarget = anchorTarget

    if raidTargetFrame.UpdateShownState then
        raidTargetFrame:UpdateShownState()
    end
end

function Nameplates:ApplyNameOnlyRaidIconAnchor(unitFrame, data)
    if not unitFrame then
        return
    end

    if not data then
        RefineUI.NameplateData = RefineUI.NameplateData or setmetatable({}, { __mode = "k" })
        data = RefineUI.NameplateData[unitFrame]
        if not data then
            data = {}
            RefineUI.NameplateData[unitFrame] = data
        end
    end

    local nameAnchor = ResolveNameOnlyRaidAnchor(unitFrame, data)
    if not nameAnchor then
        return
    end

    local raidTargetFrame = GetRaidTargetFrame(unitFrame)
    if not raidTargetFrame or not raidTargetFrame.ClearAllPoints or not raidTargetFrame.SetPoint then
        return
    end

    if raidTargetFrame.SetParent and raidTargetFrame.GetParent then
        if raidTargetFrame:GetParent() ~= unitFrame then
            pcall(raidTargetFrame.SetParent, raidTargetFrame, unitFrame)
        end
    end

    local private = self:GetPrivate()
    local constants = private and private.Constants
    local raidIconSize = (constants and constants.RAID_ICON_SIZE) or 28

    EnsureRaidTargetFrameSize(raidTargetFrame, raidIconSize)

    if nameAnchor then
        raidTargetFrame:ClearAllPoints()
        RefineUI.Point(raidTargetFrame, "BOTTOM", nameAnchor, "TOP", 0, 6)
    end

    data.RaidIconAnchorMode = "name"
    data.RaidIconAnchorTarget = nameAnchor

    if raidTargetFrame.UpdateShownState then
        raidTargetFrame:UpdateShownState()
    end
end

function Nameplates:ApplyRaidIconAnchor(unitFrame, data, isNameOnlyOverride)
    if not unitFrame then
        return
    end

    if not data then
        data = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame] or nil
    end

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

function RefineUI:UpdateNameplateRaidIconAnchor(unitFrame, data, isNameOnlyOverride)
    Nameplates:ApplyRaidIconAnchor(unitFrame, data, isNameOnlyOverride)
end

----------------------------------------------------------------------------------------
-- Visibility Pipeline
----------------------------------------------------------------------------------------
function Nameplates:UpdateVisibility(nameplate, unit)
    if not nameplate then
        return
    end

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local data = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame]
    if not data then
        return
    end

    local healthContainer = unitFrame.HealthBarsContainer or unitFrame.healthBar or unitFrame.HealthBar
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
            local castBar = unitFrame.castBar or unitFrame.CastBar
            if castBar then
                if self.SuppressCastBarForNameOnly then
                    self:SuppressCastBarForNameOnly(castBar)
                elseif self.SetCastBarVisualAlpha then
                    self:SetCastBarVisualAlpha(castBar, 0)
                else
                    castBar:SetAlpha(0)
                end
            end

            data.RefineHidden = true
            data.isCasting = false

            if self.UpdateNameplatePortraitModelEvents then
                self:UpdateNameplatePortraitModelEvents(unitFrame, unit, false)
            end

            if self.ClearDeferredPortraitRefreshQueue then
                self:ClearDeferredPortraitRefreshQueue(unitFrame)
            end

            if data.RefineHealth then
                RefineUI:SetFontStringValue(data.RefineHealth, nil, EMPTY_TEXT_OPTS)
                data.RefineHealth:Hide()
            end

            if self.ApplyRefineTextVisibility and self.IsNativeNameShown then
                self:ApplyRefineTextVisibility(data, self:IsNativeNameShown(unitFrame))
            end

            if RefineUI.ClearNameplateCrowdControl then
                RefineUI:ClearNameplateCrowdControl(unitFrame, true)
            end

            if data.PortraitFrame and RefineUI.UpdateDynamicPortrait then
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

        local castBar = unitFrame.castBar or unitFrame.CastBar
        if castBar then
            if self.SetCastBarVisualAlpha then
                self:SetCastBarVisualAlpha(castBar, 1)
            else
                castBar:SetAlpha(1)
            end
        end

        data.RefineHidden = false

        if wasHidden then
            if self.UpdateNameplatePortraitModelEvents then
                self:UpdateNameplatePortraitModelEvents(unitFrame, unit, true)
            end

            if self.UpdateHealth then
                self:UpdateHealth(nameplate, unit)
            end

            if RefineUI.UpdateNameplateCrowdControl then
                RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, "UNIT_FACTION")
            end

            if RefineUI.UpdateDynamicPortrait then
                RefineUI:UpdateDynamicPortrait(nameplate, unit, "UNIT_FACTION")
            end

            if castBar and self.RefreshCastBarForRuntimeMode then
                self:RefreshCastBarForRuntimeMode(castBar)
            end
        end
    end

    if wasHidden ~= data.RefineHidden and RefineUI.UpdateTarget then
        RefineUI:UpdateTarget(unitFrame)
    end

    if self.ApplyNpcTitleVisual then
        self:ApplyNpcTitleVisual(nameplate, unit, { allowResolve = false })
    end
end
