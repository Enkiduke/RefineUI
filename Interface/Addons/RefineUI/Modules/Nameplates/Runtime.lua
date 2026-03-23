----------------------------------------------------------------------------------------
-- Nameplates Component: Runtime
-- Description: Event wiring, CVar automation, hooks, and startup orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local max = math.max
local pcall = pcall
local wipe = table.wipe
local tinsert = table.insert

local C_NamePlate = C_NamePlate
local C_NamePlateManager = C_NamePlateManager
local C_CVar = C_CVar
local Enum = Enum
local SetCVar = SetCVar
local GetCVar = GetCVar
local IsInInstance = IsInInstance
local UnitInBattleground = UnitInBattleground
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsPlayer = UnitIsPlayer
local CreateColor = CreateColor

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local HOOK_KEY = {
    UPDATE_NAME = "Nameplates:CompactUnitFrame_UpdateName",
    UPDATE_HEALTH = "Nameplates:CompactUnitFrame_UpdateHealth",
    UPDATE_HEALTH_COLOR = "Nameplates:CompactUnitFrame_UpdateHealthColor",
    UPDATE_RAID_TARGET_ICON = "Nameplates:CompactUnitFrame_UpdateRaidTargetIcon",
    MIXIN_ON_UNIT_CLEARED = "Nameplates:NamePlateUnitFrameMixin:OnUnitCleared",
    MIXIN_UPDATE_IS_TARGET = "Nameplates:NamePlateUnitFrameMixin:UpdateIsTarget",
    MIXIN_UPDATE_RAID_TARGET_ANCHOR = "Nameplates:NamePlateUnitFrameMixin:UpdateRaidTarget:Anchor",
    MIXIN_UPDATE_ANCHORS_RAID_ANCHOR = "Nameplates:NamePlateUnitFrameMixin:UpdateAnchors:RaidAnchor",
    AURA_ITEM_SET_AURA = "Nameplates:NamePlateAuraItemMixin:SetAura",
    AURAS_REFRESH = "Nameplates:NamePlateAurasMixin:RefreshAuras",
    AURAS_REFRESH_LIST = "Nameplates:NamePlateAurasMixin:RefreshList",
}

local EVENT_KEY = {
    UNIT_ADDED = "Nameplates:UnitAdded",
    UNIT_REMOVED = "Nameplates:UnitRemoved",
    UNIT_STATE = "Nameplates:UnitState",
    THREAT_ROLE = "Nameplates:ThreatRole",
    CVAR_STATE = "Nameplates:CVarState",
    NAME_RULE_CVAR = "Nameplates:NameRuleCVar",
}

local EVENT_LIST = {
    UNIT_STATE = { "UNIT_FACTION", "UNIT_FLAGS" },
    THREAT_ROLE = { "PLAYER_ENTERING_WORLD", "PLAYER_ROLES_ASSIGNED", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "GROUP_ROSTER_UPDATE" },
    CVAR_STATE = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" },
}

local TIMER_KEY = {
    DEFERRED_AURA_LAYOUT = "Nameplates:DeferredAuraLayout:",
    DEFERRED_AURA_VISUALS = "Nameplates:DeferredAuraVisuals:",
}

local NAME_RULE_CVAR = {
    UnitNameEnemyMinionName = true,
    UnitNameEnemyPlayerName = true,
    UnitNameFocused = true,
    UnitNameFriendlyMinionName = true,
    UnitNameFriendlyPlayerName = true,
    UnitNameFriendlySpecialNPCName = true,
    UnitNameHostleNPC = true,
    UnitNameInteractiveNPC = true,
    UnitNameNPC = true,
}

local EMPTY_TEXT_OPTS = {
    emptyText = "",
}

----------------------------------------------------------------------------------------
-- Shared Runtime Helpers
----------------------------------------------------------------------------------------
local GetAuraItemUnitFrame
local GetEnemyAuraLayoutConfig
local IsFriendlyAuraLayoutUnitFrame
local GetScaledAuraLayoutOffset

local function IsRuntimeSuppressedNameplate(unitFrame, data)
    if not unitFrame then
        return false
    end

    if RefineUI.IsRuntimeSuppressedNameplate then
        return RefineUI:IsRuntimeSuppressedNameplate(unitFrame, data)
    end

    if not data then
        data = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame] or nil
    end

    return data and data.RefineHidden == true or false
end

local function UpdateTargetUnitFrame(unitFrame)
    if not unitFrame or not RefineUI.UpdateTarget then
        return
    end
    RefineUI:UpdateTarget(unitFrame)
end

local function QueueEnemyAuraLayoutRefresh(unitFrame)
    if not unitFrame or not RefineUI.After then
        return
    end

    local timerKey = TIMER_KEY.DEFERRED_AURA_LAYOUT .. tostring(unitFrame)
    RefineUI:After(timerKey, 0, function()
        if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
            return
        end

        Nameplates:RefreshEnemyAuraLayout(unitFrame)
    end)
end

