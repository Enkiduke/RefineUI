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
local C_CurveUtil = C_CurveUtil
local Enum = Enum
local GetCVar = GetCVar
local IsInInstance = IsInInstance
local UnitInBattleground = UnitInBattleground
local UnitAffectingCombat = UnitAffectingCombat
local CreateColor = CreateColor

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local Private = Nameplates:GetPrivate()
local Util = Private.Util
local Runtime = Private.Runtime
local Constants = Private.Constants
local ActiveNameplates = Private.ActiveNameplates
local NameplateData = RefineUI.NameplateData
local IsNameOnly = Util.IsNameOnly
local HEALTH_BAR_TEXTURE = Private.Textures.HEALTH_BAR

local HOOK_KEY = {
    UPDATE_NAME = "Nameplates:CompactUnitFrame_UpdateName",
    UPDATE_HEALTH = "Nameplates:CompactUnitFrame_UpdateHealth",
    UPDATE_HEALTH_COLOR = "Nameplates:CompactUnitFrame_UpdateHealthColor",
    MIXIN_ON_UNIT_CLEARED = "Nameplates:NamePlateUnitFrameMixin:OnUnitCleared",
    MIXIN_UPDATE_IS_TARGET = "Nameplates:NamePlateUnitFrameMixin:UpdateIsTarget",
    MIXIN_UPDATE_RAID_TARGET_ANCHOR = "Nameplates:NamePlateUnitFrameMixin:UpdateRaidTarget:Anchor",
    MIXIN_UPDATE_ANCHORS = "Nameplates:NamePlateUnitFrameMixin:UpdateAnchors",
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
    CVAR_UPDATE = "Nameplates:NameRuleCVar",
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

local AURA_DEBUFF_BORDER_COLOR = CreateColor(0.8, 0.1, 0.1, 1)
local auraBuffBorderColor

----------------------------------------------------------------------------------------
-- Shared Runtime Helpers
----------------------------------------------------------------------------------------
local function UpdateTargetUnitFrame(unitFrame)
    RefineUI:UpdateTarget(unitFrame)
end

local function GetAuraItemUnitFrame(auraFrame)
    local listFrame = auraFrame:GetParent()
    local aurasMixin = listFrame and listFrame:GetParent()
    local unitFrame = aurasMixin and aurasMixin:GetParent()
    if unitFrame and not unitFrame.unit then
        unitFrame = unitFrame:GetParent()
    end

    return unitFrame
end

local function GetScaledAuraLayoutOffset(value, defaultValue)
    return RefineUI:Scale(tonumber(value) or defaultValue)
end

local function GetAccessiblePositiveNumber(value)
    if not Util.IsAccessibleValue(value) or type(value) ~= "number" or value <= 0 then
        return nil
    end
    return value
end

-- Aura and name hooks fire several times per Blizzard refresh; collect targets and
-- flush once on the next frame through a single keyed timer. The flag records
-- whether the CC display should also be reconciled (aura-driven refreshes only).
local pendingAuraLayoutFrames = {}
local pendingAuraVisuals = {}

local function FlushEnemyAuraLayoutRefresh()
    for unitFrame, refreshCrowdControl in pairs(pendingAuraLayoutFrames) do
        pendingAuraLayoutFrames[unitFrame] = nil
        if not unitFrame:IsForbidden() then
            Nameplates:RefreshEnemyAuraLayout(unitFrame)
            if refreshCrowdControl then
                -- Reconcile the CC holder on aura updates, even when no cast event fires.
                RefineUI:UpdateNameplateCrowdControl(unitFrame, unitFrame.unit)
            end
        end
    end
end

local function QueueEnemyAuraLayoutRefresh(unitFrame, refreshCrowdControl)
    pendingAuraLayoutFrames[unitFrame] = refreshCrowdControl or pendingAuraLayoutFrames[unitFrame] or false
    RefineUI:After(TIMER_KEY.DEFERRED_AURA_LAYOUT, 0, FlushEnemyAuraLayoutRefresh)
end

local function GetAuraVisualInset(auraItemFrame, unitFrame)
    local aurasFrame = unitFrame and unitFrame.AurasFrame
    if not aurasFrame or unitFrame:IsFriend() then
        return 0
    end

    local auraConfig = Config.Nameplates.EnemyAuras
    local parent = auraItemFrame:GetParent()
    if parent == aurasFrame.DebuffListFrame then
        return max(0, GetScaledAuraLayoutOffset(auraConfig.DebuffSpacing, 2) * 0.5)
    end

    if parent == aurasFrame.BuffListFrame then
        return max(0, GetScaledAuraLayoutOffset(auraConfig.BuffSpacing, 2) * 0.5)
    end

    return 0
end

local function SetDefaultAuraBorderColor(border)
    local borderColor = Config.General.BorderColor
    border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end

local function ApplyAuraVisualState(auraItemFrame, aura)
    local unitFrame = GetAuraItemUnitFrame(auraItemFrame)
    if IsNameOnly(unitFrame) then
        return
    end

    Nameplates:SkinNamePlateAura(auraItemFrame, GetAuraVisualInset(auraItemFrame, unitFrame))

    local border = auraItemFrame.border
    if not border then
        return
    end

    local isHelpful
    if Util.IsAccessibleValue(aura) then
        isHelpful = Util.SafeTableIndex(aura, "isHelpful")
    end

    if isHelpful == nil then
        local listFrame = auraItemFrame:GetParent()
        local aurasMixin = listFrame and listFrame:GetParent()
        if aurasMixin and listFrame == aurasMixin.BuffListFrame then
            isHelpful = true
        elseif aurasMixin and (listFrame == aurasMixin.DebuffListFrame or listFrame == aurasMixin.CrowdControlListFrame) then
            isHelpful = false
        end
    end

    if Util.IsSecret(isHelpful) then
        if C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean then
            if not auraBuffBorderColor then
                local borderColor = Config.General.BorderColor
                auraBuffBorderColor = CreateColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
            end
            local finalColor = C_CurveUtil.EvaluateColorFromBoolean(isHelpful, auraBuffBorderColor, AURA_DEBUFF_BORDER_COLOR)
            border:SetBackdropBorderColor(finalColor:GetRGBA())
        else
            SetDefaultAuraBorderColor(border)
        end
        return
    end

    if isHelpful == false then
        local r, g, b = 0.8, 0.1, 0.1
        local dispelName
        if Util.IsAccessibleValue(aura) then
            dispelName = Util.SafeTableIndex(aura, "dispelName")
        end
        if dispelName and not Util.IsSecret(dispelName) and _G.DebuffTypeColor then
            local color = _G.DebuffTypeColor[dispelName]
            if color then
                r, g, b = color.r, color.g, color.b
            end
        end

        border:SetBackdropBorderColor(r, g, b)
        return
    end

    SetDefaultAuraBorderColor(border)
end

local function FlushAuraVisualRefresh()
    for auraItemFrame, aura in pairs(pendingAuraVisuals) do
        pendingAuraVisuals[auraItemFrame] = nil

        if not auraItemFrame:IsForbidden() then
            -- Pooled aura items can be reassigned before the flush; skip stale auras.
            local auraInstanceID = Util.IsAccessibleValue(aura) and Util.SafeTableIndex(aura, "auraInstanceID") or nil
            local currentInstanceID = Util.SafeTableIndex(auraItemFrame, "auraInstanceID")
            local isStale = auraInstanceID ~= nil and currentInstanceID ~= nil
                and not Util.IsSecret(auraInstanceID)
                and not Util.IsSecret(currentInstanceID)
                and currentInstanceID ~= auraInstanceID

            if not isStale then
                ApplyAuraVisualState(auraItemFrame, aura)
            end
        end
    end
end

local function QueueAuraVisualRefresh(auraItemFrame, aura)
    if aura == nil then
        return
    end

    pendingAuraVisuals[auraItemFrame] = aura
    RefineUI:After(TIMER_KEY.DEFERRED_AURA_VISUALS, 0, FlushAuraVisualRefresh)
end

local function ResetPooledNameplateFrameState(unitFrame)
    local data = NameplateData[unitFrame]
    if not data then
        return
    end

    if data.EventFrame then
        data.EventFrame:UnregisterAllEvents()
    end

    if data.RefineName then
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
    data.NpcTitleNameShown = nil
    data.RefineHidden = nil
    data.RefineNpcTitleAnchor = nil
    data.RefineNpcTitleFormatted = nil
    data.RefineNameRaw = nil
    data.HealthTextureApplied = nil
    data.AuraAnchorDebuffY = nil
    data.AuraLayoutStale = nil
    data.RaidIconAnchorMode = nil
    data.RaidIconAnchorTarget = nil
    data.isTarget = nil
    data.isCasting = nil
    data.isPlayer = nil
    data.inCombat = nil
    data.LastImportantCastSpellIdentifier = nil
    data.LastImportantCastIsImportant = nil
    data.PortraitRendered = nil
    data.lastPortraitMode = nil
    data.wasCasting = nil
    data.SuppressPortraitBorderRefresh = nil
    data.lastTargetNameOnly = nil
    data.TargetArrowsShown = nil
    data.TargetArrowLeftShown = nil
    data.TargetArrowAnchor = nil
    data.TargetArrowRightOffset = nil
    data.TargetArrowNameOnly = nil
end

local function GetRefineAuraBaseYOffset(data, auraConfig)
    local nameHeight = 0
    local refineName = data.RefineName
    if refineName and refineName:IsShown() then
        nameHeight = GetAccessiblePositiveNumber(refineName:GetStringHeight())
            or GetAccessiblePositiveNumber(refineName:GetHeight())
            or 0
    end

    return nameHeight + GetScaledAuraLayoutOffset(auraConfig.BaseOffsetY, 6)
end

-- Blizzard's GridLayoutFrame reads childXPadding during secure aura layout, so enemy
-- aura spacing is applied visually per aura item instead of on the list frames.
-- Anchors are cached per unit frame; Blizzard only re-anchors the lists in
-- UpdateAnchors, whose hook clears the cache.
function Nameplates:RefreshEnemyAuraLayout(unitFrame)
    local data = self:GetNameplateData(unitFrame)
    data.AuraLayoutStale = nil
    if data.RefineHidden == true or unitFrame:IsFriend() then
        return
    end

    local aurasFrame = unitFrame.AurasFrame
    local health = unitFrame.healthBar or unitFrame.HealthBar
    if not aurasFrame or not health then
        return
    end

    local auraConfig = Config.Nameplates.EnemyAuras
    local baseYOffset = GetRefineAuraBaseYOffset(data, auraConfig)
    local debuffX = GetScaledAuraLayoutOffset(auraConfig.DebuffOffsetX, 0)
    local debuffY = baseYOffset + GetScaledAuraLayoutOffset(auraConfig.DebuffOffsetY, 0)
    local buffX = GetScaledAuraLayoutOffset(auraConfig.BuffOffsetX, 0)
    local buffY = baseYOffset + GetScaledAuraLayoutOffset(auraConfig.BuffOffsetY, 0)

    if data.AuraAnchorDebuffY == debuffY
        and data.AuraAnchorDebuffX == debuffX
        and data.AuraAnchorBuffX == buffX
        and data.AuraAnchorBuffY == buffY then
        return
    end

    local debuffListFrame = aurasFrame.DebuffListFrame
    if debuffListFrame then
        debuffListFrame:ClearAllPoints()
        debuffListFrame:SetPoint("BOTTOMLEFT", health, "TOPLEFT", debuffX, debuffY)
    end

    local buffListFrame = aurasFrame.BuffListFrame
    if buffListFrame then
        buffListFrame:ClearAllPoints()
        buffListFrame:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", buffX, buffY)
    end

    data.AuraAnchorDebuffX = debuffX
    data.AuraAnchorDebuffY = debuffY
    data.AuraAnchorBuffX = buffX
    data.AuraAnchorBuffY = buffY
end

function RefineUI:RefreshAllNameplateAuraAnchors()
    for nameplate in pairs(ActiveNameplates) do
        local unitFrame = nameplate.UnitFrame
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
    if GetCVar(cvar) ~= desired then
        pcall(C_CVar.SetCVar, cvar, desired)
    end
end

function Nameplates:EnsureSimplifiedNameplatesDisabled()
    local nameplateType = Enum.NamePlateType
    if not C_NamePlateManager or not C_NamePlateManager.SetNamePlateSimplified or not nameplateType then
        return
    end

    pcall(C_NamePlateManager.SetNamePlateSimplified, nameplateType.Friendly, false)
    pcall(C_NamePlateManager.SetNamePlateSimplified, nameplateType.Enemy, false)
end

function Nameplates:IsInGroupInstanceContent()
    local _, instanceType = IsInInstance()
    if instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena" then
        return true
    end

    return Util.ReadSafeBoolean(UnitInBattleground("player")) == true
end

function Nameplates:UpdateNameplateCVars(forceApply)
    self:EnsureSimplifiedNameplatesDisabled()
    self:ApplyThreatDisplayCVarFromConfig()

    local inCombat = Util.ReadSafeBoolean(UnitAffectingCombat("player")) == true
    local inGroupContent = self:IsInGroupInstanceContent()
    local showPetNames = self:GetConfiguredNameplatesConfig().ShowPetNames == true

    local lastState = Runtime.lastCVarState
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
    local showFriendlyPlayerPets = (showFriends == 1 and showPetNames) and 1 or 0
    local showEnemyPlayerPets = showPetNames and 1 or 0

    SetCVarIfChanged("nameplateShowFriends", showFriends)
    SetCVarIfChanged("nameplateShowFriendlyPlayers", showFriends)
    SetCVarIfChanged("nameplateShowFriendlyPlayerPets", showFriendlyPlayerPets)
    SetCVarIfChanged("nameplateShowFriendlyPlayerMinions", showFriends)
    SetCVarIfChanged("nameplateShowFriendlyPlayerGuardians", showFriends)
    SetCVarIfChanged("nameplateShowFriendlyPlayerTotems", showFriends)
    SetCVarIfChanged("nameplateShowEnemyPets", showEnemyPlayerPets)
    SetCVarIfChanged("nameplateShowFriendlyNpcs", showFriends)
end

----------------------------------------------------------------------------------------
-- Deferred Refresh Queue (Portrait)
----------------------------------------------------------------------------------------
local function DrainDeferredPortraitRefreshQueue()
    Nameplates:DrainDeferredPortraitRefreshQueue()
end

function Nameplates:SetPortraitRefreshJobEnabled(enabled)
    RefineUI:SetUpdateJobEnabled(Constants.PORTRAIT_REFRESH_JOB_KEY, enabled == true, false)
end

function Nameplates:EnsurePortraitRefreshJob()
    if RefineUI:IsUpdateJobRegistered(Constants.PORTRAIT_REFRESH_JOB_KEY) then
        return
    end

    RefineUI:RegisterUpdateJob(
        Constants.PORTRAIT_REFRESH_JOB_KEY,
        Constants.PORTRAIT_REFRESH_INTERVAL_SECONDS,
        DrainDeferredPortraitRefreshQueue,
        {
            enabled = false,
            safe = true,
            disableOnError = true,
        }
    )
end

function Nameplates:ClearDeferredPortraitRefreshQueue(unitFrame)
    if unitFrame then
        local queued = Runtime.pendingPortraitRefreshByFrame[unitFrame]
        if queued then
            queued.cancelled = true
            Runtime.pendingPortraitRefreshByFrame[unitFrame] = nil
        end
        return
    end

    wipe(Runtime.pendingPortraitRefreshQueue)
    wipe(Runtime.pendingPortraitRefreshByFrame)
    Runtime.pendingPortraitRefreshHead = 1
    self:SetPortraitRefreshJobEnabled(false)
end

function Nameplates:QueuePortraitRefresh(unitFrame, unit, event)
    if IsNameOnly(unitFrame) then
        return
    end

    local resolvedUnit = Util.ResolveUnitToken(unit, unitFrame.unit)
    if not resolvedUnit then
        return
    end

    local queued = Runtime.pendingPortraitRefreshByFrame[unitFrame]
    if queued then
        queued.unit = resolvedUnit
        queued.event = event or queued.event
        queued.cancelled = false
        return
    end

    self:EnsurePortraitRefreshJob()

    local entry = {
        unitFrame = unitFrame,
        unit = resolvedUnit,
        event = event,
        cancelled = false,
    }
    Runtime.pendingPortraitRefreshByFrame[unitFrame] = entry
    tinsert(Runtime.pendingPortraitRefreshQueue, entry)
    self:SetPortraitRefreshJobEnabled(true)
end

function Nameplates:DrainDeferredPortraitRefreshQueue()
    local queue = Runtime.pendingPortraitRefreshQueue
    local head = Runtime.pendingPortraitRefreshHead
    local tail = #queue
    local budget = Constants.PORTRAIT_REFRESH_BUDGET_PER_TICK
    local processed = 0

    while processed < budget and head <= tail do
        local entry = queue[head]
        queue[head] = nil
        head = head + 1

        local unitFrame = entry.unitFrame
        if Runtime.pendingPortraitRefreshByFrame[unitFrame] == entry then
            Runtime.pendingPortraitRefreshByFrame[unitFrame] = nil
        end

        if not entry.cancelled then
            local nameplate = unitFrame:GetParent()
            if nameplate and nameplate.UnitFrame == unitFrame then
                local unit = Util.ResolveUnitToken(entry.unit, unitFrame.unit)
                if unit then
                    RefineUI:UpdateDynamicPortrait(nameplate, unit, entry.event)
                end
            end
        end

        processed = processed + 1
    end

    if head > tail then
        wipe(queue)
        Runtime.pendingPortraitRefreshHead = 1
        self:SetPortraitRefreshJobEnabled(false)
    else
        Runtime.pendingPortraitRefreshHead = head
    end
end

----------------------------------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------------------------------
local function RefreshAddedNameplate(nameplate, unit, event)
    ActiveNameplates[nameplate] = unit

    Nameplates:StyleNameplate(nameplate, unit)
    Nameplates:UpdateVisibility(nameplate, unit)
    Nameplates:ApplyNpcTitleVisual(nameplate, unit, "resolve")

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local data = Nameplates:GetNameplateData(unitFrame)
    data.PortraitRendered = nil
    data.lastPortraitMode = nil
    data.wasCasting = false

    if not IsNameOnly(unitFrame) then
        RefineUI:UpdateDynamicPortrait(nameplate, unit)
        -- After the portrait: the CC display anchors its icon to the portrait frame.
        RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, event)
        QueueEnemyAuraLayoutRefresh(unitFrame)
    end

    UpdateTargetUnitFrame(unitFrame)
