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
local pcall = pcall
local next = next
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

    return state
end

-- Blizzard items never take clicks (SetMouseClickEnabled(false)); motion only drives
-- their tooltips. Items claimed by RefineUI trackers manage their own mouse state.
local function SetViewerItemTooltipsEnabled(viewer, enabled)
    local itemPool = viewer.itemFramePool
    if not itemPool then
        return
    end

    for itemFrame in itemPool:EnumerateActive() do
        if not enabled then
            itemFrame:SetMouseMotionEnabled(false)
        elseif itemFrame:GetParent() == viewer then
            itemFrame:SetMouseMotionEnabled(viewer.tooltipsShown ~= false)
        end
    end
end

local function SuppressNativeViewer(viewer)
    viewer:SetAlpha(0)
    SetViewerItemTooltipsEnabled(viewer, false)
end

-- Edit Mode reapplies viewer opacity on layout loads, and Blizzard re-enables item
-- tooltips whenever it acquires items or changes the tooltip setting.
local function OnNativeViewerStateReset(viewer)
    if CDM.nativeAuraViewerVisibilityApplied then
        SuppressNativeViewer(viewer)
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

local function CancelScheduledRefreshWork()
    RefineUI:CancelTimer(CDM.UPDATE_TIMER_KEY)
    CDM.refreshUpdateScheduled = nil
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:EnsureBlizzardCooldownManagerEnabled()
    return SetCVarIfDifferent("cooldownViewerEnabled", true)
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

    self:EnsureBlizzardTrackerRuntime()
end

function CDM:HandleRuntimeModeConfigurationChanged()
    if self:IsRefineRuntimeOwnerActive() then
        self:InitializeRefineRuntime()
    end
    self:HandleRuntimeOwnerStateChanged()
end

function CDM:EnsureBlizzardCooldownViewerLoaded()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return false
    end

    return LoadAddonIfNeeded("Blizzard_CooldownViewer")
end

function CDM:EnsureBlizzardBridgeReady()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return false
    end

    local cvarReady = self:EnsureBlizzardCooldownManagerEnabled()
    local addonReady = self:EnsureBlizzardCooldownViewerLoaded()
    return addonReady or cvarReady
end

-- Tracked buffs render through Blizzard's Tracked Buffs viewer, so it must be loaded
-- and running the saved RefineUI layout whenever buffs are assigned.
function CDM:EnsureBlizzardTrackerRuntime()
    self.blizzardAssignmentSyncActive = nil
    if not self:IsRefineRuntimeOwnerActive() then
        return false
    end
    if not self:GetAssignedCooldownSnapshot().hasAuraAssignments or not self:EnsureBlizzardBridgeReady() then
        return false
    end

    self:InitializeNativeAuraViewerHooks()
    self.blizzardAssignmentSyncActive = self:CanUseStoredRefineBlizzardLayout() or nil
    return self.blizzardAssignmentSyncActive == true
end

function CDM:ApplyNativeAuraViewerVisibility(force)
    local refineRuntimeActive = self.IsRefineRuntimeOwnerActive and self:IsRefineRuntimeOwnerActive()
    local suppressNativeViewers = refineRuntimeActive and self:ShouldHideNativeAuraViewers()
    if not suppressNativeViewers and not self.nativeAuraViewerVisibilityApplied then
        return
    end
    if suppressNativeViewers then
        self:InitializeNativeAuraViewerHooks()
    end

    for i = 1, #self.NATIVE_AURA_VIEWERS do
        local viewer = _G[self.NATIVE_AURA_VIEWERS[i]]
        if viewer then
            local viewerState = SnapshotNativeAuraViewerState(viewer)
            if suppressNativeViewers then
                SuppressNativeViewer(viewer)
                HideViewerTooltip(viewer)
            else
                SetViewerItemTooltipsEnabled(viewer, true)
                viewer:SetAlpha(viewerState.originalAlpha)
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

    self:EnsureBlizzardTrackerRuntime()
    self:ApplyNativeAuraViewerVisibility(true)
end

function CDM:InitializeNativeAuraViewerHooks()
    if self.nativeAuraViewerHooksInstalled then
        return
    end
    if not self:IsRefineRuntimeOwnerActive() or not _G.BuffIconCooldownViewer then
        return
    end

    self:InstallBlizzardTrackerHooks()

    for i = 1, #self.NATIVE_AURA_VIEWERS do
        local viewer = _G[self.NATIVE_AURA_VIEWERS[i]]
        if viewer then
            local key = "CDM:NativeViewer:" .. self.NATIVE_AURA_VIEWERS[i]
            RefineUI:HookScriptOnce(key .. ":OnShow", viewer, "OnShow", function()
                CDM:ApplyNativeAuraViewerVisibility(true)
            end)
            RefineUI:HookOnce(key .. ":UpdateSystemSettingOpacity", viewer, "UpdateSystemSettingOpacity", OnNativeViewerStateReset)
            RefineUI:HookOnce(key .. ":RefreshLayout", viewer, "RefreshLayout", OnNativeViewerStateReset)
            RefineUI:HookOnce(key .. ":SetTooltipsShown", viewer, "SetTooltipsShown", OnNativeViewerStateReset)
        end
    end

    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame then
        RefineUI:HookScriptOnce("CDM:NativeViewer:SettingsOnShow", settingsFrame, "OnShow", function()
            CDM:ApplyNativeAuraViewerVisibility(true)
        end)
        RefineUI:HookScriptOnce("CDM:NativeViewer:SettingsOnHide", settingsFrame, "OnHide", function()
            CDM:ApplyNativeAuraViewerVisibility(true)
            CDM:RequestBlizzardTrackerSetupCheck()
        end)
    end

    self.nativeAuraViewerHooksInstalled = true
