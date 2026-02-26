----------------------------------------------------------------------------------------
-- CDM Component: Lifecycle
-- Description: Refresh lifecycle decisions, scheduling, and event-driven orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tinsert = table.insert
local issecretvalue = _G.issecretvalue

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


local function GetSafeViewerAlpha(viewer)
    if not viewer or type(viewer.GetAlpha) ~= "function" then
        return nil
    end

    local ok, alpha = pcall(viewer.GetAlpha, viewer)
    if not ok or IsSecret(alpha) or type(alpha) ~= "number" then
        return nil
    end

    return alpha
end


local function GetSafeMouseEnabled(viewer)
    if not viewer or type(viewer.IsMouseEnabled) ~= "function" then
        return nil
    end

    local ok, enabled = pcall(viewer.IsMouseEnabled, viewer)
    if not ok or IsSecret(enabled) or type(enabled) ~= "boolean" then
        return nil
    end

    return enabled
end


----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
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
    }

    local seen = {}
    local assignments = self.GetCurrentAssignments and self:GetCurrentAssignments()
    if type(assignments) == "table" then
        for i = 1, #self.TRACKER_BUCKETS do
            local bucket = self.TRACKER_BUCKETS[i]
            local ids = assignments[bucket]
            if type(ids) == "table" then
                for n = 1, #ids do
                    local cooldownID = ids[n]
                    if type(cooldownID) == "number" and cooldownID > 0 then
                        snapshot.hasAssignments = true
                        if not seen[cooldownID] then
                            seen[cooldownID] = true
                            tinsert(snapshot.allAssignedIDs, cooldownID)

                            local info = self.GetCooldownInfo and self:GetCooldownInfo(cooldownID)
                            if type(info) == "table" then
                                if info.selfAura == false then
                                    snapshot.requiresTargetAura = true
                                elseif info.selfAura == true then
                                    snapshot.requiresPlayerAura = true
                                else
                                    snapshot.requiresPlayerAura = true
                                    snapshot.requiresTargetAura = true
                                end
                            else
                                snapshot.requiresPlayerAura = true
                                snapshot.requiresTargetAura = true
                            end
                        end
                    end
                end
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
            return true
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
        return true
    end

    return true
end


function CDM:IsSettingsFrameShown()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    return settingsFrame and settingsFrame:IsShown() and true or false
end


function CDM:ShouldRefreshNow()
    if not self:IsEnabled() then
        return false
    end

    if self.IsBlizzardCooldownManagerEnabled and not self:IsBlizzardCooldownManagerEnabled() then
        return self:IsSettingsFrameShown()
    end

    if self.IsEditModeActive and self:IsEditModeActive() then
        if not self:IsRefineAuraModeActive() then
            return self:IsSettingsFrameShown()
        end
        return true
    end

    if self:IsSettingsFrameShown() then
        return true
    end

    return self:IsRefineAuraModeActive()
end


function CDM:RequestRefresh(force)
    if not force and not self:ShouldRefreshNow() then
        return
    end

    if self.refreshUpdateScheduled then
        self.refreshUpdatePending = true
        return
    end

    self.refreshUpdateScheduled = true

    local function RunRefresh()
        CDM.refreshUpdateScheduled = nil
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