local function GetAuraVisualInset(auraItemFrame, unitFrame)
    if not auraItemFrame or not unitFrame then
        return 0
    end

    local private = Nameplates:GetPrivate()
    local util = private and private.Util
    if not util or IsFriendlyAuraLayoutUnitFrame(unitFrame, util) ~= false then
        return 0
    end

    local aurasFrame = unitFrame.AurasFrame
    if not aurasFrame then
        return 0
    end

    local auraConfig = GetEnemyAuraLayoutConfig()
    if not auraConfig then
        return 0
    end

    local parent = auraItemFrame:GetParent()
    if parent == aurasFrame.DebuffListFrame then
        return max(0, GetScaledAuraLayoutOffset(auraConfig.DebuffSpacing, 2) * 0.5)
    end

    if parent == aurasFrame.BuffListFrame then
        return max(0, GetScaledAuraLayoutOffset(auraConfig.BuffSpacing, 2) * 0.5)
    end

    return 0
end

local function ApplyAuraVisualState(auraItemFrame, aura)
    if not auraItemFrame then
        return
    end

    local private = Nameplates:GetPrivate()
    local util = private and private.Util
    if not util then
        return
    end

    local unitFrame = GetAuraItemUnitFrame(auraItemFrame)
    if IsRuntimeSuppressedNameplate(unitFrame) then
        return
    end

    Nameplates:SkinNamePlateAura(auraItemFrame, GetAuraVisualInset(auraItemFrame, unitFrame))

    if not auraItemFrame.border then
        return
    end

    local isHelpful = util.SafeTableIndex(aura, "isHelpful")
    if util.IsSecret(isHelpful) then
        local borderColor = Config.General.BorderColor
        local buffColor = CreateColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        local debuffColor = CreateColor(0.8, 0.1, 0.1, 1)
        local curveUtil = _G.C_CurveUtil
        if curveUtil and type(curveUtil.EvaluateColorFromBoolean) == "function" then
            local finalColor = curveUtil.EvaluateColorFromBoolean(isHelpful, buffColor, debuffColor)
            auraItemFrame.border:SetBackdropBorderColor(finalColor:GetRGBA())
        else
            auraItemFrame.border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
        return
    end

    if isHelpful then
        local borderColor = Config.General.BorderColor
        auraItemFrame.border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        return
    end

    local r, g, b = 0.8, 0.1, 0.1
    local dispelName = util.SafeTableIndex(aura, "dispelName")
    if dispelName and _G.DebuffTypeColor then
        local color = _G.DebuffTypeColor[dispelName]
        if color then
            r, g, b = color.r, color.g, color.b
        end
    end

    auraItemFrame.border:SetBackdropBorderColor(r, g, b)
end

local function QueueAuraVisualRefresh(auraItemFrame, aura)
    if not auraItemFrame or not RefineUI.After then
        return
    end

    local auraInstanceID = aura and aura.auraInstanceID
    local timerKey = TIMER_KEY.DEFERRED_AURA_VISUALS .. tostring(auraItemFrame)
    RefineUI:After(timerKey, 0, function()
        if not auraItemFrame or (auraItemFrame.IsForbidden and auraItemFrame:IsForbidden()) then
            return
        end

        if auraInstanceID ~= nil and auraItemFrame.auraInstanceID ~= auraInstanceID then
            return
        end

        ApplyAuraVisualState(auraItemFrame, aura)
    end)
end

local function ResetPooledNameplateFrameState(unitFrame)
    if not unitFrame then
        return
    end

    local data = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame]
    if not data then
        return
    end

    if data.EventFrame then
        data.EventFrame:UnregisterAllEvents()
    end

    if data.RefineName and data.RefineName.SetText then
        data.RefineName:SetText("")
        data.RefineName:Hide()
    end

    if data.RefineHealth then
        RefineUI:SetFontStringValue(data.RefineHealth, nil, EMPTY_TEXT_OPTS)
        data.RefineHealth:Hide()
    end

    if data.RefineNpcTitle then
        Nameplates:SetNpcTitleText(data, nil)
    end

    data.EventFrameUnit = nil
    data.NameSource = nil
    data.RefineHidden = nil
    data.RefineNpcTitleAnchor = nil
    data.RefineNpcTitleFormatted = nil
    data.RefineNameText = nil
    data.RaidIconAnchorMode = nil
    data.RaidIconAnchorTarget = nil
    data.isTarget = nil
    data.isCasting = nil
    data.isPlayer = nil
    data.inCombat = nil
    data.LastImportantCastSpellIdentifier = nil
    data.LastImportantCastIsImportant = nil
    data.lastPortraitGUID = nil
    data.lastPortraitMode = nil
    data.PortraitVisualSignature = nil
    data.BorderVisualSignature = nil
    data.CrowdControlVisualSignature = nil
    data.wasCasting = nil
    data.CrowdControlAuraDurationSeconds = nil
    data.CrowdControlExpirationTime = nil
    data._borderColorDirty = nil
    data._borderColorForceCastCheck = nil
    data.SuppressPortraitBorderRefresh = nil
    data.lastTargetNameOnly = nil
    data.TargetArrowsShown = nil
    data.TargetArrowLeftShown = nil
    data.TargetArrowAnchor = nil
    data.TargetArrowRightOffset = nil
    data.TargetArrowNameOnly = nil
end

