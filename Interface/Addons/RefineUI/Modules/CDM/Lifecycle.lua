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
local C_AddOns = C_AddOns
local C_CVar = C_CVar
local SetCVar = SetCVar
local GetCVarBool = GetCVarBool
local issecretvalue = _G.issecretvalue

local lifecycleEventFrame = CreateFrame("Frame")
lifecycleEventFrame:RegisterEvent("UNIT_AURA")
lifecycleEventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
lifecycleEventFrame:RegisterEvent("ADDON_LOADED")
lifecycleEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
lifecycleEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
lifecycleEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
lifecycleEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
lifecycleEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
lifecycleEventFrame:RegisterEvent("SPELLS_CHANGED")
lifecycleEventFrame:RegisterEvent("UNIT_TARGET")
lifecycleEventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
lifecycleEventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
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

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:EnsureBlizzardCooldownManagerEnabled()
    if not self:IsEnabled() then
        return false
    end
    return SetCVarIfDifferent("cooldownViewerEnabled", true)
end

function CDM:EnsureBlizzardCooldownViewerLoaded()
    if not self:IsEnabled() then
        return false
    end

    return LoadAddonIfNeeded("Blizzard_CooldownViewer")
end

function CDM:EnsureBlizzardBridgeReady()
    if not self:IsEnabled() then
        return false
    end

    local cvarReady = self:EnsureBlizzardCooldownManagerEnabled()
    local addonReady = self:EnsureBlizzardCooldownViewerLoaded()
    return cvarReady or addonReady
end

function CDM:ApplyNativeAuraViewerVisibility(force)
    if not self:IsEnabled() then
        return
    end
    if self.IsBlizzardCooldownManagerEnabled and not self:IsBlizzardCooldownManagerEnabled() then
        return
    end
    if not force
        and self.IsEditModeActive
        and self:IsEditModeActive()
        and not self:IsRefineAuraModeActive()
    then
        return
    end

    local suppressNativeViewers = self:IsRefineAuraModeActive() and self:ShouldHideNativeAuraViewers()
    for i = 1, #self.NATIVE_AURA_VIEWERS do
        local viewer = _G[self.NATIVE_AURA_VIEWERS[i]]
        if viewer then
            if viewer._refineUICDMOriginalAlpha == nil and type(viewer.GetAlpha) == "function" then
                local ok, alpha = pcall(viewer.GetAlpha, viewer)
                if ok and type(alpha) == "number" and not IsSecret(alpha) then
                    viewer._refineUICDMOriginalAlpha = alpha
                else
                    viewer._refineUICDMOriginalAlpha = 1
                end
            end

            if viewer._refineUICDMOriginalMouse == nil and type(viewer.IsMouseEnabled) == "function" then
                local ok, mouseEnabled = pcall(viewer.IsMouseEnabled, viewer)
                if ok and type(mouseEnabled) == "boolean" then
                    viewer._refineUICDMOriginalMouse = mouseEnabled
                end
            end

            if suppressNativeViewers then
                if type(viewer.SetAlpha) == "function" then
                    viewer:SetAlpha(0)
                end
                if type(viewer.EnableMouse) == "function" then
                    viewer:EnableMouse(false)
                end
            else
                if type(viewer.SetAlpha) == "function" then
                    viewer:SetAlpha(type(viewer._refineUICDMOriginalAlpha) == "number" and viewer._refineUICDMOriginalAlpha or 1)
                end
                if type(viewer.EnableMouse) == "function" then
                    if type(viewer._refineUICDMOriginalMouse) == "boolean" then
                        viewer:EnableMouse(viewer._refineUICDMOriginalMouse)
                    else
                        viewer:EnableMouse(true)
                    end
                end
            end
        end
    end
end

function CDM:InitializeNativeAuraViewerHooks()
    if self.nativeAuraViewerHooksInstalled then
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
                                    snapshot.requiresTargetAura = true
                                    snapshot.targetDependentCooldownIDs[cooldownID] = true
                                    if type(associatedSpellIDs) == "table" then
                                        for spellIndex = 1, #associatedSpellIDs do
                                            local spellID = associatedSpellIDs[spellIndex]
                                            if type(spellID) == "number" and spellID > 0 then
                                                local targetSet = snapshot.targetSpellToCooldownIDs[spellID]
                                                if type(targetSet) ~= "table" then
                                                    targetSet = {}
                                                    snapshot.targetSpellToCooldownIDs[spellID] = targetSet
                                                end
                                                targetSet[cooldownID] = true
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
    return self:IsEnabled()
end