end

function Nameplates:OnNameplateAdded(event, unit)
    local safeUnit = Util.ResolveUnitToken(unit)
    local nameplate = safeUnit and self:SafeGetNamePlateForUnit(safeUnit)
    if nameplate then
        RefreshAddedNameplate(nameplate, safeUnit, event)
    end
end

function Nameplates:OnNameplateRemoved(_event, unit)
    if not Util.IsUsableUnitToken(unit) then
        return
    end

    local removedUnitFrame
    for nameplate, unitToken in pairs(ActiveNameplates) do
        if unitToken == unit then
            ActiveNameplates[nameplate] = nil
            removedUnitFrame = nameplate.UnitFrame
            break
        end
    end

    if not removedUnitFrame then
        return
    end

    self:ClearDeferredPortraitRefreshQueue(removedUnitFrame)
    self:CancelNpcTitleResolve(removedUnitFrame)
    self:CancelNpcTitleRetry(removedUnitFrame)
    pendingAuraLayoutFrames[removedUnitFrame] = nil

    ResetPooledNameplateFrameState(removedUnitFrame)
    RefineUI:ClearNameplateCrowdControl(removedUnitFrame)
end

function Nameplates:HandleNameplateUnitStateEvent(event, unit)
    if Util.IsDisallowedNameplateUnitToken(unit) then
        return
    end

    local nameplate = self:SafeGetNamePlateForUnit(unit)
    local unitFrame = nameplate and nameplate.UnitFrame
    if not unitFrame then
        return
    end

    self:UpdateVisibility(nameplate, unit)

    local isNameOnly = IsNameOnly(unitFrame)
    if not isNameOnly then
        self:UpdateHealth(nameplate, unit)
    end

    UpdateTargetUnitFrame(unitFrame)

    if not isNameOnly then
        RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, event)
    end