GetAuraItemUnitFrame = function(auraFrame)
    if not auraFrame or not auraFrame.GetParent then
        return nil
    end

    local listFrame = auraFrame:GetParent()
    local aurasMixin = listFrame and listFrame.GetParent and listFrame:GetParent() or nil
    local unitFrame = aurasMixin and aurasMixin.GetParent and aurasMixin:GetParent() or nil
    if unitFrame and not unitFrame.unit and unitFrame.GetParent then
        unitFrame = unitFrame:GetParent()
    end

    return unitFrame
end

GetEnemyAuraLayoutConfig = function()
    local nameplatesConfig = Config and Config.Nameplates
    return nameplatesConfig and nameplatesConfig.EnemyAuras or nil
end

local function ReadAuraLayoutNumber(value, defaultValue)
    local number = tonumber(value)
    if number == nil then
        number = defaultValue
    end
    return number
end

GetScaledAuraLayoutOffset = function(value, defaultValue)
    return RefineUI:Scale(ReadAuraLayoutNumber(value, defaultValue))
end

local function GetAccessiblePositiveNumber(value)
    local private = Nameplates:GetPrivate()
    local util = private and private.Util
    if not util or not util.IsAccessibleValue or not util.IsAccessibleValue(value) then
        return nil
    end

    if type(value) ~= "number" or value <= 0 then
        return nil
    end

    return value
end

IsFriendlyAuraLayoutUnitFrame = function(unitFrame, util)
    if not unitFrame or not util then
        return nil
    end

    local isFriend
    if type(unitFrame.IsFriend) == "function" then
        local ok, friend = pcall(unitFrame.IsFriend, unitFrame)
        if ok then
            isFriend = util.ReadSafeBoolean(friend)
        end
    end

    if isFriend == nil then
        isFriend = util.ReadSafeBoolean(unitFrame.isFriend)
    end

    return isFriend
end

local function GetRefineAuraBaseYOffset(data, auraConfig)
    local nameHeight = 0
    local refineName = data and data.RefineName
    if refineName and refineName.IsShown and refineName:IsShown() then
        local resolvedHeight
        if refineName.GetStringHeight then
            resolvedHeight = refineName:GetStringHeight()
        end
        resolvedHeight = GetAccessiblePositiveNumber(resolvedHeight)
        if not resolvedHeight then
            resolvedHeight = refineName.GetHeight and refineName:GetHeight() or 0
        end
        resolvedHeight = GetAccessiblePositiveNumber(resolvedHeight)
        if resolvedHeight then
            nameHeight = resolvedHeight
        end
    end

    return nameHeight + GetScaledAuraLayoutOffset(auraConfig and auraConfig.BaseOffsetY, 6)
end

local function ApplyAuraListAnchor(listFrame, anchorPoint, anchorTarget, relativePoint, xOffset, yOffset)
    if not listFrame or not anchorTarget then
        return
    end

    listFrame:ClearAllPoints()
    listFrame:SetPoint(anchorPoint, anchorTarget, relativePoint, xOffset, yOffset)
end

local function ApplyAuraListSpacing(listFrame, spacing)
    -- Blizzard's GridLayoutFrame reads childXPadding during secure aura layout.
    -- Writing that Lua field from addon code taints later layout/measurement paths.
    -- Enemy aura spacing is applied visually per aura item instead of mutating the
    -- Blizzard-owned grid configuration.
end

function Nameplates:RefreshEnemyAuraLayout(unitFrame)
    if not unitFrame then
        return
    end

    local private = self:GetPrivate()
    local util = private and private.Util
    local auraConfig = GetEnemyAuraLayoutConfig()
    if not util or not auraConfig then
        return
    end

    local data = self:GetNameplateData(unitFrame)
    if IsRuntimeSuppressedNameplate(unitFrame, data) then
        return
    end

    local isFriend = IsFriendlyAuraLayoutUnitFrame(unitFrame, util)
    if isFriend ~= false then
        return
    end

    local aurasFrame = unitFrame.AurasFrame
    local health = unitFrame.healthBar or unitFrame.HealthBar
    if not aurasFrame or not health then
        return
    end

    local baseYOffset = GetRefineAuraBaseYOffset(data, auraConfig)

    local debuffListFrame = aurasFrame.DebuffListFrame
    if debuffListFrame then
        ApplyAuraListAnchor(
            debuffListFrame,
            "BOTTOMLEFT",
            health,
            "TOPLEFT",
            GetScaledAuraLayoutOffset(auraConfig.DebuffOffsetX, 0),
            baseYOffset + GetScaledAuraLayoutOffset(auraConfig.DebuffOffsetY, 0)
        )
        ApplyAuraListSpacing(debuffListFrame, GetScaledAuraLayoutOffset(auraConfig.DebuffSpacing, 2))
    end

    local buffListFrame = aurasFrame.BuffListFrame
    if buffListFrame then
        ApplyAuraListAnchor(
            buffListFrame,
            "BOTTOMRIGHT",
            health,
            "TOPRIGHT",
            GetScaledAuraLayoutOffset(auraConfig.BuffOffsetX, 0),
            baseYOffset + GetScaledAuraLayoutOffset(auraConfig.BuffOffsetY, 0)
        )
        ApplyAuraListSpacing(buffListFrame, GetScaledAuraLayoutOffset(auraConfig.BuffSpacing, 2))
    end
end

