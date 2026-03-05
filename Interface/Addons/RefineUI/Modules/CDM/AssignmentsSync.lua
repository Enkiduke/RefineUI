----------------------------------------------------------------------------------------
-- CDM Component: AssignmentsSync
-- Description: Synchronization of assignment state with Blizzard tracked-buff layouts.
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

local C_CooldownViewer = C_CooldownViewer
local InCombatLockdown = InCombatLockdown
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TRACKED_BUFF = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff
local TRACKED_BAR = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar
local HIDDEN_AURA = (Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.HiddenAura) or -2

local LAYOUT_STATUS_SUCCESS = Enum and Enum.CooldownLayoutStatus and Enum.CooldownLayoutStatus.Success

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsUsableCooldownID(value)
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return type(value) == "number" and value > 0
end

local function IsSuccessStatus(status)
    if issecretvalue and issecretvalue(status) then
        return false
    end
    if status == nil then
        return true
    end
    if LAYOUT_STATUS_SUCCESS ~= nil then
        return status == LAYOUT_STATUS_SUCCESS
    end
    return status == true or status == 0
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:SyncAssignedCooldownsToTrackedBuff(layoutKey)
    if self.GetSyncStrategy and self:GetSyncStrategy() == "mirror_only" then
        return false, false
    end

    if not TRACKED_BUFF then
        return false, false
    end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, false
    end

    local provider, settingsFrame = self:GetCooldownViewerDataProvider()
    if not provider or type(provider.SetCooldownToCategory) ~= "function" then
        return false, false
    end
    if not settingsFrame or not settingsFrame:IsShown() then
        return false, false
    end

    local layoutManager = nil
    if settingsFrame and type(settingsFrame.GetLayoutManager) == "function" then
        layoutManager = settingsFrame:GetLayoutManager()
    elseif type(provider.GetLayoutManager) == "function" then
        layoutManager = provider:GetLayoutManager()
    end

    if self:IsLayoutManagerBusy(layoutManager) then
        return false, false
    end

    local scoped = self:GetScopedAssignments(layoutKey)
    local assignedSet = self:GetAssignedIDSet(scoped)
    local changed = false
    local lockApplied = false

    if layoutManager and type(layoutManager.LockNotifications) == "function" then
        local okLock = pcall(layoutManager.LockNotifications, layoutManager)
        lockApplied = okLock and true or false
    end

    for cooldownID in pairs(assignedSet) do
        if IsUsableCooldownID(cooldownID) then
            local info = provider.GetCooldownInfoForID and provider:GetCooldownInfoForID(cooldownID)
            local currentCategory = info and info.category
            if currentCategory ~= TRACKED_BUFF then
                local okSet, status = pcall(provider.SetCooldownToCategory, provider, cooldownID, TRACKED_BUFF)
                if okSet and IsSuccessStatus(status) then
                    changed = true
                end
            end
        end
    end

    if lockApplied and layoutManager and type(layoutManager.UnlockNotifications) == "function" then
        pcall(layoutManager.UnlockNotifications, layoutManager, false)
    end

    if changed then
        if type(provider.MarkDirty) == "function" then
            pcall(provider.MarkDirty, provider)
        end
        if settingsFrame and type(settingsFrame.SaveCurrentLayout) == "function" then
            pcall(settingsFrame.SaveCurrentLayout, settingsFrame)
        end
        if self.MarkReloadRecommendationPending then
            self:MarkReloadRecommendationPending()
        end
    end

    return changed, true
end


function CDM:SyncCurrentLayoutToTrackedBuff()
    return self:SyncAssignedCooldownsToTrackedBuff(self:GetCurrentLayoutKey())
end


function CDM:HasUnsafeSecretCooldownState()
    return false
end


function CDM:IsLayoutManagerBusy(layoutManager)
    local manager = layoutManager
    if not manager then
        local settingsFrame = self:GetCooldownViewerSettingsFrame()
        if settingsFrame and type(settingsFrame.GetLayoutManager) == "function" then
            manager = settingsFrame:GetLayoutManager()
        end
    end

    if not manager then
        return false
    end

    if type(manager.AreNotificationsLocked) == "function" then
        local okLocked, isLocked = pcall(manager.AreNotificationsLocked, manager)
        if okLocked and not (issecretvalue and issecretvalue(isLocked)) and isLocked then
            return true
        end
    end

    if not (issecretvalue and issecretvalue(manager.notificationLockCount))
        and type(manager.notificationLockCount) == "number"
        and manager.notificationLockCount > 0
    then
        return true
    end

    if not (issecretvalue and issecretvalue(manager.notifying)) and manager.notifying == true then
        return true
    end

    return false
end


function CDM:ScheduleTrackedBuffSyncRetry()
    return false
end


function CDM:RequestTrackedBuffSync(layoutKey)
    if self.GetSyncStrategy and self:GetSyncStrategy() == "mirror_only" then
        return false
    end

    self.pendingTrackedBuffSync = true
    self.pendingTrackedBuffSyncKey = layoutKey or self:GetCurrentLayoutKey()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame and settingsFrame:IsShown() then
        return self:ProcessPendingTrackedBuffSync()
    end
    return false