end

function Nameplates:HandleNameplateCVarEvent(event)
    self:UpdateNameplateCVars(event == "PLAYER_ENTERING_WORLD")

    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" or self:IsNameplateSizeApplyPending() then
        self:ApplyConfiguredBlizzardNameplateSize(true)
    end

    if event ~= "PLAYER_ENTERING_WORLD" then
        return
    end

    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unitFrame = nameplate.UnitFrame
        if unitFrame then
            self:CancelNpcTitleRetry(unitFrame)
        end
    end

    -- ActiveNameplates is maintained by the add/remove events. Wiping it here would
    -- orphan plates added before this handler, skipping their removal cleanup.
    wipe(Runtime.npcTitleCacheByGUID)
    self:ClearNpcTitleResolveQueue()
    self:ClearDeferredPortraitRefreshQueue()
end

function Nameplates:HandleCVarUpdate(_event, cvarName)
    if cvarName == Constants.NAMEPLATE_THREAT_DISPLAY_CVAR then
        Runtime.threatHealthColorMirrored = nil
        return
    end

    if type(cvarName) == "string" and NAME_RULE_CVAR[cvarName] then
        RefineUI:RefreshAllNameplateNameRules()
    end
end

----------------------------------------------------------------------------------------
-- Hook Wiring
----------------------------------------------------------------------------------------
-- Blizzard's CompactUnitFrame functions also drive raid/party frames; only the unit
-- frame owned by a nameplate passes this check.
local function GetOwningNameplate(frame)
    if frame:IsForbidden() then
        return nil
    end

    local nameplate = frame:GetParent()
    if nameplate and nameplate.UnitFrame == frame and Util.IsUsableUnitToken(frame.unit) then
        return nameplate
    end
    return nil