function RefineUI:RefreshAllNameplateAuraAnchors(_reason)
    local private = Nameplates:GetPrivate()
    local activeNameplates = private and private.ActiveNameplates or {}

    for nameplate in pairs(activeNameplates) do
        local unitFrame = nameplate and nameplate.UnitFrame
        if unitFrame then
            Nameplates:RefreshEnemyAuraLayout(unitFrame)
        end
    end
end

----------------------------------------------------------------------------------------
-- CVar Helpers
----------------------------------------------------------------------------------------
local function SetCVarIfChanged(cvar, value)
    local desired = tostring(value)
    local current = GetCVar and GetCVar(cvar)
    if current ~= desired then
        if C_CVar and type(C_CVar.SetCVar) == "function" then
            pcall(C_CVar.SetCVar, cvar, desired)
        else
            pcall(SetCVar, cvar, desired)
        end
    end
end

function Nameplates:EnsureSimplifiedNameplatesDisabled()
    if not C_NamePlateManager or not C_NamePlateManager.SetNamePlateSimplified then
        return
    end

    local nameplateType = Enum and Enum.NamePlateType
    if not nameplateType then
        return
    end

    pcall(C_NamePlateManager.SetNamePlateSimplified, nameplateType.Friendly, false)
    pcall(C_NamePlateManager.SetNamePlateSimplified, nameplateType.Enemy, false)
end

function Nameplates:IsInGroupInstanceContent()
    local private = self:GetPrivate()
    local util = private and private.Util
    if not util then
        return false
    end

    local _, instanceType = IsInInstance()
    if instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena" then
        return true
    end

    local inBattleground = util.ReadSafeBoolean(UnitInBattleground("player"))
    return inBattleground == true
end

function Nameplates:UpdateNameplateCVars(forceApply)
    local private = self:GetPrivate()
    local util = private and private.Util
    local runtime = private and private.Runtime
    if not runtime or not util then
        return
    end

    self:EnsureSimplifiedNameplatesDisabled()
    self:ApplyThreatDisplayCVarFromConfig()

    local inCombat = util.ReadSafeBoolean(UnitAffectingCombat("player"))
    if inCombat == nil then
        inCombat = false
    end

    local inGroupContent = self:IsInGroupInstanceContent()
    local cfg = self:GetConfiguredNameplatesConfig()
    local showPetNames = cfg and cfg.ShowPetNames == true

    local lastState = runtime.lastCVarState
    if (not forceApply)
        and lastState.inCombat == inCombat
        and lastState.inGroupContent == inGroupContent
        and lastState.showPetNames == showPetNames then
        return
    end

    lastState.inCombat = inCombat
    lastState.inGroupContent = inGroupContent
    lastState.showPetNames = showPetNames

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

----------------------------------------------------------------------------------------
-- Deferred Refresh Queue (Portrait)
----------------------------------------------------------------------------------------
function Nameplates:SetPortraitRefreshJobEnabled(enabled)
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    local constants = private and private.Constants
    if not runtime or not constants then
        return
    end

    if not RefineUI.SetUpdateJobEnabled then
        return
    end

    RefineUI:SetUpdateJobEnabled(constants.PORTRAIT_REFRESH_JOB_KEY, enabled == true, false)
end

function Nameplates:EnsurePortraitRefreshJob()
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    local constants = private and private.Constants
    if not runtime or not constants then
        return false
    end

    if not RefineUI.RegisterUpdateJob then
        return false
    end

    if RefineUI.IsUpdateJobRegistered and RefineUI:IsUpdateJobRegistered(constants.PORTRAIT_REFRESH_JOB_KEY) then
        return true
    end

    local interval = constants.PORTRAIT_REFRESH_INTERVAL_SECONDS or 0.03
    RefineUI:RegisterUpdateJob(
        constants.PORTRAIT_REFRESH_JOB_KEY,
        interval,
        function()
            Nameplates:DrainDeferredPortraitRefreshQueue()
        end,
        {
            enabled = false,
            safe = true,
            disableOnError = true,
        }
    )

    return true
end

function Nameplates:ClearDeferredPortraitRefreshQueue(unitFrame)
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    if not runtime then
        return
    end

    if unitFrame then
        local queued = runtime.pendingPortraitRefreshByFrame[unitFrame]
        if queued then
            queued.cancelled = true
            runtime.pendingPortraitRefreshByFrame[unitFrame] = nil
        end
        return
    end

    wipe(runtime.pendingPortraitRefreshQueue)
    wipe(runtime.pendingPortraitRefreshByFrame)
    runtime.pendingPortraitRefreshHead = 1
    self:SetPortraitRefreshJobEnabled(false)
end

