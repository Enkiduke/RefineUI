local _, RefineUI = ...
local Module = RefineUI:RegisterModule("CooldownAuraTrackers")

local _G = _G
local type = type
local tonumber = tonumber
local tinsert = table.insert
local issecretvalue = _G.issecretvalue
local CreateFrame = CreateFrame
local UIParent = UIParent
local ReloadUI = ReloadUI

Module.TRACKER_BUCKETS = { "Left", "Right", "Bottom" }
Module.NOT_TRACKED_KEY = "NotTracked"
Module.BUCKET_LABELS = {
    Left = "Left",
    Right = "Right",
    Bottom = "Bottom",
    NotTracked = "Not Tracked",
}
Module.TRACKER_FRAME_NAMES = {
    Left = "RefineUI_CDM_LeftTracker",
    Right = "RefineUI_CDM_RightTracker",
    Bottom = "RefineUI_CDM_BottomTracker",
}
Module.TRACKER_DEFAULT_DIRECTION = {
    Left = "LEFT",
    Right = "RIGHT",
    Bottom = "LEFT",
}
Module.SETTINGS_SECTION_TITLE = "RefineUI Aura Trackers"
Module.UPDATE_THROTTLE_KEY = "CooldownAuraTrackers:Refresh"
Module.UPDATE_TIMER_KEY = "CooldownAuraTrackers:Refresh:NextFrame"
Module.STATE_REGISTRY = "CooldownAuraTrackers:State"
Module.NATIVE_AURA_VIEWERS = {
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local function IsStringUnitToken(unit)
    if (issecretvalue and issecretvalue(unit)) or type(unit) ~= "string" then
        return false
    end
    return true
end

function Module:GetConfig()
    RefineUI.Config.CooldownAuraTrackers = RefineUI.Config.CooldownAuraTrackers or {}
    local cfg = RefineUI.Config.CooldownAuraTrackers
    if cfg.Enable == nil then
        cfg.Enable = true
    end
    if type(cfg.IconSize) ~= "number" then
        cfg.IconSize = 44
    end
    if type(cfg.IconScale) ~= "number" then
        if type(cfg.IconSize) == "number" and cfg.IconSize > 0 then
            cfg.IconScale = cfg.IconSize / 44
        else
            cfg.IconScale = 1
        end
    end
    if type(cfg.Spacing) ~= "number" then
        cfg.Spacing = 6
    end
    if type(cfg.BucketSettings) ~= "table" then
        cfg.BucketSettings = {}
    end
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        if type(cfg.BucketSettings[bucket]) ~= "table" then
            cfg.BucketSettings[bucket] = {}
        end
        if type(cfg.BucketSettings[bucket].IconScale) ~= "number" then
            local legacySize = cfg.BucketSettings[bucket].IconSize
            if type(legacySize) == "number" and legacySize > 0 then
                cfg.BucketSettings[bucket].IconScale = legacySize / 44
            else
                cfg.BucketSettings[bucket].IconScale = cfg.IconScale
            end
        end
        if type(cfg.BucketSettings[bucket].Spacing) ~= "number" then
            cfg.BucketSettings[bucket].Spacing = cfg.Spacing
        end
        if cfg.BucketSettings[bucket].Orientation ~= "VERTICAL" then
            cfg.BucketSettings[bucket].Orientation = "HORIZONTAL"
        end
        if type(cfg.BucketSettings[bucket].Direction) ~= "string" or cfg.BucketSettings[bucket].Direction == "" then
            cfg.BucketSettings[bucket].Direction = self.TRACKER_DEFAULT_DIRECTION[bucket] or "RIGHT"
        end
    end
    if cfg.HideNativeAuraViewers == nil then
        cfg.HideNativeAuraViewers = true
    end
    if cfg.AuraMode ~= "blizzard" then
        cfg.AuraMode = "refineui"
    end
    if cfg.SyncStrategy ~= "auto_safe" and cfg.SyncStrategy ~= "mirror_only" then
        cfg.SyncStrategy = "auto_safe"
    end
    if cfg.SourceScope ~= "all_auras" then
        cfg.SourceScope = "buffs_exact"
    end
    if type(cfg.PayloadGhostTTL) ~= "number" then
        cfg.PayloadGhostTTL = 0.20
    end
    if cfg.PayloadGhostTTL < 0 then
        cfg.PayloadGhostTTL = 0
    elseif cfg.PayloadGhostTTL > 2 then
        cfg.PayloadGhostTTL = 2
    end
    if type(cfg.LayoutAssignments) ~= "table" then
        cfg.LayoutAssignments = {}
    end
    return cfg
end

function Module:IsEnabled()
    return self:GetConfig().Enable ~= false
end

function Module:GetCooldownViewerSettingsFrame()
    return _G.CooldownViewerSettings
end

function Module:StateGet(owner, key, defaultValue)
    return RefineUI:RegistryGet(self.STATE_REGISTRY, owner, key, defaultValue)
end

function Module:StateSet(owner, key, value)
    return RefineUI:RegistrySet(self.STATE_REGISTRY, owner, key, value)
end

function Module:StateClear(owner, key)
    return RefineUI:RegistryClear(self.STATE_REGISTRY, owner, key)
end

function Module:MarkReloadRecommendationPending()
    self.reloadRecommendationPending = true
end

function Module:ShowReloadRecommendationPrompt()
    if self.ReloadPrompt then
        self.ReloadPrompt:Show()
        return
    end

    local frame = CreateFrame("Frame", "RefineUI_CooldownAuraTrackersReloadPrompt", UIParent)
    RefineUI:AddAPI(frame)
    frame:SetSize(360, 150)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetTemplate("Transparent")
    frame:EnableMouse(true)

    local header = CreateFrame("Frame", nil, frame)
    RefineUI:AddAPI(header)
    header:SetSize(360, 26)
    header:SetPoint("TOP", frame, "TOP", 0, 0)
    header:SetTemplate("Overlay")

    local title = header:CreateFontString(nil, "OVERLAY")
    RefineUI:AddAPI(title)
    title:Font(14, nil, nil, true)
    title:SetPoint("CENTER", header, "CENTER", 0, 0)
    title:SetText("Cooldown Settings Updated")
    title:SetTextColor(1, 0.82, 0)

    local message = frame:CreateFontString(nil, "OVERLAY")
    RefineUI:AddAPI(message)
    message:Font(12, nil, nil, true)
    message:SetPoint("TOP", header, "BOTTOM", 0, -15)
    message:SetWidth(330)
    message:SetText("A UI reload is recommended after changing\ntracked cooldown aura settings.")

    local reloadButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    RefineUI:AddAPI(reloadButton)
    reloadButton:SetSize(110, 26)
    reloadButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -12, 15)
    reloadButton:SkinButton()
    reloadButton:SetText("Reload")
    reloadButton:SetScript("OnClick", function()
        ReloadUI()
    end)

    local laterButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    RefineUI:AddAPI(laterButton)
    laterButton:SetSize(110, 26)
    laterButton:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 12, 15)
    laterButton:SkinButton()
    laterButton:SetText("Later")
    laterButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    self.ReloadPrompt = frame