end

function Nameplates:RegisterRuntimeHooks()
    if Runtime.runtimeHooksRegistered == true then
        return
    end

    -- CompactUnitFrame_UpdateHealth calls UpdateName and UpdateHealthColor, so these
    -- three hooks run on every health change of every plate. Keep them cheap.
    RefineUI:HookOnce(HOOK_KEY.UPDATE_NAME, "CompactUnitFrame_UpdateName", function(frame)
        local nameplate = GetOwningNameplate(frame)
        if not nameplate then return end

        Nameplates:UpdateName(nameplate, frame.unit)
        -- Avoid mutating aura anchors inline inside CompactUnitFrame's update path.
        -- Deferring preserves the visual behavior while keeping Blizzard's
        -- secret-sensitive setup and heal-prediction pass isolated.
        local data = NameplateData[frame]
        if data and data.AuraLayoutStale then
            QueueEnemyAuraLayoutRefresh(frame)
        end
    end)

    RefineUI:HookOnce(HOOK_KEY.UPDATE_HEALTH, "CompactUnitFrame_UpdateHealth", function(frame)
        local nameplate = GetOwningNameplate(frame)
        if not nameplate or IsNameOnly(frame) then return end

        -- NAME_PLATE_UNIT_ADDED ordering relative to Blizzard's driver is not stable.
        -- Mirror the text here so the first visible health text follows Blizzard's own
        -- authoritative unit-frame health update instead of the event race.
        Nameplates:UpdateHealth(nameplate, frame.unit)
    end)

    RefineUI:HookOnce(HOOK_KEY.UPDATE_HEALTH_COLOR, "CompactUnitFrame_UpdateHealthColor", function(frame)
        local nameplate = GetOwningNameplate(frame)
        if not nameplate then return end

        -- UpdateAnchors swaps Blizzard's bar atlas back in and clears this flag.
        local data = NameplateData[frame]
        if not (data and (data.HealthTextureApplied or data.RefineHidden == true)) then
            local health = frame.healthBar or frame.HealthBar
            if health then
                health:SetStatusBarTexture(HEALTH_BAR_TEXTURE)
                health:SetStatusBarDesaturated(true)
                if data then
                    data.HealthTextureApplied = true
                end
            end
        end

        Nameplates:UpdateThreatColor(nameplate, frame.unit)
    end)

    local unitFrameMixin = _G.NamePlateUnitFrameMixin
    if unitFrameMixin then
        RefineUI:HookOnce(HOOK_KEY.MIXIN_ON_UNIT_CLEARED, unitFrameMixin, "OnUnitCleared", function(frame)
            if frame:IsForbidden() then return end
            ResetPooledNameplateFrameState(frame)
        end)

        RefineUI:HookOnce(HOOK_KEY.MIXIN_UPDATE_IS_TARGET, unitFrameMixin, "UpdateIsTarget", function(frame)
            if frame:IsForbidden() then return end
            UpdateTargetUnitFrame(frame)
        end)

        RefineUI:HookOnce(HOOK_KEY.MIXIN_UPDATE_RAID_TARGET_ANCHOR, unitFrameMixin, "UpdateRaidTarget", function(frame)
            if frame:IsForbidden() then return end

            Nameplates:ApplyRaidIconAnchor(frame, NameplateData[frame])
            UpdateTargetUnitFrame(frame)
        end)

        -- UpdateAnchors re-anchors the aura lists, resets the health bar height and atlas,
        -- and runs on every SetUnit and nameplate resize.
        RefineUI:HookOnce(HOOK_KEY.MIXIN_UPDATE_ANCHORS, unitFrameMixin, "UpdateAnchors", function(frame)
            if frame:IsForbidden() then return end

            Nameplates:ApplyConfiguredNameplateHeight(frame)

            local data = NameplateData[frame]
            if data then
                -- Blizzard just re-anchored the raid icon; force ours back on.
                data.RaidIconAnchorMode = nil
            end
            Nameplates:ApplyRaidIconAnchor(frame, data)
            if data then
                data.HealthTextureApplied = nil
                data.AuraAnchorDebuffY = nil
            end
            -- Avoid aura container mutation inside Blizzard's UpdateAnchors setup path.
            -- NamePlateBaseMixin:ApplyFrameOptions calls UpdateAnchors before
            -- CompactUnitFrame_SetUnit finishes its heal-prediction pass, and touching
            -- aura anchors there can taint the native nameplate health-bar flow.
            if frame.unit then
                QueueEnemyAuraLayoutRefresh(frame)
            end
            UpdateTargetUnitFrame(frame)
        end)
    end

    local aurasMixin = _G.NamePlateAurasMixin
    if aurasMixin and aurasMixin.RefreshAuras then
        RefineUI:HookOnce(HOOK_KEY.AURAS_REFRESH, aurasMixin, "RefreshAuras", function(auras)
            if auras:IsForbidden() then return end

            local unitFrame = auras:GetParent()
            if unitFrame and not unitFrame.unit then
                unitFrame = unitFrame:GetParent()
            end
            if not unitFrame or not Util.IsUsableUnitToken(unitFrame.unit) or IsNameOnly(unitFrame) then
                return
            end

            QueueEnemyAuraLayoutRefresh(unitFrame, true)
        end)
    end

    local auraItemMixin = _G.NamePlateAuraItemMixin
    if auraItemMixin and auraItemMixin.SetAura then
        RefineUI:HookOnce(HOOK_KEY.AURA_ITEM_SET_AURA, auraItemMixin, "SetAura", function(auraItem, aura)
            if auraItem:IsForbidden() or IsNameOnly(GetAuraItemUnitFrame(auraItem)) then return end
            QueueAuraVisualRefresh(auraItem, aura)
        end)
    end

    if aurasMixin and aurasMixin.RefreshList then
        RefineUI:HookOnce(HOOK_KEY.AURAS_REFRESH_LIST, aurasMixin, "RefreshList", function(auras, listFrame)
            if auras:IsForbidden() then return end

            local unitFrame = auras:GetParent()
            if unitFrame and not unitFrame.unit then
                unitFrame = unitFrame:GetParent()
            end
            if not unitFrame or IsNameOnly(unitFrame) or not (unitFrame.healthBar or unitFrame.HealthBar) then
                return
            end

            if listFrame == auras.DebuffListFrame
                or listFrame == auras.BuffListFrame
                or listFrame == auras.CrowdControlListFrame then
                QueueEnemyAuraLayoutRefresh(unitFrame, true)
            end
        end)
    end

    Runtime.runtimeHooksRegistered = true