function Nameplates:QueuePortraitRefresh(unitFrame, unit, event)
    if not unitFrame or not RefineUI.UpdateDynamicPortrait then
        return
    end

    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    local util = private and private.Util
    if not runtime or not util then
        return
    end

    local data = self:GetNameplateData(unitFrame)
    if IsRuntimeSuppressedNameplate(unitFrame, data) then
        return
    end

    local resolvedUnit = util.ResolveUnitToken(unit, unitFrame.unit)
    if not resolvedUnit then
        return
    end

    if not self:EnsurePortraitRefreshJob() then
        local nameplate = unitFrame.GetParent and unitFrame:GetParent() or nil
        if nameplate and nameplate.UnitFrame == unitFrame then
            RefineUI:UpdateDynamicPortrait(nameplate, resolvedUnit, event)
        end
        return
    end

    local queued = runtime.pendingPortraitRefreshByFrame[unitFrame]
    if queued then
        queued.unit = resolvedUnit
        queued.event = event or queued.event
        queued.cancelled = false
        return
    end

    local entry = {
        unitFrame = unitFrame,
        unit = resolvedUnit,
        event = event,
        cancelled = false,
    }
    runtime.pendingPortraitRefreshByFrame[unitFrame] = entry
    tinsert(runtime.pendingPortraitRefreshQueue, entry)
    self:SetPortraitRefreshJobEnabled(true)
end

function Nameplates:DrainDeferredPortraitRefreshQueue()
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    local constants = private and private.Constants
    local util = private and private.Util
    if not runtime or not constants or not util then
        return
    end

    local queue = runtime.pendingPortraitRefreshQueue
    local head = runtime.pendingPortraitRefreshHead or 1
    local tail = #queue
    if head > tail then
        wipe(queue)
        runtime.pendingPortraitRefreshHead = 1
        self:SetPortraitRefreshJobEnabled(false)
        return
    end

    local budget = constants.PORTRAIT_REFRESH_BUDGET_PER_TICK or 6
    local processed = 0
    while processed < budget and head <= tail do
        local entry = queue[head]
        queue[head] = nil
        head = head + 1

        if entry and entry.unitFrame then
            runtime.pendingPortraitRefreshByFrame[entry.unitFrame] = nil

            if not entry.cancelled then
                local unitFrame = entry.unitFrame
                local nameplate = unitFrame.GetParent and unitFrame:GetParent() or nil
                if nameplate and nameplate.UnitFrame == unitFrame then
                    local unit = util.ResolveUnitToken(entry.unit, unitFrame.unit)
                    if unit then
                        RefineUI:UpdateDynamicPortrait(nameplate, unit, entry.event)
                    end
                end
            end
        end

        processed = processed + 1
    end

    runtime.pendingPortraitRefreshHead = head
    if head > tail then
        wipe(queue)
        runtime.pendingPortraitRefreshHead = 1
        self:SetPortraitRefreshJobEnabled(false)
    else
        self:SetPortraitRefreshJobEnabled(true)
    end
end

----------------------------------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------------------------------
function Nameplates:OnNameplateAdded(event, unit)
    local private = self:GetPrivate()
    local util = private and private.Util
    local activeNameplates = private and private.ActiveNameplates
    local runtime = private and private.Runtime
    if not util or not activeNameplates then
        return
    end

    local safeUnit = util.ResolveUnitToken(unit)
    if not safeUnit then
        return
    end

    self:EnsureConfiguredNameplateSizeHooks()

    local nameplate = self:SafeGetNamePlateForUnit(safeUnit)
    if not nameplate then
        return
    end

    if nameplate.UnitFrame then
        local data = self:GetNameplateData(nameplate.UnitFrame)
        if util.IsUsableUnitToken(safeUnit) then
            data.isPlayer = util.ReadSafeBoolean(UnitIsPlayer(safeUnit)) == true
        end
    end

    activeNameplates[nameplate] = safeUnit

    self:StyleNameplate(nameplate, safeUnit)
    self:UpdateVisibility(nameplate, safeUnit)
    self:ApplyNpcTitleVisual(nameplate, safeUnit, { allowResolve = true })

    local unitFrame = nameplate.UnitFrame
    local data = unitFrame and self:GetNameplateData(unitFrame) or nil
    local isNameOnly = data and data.RefineHidden == true

    if not isNameOnly and RefineUI.UpdateNameplateCrowdControl then
        RefineUI:UpdateNameplateCrowdControl(unitFrame, safeUnit, event)
    end

    if data then
        data.lastPortraitGUID = nil
        data.lastPortraitMode = nil
        data.PortraitVisualSignature = nil
        data.BorderVisualSignature = nil
        data.wasCasting = false
    end

    if (not isNameOnly) and RefineUI.UpdateDynamicPortrait then
        RefineUI:UpdateDynamicPortrait(nameplate, safeUnit)
    end

    if unitFrame then
        UpdateTargetUnitFrame(unitFrame)
    end
end

function Nameplates:OnNameplateRemoved(_event, unit)
    local private = self:GetPrivate()
    local util = private and private.Util
    local activeNameplates = private and private.ActiveNameplates
    local runtime = private and private.Runtime
    if not util or not activeNameplates then
        return
    end

    if not util.IsUsableUnitToken(unit) then
        return
    end

    local removedUnitFrame = nil
    for nameplate, unitToken in pairs(activeNameplates) do
        if util.IsUsableUnitToken(unitToken) and unitToken == unit then
            activeNameplates[nameplate] = nil
            removedUnitFrame = nameplate and nameplate.UnitFrame or nil
            break
        end
    end

    if not removedUnitFrame then
        return
    end

    if self.ClearDeferredPortraitRefreshQueue then
        self:ClearDeferredPortraitRefreshQueue(removedUnitFrame)
    end

    if self.CancelNpcTitleResolve then
        self:CancelNpcTitleResolve(removedUnitFrame)
    end

    self:CancelNpcTitleRetry(removedUnitFrame)

    ResetPooledNameplateFrameState(removedUnitFrame)

    if RefineUI.ClearNameplateCrowdControl then
        RefineUI:ClearNameplateCrowdControl(removedUnitFrame, true)
    end