function CDM:GetDirtyCooldownIDsForEvent(event, unit, unitAuraUpdateInfo)
    local snapshot = self:GetAssignedCooldownSnapshot()
    if not snapshot or not snapshot.hasAssignments then
        return nil
    end

    local dirtyCooldownIDs = {}
    local seen = {}

    if event == "UNIT_AURA" then
        local spellToCooldownIDs = nil
        local dependentCooldownIDs = nil
        if unit == "player" then
            spellToCooldownIDs = snapshot.playerSpellToCooldownIDs
            dependentCooldownIDs = snapshot.playerDependentCooldownIDs
        elseif unit == "target" then
            spellToCooldownIDs = snapshot.targetSpellToCooldownIDs
            dependentCooldownIDs = snapshot.targetDependentCooldownIDs
        end

        if type(unitAuraUpdateInfo) == "table" and type(unitAuraUpdateInfo.addedAuras) == "table" then
            for auraIndex = 1, #unitAuraUpdateInfo.addedAuras do
                local auraData = unitAuraUpdateInfo.addedAuras[auraIndex]
                if type(auraData) == "table" then
                    local spellID = auraData.spellID
                    if IsSecret(spellID) or type(spellID) ~= "number" or spellID <= 0 then
                        spellID = auraData.spellId
                    end
                    if not IsSecret(spellID) and type(spellID) == "number" and spellID > 0 then
                        AddCooldownSetToList(dirtyCooldownIDs, seen, spellToCooldownIDs and spellToCooldownIDs[spellID])
                    end
                end
            end
        end

        if #dirtyCooldownIDs == 0 then
            AddCooldownSetToList(dirtyCooldownIDs, seen, dependentCooldownIDs)
        end

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
    if not self:IsEnabled() then
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

    if self:IsSettingsFrameShown() and self.RefreshSettingsSection then
        self:RefreshSettingsSection()
    end
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function CDM:OnEnable()
    if not self:IsEnabled() then
        return
    end

    RefineUI:CreateDataRegistry(self.STATE_REGISTRY, "k")

    self:InitializeAssignments()
    self:InitializeTrackers()
    self:InitializeSettingsInjection()
    self:InitializeVisuals()
    self:EnsureBlizzardBridgeReady()
    if self.InitializeAuraProbe then
        self:InitializeAuraProbe()
    end
    self:InitializeNativeAuraViewerHooks()
    self:ApplyNativeAuraViewerVisibility(true)

    if self.ShouldUseRuntimeResolverFallback
        and self:ShouldUseRuntimeResolverFallback()
        and self.PrimeRuntimeAuraCache
    then
        self:PrimeRuntimeAuraCache()
    end

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

    local function InvalidateRuntimeState()
        if self.InvalidateCooldownCatalog then
            self:InvalidateCooldownCatalog()
        end
        if self.ShouldUseRuntimeResolverFallback
            and self:ShouldUseRuntimeResolverFallback()
            and self.InvalidateRuntimeResolver
        then
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
        if self.ShouldUseRuntimeResolverFallback
            and self:ShouldUseRuntimeResolverFallback()
            and self.PrimeRuntimeAuraCache
        then
            self:PrimeRuntimeAuraCache()
        end
        if self.RequestAuraProbeReconcile then
            self:RequestAuraProbeReconcile()
        end
    end

    local function OnEvent(_frame, event, ...)
        local dirtyCooldownIDs = nil
        if event == "UNIT_TARGET" then
            local unit = ...
            if not IsStringUnitToken(unit) or unit ~= "player" then
                return
            end
            if not self:ShouldRefreshForAuraEvent(event, "target") then
                return
            end
            dirtyCooldownIDs = self:GetDirtyCooldownIDsForEvent(event, "target")
            if self.ShouldUseRuntimeResolverFallback
                and self:ShouldUseRuntimeResolverFallback()
                and self.ClearRuntimeAuraCache
            then
                self:ClearRuntimeAuraCache("target")
            end
            if self.ShouldUseRuntimeResolverFallback
                and self:ShouldUseRuntimeResolverFallback()
                and self.PrimeRuntimeAuraCache
            then
                self:PrimeRuntimeAuraCache("target")
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
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
            if event == "ADDON_LOADED" then
                local addonName = ...
                if addonName ~= "Blizzard_CooldownViewer" then
                    return
                end
                self.nativeAuraViewerHooksInstalled = nil
                self:InitializeNativeAuraViewerHooks()
                if self.InstallBlizzardSettingsRedirect then
                    self:InstallBlizzardSettingsRedirect()
                end
                self.viewerVisualHooksInstalled = nil
                if self.InitializeVisuals then
                    self:InitializeVisuals()
                end
                if self.InstallVisualMenuHooks then
                    self:InstallVisualMenuHooks()
                end
                if self.RequestCooldownViewerVisualRefresh then
                    self:RequestCooldownViewerVisualRefresh()
                end
            end
            InvalidateRuntimeState()
        end

        if event == "ADDON_LOADED"
            or event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_REGEN_ENABLED"
        then
            self:EnsureBlizzardBridgeReady()
            self:ApplyNativeAuraViewerVisibility(true)
        end
        self:RequestRefresh(true, dirtyCooldownIDs)
    end

    lifecycleEventFrame:SetScript("OnEvent", function(frame, event, ...)
        if event == "UNIT_AURA" then
            local unit, unitAuraUpdateInfo = ...
            if not self:ShouldProcessAuraUnit(unit) then
                return
            end
            if self.ShouldUseRuntimeResolverFallback
                and self:ShouldUseRuntimeResolverFallback()
                and self.HandleUnitAuraUpdate
            then
                self:HandleUnitAuraUpdate(unit, unitAuraUpdateInfo)
            end
            if not self:ShouldRefreshForAuraEvent(event, unit) then
                return
            end
            self:RequestRefresh(true, self:GetDirtyCooldownIDsForEvent(event, unit, unitAuraUpdateInfo))
            return
        elseif event == "PLAYER_TOTEM_UPDATE" then
            if not self:ShouldRefreshForAuraEvent(event, "player") then
                return
            end
            self:RequestRefresh(true, self:GetDirtyCooldownIDsForEvent(event, "player"))
            return
        end

        OnEvent(frame, event, ...)
    end)

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
            CDM:EnsureBlizzardBridgeReady()
            CDM:ApplyNativeAuraViewerVisibility(true)
        end, self)
        self.cooldownViewerEnabledCVarCallbackRegistered = true
    end

    if self.RequestAuraProbeReconcile then
        self:RequestAuraProbeReconcile()
    end
    self:RequestRefresh(true)
end
