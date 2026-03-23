----------------------------------------------------------------------------------------
-- CDM Component: Lifecycle
-- Description: Standalone refresh lifecycle and event-driven runtime orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tinsert = table.insert
local pcall = pcall
local pairs = pairs
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local C_AddOns = C_AddOns
local C_CVar = C_CVar
local SetCVar = SetCVar
local GetCVarBool = GetCVarBool
local GameTooltip = _G.GameTooltip
local GameTooltip_Hide = GameTooltip_Hide
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local NATIVE_AURA_VIEWER_STATE_KEY = "nativeAuraViewerState"
local function IsStringUnitToken(unit)
    if (issecretvalue and issecretvalue(unit)) or type(unit) ~= "string" then
        return false
    end
    return true
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function AddCooldownIDToList(list, seen, cooldownID)
    if type(cooldownID) ~= "number" or cooldownID <= 0 or seen[cooldownID] then
        return
    end

    seen[cooldownID] = true
    list[#list + 1] = cooldownID
end

local function AddCooldownSetToList(list, seen, cooldownSet)
    if type(cooldownSet) ~= "table" then
        return
    end

    for cooldownID in pairs(cooldownSet) do
        AddCooldownIDToList(list, seen, cooldownID)
    end
end

local function SetCVarIfDifferent(name, value)
    local desired = value and true or false
    local current = nil
    if type(GetCVarBool) == "function" then
        local ok, cvarValue = pcall(GetCVarBool, name)
        if ok and type(cvarValue) == "boolean" and not IsSecret(cvarValue) then
            current = cvarValue
        end
    end

    if current == desired then
        return true
    end

    if C_CVar and type(C_CVar.SetCVar) == "function" then
        local ok = pcall(C_CVar.SetCVar, name, desired and 1 or 0)
        return ok and true or false
    end
    if type(SetCVar) == "function" then
        local ok = pcall(SetCVar, name, desired and 1 or 0)
        return ok and true or false
    end

    return false
end

local function IsAddonLoaded(addonName)
    if type(addonName) ~= "string" or addonName == "" then
        return false
    end

    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, addonName)
        if ok and loaded then
            return true
        end
    end

    if type(_G.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(_G.IsAddOnLoaded, addonName)
        if ok and loaded then
            return true
        end
    end

    return false
end

local function LoadAddonIfNeeded(addonName)
    if IsAddonLoaded(addonName) then
        return true
    end

    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        local ok, loaded = pcall(C_AddOns.LoadAddOn, addonName)
        if ok and loaded ~= false then
            return true
        end
    end

    if type(_G.LoadAddOn) == "function" then
        local ok, loaded = pcall(_G.LoadAddOn, addonName)
        if ok and loaded ~= false then
            return true
        end
    end

    return IsAddonLoaded(addonName)
end

local function GetNativeAuraViewerState(viewer)
    local state = CDM:StateGet(viewer, NATIVE_AURA_VIEWER_STATE_KEY)
    if type(state) ~= "table" then
        state = {}
        CDM:StateSet(viewer, NATIVE_AURA_VIEWER_STATE_KEY, state)
    end

    return state
end

local function SnapshotNativeAuraViewerState(viewer)
    local state = GetNativeAuraViewerState(viewer)

    if state.originalAlpha == nil and type(viewer.GetAlpha) == "function" then
        local ok, alpha = pcall(viewer.GetAlpha, viewer)
        if ok and type(alpha) == "number" and not IsSecret(alpha) then
            state.originalAlpha = alpha
        else
            state.originalAlpha = 1
        end
    end

    if state.originalMouseEnabled == nil and type(viewer.IsMouseEnabled) == "function" then
        local ok, mouseEnabled = pcall(viewer.IsMouseEnabled, viewer)
        if ok and type(mouseEnabled) == "boolean" then
            state.originalMouseEnabled = mouseEnabled
        end
    end

    return state
end

local function ApplyViewerInteractivity(viewer, enabled)
    if not viewer then
        return
    end

    local inputEnabled = enabled and true or false
    if type(viewer.EnableMouse) == "function" then
        pcall(viewer.EnableMouse, viewer, inputEnabled)
    end
    if type(viewer.SetMouseClickEnabled) == "function" then
        pcall(viewer.SetMouseClickEnabled, viewer, inputEnabled)
    end
    if type(viewer.SetMouseMotionEnabled) == "function" then
        pcall(viewer.SetMouseMotionEnabled, viewer, inputEnabled)
    end

    local itemPool = viewer.itemFramePool
    if type(itemPool) ~= "table" or type(itemPool.EnumerateActive) ~= "function" then
        return
    end

    for itemFrame in itemPool:EnumerateActive() do
        if type(itemFrame.EnableMouse) == "function" then
            pcall(itemFrame.EnableMouse, itemFrame, inputEnabled)
        end
        if type(itemFrame.SetMouseClickEnabled) == "function" then
            pcall(itemFrame.SetMouseClickEnabled, itemFrame, inputEnabled)
        end
        if type(itemFrame.SetMouseMotionEnabled) == "function" then
            pcall(itemFrame.SetMouseMotionEnabled, itemFrame, inputEnabled)
        end
    end
end

local function HideViewerTooltip(viewer)
    if not GameTooltip or type(GameTooltip.GetOwner) ~= "function" or type(GameTooltip_Hide) ~= "function" then
        return
    end

    local ok, owner = pcall(GameTooltip.GetOwner, GameTooltip)
    if not ok or not owner then
        return
    end

    if owner == viewer then
        GameTooltip_Hide()
        return
    end

    local itemPool = viewer.itemFramePool
    if type(itemPool) ~= "table" or type(itemPool.EnumerateActive) ~= "function" then
        return
    end

    for itemFrame in itemPool:EnumerateActive() do
        if owner == itemFrame then
            GameTooltip_Hide()
            return
        end
    end
end

local function GetViewerShownState(viewer)
    if not viewer or type(viewer.IsShown) ~= "function" then
        return false
    end

    local ok, shown = pcall(viewer.IsShown, viewer)
    if not ok or IsSecret(shown) then
        return false
    end

    return shown == true
end

local function EnsureNativeAuraViewerBlocker(viewer)
    if not viewer then
        return nil
    end

    local state = GetNativeAuraViewerState(viewer)
    if state.blockerFrame then
        return state.blockerFrame
    end

    local blocker = CreateFrame("Frame", nil, viewer)
    blocker:EnableMouse(true)
    blocker:SetClampedToScreen(false)
    blocker:SetAllPoints(viewer)
    blocker:SetScript("OnEnter", function()
        HideViewerTooltip(viewer)
    end)
    blocker:SetScript("OnMouseDown", function()
    end)
    blocker:SetScript("OnMouseUp", function()
    end)
    blocker:SetScript("OnHide", function()
        HideViewerTooltip(viewer)
    end)

    state.blockerFrame = blocker
    return blocker
end

local function SyncNativeAuraViewerBlocker(viewer, suppressNativeViewers)
    local blocker = EnsureNativeAuraViewerBlocker(viewer)
    if not blocker then
        return
    end

    blocker:SetFrameStrata(viewer:GetFrameStrata())
    blocker:SetFrameLevel((viewer:GetFrameLevel() or 0) + 50)
    blocker:SetShown(suppressNativeViewers and GetViewerShownState(viewer))
end

local function CancelScheduledRefreshWork()
    if RefineUI.CancelTimer then
        RefineUI:CancelTimer(CDM.UPDATE_TIMER_KEY)
    end
    if RefineUI.CancelThrottle then
        RefineUI:CancelThrottle(CDM.UPDATE_THROTTLE_KEY)
    end

    CDM.refreshUpdateScheduled = nil
    CDM.refreshUpdatePending = nil
    CDM.pendingDirtyCooldownIDs = nil
end

local function WasRefineRuntimeOwnerPreviouslyActive(previousEnabled, previousMode)
    return previousEnabled ~= false and previousMode ~= "blizzard"
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:EnsureBlizzardCooldownManagerEnabled()
    local changed = SetCVarIfDifferent("cooldownViewerEnabled", true)
    if changed then
        self.refineRuntimeTouchedBlizzard = true
    end
    return changed
end

function CDM:InitializeRefineRuntime()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return
    end

    if self.InitializeAssignments then
        self:InitializeAssignments()
    end
    if self.InitializeTrackers then
        self:InitializeTrackers()
    end
    if self.InitializeVisuals then
        self:InitializeVisuals()
    end

    if self.EnsureBlizzardPrimaryAuraRuntime then
        self:EnsureBlizzardPrimaryAuraRuntime()
    end
end

function CDM:HandleRuntimeModeConfigurationChanged(previousEnabled, previousMode)
    local wasRefineRuntimeActive = WasRefineRuntimeOwnerPreviouslyActive(previousEnabled, previousMode)
    local refineRuntimeActive = self.IsRefineRuntimeOwnerActive and self:IsRefineRuntimeOwnerActive()

    if refineRuntimeActive then
        self:InitializeRefineRuntime()
        if not wasRefineRuntimeActive and self.ActivateStoredRefineBlizzardLayout then
            self:ActivateStoredRefineBlizzardLayout()
        end
    end

    self:HandleRuntimeOwnerStateChanged()

    if wasRefineRuntimeActive
        and not refineRuntimeActive
        and self.refineRuntimeTouchedBlizzard
        and self.RequireReloadForBlizzardIsolation
    then
        self:RequireReloadForBlizzardIsolation()
    end
end

function CDM:EnsureBlizzardCooldownViewerLoaded()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return false
    end

    local loaded = LoadAddonIfNeeded("Blizzard_CooldownViewer")
    if loaded then
        self.refineRuntimeTouchedBlizzard = true
    end
    return loaded
end

function CDM:EnsureBlizzardBridgeReady()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return false
    end

    local cvarReady = self:EnsureBlizzardCooldownManagerEnabled()
    local addonReady = self:EnsureBlizzardCooldownViewerLoaded()
    return addonReady or cvarReady
end

function CDM:ShouldEnableAuraProbeFallback(snapshot)
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return false
    end

    snapshot = snapshot or (self.GetAssignedCooldownSnapshot and self:GetAssignedCooldownSnapshot()) or nil
    return type(snapshot) == "table" and snapshot.hasAssignments == true
end

function CDM:EnsureOptionalAuraProbeFallback(snapshot)
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return false
    end
    if not self:ShouldEnableAuraProbeFallback(snapshot) then
        return false
    end
    if not self:EnsureBlizzardBridgeReady() then
        return false
    end
    if self.InitializeAuraProbe then
        self:InitializeAuraProbe()
    end
    if self.InitializeNativeAuraViewerHooks then
        self:InitializeNativeAuraViewerHooks()
    end
    return self.auraProbeInitialized == true
end

function CDM:EnsureBlizzardPrimaryAuraRuntime(snapshot)
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        self.blizzardPrimaryAuraRuntimeActive = nil
        return false
    end

    if not self:EnsureOptionalAuraProbeFallback(snapshot) then
        self.blizzardPrimaryAuraRuntimeActive = nil
        return false
    end

    if self.CanUseStoredRefineBlizzardLayout and self:CanUseStoredRefineBlizzardLayout() then
        self.blizzardAssignmentSyncActive = true
        self.blizzardPrimaryAuraRuntimeActive = true
        return true
    end

    self.blizzardAssignmentSyncActive = nil
    self.blizzardPrimaryAuraRuntimeActive = nil
    return false
end

function CDM:ApplyNativeAuraViewerVisibility(force)
    local refineRuntimeActive = self.IsRefineRuntimeOwnerActive and self:IsRefineRuntimeOwnerActive()
    local suppressNativeViewers = refineRuntimeActive and self:ShouldHideNativeAuraViewers()
    if not suppressNativeViewers and not self.nativeAuraViewerVisibilityApplied then
        return
    end

    for i = 1, #self.NATIVE_AURA_VIEWERS do
        local viewer = _G[self.NATIVE_AURA_VIEWERS[i]]
        if viewer then
            local viewerState = SnapshotNativeAuraViewerState(viewer)
            SyncNativeAuraViewerBlocker(viewer, suppressNativeViewers)

            if suppressNativeViewers then
                ApplyViewerInteractivity(viewer, false)
                if type(viewer.SetAlpha) == "function" then
                    viewer:SetAlpha(0)
                end
                HideViewerTooltip(viewer)
            else
                local mouseEnabled = viewerState.originalMouseEnabled
                ApplyViewerInteractivity(viewer, mouseEnabled ~= false)
                if type(viewer.SetAlpha) == "function" then
                    viewer:SetAlpha(type(viewerState.originalAlpha) == "number" and viewerState.originalAlpha or 1)
                end
            end
        end
    end

    self.nativeAuraViewerVisibilityApplied = suppressNativeViewers and true or nil
end

function CDM:HandleRuntimeOwnerStateChanged()
    local refineRuntimeActive = self.IsRefineRuntimeOwnerActive and self:IsRefineRuntimeOwnerActive()

    if not refineRuntimeActive then
        CancelScheduledRefreshWork()
        if self.HideTrackers then
            self:HideTrackers()
        end
        if self.RestorePreviousBlizzardLayout then
            self:RestorePreviousBlizzardLayout()
        end
        self:ApplyNativeAuraViewerVisibility(true)
        return
    end

    if self.EnsureBlizzardPrimaryAuraRuntime then
        self:EnsureBlizzardPrimaryAuraRuntime()
    end

    self:ApplyNativeAuraViewerVisibility(true)

    if self.PrimeRuntimeAuraCache then
        self:PrimeRuntimeAuraCache()
    end
end

function CDM:InitializeNativeAuraViewerHooks()
    if self.nativeAuraViewerHooksInstalled then
        return
    end
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return
    end
    if not self.auraProbeInitialized then
        return
    end

    for i = 1, #self.NATIVE_AURA_VIEWERS do
        local viewer = _G[self.NATIVE_AURA_VIEWERS[i]]
        if viewer then
            RefineUI:HookScriptOnce("CDM:NativeViewer:" .. self.NATIVE_AURA_VIEWERS[i] .. ":OnShow", viewer, "OnShow", function()
                CDM:ApplyNativeAuraViewerVisibility(true)
            end)
        end
    end

    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame then
        RefineUI:HookScriptOnce("CDM:NativeViewer:SettingsOnShow", settingsFrame, "OnShow", function()
            CDM:ApplyNativeAuraViewerVisibility(true)
        end)
        RefineUI:HookScriptOnce("CDM:NativeViewer:SettingsOnHide", settingsFrame, "OnHide", function()
            CDM:ApplyNativeAuraViewerVisibility(true)
        end)
    end

    self.nativeAuraViewerHooksInstalled = true
end

function CDM:ShouldProcessAuraUnit(unit)
    if not self:IsRefineRuntimeOwnerActive() then
        return false
    end
    if not IsStringUnitToken(unit) then
        return false
    end
    return unit == "player" or unit == "target"
end

function CDM:MarkAssignedCooldownSnapshotDirty()
    self.assignedCooldownSnapshotDirty = true
end

function CDM:GetAssignedCooldownSnapshot()
    local layoutKey = self.GetCurrentLayoutKey and self:GetCurrentLayoutKey() or "0:0"
    local cached = self.assignedCooldownSnapshot
    if cached and not self.assignedCooldownSnapshotDirty and cached.layoutKey == layoutKey then
        return cached
    end

    local snapshot = {
        layoutKey = layoutKey,
        allAssignedIDs = {},
        requiresPlayerAura = false,
        requiresTargetAura = false,
        hasAssignments = false,
        cooldownBuckets = {},
        bucketCooldownIDs = {},
        associatedSpellToCooldownIDs = {},
        playerSpellToCooldownIDs = {},
        targetSpellToCooldownIDs = {},
        totemSpellToCooldownIDs = {},
        playerDependentCooldownIDs = {},
        targetDependentCooldownIDs = {},
    }

    local seen = {}
    local assignments = self.GetCurrentAssignments and self:GetCurrentAssignments()
    if type(assignments) == "table" then
        for i = 1, #self.TRACKER_BUCKETS do
            local bucket = self.TRACKER_BUCKETS[i]
            local ids = assignments[bucket]
            if type(ids) == "table" then
                snapshot.bucketCooldownIDs[bucket] = {}
                for n = 1, #ids do
                    local cooldownID = ids[n]
                    if type(cooldownID) == "number" and cooldownID > 0 then
                        snapshot.hasAssignments = true
                        snapshot.bucketCooldownIDs[bucket][#snapshot.bucketCooldownIDs[bucket] + 1] = cooldownID

                        local bucketList = snapshot.cooldownBuckets[cooldownID]
                        if type(bucketList) ~= "table" then
                            bucketList = {}
                            snapshot.cooldownBuckets[cooldownID] = bucketList
                        end
                        bucketList[#bucketList + 1] = bucket

                        if not seen[cooldownID] then
                            seen[cooldownID] = true
                            tinsert(snapshot.allAssignedIDs, cooldownID)

                            local info = self.GetCooldownInfo and self:GetCooldownInfo(cooldownID)
                            local associatedSpellIDs = self.GetAssociatedSpellIDs and self:GetAssociatedSpellIDs(info) or nil
                            if type(associatedSpellIDs) == "table" then
                                for spellIndex = 1, #associatedSpellIDs do
                                    local spellID = associatedSpellIDs[spellIndex]
                                    if type(spellID) == "number" and spellID > 0 then
                                        local associatedSet = snapshot.associatedSpellToCooldownIDs[spellID]
                                        if type(associatedSet) ~= "table" then
                                            associatedSet = {}
                                            snapshot.associatedSpellToCooldownIDs[spellID] = associatedSet
                                        end
                                        associatedSet[cooldownID] = true
                                    end
                                end
                            end

                            if not IsSecret(info) and type(info) == "table" then
                                local selfAura = info.selfAura
                                if not IsSecret(selfAura) and selfAura == false then
                                    -- Some target-classified cooldowns can still resolve from
                                    -- player aura events first (for example self-cast target buffs),
                                    -- so refresh ownership must include both units.
                                    snapshot.requiresPlayerAura = true
                                    snapshot.requiresTargetAura = true
                                    snapshot.playerDependentCooldownIDs[cooldownID] = true
                                    snapshot.targetDependentCooldownIDs[cooldownID] = true
                                    if type(associatedSpellIDs) == "table" then
                                        for spellIndex = 1, #associatedSpellIDs do
                                            local spellID = associatedSpellIDs[spellIndex]
                                            if type(spellID) == "number" and spellID > 0 then
                                                local playerSet = snapshot.playerSpellToCooldownIDs[spellID]
                                                if type(playerSet) ~= "table" then
                                                    playerSet = {}
                                                    snapshot.playerSpellToCooldownIDs[spellID] = playerSet
                                                end
                                                playerSet[cooldownID] = true

                                                local targetSet = snapshot.targetSpellToCooldownIDs[spellID]
                                                if type(targetSet) ~= "table" then
                                                    targetSet = {}
                                                    snapshot.targetSpellToCooldownIDs[spellID] = targetSet
                                                end
                                                targetSet[cooldownID] = true

                                                local totemSet = snapshot.totemSpellToCooldownIDs[spellID]
                                                if type(totemSet) ~= "table" then
                                                    totemSet = {}
                                                    snapshot.totemSpellToCooldownIDs[spellID] = totemSet
                                                end
                                                totemSet[cooldownID] = true
                                            end
                                        end
                                    end
                                elseif not IsSecret(selfAura) and selfAura == true then
                                    snapshot.requiresPlayerAura = true
                                    snapshot.playerDependentCooldownIDs[cooldownID] = true
                                    if type(associatedSpellIDs) == "table" then
                                        for spellIndex = 1, #associatedSpellIDs do
                                            local spellID = associatedSpellIDs[spellIndex]
                                            if type(spellID) == "number" and spellID > 0 then
                                                local playerSet = snapshot.playerSpellToCooldownIDs[spellID]
                                                if type(playerSet) ~= "table" then
                                                    playerSet = {}
                                                    snapshot.playerSpellToCooldownIDs[spellID] = playerSet
                                                end
                                                playerSet[cooldownID] = true

                                                local totemSet = snapshot.totemSpellToCooldownIDs[spellID]
                                                if type(totemSet) ~= "table" then
                                                    totemSet = {}
                                                    snapshot.totemSpellToCooldownIDs[spellID] = totemSet
                                                end
                                                totemSet[cooldownID] = true
                                            end
                                        end
                                    end
                                else
                                    snapshot.requiresPlayerAura = true
                                    snapshot.requiresTargetAura = true
                                    snapshot.playerDependentCooldownIDs[cooldownID] = true
                                    snapshot.targetDependentCooldownIDs[cooldownID] = true
                                    if type(associatedSpellIDs) == "table" then
                                        for spellIndex = 1, #associatedSpellIDs do
                                            local spellID = associatedSpellIDs[spellIndex]
                                            if type(spellID) == "number" and spellID > 0 then
                                                local playerSet = snapshot.playerSpellToCooldownIDs[spellID]
                                                if type(playerSet) ~= "table" then
                                                    playerSet = {}
                                                    snapshot.playerSpellToCooldownIDs[spellID] = playerSet
                                                end
                                                playerSet[cooldownID] = true

                                                local targetSet = snapshot.targetSpellToCooldownIDs[spellID]
                                                if type(targetSet) ~= "table" then
                                                    targetSet = {}
                                                    snapshot.targetSpellToCooldownIDs[spellID] = targetSet
                                                end
                                                targetSet[cooldownID] = true

                                                local totemSet = snapshot.totemSpellToCooldownIDs[spellID]
                                                if type(totemSet) ~= "table" then
                                                    totemSet = {}
                                                    snapshot.totemSpellToCooldownIDs[spellID] = totemSet
                                                end
                                                totemSet[cooldownID] = true
                                            end
                                        end
                                    end
                                end
                            else
                                snapshot.requiresPlayerAura = true
                                snapshot.requiresTargetAura = true
                                snapshot.playerDependentCooldownIDs[cooldownID] = true
                                snapshot.targetDependentCooldownIDs[cooldownID] = true
                            end
                        end
                    end
                end
            else
                snapshot.bucketCooldownIDs[bucket] = {}
            end
        end
    end

    self.assignedCooldownSnapshot = snapshot
    self.assignedCooldownSnapshotDirty = nil
    return snapshot
end

function CDM:ShouldRefreshForAuraEvent(event, unit)
    if not self:IsRefineRuntimeOwnerActive() then
        return false
    end
    local snapshot = self:GetAssignedCooldownSnapshot()
    if not snapshot or not snapshot.hasAssignments then
        return false
    end

    if event == "UNIT_AURA" then
        if unit == "player" then
            return snapshot.requiresPlayerAura
        end
        if unit == "target" then
            return snapshot.requiresTargetAura
        end
        return false
    end

    if event == "UNIT_TARGET" then
        return snapshot.requiresTargetAura
    end

    if event == "PLAYER_TOTEM_UPDATE" then
        return snapshot.hasAssignments
    end

    return true
end

function CDM:IsSettingsFrameShown()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    return settingsFrame and settingsFrame:IsShown() and true or false
end

function CDM:ShouldRefreshNow()
    return self:IsRefineRuntimeOwnerActive()
end

function CDM:GetDirtyCooldownIDsForEvent(event, unit)
    if not self:IsRefineRuntimeOwnerActive() then
        return nil
    end
    local snapshot = self:GetAssignedCooldownSnapshot()
    if not snapshot or not snapshot.hasAssignments then
        return nil
    end

    local dirtyCooldownIDs = {}
    local seen = {}

    if event == "UNIT_AURA" then
        local dependentCooldownIDs = nil
        if unit == "player" then
            dependentCooldownIDs = snapshot.playerDependentCooldownIDs
        elseif unit == "target" then
            dependentCooldownIDs = snapshot.targetDependentCooldownIDs
        end

        AddCooldownSetToList(dirtyCooldownIDs, seen, dependentCooldownIDs)
        return #dirtyCooldownIDs > 0 and dirtyCooldownIDs or nil
    end

    if event == "UNIT_TARGET" then
        AddCooldownSetToList(dirtyCooldownIDs, seen, snapshot.targetDependentCooldownIDs)
        return #dirtyCooldownIDs > 0 and dirtyCooldownIDs or nil
    end

    if event == "PLAYER_TOTEM_UPDATE" then
        AddCooldownSetToList(dirtyCooldownIDs, seen, snapshot.playerDependentCooldownIDs)
        return #dirtyCooldownIDs > 0 and dirtyCooldownIDs or nil
    end

    return nil
end

function CDM:RequestRefresh(force, dirtyCooldownIDs)
    if not self:IsRefineRuntimeOwnerActive() then
        CancelScheduledRefreshWork()
        if self.HideTrackers then
            self:HideTrackers()
        end
        return
    end

    if not force and not self:ShouldRefreshNow() then
        return
    end

    if type(dirtyCooldownIDs) == "table" and #dirtyCooldownIDs > 0 then
        local pendingDirtyCooldownIDs = self.pendingDirtyCooldownIDs
        if type(pendingDirtyCooldownIDs) ~= "table" then
            pendingDirtyCooldownIDs = {}
            self.pendingDirtyCooldownIDs = pendingDirtyCooldownIDs
        end
        for i = 1, #dirtyCooldownIDs do
            local cooldownID = dirtyCooldownIDs[i]
            if type(cooldownID) == "number" and cooldownID > 0 then
                pendingDirtyCooldownIDs[cooldownID] = true
            end
        end
    end

    if self.refreshUpdateScheduled then
        self.refreshUpdatePending = true
        return
    end

    self.refreshUpdateScheduled = true

    local function RunRefresh()
        CDM.refreshUpdateScheduled = nil
        CDM:IncrementPerfCounter("cdm_full_refresh")
        CDM:RefreshAll()
        if CDM.refreshUpdatePending then
            CDM.refreshUpdatePending = nil
            CDM:RequestRefresh()
        end
    end

    if RefineUI.After then
        RefineUI:After(self.UPDATE_TIMER_KEY, 0, RunRefresh)
        return
    end

    RefineUI:Throttle(self.UPDATE_THROTTLE_KEY, 0, RunRefresh)
end

function CDM:RefreshAll()
    if not self:IsRefineRuntimeOwnerActive() then
        if self.HideTrackers then
            self:HideTrackers()
        end
        return
    end

    if self.PruneCurrentLayoutAssignments and self.assignmentsPruneDirty and not self:IsEditModeActive() then
        self:PruneCurrentLayoutAssignments()
    end

    local pendingDirtyCooldownIDs = self.pendingDirtyCooldownIDs
    self.pendingDirtyCooldownIDs = nil

    if self.RefreshTrackers then
        self:RefreshTrackers(pendingDirtyCooldownIDs)
    end

    if (not InCombatLockdown or not InCombatLockdown())
        and self:IsSettingsFrameShown()
        and self.RefreshSettingsSection
    then
        self:RefreshSettingsSection()
    end
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function CDM:OnEnable()
    RefineUI:CreateDataRegistry(self.STATE_REGISTRY, "k")

    self:InitializeAssignments()
    self:InitializeSettingsInjection()

    if not self.cdmSlashCommandRegistered and RefineUI.RegisterChatCommand then
        RefineUI:RegisterChatCommand("cdm", function()
            if CDM.OpenSettingsPanel then
                CDM:OpenSettingsPanel()
            else
                RefineUI:Print("CDM settings are unavailable right now.")
            end
        end)
        self.cdmSlashCommandRegistered = true
    end

    if self:IsRefineRuntimeOwnerActive() then
        self:InitializeRefineRuntime()
    end
    self:HandleRuntimeOwnerStateChanged()

    local function InvalidateRuntimeState()
        if not self:IsRefineRuntimeOwnerActive() then
            return
        end
        if self.InvalidateCooldownCatalog then
            self:InvalidateCooldownCatalog()
        end
        if self.InvalidateRuntimeResolver then
            self:InvalidateRuntimeResolver()
        end
        if self.InvalidateAuraProbeCache then
            self:InvalidateAuraProbeCache()
        end
        if self.MarkAssignmentsPruneDirty then
            self:MarkAssignmentsPruneDirty()
        end
        if self.MarkAssignedCooldownSnapshotDirty then
            self:MarkAssignedCooldownSnapshotDirty()
        end
        if self.EnsureOptionalAuraProbeFallback then
            self:EnsureOptionalAuraProbeFallback()
        end
        if self.PrimeRuntimeAuraCache then
            self:PrimeRuntimeAuraCache()
        end
        if self.RequestAuraProbeReconcile then
            self:RequestAuraProbeReconcile()
        end
    end

    local function OnEvent(event, ...)
        local dirtyCooldownIDs = nil
        if event == "UNIT_TARGET" then
            if not self:IsRefineRuntimeOwnerActive() then
                return
            end
            local unit = ...
            if not IsStringUnitToken(unit) or unit ~= "player" then
                return
            end
            if not self:ShouldRefreshForAuraEvent(event, "target") then
                return
            end
            dirtyCooldownIDs = self:GetDirtyCooldownIDsForEvent(event, "target")
            if self.ClearRuntimeAuraCache then
                self:ClearRuntimeAuraCache("target")
            end
            if self.PrimeRuntimeAuraCache then
                self:PrimeRuntimeAuraCache("target")
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            if not self:IsRefineRuntimeOwnerActive() then
                return
            end
            local unit = ...
            if not IsStringUnitToken(unit) or unit ~= "player" then
                return
            end
            InvalidateRuntimeState()
        elseif event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_REGEN_DISABLED"
            or event == "PLAYER_REGEN_ENABLED"
            or event == "TRAIT_CONFIG_UPDATED"
            or event == "SPELLS_CHANGED"
            or event == "ADDON_LOADED"
            or event == "COOLDOWN_VIEWER_DATA_LOADED"
            or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED"
        then
            if event == "PLAYER_REGEN_DISABLED" then
                self.lastCombatEndedTime = nil
            elseif event == "PLAYER_REGEN_ENABLED" and type(GetTime) == "function" then
                self.lastCombatEndedTime = GetTime()
            end

            if event == "ADDON_LOADED" then
                local addonName = ...
                if addonName ~= "Blizzard_CooldownViewer" then
                    return
                end
                if not self:IsRefineRuntimeOwnerActive() then
                    self:HandleRuntimeOwnerStateChanged()
                    return
                end
                self.nativeAuraViewerHooksInstalled = nil
                if self.InitializeAuraProbe then
                    self:InitializeAuraProbe()
                end
                self:InitializeNativeAuraViewerHooks()
            end
            InvalidateRuntimeState()
        end

        if event == "ADDON_LOADED"
            or event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_REGEN_ENABLED"
            or event == "COOLDOWN_VIEWER_DATA_LOADED"
        then
            self:HandleRuntimeOwnerStateChanged()
            if event == "PLAYER_ENTERING_WORLD"
                and self.RequestPendingPostReloadSettingsOpen
            then
                self:RequestPendingPostReloadSettingsOpen()
            end
        end
        self:RequestRefresh(true, dirtyCooldownIDs)
    end

    if not self.lifecycleEventsRegistered then
        RefineUI:OnEvents({
            "ADDON_LOADED",
            "PLAYER_ENTERING_WORLD",
            "PLAYER_REGEN_DISABLED",
            "PLAYER_REGEN_ENABLED",
            "PLAYER_SPECIALIZATION_CHANGED",
            "TRAIT_CONFIG_UPDATED",
            "SPELLS_CHANGED",
            "UNIT_TARGET",
            "COOLDOWN_VIEWER_DATA_LOADED",
            "COOLDOWN_VIEWER_TABLE_HOTFIXED",
        }, OnEvent, "CDM:Lifecycle")
        self.lifecycleEventsRegistered = true
    end

    -- Route secret-heavy aura events through the shared EventBus so the raw
    -- UNIT_AURA updateInfo table never enters addon code.
    RefineUI:RegisterEventCallback("UNIT_AURA", function(_event, unit)
        if not self:IsRefineRuntimeOwnerActive() then
            return
        end
        if not self:ShouldProcessAuraUnit(unit) then
            return
        end
        if self.PrimeRuntimeAuraCache then
            self:PrimeRuntimeAuraCache(unit)
        end
        if not self:ShouldRefreshForAuraEvent("UNIT_AURA", unit) then
            return
        end
        self:RequestRefresh(true, self:GetDirtyCooldownIDsForEvent("UNIT_AURA", unit))
    end, "CDM:Runtime:UnitAura")

    RefineUI:RegisterEventCallback("PLAYER_TOTEM_UPDATE", function()
        if not self:IsRefineRuntimeOwnerActive() then
            return
        end
        if not self:ShouldRefreshForAuraEvent("PLAYER_TOTEM_UPDATE", "player") then
            return
        end
        self:RequestRefresh(true, self:GetDirtyCooldownIDsForEvent("PLAYER_TOTEM_UPDATE", "player"))
    end, "CDM:Runtime:PlayerTotemUpdate")

    if RefineUI.LibEditMode and type(RefineUI.LibEditMode.RegisterCallback) == "function" then
        RefineUI.LibEditMode:RegisterCallback("enter", function()
            CDM:ApplyNativeAuraViewerVisibility(true)
            CDM:RequestRefresh(true)
        end)
        RefineUI.LibEditMode:RegisterCallback("exit", function()
            CDM:ApplyNativeAuraViewerVisibility(true)
            CDM:RequestRefresh(true)
        end)
    end

    if _G.EditModeManagerFrame then
        RefineUI:HookScriptOnce("CDM:EditMode:OnShow", _G.EditModeManagerFrame, "OnShow", function()
            CDM:ApplyNativeAuraViewerVisibility(true)
            CDM:RequestRefresh(true)
        end)
        RefineUI:HookScriptOnce("CDM:EditMode:OnHide", _G.EditModeManagerFrame, "OnHide", function()
            CDM:ApplyNativeAuraViewerVisibility(true)
            CDM:RequestRefresh(true)
        end)
    end

    local cvarRegistry = _G.CVarCallbackRegistry
    if cvarRegistry and type(cvarRegistry.RegisterCallback) == "function" and not self.cooldownViewerEnabledCVarCallbackRegistered then
        cvarRegistry:RegisterCallback("cooldownViewerEnabled", function()
            CDM:HandleRuntimeOwnerStateChanged()
        end, self)
        self.cooldownViewerEnabledCVarCallbackRegistered = true
    end

    self:RequestRefresh(true)
end