end

function Nameplates:HandleNameplateUnitStateEvent(event, unit)
    local private = self:GetPrivate()
    local util = private and private.Util
    if not util or util.IsDisallowedNameplateUnitToken(unit) then
        return
    end

    local nameplate = self:SafeGetNamePlateForUnit(unit)
    if not nameplate then
        return
    end

    self:UpdateVisibility(nameplate, unit)

    local unitFrame = nameplate.UnitFrame
    local data = unitFrame and self:GetNameplateData(unitFrame) or nil
    local isNameOnly = IsRuntimeSuppressedNameplate(unitFrame, data)

    if not isNameOnly then
        self:UpdateHealth(nameplate, unit)
    end

    if unitFrame then
        UpdateTargetUnitFrame(unitFrame)
    end

    if (not isNameOnly) and RefineUI.UpdateNameplateCrowdControl then
        RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, event)
    end
end

function Nameplates:HandleNameplateCVarEvent(event)
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    if not runtime then
        return
    end

    self:UpdateNameplateCVars(event == "PLAYER_ENTERING_WORLD")

    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" or self:IsNameplateSizeApplyPending() then
        self:ApplyConfiguredBlizzardNameplateSize(true)
    end

    if event ~= "PLAYER_ENTERING_WORLD" then
        return
    end

    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            local unitFrame = nameplate and nameplate.UnitFrame
            if unitFrame then
                self:CancelNpcTitleRetry(unitFrame)
            end
        end
    end

    wipe(runtime.npcTitleCacheByGUID)
    if self.ClearNpcTitleResolveQueue then
        self:ClearNpcTitleResolveQueue()
    end
    if self.ClearDeferredPortraitRefreshQueue then
        self:ClearDeferredPortraitRefreshQueue()
    end
    wipe(private.ActiveNameplates)
end

function Nameplates:HandleNameRuleCVarUpdate(_event, cvarName)
    if type(cvarName) ~= "string" or not NAME_RULE_CVAR[cvarName] then
        return
    end

    if type(RefineUI.RefreshAllNameplateNameRules) == "function" then
        RefineUI:RefreshAllNameplateNameRules(cvarName)
    end
end