end

function Module:ShowReloadRecommendationIfPending()
    if not self.reloadRecommendationPending then
        return
    end

    self.reloadRecommendationPending = nil
    self:ShowReloadRecommendationPrompt()
end

function Module:ShouldProcessAuraUnit(unit)
    if not IsStringUnitToken(unit) then
        return false
    end
    return unit == "player" or unit == "target"
end

function Module:MarkAssignedCooldownSnapshotDirty()
    self.assignedCooldownSnapshotDirty = true
end

function Module:GetAssignedCooldownSnapshot()
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

function Module:ShouldRefreshForAuraEvent(event, unit)
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

function Module:IsSettingsFrameShown()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    return settingsFrame and settingsFrame:IsShown() and true or false
end

function Module:ShouldRefreshNow()
    if self.IsEditModeActive and self:IsEditModeActive() then
        return true
    end

    if self:IsSettingsFrameShown() then
        return true
    end

    return self:IsRefineAuraModeActive()
end

function Module:RequestRefresh(force)
    if not force and not self:ShouldRefreshNow() then
        return
    end

    if self.refreshUpdateScheduled then
        self.refreshUpdatePending = true
        return
    end

    self.refreshUpdateScheduled = true

    local function RunRefresh()
        Module.refreshUpdateScheduled = nil
        Module:RefreshAll()
        if Module.refreshUpdatePending then
            Module.refreshUpdatePending = nil
            Module:RequestRefresh()
        end
    end

    if RefineUI.After then
        RefineUI:After(self.UPDATE_TIMER_KEY, 0, RunRefresh)
        return
    end

    RefineUI:Throttle(self.UPDATE_THROTTLE_KEY, 0, RunRefresh)
end

function Module:GetSyncStrategy()
    return self:GetConfig().SyncStrategy or "auto_safe"
end

function Module:GetSourceScope()
    return self:GetConfig().SourceScope or "buffs_exact"
end

function Module:GetPayloadGhostTTL()
    local ttl = self:GetConfig().PayloadGhostTTL
    if type(ttl) ~= "number" then
        return 0.20
    end
    if ttl < 0 then
        return 0
    end
    if ttl > 2 then
        return 2
    end
    return ttl
end

function Module:GetAuraMode()
    local cfg = self:GetConfig()
    if cfg.AuraMode == "blizzard" then
        return "blizzard"
    end
    return "refineui"
end

function Module:IsRefineAuraModeActive()
    return self:GetAuraMode() == "refineui"