end

function CDM:MarkAssignedCooldownSnapshotDirty()
    self.assignedCooldownSnapshotDirty = true
end

function CDM:GetAssignedCooldownSnapshot()
    local layoutKey = self:GetCurrentLayoutKey()
    local cached = self.assignedCooldownSnapshot
    if cached and not self.assignedCooldownSnapshotDirty and cached.layoutKey == layoutKey then
        return cached
    end

    local snapshot = {
        layoutKey = layoutKey,
        hasAssignments = false,
        hasAuraAssignments = false,
        bucketByCooldownID = {},
        bucketCooldownIDs = {},
        externalCooldownIDs = {},
    }

    local assignments = self:GetCurrentAssignments()
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        local ids = assignments[bucket]
        local bucketIDs = {}
        snapshot.bucketCooldownIDs[bucket] = bucketIDs
        for n = 1, #ids do
            local cooldownID = ids[n]
            if type(cooldownID) == "number" and cooldownID > 0 and not snapshot.bucketByCooldownID[cooldownID] then
                snapshot.hasAssignments = true
                snapshot.bucketByCooldownID[cooldownID] = bucket
                bucketIDs[#bucketIDs + 1] = cooldownID
                if self:IsExternalCooldownID(cooldownID) then
                    snapshot.externalCooldownIDs[cooldownID] = true
                else
                    snapshot.hasAuraAssignments = true
                end
            end
        end
    end

    self.assignedCooldownSnapshot = snapshot
    self.assignedCooldownSnapshotDirty = nil
    return snapshot
end

function CDM:IsSettingsFrameShown()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    return settingsFrame and settingsFrame:IsShown() and true or false
end

function CDM:RequestRefresh()
    if not self:IsRefineRuntimeOwnerActive() then
        CancelScheduledRefreshWork()
        self:HideTrackers()
        return
    end

    if self.refreshUpdateScheduled then
        return
    end

    self.refreshUpdateScheduled = true
    RefineUI:After(self.UPDATE_TIMER_KEY, 0, function()
        CDM.refreshUpdateScheduled = nil
        CDM:RefreshAll()
    end)
end

function CDM:RefreshAll()
    if not self:IsRefineRuntimeOwnerActive() then
        self:HideTrackers()
        return
    end

    local inCombat = InCombatLockdown()
    -- Blizzard's cooldown lists can be partial in combat; pruning then would drop saved assignments.
    if self.assignmentsPruneDirty and not inCombat and not self:IsEditModeActive() then
        self:PruneCurrentLayoutAssignments()
    end

    self:RefreshTrackers()

    if not inCombat and self:IsSettingsFrameShown() and self.RefreshSettingsSection then
        self:RefreshSettingsSection()
    end
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function CDM:OnEnable()
    RefineUI:CreateDataRegistry(self.STATE_REGISTRY, "k")

    self:InitializeAssignments()
    if self.ScanExternalCooldowns then
        self:ScanExternalCooldowns()
    end
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
        self:InvalidateCooldownCatalog()
        self:MarkAssignmentsPruneDirty()
        self:MarkAssignedCooldownSnapshotDirty()
        self:EnsureBlizzardTrackerRuntime()
    end

    local function OnEvent(event, ...)
        if event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
            if next(self:GetAssignedCooldownSnapshot().externalCooldownIDs) then
                self:RequestExternalTrackerRefresh()
            end
            return
        elseif event == "PLAYER_REGEN_DISABLED" then
            self.lastCombatEndedTime = nil
            return
        elseif event == "BAG_UPDATE_DELAYED" then
            self:ScanExternalCooldowns()
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            local slot = ...
            if slot ~= 13 and slot ~= 14 then
                return
            end
            self:ScanExternalCooldowns()
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            local unit = ...
            if not IsStringUnitToken(unit) or unit ~= "player" then
                return
            end
            InvalidateRuntimeState()
        elseif event == "ADDON_LOADED" then
            local addonName = ...
            if addonName ~= "Blizzard_CooldownViewer" then
                return
            end
            self.nativeAuraViewerHooksInstalled = nil
            InvalidateRuntimeState()
        else
            if event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
                self:ScanExternalCooldowns()
            elseif event == "PLAYER_REGEN_ENABLED" then
                self.lastCombatEndedTime = GetTime()
            end
            InvalidateRuntimeState()
        end

        if event == "ADDON_LOADED"
            or event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_REGEN_ENABLED"
            or event == "COOLDOWN_VIEWER_DATA_LOADED"
        then
            self:HandleRuntimeOwnerStateChanged()
            if event == "PLAYER_ENTERING_WORLD" then
                self:RequestPendingPostReloadSettingsOpen()
                self:RequestBlizzardTrackerSetupCheck()
            end
        end
        self:RequestRefresh()
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
            "SPELL_UPDATE_COOLDOWN",
            "BAG_UPDATE_DELAYED",
            "BAG_UPDATE_COOLDOWN",
            "PLAYER_EQUIPMENT_CHANGED",
            "COOLDOWN_VIEWER_DATA_LOADED",
            "COOLDOWN_VIEWER_TABLE_HOTFIXED",
        }, OnEvent, "CDM:Lifecycle")
        self.lifecycleEventsRegistered = true
    end

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
            CDM:RequestBlizzardTrackerSetupCheck()
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