----------------------------------------------------------------------------------------
-- Hook Wiring
----------------------------------------------------------------------------------------
function Nameplates:RegisterRuntimeHooks()
    local private = self:GetPrivate()
    local util = private and private.Util
    local runtime = private and private.Runtime
    if not util or not runtime then
        return
    end

    if runtime.runtimeHooksRegistered == true then
        return
    end

    local textures = private and private.Textures
    local healthBarTexture = textures and textures.HEALTH_BAR

    RefineUI:HookOnce(HOOK_KEY.UPDATE_NAME, "CompactUnitFrame_UpdateName", function(frame)
        if frame:IsForbidden() then return end
        if not util.IsUsableUnitToken(frame.unit) then return end
        if not frame.unit:find("nameplate") then return end

        local nameplate = frame:GetParent()
        if nameplate and nameplate.UnitFrame == frame then
            Nameplates:UpdateName(nameplate, frame.unit)
            -- Avoid mutating aura anchors inline inside CompactUnitFrame's update path.
            -- Deferring preserves the visual behavior while keeping Blizzard's
            -- secret-sensitive setup and heal-prediction pass isolated.
            QueueEnemyAuraLayoutRefresh(frame)
        end
    end)

    RefineUI:HookOnce(HOOK_KEY.UPDATE_HEALTH, "CompactUnitFrame_UpdateHealth", function(frame)
        if frame:IsForbidden() then return end
        if not util.IsUsableUnitToken(frame.unit) then return end
        if not frame.unit:find("nameplate") then return end

        local nameplate = frame:GetParent()
        if nameplate and nameplate.UnitFrame == frame then
            local data = RefineUI.NameplateData and RefineUI.NameplateData[frame] or nil
            if IsRuntimeSuppressedNameplate(frame, data) then
                return
            end
            -- NAME_PLATE_UNIT_ADDED ordering relative to Blizzard's driver is not stable.
            -- Mirror the text here so the first visible health text follows Blizzard's own
            -- authoritative unit-frame health update instead of the event race.
            Nameplates:UpdateHealth(nameplate, frame.unit)
        end
    end)

    RefineUI:HookOnce(HOOK_KEY.UPDATE_HEALTH_COLOR, "CompactUnitFrame_UpdateHealthColor", function(frame)
        if frame:IsForbidden() then return end
        if not util.IsUsableUnitToken(frame.unit) then return end
        if not frame.unit:find("nameplate") then return end

        local data = RefineUI.NameplateData and RefineUI.NameplateData[frame] or nil

        local health = frame.healthBar or frame.HealthBar
        if health and healthBarTexture and not IsRuntimeSuppressedNameplate(frame, data) then
            health:SetStatusBarTexture(healthBarTexture)
            health:SetStatusBarDesaturated(true)
        end

        local nameplate = frame:GetParent()
        if nameplate and nameplate.UnitFrame == frame then
            Nameplates:UpdateThreatColor(nameplate, frame.unit, false)
        end
    end)

    RefineUI:HookOnce(HOOK_KEY.UPDATE_RAID_TARGET_ICON, "CompactUnitFrame_UpdateRaidTargetIcon", function(frame)
        if frame:IsForbidden() then return end

        local nameplate = frame.GetParent and frame:GetParent() or nil
        if not nameplate or nameplate.UnitFrame ~= frame then return end

        local data = RefineUI.NameplateData[frame]
        Nameplates:ApplyRaidIconAnchor(frame, data)

        if RefineUI.RefreshNameplateVisualState then
            RefineUI:RefreshNameplateVisualState(frame, frame.unit, "RAID_TARGET_UPDATE", {
                refreshPortrait = true,
            })
        end

        UpdateTargetUnitFrame(frame)
    end)

    if _G.NamePlateUnitFrameMixin then
        RefineUI:HookOnce(HOOK_KEY.MIXIN_ON_UNIT_CLEARED, _G.NamePlateUnitFrameMixin, "OnUnitCleared", function(frame)
            if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
            ResetPooledNameplateFrameState(frame)
        end)

        RefineUI:HookOnce(HOOK_KEY.MIXIN_UPDATE_IS_TARGET, _G.NamePlateUnitFrameMixin, "UpdateIsTarget", function(frame)
            if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
            UpdateTargetUnitFrame(frame)
        end)

        RefineUI:HookOnce(HOOK_KEY.MIXIN_UPDATE_RAID_TARGET_ANCHOR, _G.NamePlateUnitFrameMixin, "UpdateRaidTarget", function(frame)
            if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end

            local data = RefineUI.NameplateData[frame]
            Nameplates:ApplyRaidIconAnchor(frame, data)
            UpdateTargetUnitFrame(frame)
        end)

        RefineUI:HookOnce(HOOK_KEY.MIXIN_UPDATE_ANCHORS_RAID_ANCHOR, _G.NamePlateUnitFrameMixin, "UpdateAnchors", function(frame)
            if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end

            local data = RefineUI.NameplateData[frame]
            Nameplates:ApplyRaidIconAnchor(frame, data)
            -- Avoid aura container mutation inside Blizzard's UpdateAnchors setup path.
            -- NamePlateBaseMixin:ApplyFrameOptions calls UpdateAnchors before
            -- CompactUnitFrame_SetUnit finishes its heal-prediction pass, and touching
            -- aura anchors there can taint the native nameplate health-bar flow.
            UpdateTargetUnitFrame(frame)
        end)
    end

    if _G.NamePlateAurasMixin and _G.NamePlateAurasMixin.RefreshAuras then
        RefineUI:HookOnce(HOOK_KEY.AURAS_REFRESH, _G.NamePlateAurasMixin, "RefreshAuras", function(aurasMixin)
            if aurasMixin:IsForbidden() then return end

            local unitFrame = aurasMixin:GetParent()
            if unitFrame and not unitFrame.unit then
                unitFrame = unitFrame:GetParent()
            end
            if not unitFrame or not util.IsUsableUnitToken(unitFrame.unit) then
                return
            end

            local data = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame]
            if IsRuntimeSuppressedNameplate(unitFrame, data) then
                if RefineUI.ClearNameplateCrowdControl then
                    RefineUI:ClearNameplateCrowdControl(unitFrame, true)
                end
                return
            end

            QueueEnemyAuraLayoutRefresh(unitFrame)

            local hasCachedCrowdControl = data and (
                data.CrowdControlActive == true
                or data.CrowdControlAuraInstanceID ~= nil
                or data.CrowdControlSuppressed == true
            )
            if not hasCachedCrowdControl then
                local aurasFrame = unitFrame.AurasFrame
                local crowdControlList = aurasFrame and aurasFrame.crowdControlList
                local hasActiveCrowdControlAura = false
                if crowdControlList and type(crowdControlList.GetTop) == "function" then
                    local ok, aura = pcall(crowdControlList.GetTop, crowdControlList)
                    hasActiveCrowdControlAura = ok and aura ~= nil
                end

                if not hasActiveCrowdControlAura then
                    return
                end
            end

            if RefineUI.UpdateNameplateCrowdControl then
                RefineUI:UpdateNameplateCrowdControl(unitFrame, unitFrame.unit, "UNIT_AURA")
            end
        end)
    end

    if _G.NamePlateAuraItemMixin and _G.NamePlateAuraItemMixin.SetAura then
        RefineUI:HookOnce(HOOK_KEY.AURA_ITEM_SET_AURA, _G.NamePlateAuraItemMixin, "SetAura", function(selfFrame, aura)
            if selfFrame:IsForbidden() then return end

            local unitFrame = GetAuraItemUnitFrame(selfFrame)
            if IsRuntimeSuppressedNameplate(unitFrame) then
                return
            end

            QueueAuraVisualRefresh(selfFrame, aura)
        end)
    end

    if _G.NamePlateAurasMixin and _G.NamePlateAurasMixin.RefreshList then
        RefineUI:HookOnce(HOOK_KEY.AURAS_REFRESH_LIST, _G.NamePlateAurasMixin, "RefreshList", function(aurasMixin, listFrame)
            if aurasMixin:IsForbidden() then return end

            local unitFrame = aurasMixin:GetParent()
            if unitFrame and not unitFrame.unit then
                unitFrame = unitFrame:GetParent()
            end
            if IsRuntimeSuppressedNameplate(unitFrame) then
                return
            end

            local health = unitFrame and (unitFrame.healthBar or unitFrame.HealthBar)
            if not health then
                return
            end

            if listFrame == aurasMixin.DebuffListFrame
                or listFrame == aurasMixin.BuffListFrame
                or listFrame == aurasMixin.CrowdControlListFrame then
                QueueEnemyAuraLayoutRefresh(unitFrame)
            end
        end)
    end

    runtime.runtimeHooksRegistered = true