end

----------------------------------------------------------------------------------------
-- Startup Orchestration
----------------------------------------------------------------------------------------
function Nameplates:StyleExistingNameplates()
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unit = nameplate.UnitFrame and nameplate.UnitFrame.unit
        if unit then
            RefreshAddedNameplate(nameplate, unit, "OnEnable")
        end
    end
end

function Nameplates:RegisterRuntimeEvents()
    if Runtime.runtimeEventsRegistered == true then
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

    RefineUI:OnEvents(EVENT_LIST.THREAT_ROLE, function(event, unit)
        Nameplates:HandleThreatRoleEvent(event, unit)
    end, EVENT_KEY.THREAT_ROLE)

    RefineUI:OnEvents(EVENT_LIST.CVAR_STATE, function(event)
        Nameplates:HandleNameplateCVarEvent(event)
    end, EVENT_KEY.CVAR_STATE)

    RefineUI:RegisterEventCallback("CVAR_UPDATE", function(event, cvarName)
        Nameplates:HandleCVarUpdate(event, cvarName)
    end, EVENT_KEY.CVAR_UPDATE)

    Runtime.runtimeEventsRegistered = true
end

function Nameplates:EnableRuntime()
    self:EnsureSimplifiedNameplatesDisabled()
    self:RefreshPlayerThreatRole()
    self:ApplyConfiguredBlizzardNameplateSize(true)
    RefineUI:RefreshNameplateCastColors(false)

    local cfg = self:GetConfiguredNameplatesConfig()
    if cfg.Alpha then
        SetCVarIfChanged("nameplateMinAlpha", cfg.Alpha)
    end
    SetCVarIfChanged("nameplateMaxAlpha", 1.0)

    self:ApplyThreatDisplayCVarFromConfig()
    self:RegisterRuntimeEvents()
    self:UpdateNameplateCVars()
    self:StyleExistingNameplates()
    self:RegisterRuntimeHooks()

    RefineUI:RefreshNameplateThreatColors()

    self:RegisterEditModeFrame()
    self:RegisterEditModeCallbacks()
end

----------------------------------------------------------------------------------------
-- Public API (Compatibility)
----------------------------------------------------------------------------------------
function RefineUI:ApplyNameplateCVarSettings()
    Nameplates:UpdateNameplateCVars(true)
end