end


function CDM:ProcessPendingTrackedBuffSync()
    if not self.pendingTrackedBuffSync then
        return false
    end

    if self.GetSyncStrategy and self:GetSyncStrategy() == "mirror_only" then
        self.pendingTrackedBuffSync = nil
        self.pendingTrackedBuffSyncKey = nil
        return true
    end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end

    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if not settingsFrame or not settingsFrame:IsShown() then
        return false
    end

    local provider = self:GetCooldownViewerDataProvider()
    if not provider then
        return false
    end

    local changed, attempted = self:SyncAssignedCooldownsToTrackedBuff(self.pendingTrackedBuffSyncKey)
    if not attempted then
        return false
    end

    self.pendingTrackedBuffSync = nil
    self.pendingTrackedBuffSyncKey = nil
    return changed or true
end


function CDM:ClearBlizzardTrackedBuffCategory()
    if (not TRACKED_BUFF and not TRACKED_BAR) or not HIDDEN_AURA then
        return false, false
    end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, false
    end

    local provider, settingsFrame = self:GetCooldownViewerDataProvider()
    if not provider or type(provider.SetCooldownToCategory) ~= "function" then
        return false, false
    end
    if not settingsFrame or not settingsFrame:IsShown() then
        return false, false
    end

    local layoutManager = nil
    if settingsFrame and type(settingsFrame.GetLayoutManager) == "function" then
        layoutManager = settingsFrame:GetLayoutManager()
    elseif type(provider.GetLayoutManager) == "function" then
        layoutManager = provider:GetLayoutManager()
    end

    if self:IsLayoutManagerBusy(layoutManager) then
        return false, false
    end

    local categoriesToClear = {}
    if TRACKED_BUFF then
        categoriesToClear[#categoriesToClear + 1] = TRACKED_BUFF
    end
    if TRACKED_BAR and TRACKED_BAR ~= TRACKED_BUFF then
        categoriesToClear[#categoriesToClear + 1] = TRACKED_BAR
    end

    local trackedIDs = {}
    local seenIDs = {}
    for i = 1, #categoriesToClear do
        local category = categoriesToClear[i]
        local categoryIDs = nil
        if type(provider.GetOrderedCooldownIDsForCategory) == "function" then
            categoryIDs = provider:GetOrderedCooldownIDsForCategory(category, true)
        end
        if type(categoryIDs) ~= "table"
            and C_CooldownViewer
            and type(C_CooldownViewer.GetCooldownViewerCategorySet) == "function" then
            categoryIDs = C_CooldownViewer.GetCooldownViewerCategorySet(category, true)
        end

        if type(categoryIDs) == "table" then
            for n = 1, #categoryIDs do
                local cooldownID = categoryIDs[n]
                if IsUsableCooldownID(cooldownID) and not seenIDs[cooldownID] then
                    seenIDs[cooldownID] = true
                    trackedIDs[#trackedIDs + 1] = cooldownID
                end
            end
        end
    end

    local changed = false
    local lockApplied = false
    if layoutManager and type(layoutManager.LockNotifications) == "function" then
        local okLock = pcall(layoutManager.LockNotifications, layoutManager)
        lockApplied = okLock and true or false
    end

    for i = 1, #trackedIDs do
        local cooldownID = trackedIDs[i]
        if IsUsableCooldownID(cooldownID) then
            local info = provider.GetCooldownInfoForID and provider:GetCooldownInfoForID(cooldownID)
            local currentCategory = info and info.category
            if currentCategory == TRACKED_BUFF or currentCategory == TRACKED_BAR then
                local okSet, status = pcall(provider.SetCooldownToCategory, provider, cooldownID, HIDDEN_AURA)
                if okSet and IsSuccessStatus(status) then
                    changed = true
                end
            end
        end
    end

    if lockApplied and layoutManager and type(layoutManager.UnlockNotifications) == "function" then
        pcall(layoutManager.UnlockNotifications, layoutManager, false)
    end

    if changed then
        if type(provider.MarkDirty) == "function" then
            pcall(provider.MarkDirty, provider)
        end
        if settingsFrame and type(settingsFrame.SaveCurrentLayout) == "function" then
            pcall(settingsFrame.SaveCurrentLayout, settingsFrame)
        end
        if self.MarkReloadRecommendationPending then
            self:MarkReloadRecommendationPending()
        end
        self:MarkAssignmentsPruneDirty()
    end

    return changed, true
end


function CDM:RequestInitialTrackedBuffClear()
    local cfg = self:GetConfig()
    if cfg.BlizzardTrackedBuffsCleared == true then
        self.pendingInitialTrackedBuffClear = nil
        return true
    end

    local changed, attempted = self:ClearBlizzardTrackedBuffCategory()
    if attempted then
        cfg.BlizzardTrackedBuffsCleared = true
        self.pendingInitialTrackedBuffClear = nil
        return changed or true
    end

    self.pendingInitialTrackedBuffClear = true
    return false
end


function CDM:ProcessPendingInitialTrackedBuffClear()
    if not self.pendingInitialTrackedBuffClear then
        return false
    end

    return self:RequestInitialTrackedBuffClear()
end