end

----------------------------------------------------------------------------------------
-- Startup Orchestration
----------------------------------------------------------------------------------------
function Nameplates:StyleExistingNameplates()
    if not C_NamePlate or type(C_NamePlate.GetNamePlates) ~= "function" then
        return
    end

    local private = self:GetPrivate()
    local activeNameplates = private and private.ActiveNameplates or {}
    local runtime = private and private.Runtime
    local util = private and private.Util

    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unit = nameplate.UnitFrame and nameplate.UnitFrame.unit
        if unit then
            activeNameplates[nameplate] = unit

            self:StyleNameplate(nameplate, unit)
            self:UpdateVisibility(nameplate, unit)
            self:ApplyNpcTitleVisual(nameplate, unit, { allowResolve = true })

            local unitFrame = nameplate.UnitFrame
            local data = unitFrame and self:GetNameplateData(unitFrame) or nil
            local isNameOnly = data and data.RefineHidden == true

            if (not isNameOnly) and RefineUI.UpdateNameplateCrowdControl then
                RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, "OnEnable")
            end
            if (not isNameOnly) and RefineUI.UpdateDynamicPortrait then
                RefineUI:UpdateDynamicPortrait(nameplate, unit)
            end
            if unitFrame then
                UpdateTargetUnitFrame(unitFrame)
            end
        end
    end
end

function Nameplates:RegisterRuntimeEvents()
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    if not runtime then
        return
    end

    if runtime.runtimeEventsRegistered == true then
        return
    end

    RefineUI:RegisterEventCallback("NAME_PLATE_UNIT_ADDED", function(event, unit)
        Nameplates:OnNameplateAdded(event, unit)
    end, EVENT_KEY.UNIT_ADDED)

    RefineUI:RegisterEventCallback("NAME_PLATE_UNIT_REMOVED", function(event, unit)
        Nameplates:OnNameplateRemoved(event, unit)
    end, EVENT_KEY.UNIT_REMOVED)

    RefineUI:OnEvents(EVENT_LIST.UNIT_STATE, function(event, unit)
        Nameplates:HandleNameplateUnitStateEvent(event, unit)
    end, EVENT_KEY.UNIT_STATE)

    RefineUI:OnEvents(
        EVENT_LIST.THREAT_ROLE,
        function(event, unit)
            Nameplates:HandleThreatRoleEvent(event, unit)
        end,
        EVENT_KEY.THREAT_ROLE
    )

    RefineUI:OnEvents(
        EVENT_LIST.CVAR_STATE,
        function(event)
            Nameplates:HandleNameplateCVarEvent(event)
        end,
        EVENT_KEY.CVAR_STATE
    )

    RefineUI:RegisterEventCallback("CVAR_UPDATE", function(event, cvarName)
        Nameplates:HandleNameRuleCVarUpdate(event, cvarName)
    end, EVENT_KEY.NAME_RULE_CVAR)

    runtime.runtimeEventsRegistered = true
end

function Nameplates:EnableRuntime()
    self:EnsureSimplifiedNameplatesDisabled()
    self:RefreshPlayerThreatRole()
    self:EnsureConfiguredNameplateSizeHooks()
    self:ApplyConfiguredBlizzardNameplateSize(true)

    if type(RefineUI.RefreshNameplateCastColors) == "function" then
        RefineUI:RefreshNameplateCastColors(false)
    end

    local cfg = self:GetConfiguredNameplatesConfig()
    if cfg and cfg.Alpha then
        SetCVarIfChanged("nameplateMinAlpha", cfg.Alpha)
    end
    SetCVarIfChanged("nameplateMaxAlpha", 1.0)

    self:ApplyThreatDisplayCVarFromConfig()
    self:RegisterRuntimeEvents()
    self:UpdateNameplateCVars()
    self:StyleExistingNameplates()
    self:RegisterRuntimeHooks()

    RefineUI:RefreshNameplateThreatColors(true)

    if self.RegisterEditModeFrame then
        self:RegisterEditModeFrame()
    end
    if self.RegisterEditModeCallbacks then
        self:RegisterEditModeCallbacks()
    end
end

----------------------------------------------------------------------------------------
-- Public API (Compatibility)
----------------------------------------------------------------------------------------
function RefineUI:ApplyNameplateCVarSettings()
    Nameplates:UpdateNameplateCVars(true)
end