function CDM:ApplyNativeAuraViewerVisibility(force)
    if self.IsBlizzardCooldownManagerEnabled and not self:IsBlizzardCooldownManagerEnabled() then
        return
    end

    if not force
        and self.IsEditModeActive and self:IsEditModeActive()
        and not self:IsRefineAuraModeActive()
    then
        return
    end

    local suppressNativeViewers = self:IsEnabled()
        and self:IsRefineAuraModeActive()
        and self:ShouldHideNativeAuraViewers()

    for i = 1, #self.NATIVE_AURA_VIEWERS do
        local viewer = _G[self.NATIVE_AURA_VIEWERS[i]]
        if viewer then
            local originalAlpha = self:StateGet(viewer, "nativeAuraViewerOriginalAlpha")
            if originalAlpha == nil then
                self:StateSet(viewer, "nativeAuraViewerOriginalAlpha", GetSafeViewerAlpha(viewer) or 1)
            end

            local originalMouse = self:StateGet(viewer, "nativeAuraViewerOriginalMouse")
            if originalMouse == nil and type(viewer.IsMouseEnabled) == "function" then
                local mouseEnabled = GetSafeMouseEnabled(viewer)
                if type(mouseEnabled) == "boolean" then
                    self:StateSet(viewer, "nativeAuraViewerOriginalMouse", mouseEnabled)
                end
            end

            local appliedSuppressedState = self:StateGet(viewer, "nativeAuraViewerSuppressedState")
            if appliedSuppressedState ~= suppressNativeViewers then
                if suppressNativeViewers then
                    viewer:SetAlpha(0)
                    if type(viewer.EnableMouse) == "function" then
                        viewer:EnableMouse(false)
                    end
                else
                    local alpha = self:StateGet(viewer, "nativeAuraViewerOriginalAlpha", 1)
                    if IsSecret(alpha) or type(alpha) ~= "number" then
                        alpha = 1
                    end
                    viewer:SetAlpha(alpha)

                    if type(viewer.EnableMouse) == "function" then
                        local restoreMouse = self:StateGet(viewer, "nativeAuraViewerOriginalMouse")
                        if type(restoreMouse) == "boolean" then
                            viewer:EnableMouse(restoreMouse)
                        else
                            viewer:EnableMouse(true)
                        end
                    end
                end

                self:StateSet(viewer, "nativeAuraViewerSuppressedState", suppressNativeViewers and true or false)
            end
        end
    end
end


function CDM:InitializeNativeAuraViewerHooks()
    if self.nativeAuraViewerHooksInstalled then
        return
    end

    for i = 1, #self.NATIVE_AURA_VIEWERS do
        local viewerName = self.NATIVE_AURA_VIEWERS[i]
        local viewer = _G[viewerName]
        if viewer then
            RefineUI:HookScriptOnce("CDM:NativeViewer:OnShow:" .. viewerName, viewer, "OnShow", function()
                CDM:ApplyNativeAuraViewerVisibility()
            end)
        end
    end

    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame then
        RefineUI:HookScriptOnce("CDM:NativeViewer:SettingsOnShow", settingsFrame, "OnShow", function()
            CDM:ApplyNativeAuraViewerVisibility()
        end)
        RefineUI:HookScriptOnce("CDM:NativeViewer:SettingsOnHide", settingsFrame, "OnHide", function()
            CDM:ApplyNativeAuraViewerVisibility()
        end)
    end

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_event, addonName)
        if addonName == "Blizzard_CooldownViewer" then
            CDM.nativeAuraViewerHooksInstalled = nil
            CDM:InitializeNativeAuraViewerHooks()
            CDM:ApplyNativeAuraViewerVisibility()
        end
    end, "CDM:NativeViewer:AddonLoaded")

    self.nativeAuraViewerHooksInstalled = true
end


