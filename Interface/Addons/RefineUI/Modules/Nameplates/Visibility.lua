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
local function GetUtil()
    local private = Nameplates:GetPrivate()
    return private and private.Util
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
    local healthBar = unitFrame.healthBar or unitFrame.HealthBar or unitFrame

    if raidTargetFrame.SetFrameLevel and healthBar and healthBar.GetFrameLevel then
        raidTargetFrame:SetFrameLevel(healthBar:GetFrameLevel() + 5)
    end

    raidTargetFrame:SetSize((constants and constants.RAID_ICON_SIZE) or 28, (constants and constants.RAID_ICON_SIZE) or 28)
    raidTargetFrame:ClearAllPoints()
    RefineUI.Point(raidTargetFrame, "CENTER", healthBar, "RIGHT", 0, 0)
    data.RaidIconAnchorMode = "portrait"
    data.RaidIconAnchorTarget = healthBar
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

    raidTargetFrame:SetSize(raidIconSize, raidIconSize)
    raidTargetFrame:ClearAllPoints()
    RefineUI.Point(raidTargetFrame, "BOTTOM", nameAnchor, "TOP", 0, 10)
    data.RaidIconAnchorMode = "name"
    data.RaidIconAnchorTarget = nameAnchor
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

        local castBar = unitFrame.castBar or unitFrame.CastBar
        if castBar then
            castBar:SetAlpha(0)
            castBar:Hide()
        end

        if RefineUI.ClearNameplateCrowdControl then
            RefineUI:ClearNameplateCrowdControl(unitFrame, true)
        end

        data.RefineHidden = true
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
        if castBar and castBar:IsShown() then
            castBar:SetAlpha(1)
        elseif castBar and type(castBar.UpdateIsShown) == "function" then
            castBar:UpdateIsShown()
            if castBar:IsShown() then
                castBar:SetAlpha(1)
            end
        end

        data.RefineHidden = false

        if RefineUI.UpdateNameplateCrowdControl then
            RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, "UNIT_FACTION")
        end

        if wasHidden and RefineUI.UpdateDynamicPortrait then
            RefineUI:UpdateDynamicPortrait(nameplate, unit, "UNIT_FACTION")
        end
    end

    if self.ApplyNpcTitleVisual then
        self:ApplyNpcTitleVisual(nameplate, unit, { allowResolve = false })
    end
end