end

function Module:SetAuraMode(mode)
    local cfg = self:GetConfig()
    if mode == "blizzard" then
        cfg.AuraMode = "blizzard"
    else
        cfg.AuraMode = "refineui"
    end

    self:ApplyNativeAuraViewerVisibility()
    self:RequestRefresh(true)
end

function Module:ShouldHideNativeAuraViewers()
    local cfg = self:GetConfig()
    return cfg.HideNativeAuraViewers ~= false
end

function Module:ApplyNativeAuraViewerVisibility()
    local suppressNativeViewers = self:IsEnabled()
        and self:IsRefineAuraModeActive()
        and self:ShouldHideNativeAuraViewers()

    for i = 1, #self.NATIVE_AURA_VIEWERS do
        local viewer = _G[self.NATIVE_AURA_VIEWERS[i]]
        if viewer then
            local originalAlpha = self:StateGet(viewer, "nativeAuraViewerOriginalAlpha")
            if originalAlpha == nil then
                self:StateSet(viewer, "nativeAuraViewerOriginalAlpha", viewer:GetAlpha() or 1)
            end

            local originalMouse = self:StateGet(viewer, "nativeAuraViewerOriginalMouse")
            if originalMouse == nil and type(viewer.IsMouseEnabled) == "function" then
                self:StateSet(viewer, "nativeAuraViewerOriginalMouse", viewer:IsMouseEnabled() and true or false)
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
                    if type(alpha) ~= "number" then
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

function Module:InitializeNativeAuraViewerHooks()
    if self.nativeAuraViewerHooksInstalled then
        return
    end

    for i = 1, #self.NATIVE_AURA_VIEWERS do
        local viewerName = self.NATIVE_AURA_VIEWERS[i]
        local viewer = _G[viewerName]
        if viewer then
            RefineUI:HookScriptOnce("CooldownAuraTrackers:NativeViewer:OnShow:" .. viewerName, viewer, "OnShow", function()
                Module:ApplyNativeAuraViewerVisibility()
            end)
        end
    end

    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame then
        RefineUI:HookScriptOnce("CooldownAuraTrackers:NativeViewer:SettingsOnShow", settingsFrame, "OnShow", function()
            Module:ApplyNativeAuraViewerVisibility()
        end)
        RefineUI:HookScriptOnce("CooldownAuraTrackers:NativeViewer:SettingsOnHide", settingsFrame, "OnHide", function()
            Module:ApplyNativeAuraViewerVisibility()
        end)
    end

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_event, addonName)
        if addonName == "Blizzard_CooldownViewer" then
            Module.nativeAuraViewerHooksInstalled = nil
            Module:InitializeNativeAuraViewerHooks()
            Module:ApplyNativeAuraViewerVisibility()
        end
    end, "CooldownAuraTrackers:NativeViewer:AddonLoaded")

    self.nativeAuraViewerHooksInstalled = true
end

function Module:RefreshAll()
    local inEditMode = self.IsEditModeActive and self:IsEditModeActive()
    local settingsShown = self:IsSettingsFrameShown()

    if not self:IsEnabled() then
        self:ApplyNativeAuraViewerVisibility()
        if self.HideTrackers then
            self:HideTrackers()
        end
        return
    end

    self:ApplyNativeAuraViewerVisibility()
    if not inEditMode and not self:IsRefineAuraModeActive() then
        if self.HideTrackers then
            self:HideTrackers()
        end
        if settingsShown and self.RefreshSettingsSection then
            self:RefreshSettingsSection()
        end
        return
    end

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

function Module:OnEnable()
    if not self:IsEnabled() then
        return
    end

    RefineUI:CreateDataRegistry(self.STATE_REGISTRY, "k")

    self:InitializeAssignments()
    self:InitializeAuraProbe()
    self:InitializeTrackers()
    self:InitializeSettingsInjection()
    self:InitializeNativeAuraViewerHooks()

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
    }, OnEvent, "CooldownAuraTrackers")

    if RefineUI.LibEditMode and type(RefineUI.LibEditMode.RegisterCallback) == "function" then
        RefineUI.LibEditMode:RegisterCallback("enter", function()
            Module:RequestRefresh()
        end)
        RefineUI.LibEditMode:RegisterCallback("exit", function()
            Module:RequestRefresh()
        end)
    end

    if _G.EditModeManagerFrame then
        RefineUI:HookScriptOnce("CooldownAuraTrackers:EditMode:OnShow", _G.EditModeManagerFrame, "OnShow", function()
            Module:RequestRefresh()
        end)
        RefineUI:HookScriptOnce("CooldownAuraTrackers:EditMode:OnHide", _G.EditModeManagerFrame, "OnHide", function()
            Module:RequestRefresh()
        end)
    end

    self:ApplyNativeAuraViewerVisibility()
    self:RequestRefresh(true)
end