function CDM:RefreshAll()
    local inEditMode = self.IsEditModeActive and self:IsEditModeActive()
    local settingsShown = self:IsSettingsFrameShown()
    local blizzardCooldownManagerEnabled = true
    if self.IsBlizzardCooldownManagerEnabled then
        blizzardCooldownManagerEnabled = self:IsBlizzardCooldownManagerEnabled()
    end

    if not self:IsEnabled() or not blizzardCooldownManagerEnabled then
        self:ApplyNativeAuraViewerVisibility()
        if self.HideTrackers then
            self:HideTrackers()
        end
        if settingsShown and self.RefreshSettingsSection then
            self:RefreshSettingsSection()
        end
        return
    end

    if not self:IsRefineAuraModeActive() then
        if not inEditMode then
            self:ApplyNativeAuraViewerVisibility()
        end
        if self.HideTrackers then
            self:HideTrackers()
        end
        if settingsShown and self.RefreshSettingsSection then
            self:RefreshSettingsSection()
        end
        return
    end

    self:ApplyNativeAuraViewerVisibility()

    if not inEditMode and self.PruneCurrentLayoutAssignments and self.assignmentsPruneDirty then
        self:PruneCurrentLayoutAssignments()
    end

    if self.RefreshTrackers then
        self:RefreshTrackers()
    end

    if settingsShown and self.RefreshSettingsSection then
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
    self:InitializeAuraProbe()
    self:InitializeTrackers()
    self:InitializeSettingsInjection()
    self:InitializeVisuals()
    self:InitializeNativeAuraViewerHooks()

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

    local function OnEvent(event, ...)
        local shouldInvalidateAuraProbe = false
        if event == "UNIT_AURA" then
            local unit = ...
            if not self:ShouldProcessAuraUnit(unit) then
                return
            end
            if not self:ShouldRefreshForAuraEvent(event, unit) then
                return
            end
        elseif event == "UNIT_TARGET" then
            local unit = ...
            if not IsStringUnitToken(unit) or unit ~= "player" then
                return
            end
            if not self:ShouldRefreshForAuraEvent(event, "target") then
                return
            end
        elseif event == "PLAYER_TOTEM_UPDATE" then
            if not self:ShouldRefreshForAuraEvent(event, "player") then
                return
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            local snapshot = self:GetAssignedCooldownSnapshot()
            if not snapshot or not snapshot.hasAssignments then
                return
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            local unit = ...
            if not IsStringUnitToken(unit) or unit ~= "player" then
                return
            end
            shouldInvalidateAuraProbe = true
        elseif event == "PLAYER_ENTERING_WORLD" or event == "TRAIT_CONFIG_UPDATED" or event == "SPELLS_CHANGED"
            or event == "COOLDOWN_VIEWER_DATA_LOADED" or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
            shouldInvalidateAuraProbe = true
        end

        if shouldInvalidateAuraProbe and self.InvalidateAuraProbeCache then
            self:InvalidateAuraProbeCache()
        end
        if shouldInvalidateAuraProbe and self.MarkAssignmentsPruneDirty then
            self:MarkAssignmentsPruneDirty()
        end
        if shouldInvalidateAuraProbe and self.MarkAssignedCooldownSnapshotDirty then
            self:MarkAssignedCooldownSnapshotDirty()
        end
        if shouldInvalidateAuraProbe and self.RequestAuraProbeReconcile then
            self:RequestAuraProbeReconcile()
        end
        if self:ShouldRefreshNow() then
            self:RequestRefresh()
        end
    end

    RefineUI:OnEvents({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_SPECIALIZATION_CHANGED",
        "TRAIT_CONFIG_UPDATED",
        "SPELLS_CHANGED",
        "UNIT_AURA",
        "UNIT_TARGET",
        "PLAYER_TOTEM_UPDATE",
        "PLAYER_REGEN_ENABLED",
        "COOLDOWN_VIEWER_DATA_LOADED",
        "COOLDOWN_VIEWER_TABLE_HOTFIXED",
    }, OnEvent, "CDM")

    if RefineUI.LibEditMode and type(RefineUI.LibEditMode.RegisterCallback) == "function" then
        RefineUI.LibEditMode:RegisterCallback("enter", function()
            CDM:RequestRefresh()
        end)
        RefineUI.LibEditMode:RegisterCallback("exit", function()
            CDM:RequestRefresh()
        end)
    end

    if _G.EditModeManagerFrame then
        RefineUI:HookScriptOnce("CDM:EditMode:OnShow", _G.EditModeManagerFrame, "OnShow", function()
            CDM:RequestRefresh()
        end)
        RefineUI:HookScriptOnce("CDM:EditMode:OnHide", _G.EditModeManagerFrame, "OnHide", function()
            CDM:RequestRefresh()
        end)
    end

    local cvarRegistry = _G.CVarCallbackRegistry
    if cvarRegistry and type(cvarRegistry.RegisterCallback) == "function" and not self.cooldownViewerEnabledCVarCallbackRegistered then
        cvarRegistry:RegisterCallback("cooldownViewerEnabled", function()
            if CDM.RequestCooldownViewerVisualRefresh then
                CDM:RequestCooldownViewerVisualRefresh()
            end
            CDM:RequestRefresh(true)
        end, self)
        self.cooldownViewerEnabledCVarCallbackRegistered = true
    end

    self:ApplyNativeAuraViewerVisibility()
    self:RequestRefresh(true)
end
