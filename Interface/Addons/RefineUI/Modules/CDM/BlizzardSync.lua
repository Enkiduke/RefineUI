----------------------------------------------------------------------------------------
-- CDM Component: BlizzardSync
-- Description: Dedicated Blizzard CDM layout sync for Refine-owned assignment sets.
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
local pairs = pairs
local tinsert = table.insert
local InCombatLockdown = InCombatLockdown
local Enum = Enum
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local REFINE_BLIZZARD_LAYOUT_NAME = "RefineUI CDM"
local DEFAULT_LAYOUT_ID = 0
local TRACKED_BUFF_CATEGORY = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff or nil
local HIDDEN_AURA_CATEGORY = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.HiddenAura or -2

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function GetSettingsFrame()
    if CDM.GetBlizzardCooldownViewerSettingsFrame then
        return CDM:GetBlizzardCooldownViewerSettingsFrame()
    end
    return _G.CooldownViewerSettings
end

local function GetLoadedSyncContext()
    local settingsFrame = GetSettingsFrame()
    if not settingsFrame then
        return nil
    end

    local layoutManager = type(settingsFrame.GetLayoutManager) == "function" and settingsFrame:GetLayoutManager() or nil
    local dataProvider = type(settingsFrame.GetDataProvider) == "function" and settingsFrame:GetDataProvider() or nil
    if not layoutManager or not dataProvider then
        return nil
    end
    if type(layoutManager.IsLoaded) == "function" and not layoutManager:IsLoaded() then
        return nil
    end
    if type(dataProvider.GetLayoutManager) == "function" and not dataProvider:GetLayoutManager() then
        return nil
    end

    return settingsFrame, layoutManager, dataProvider
end

local function GetStoredSyncState()
    local cfg = CDM.GetConfig and CDM:GetConfig() or nil
    if type(cfg) ~= "table" then
        return nil
    end

    if type(cfg.BlizzardSyncState) ~= "table" then
        cfg.BlizzardSyncState = {}
    end

    local state = cfg.BlizzardSyncState
    if type(state.previousLayoutIDBySpec) ~= "table" then
        state.previousLayoutIDBySpec = {}
    end

    return state
end

local function GetCurrentSpecTag(layoutManager)
    if not layoutManager or type(layoutManager.GetCurrentSpecTag) ~= "function" then
        return nil
    end

    local specTag = layoutManager:GetCurrentSpecTag()
    if type(specTag) == "number" and specTag > 0 and not IsSecret(specTag) then
        return specTag
    end

    return nil
end

local function GetActiveLayoutID(layoutManager)
    if not layoutManager or type(layoutManager.GetActiveLayoutID) ~= "function" then
        return nil
    end

    local activeLayoutID = layoutManager:GetActiveLayoutID()
    if activeLayoutID == nil then
        return DEFAULT_LAYOUT_ID
    end
    if type(activeLayoutID) == "number" and not IsSecret(activeLayoutID) then
        return activeLayoutID
    end

    return DEFAULT_LAYOUT_ID
end

local function GetLayoutID(layout)
    if not layout or type(_G.CooldownManagerLayout_GetID) ~= "function" then
        return nil
    end

    local layoutID = _G.CooldownManagerLayout_GetID(layout)
    if type(layoutID) == "number" and not IsSecret(layoutID) then
        return layoutID
    end

    return nil
end

local function GetLayoutName(layout)
    if not layout or type(_G.CooldownManagerLayout_GetName) ~= "function" then
        return nil
    end

    local layoutName = _G.CooldownManagerLayout_GetName(layout)
    if type(layoutName) == "string" and layoutName ~= "" and not IsSecret(layoutName) then
        return layoutName
    end

    return nil
end

local function FindLayoutByName(layoutManager, layoutName, specTag)
    if not layoutManager then
        return nil
    end

    if type(layoutManager.GetLayoutByName) == "function" then
        local layout = layoutManager:GetLayoutByName(layoutName, specTag)
        if layout then
            return layout
        end
    end

    if type(layoutManager.EnumerateLayouts) ~= "function" then
        return nil
    end

    for _layoutID, layout in layoutManager:EnumerateLayouts() do
        if GetLayoutName(layout) == layoutName then
            if specTag == nil or (type(_G.CooldownManagerLayout_GetClassAndSpecTag) == "function" and _G.CooldownManagerLayout_GetClassAndSpecTag(layout) == specTag) then
                return layout
            end
        end
    end

    return nil
end

local function SetTableValue(target, key, value)
    if type(target) == "table" and key ~= nil then
        target[key] = value
    end
end

local function CopyAssignedCooldownIDs(snapshot)
    local ordered = {}
    local assignedSet = {}
    if type(snapshot) ~= "table" or type(snapshot.bucketCooldownIDs) ~= "table" then
        return ordered, assignedSet
    end

    for i = 1, #CDM.TRACKER_BUCKETS do
        local bucket = CDM.TRACKER_BUCKETS[i]
        local ids = snapshot.bucketCooldownIDs[bucket]
        if type(ids) == "table" then
            for n = 1, #ids do
                local cooldownID = ids[n]
                if type(cooldownID) == "number" and cooldownID > 0 and not assignedSet[cooldownID] then
                    assignedSet[cooldownID] = true
                    ordered[#ordered + 1] = cooldownID
                end
            end
        end
    end

    return ordered, assignedSet
end

local function BuildOrderedCooldownIDs(defaultOrderedCooldownIDs, assignedOrderedIDs, assignedSet)
    local ordered = {}
    local seen = {}

    if type(assignedOrderedIDs) == "table" then
        for i = 1, #assignedOrderedIDs do
            local cooldownID = assignedOrderedIDs[i]
            if type(cooldownID) == "number" and cooldownID > 0 and not seen[cooldownID] then
                seen[cooldownID] = true
                ordered[#ordered + 1] = cooldownID
            end
        end
    end

    if type(defaultOrderedCooldownIDs) == "table" then
        for i = 1, #defaultOrderedCooldownIDs do
            local cooldownID = defaultOrderedCooldownIDs[i]
            if type(cooldownID) == "number" and cooldownID > 0 and not seen[cooldownID] then
                seen[cooldownID] = true
                ordered[#ordered + 1] = cooldownID
            end
        end
    end

    if type(assignedSet) == "table" then
        for cooldownID in pairs(assignedSet) do
            if type(cooldownID) == "number" and cooldownID > 0 and not seen[cooldownID] then
                seen[cooldownID] = true
                ordered[#ordered + 1] = cooldownID
            end
        end
    end

    return ordered
end

local function BuildCategoryCooldownIDs(validAuraCooldownIDs, assignedSet)
    local trackedBuffIDs = {}
    local hiddenAuraIDs = {}

    if type(validAuraCooldownIDs) ~= "table" then
        return trackedBuffIDs, hiddenAuraIDs
    end

    for i = 1, #validAuraCooldownIDs do
        local cooldownID = validAuraCooldownIDs[i]
        if type(cooldownID) == "number" and cooldownID > 0 then
            if type(assignedSet) == "table" and assignedSet[cooldownID] then
                trackedBuffIDs[#trackedBuffIDs + 1] = cooldownID
            else
                hiddenAuraIDs[#hiddenAuraIDs + 1] = cooldownID
            end
        end
    end

    return trackedBuffIDs, hiddenAuraIDs
end

local function NeedsCategoryWrite(layoutManager, layout, cooldownIDs, category)
    if not layoutManager or not layout or type(cooldownIDs) ~= "table" then
        return false
    end

    local accessMode = Enum and Enum.CDMLayoutMode and Enum.CDMLayoutMode.AccessOnly or nil
    for i = 1, #cooldownIDs do
        local cooldownID = cooldownIDs[i]
        local block = type(layoutManager.GetCooldownIDDataBlockForLayout) == "function"
            and layoutManager:GetCooldownIDDataBlockForLayout(layout, cooldownID, accessMode)
            or nil
        if type(block) ~= "table" or block.category ~= category then
            return true
        end
    end

    return false
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:GetRefineBlizzardLayoutName()
    return REFINE_BLIZZARD_LAYOUT_NAME
end

function CDM:IsBlizzardPrimaryAuraRuntimeActive()
    return self:IsRefineRuntimeOwnerActive()
        and self.auraProbeInitialized == true
        and self.blizzardAssignmentSyncActive == true
end

function CDM:MarkBlizzardAssignmentSyncDirty(reason)
    self.blizzardAssignmentSyncDirty = true
    if type(reason) == "string" and reason ~= "" then
        self.blizzardAssignmentSyncReason = reason
    end
end

function CDM:ClearBlizzardAssignmentSyncDirty()
    self.blizzardAssignmentSyncDirty = nil
    self.blizzardAssignmentSyncReason = nil
end

function CDM:GetStoredBlizzardSyncState()
    return GetStoredSyncState()
end

function CDM:GetBlizzardAssignmentSyncContext()
    return GetLoadedSyncContext()
end

function CDM:EnsureRefineBlizzardLayout()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return nil
    end

    if self.EnsureBlizzardBridgeReady and not self:EnsureBlizzardBridgeReady() then
        return nil
    end

    local settingsFrame, layoutManager = GetLoadedSyncContext()
    if not settingsFrame or not layoutManager then
        return nil
    end

    local specTag = GetCurrentSpecTag(layoutManager)
    if not specTag then
        return nil
    end

    local layout = FindLayoutByName(layoutManager, REFINE_BLIZZARD_LAYOUT_NAME, specTag)
    if layout then
        local layoutID = GetLayoutID(layout)
        if layoutID then
            self.refineBlizzardLayoutID = layoutID
            self.refineBlizzardLayoutSpecTag = specTag
            return layoutID
        end
    end

    if type(layoutManager.AddLayout) ~= "function" then
        return nil
    end

    local newLayout, status = layoutManager:AddLayout(REFINE_BLIZZARD_LAYOUT_NAME, specTag)
    local success = Enum and Enum.CooldownLayoutStatus and Enum.CooldownLayoutStatus.Success
    if status ~= success or not newLayout then
        return nil
    end

    if type(settingsFrame.SaveCurrentLayout) == "function" then
        settingsFrame:SaveCurrentLayout()
    elseif type(layoutManager.SaveLayouts) == "function" then
        layoutManager:SaveLayouts()
    end

    local layoutID = GetLayoutID(newLayout)
    if layoutID then
        self.refineBlizzardLayoutID = layoutID
        self.refineBlizzardLayoutSpecTag = specTag
        self.refineRuntimeTouchedBlizzard = true
    end

    return layoutID
end

function CDM:SnapshotPreviousBlizzardLayout(layoutManager, refineLayoutID)
    if not layoutManager then
        return
    end

    local specTag = GetCurrentSpecTag(layoutManager)
    if not specTag then
        return
    end

    self.previousBlizzardLayoutIDBySpec = self.previousBlizzardLayoutIDBySpec or {}
    if self.previousBlizzardLayoutIDBySpec[specTag] ~= nil then
        return
    end

    local activeLayoutID = GetActiveLayoutID(layoutManager)

    if refineLayoutID and activeLayoutID == refineLayoutID then
        return
    end

    self.previousBlizzardLayoutIDBySpec[specTag] = activeLayoutID

    local storedState = GetStoredSyncState()
    if storedState then
        storedState.previousLayoutIDBySpec[specTag] = activeLayoutID
    end
end

function CDM:SwitchToRefineBlizzardLayout()
    local settingsFrame, layoutManager = GetLoadedSyncContext()
    if not settingsFrame or not layoutManager then
        return false
    end

    local refineLayoutID = self:EnsureRefineBlizzardLayout()
    if type(refineLayoutID) ~= "number" then
        return false
    end

    self:SnapshotPreviousBlizzardLayout(layoutManager, refineLayoutID)

    local activeLayoutID = type(layoutManager.GetActiveLayoutID) == "function" and layoutManager:GetActiveLayoutID() or nil
    if activeLayoutID ~= refineLayoutID and type(layoutManager.SetActiveLayoutByID) == "function" then
        layoutManager:SetActiveLayoutByID(refineLayoutID)
    end

    self.refineBlizzardLayoutID = refineLayoutID
    self.refineRuntimeTouchedBlizzard = true
    return true
end

function CDM:IsStoredBlizzardAssignmentSyncCurrent(layoutManager)
    local storedState = GetStoredSyncState()
    if type(storedState) ~= "table" then
        return false
    end

    local currentLayoutKey = self.GetCurrentLayoutKey and self:GetCurrentLayoutKey() or nil
    if currentLayoutKey ~= storedState.layoutKey then
        return false
    end

    local currentSpecTag = GetCurrentSpecTag(layoutManager)
    if currentSpecTag ~= storedState.specTag then
        return false
    end

    return true
end

function CDM:CanUseStoredRefineBlizzardLayout()
    local _settingsFrame, layoutManager = GetLoadedSyncContext()
    if not layoutManager then
        return false
    end
    if not self:IsStoredBlizzardAssignmentSyncCurrent(layoutManager) then
        return false
    end

    local specTag = GetCurrentSpecTag(layoutManager)
    local refineLayout = FindLayoutByName(layoutManager, REFINE_BLIZZARD_LAYOUT_NAME, specTag)
    local refineLayoutID = GetLayoutID(refineLayout)
    if type(refineLayoutID) ~= "number" then
        return false
    end

    local activeLayoutID = GetActiveLayoutID(layoutManager)
    if activeLayoutID ~= refineLayoutID then
        return false
    end

    self.refineBlizzardLayoutID = refineLayoutID
    self.refineBlizzardLayoutSpecTag = specTag
    return true
end

function CDM:ActivateStoredRefineBlizzardLayout()
    local settingsFrame, layoutManager = GetLoadedSyncContext()
    if not settingsFrame or not layoutManager then
        return false
    end
    if not self:IsStoredBlizzardAssignmentSyncCurrent(layoutManager) then
        return false
    end

    local specTag = GetCurrentSpecTag(layoutManager)
    local refineLayout = FindLayoutByName(layoutManager, REFINE_BLIZZARD_LAYOUT_NAME, specTag)
    local refineLayoutID = GetLayoutID(refineLayout)
    if type(refineLayoutID) ~= "number" then
        return false
    end

    self:SnapshotPreviousBlizzardLayout(layoutManager, refineLayoutID)

    local activeLayoutID = GetActiveLayoutID(layoutManager)
    if activeLayoutID ~= refineLayoutID and type(layoutManager.SetActiveLayoutByID) == "function" then
        layoutManager:SetActiveLayoutByID(refineLayoutID)
        if type(settingsFrame.SaveCurrentLayout) == "function" then
            settingsFrame:SaveCurrentLayout()
        elseif type(layoutManager.SaveLayouts) == "function" then
            layoutManager:SaveLayouts()
        end
    end

    self.refineBlizzardLayoutID = refineLayoutID
    self.refineBlizzardLayoutSpecTag = specTag
    self.refineRuntimeTouchedBlizzard = true
    return true
end

function CDM:RestorePreviousBlizzardLayout()
    local settingsFrame, layoutManager = GetLoadedSyncContext()
    if not settingsFrame or not layoutManager then
        return false
    end

    local specTag = GetCurrentSpecTag(layoutManager)
    self.blizzardAssignmentSyncActive = nil
    self.blizzardPrimaryAuraRuntimeActive = nil

    local previousLayoutIDBySpec = self.previousBlizzardLayoutIDBySpec
    if type(previousLayoutIDBySpec) ~= "table" then
        local storedState = GetStoredSyncState()
        previousLayoutIDBySpec = storedState and storedState.previousLayoutIDBySpec or nil
    end

    if not specTag or type(previousLayoutIDBySpec) ~= "table" then
        return false
    end

    local previousLayoutID = previousLayoutIDBySpec[specTag]
    if previousLayoutID == nil then
        return false
    end

    local changed = false
    if previousLayoutID == DEFAULT_LAYOUT_ID then
        if type(layoutManager.UseDefaultLayout) == "function" then
            layoutManager:UseDefaultLayout()
            changed = true
        end
    elseif type(layoutManager.GetLayout) == "function" and layoutManager:GetLayout(previousLayoutID) then
        if type(layoutManager.SetActiveLayoutByID) == "function" then
            layoutManager:SetActiveLayoutByID(previousLayoutID)
            changed = true
        end
    elseif type(layoutManager.UseDefaultLayout) == "function" then
        layoutManager:UseDefaultLayout()
        changed = true
    end

    if changed then
        if type(settingsFrame.SaveCurrentLayout) == "function" then
            settingsFrame:SaveCurrentLayout()
        elseif type(layoutManager.SaveLayouts) == "function" then
            layoutManager:SaveLayouts()
        end
    end

    if type(self.previousBlizzardLayoutIDBySpec) == "table" then
        self.previousBlizzardLayoutIDBySpec[specTag] = nil
    end

    local storedState = GetStoredSyncState()
    if storedState and type(storedState.previousLayoutIDBySpec) == "table" then
        storedState.previousLayoutIDBySpec[specTag] = nil
    end

    return changed
end

function CDM:SyncAssignmentsToBlizzardLayout()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return false
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        self:MarkBlizzardAssignmentSyncDirty("combat")
        return false
    end

    if not self:SwitchToRefineBlizzardLayout() then
        self:MarkBlizzardAssignmentSyncDirty("layout")
        return false
    end

    local settingsFrame, layoutManager, dataProvider = GetLoadedSyncContext()
    if not settingsFrame or not layoutManager or not dataProvider then
        self:MarkBlizzardAssignmentSyncDirty("context")
        return false
    end

    local validAuraCooldownIDs = self.GetValidAuraCooldownIDs and self:GetValidAuraCooldownIDs(true) or {}
    local snapshot = self.GetAssignedCooldownSnapshot and self:GetAssignedCooldownSnapshot() or nil
    local assignedOrderedIDs, assignedSet = CopyAssignedCooldownIDs(snapshot)
    local defaultOrderedCooldownIDs = type(dataProvider.GetDefaultOrderedCooldownIDs) == "function" and dataProvider:GetDefaultOrderedCooldownIDs() or {}
    local orderedCooldownIDs = BuildOrderedCooldownIDs(defaultOrderedCooldownIDs, assignedOrderedIDs, assignedSet)
    local trackedBuffIDs, hiddenAuraIDs = BuildCategoryCooldownIDs(validAuraCooldownIDs, assignedSet)
    local refineLayout = type(layoutManager.GetLayout) == "function" and layoutManager:GetLayout(self.refineBlizzardLayoutID) or nil

    if not refineLayout then
        self:MarkBlizzardAssignmentSyncDirty("layout")
        return false
    end

    if type(layoutManager.LockNotifications) == "function" then
        layoutManager:LockNotifications()
    end

    local categoryChanged = false
    if type(layoutManager.WriteCooldownCategoryToLayout) == "function" then
        if NeedsCategoryWrite(layoutManager, refineLayout, trackedBuffIDs, TRACKED_BUFF_CATEGORY) then
            layoutManager:WriteCooldownCategoryToLayout(refineLayout, TRACKED_BUFF_CATEGORY, trackedBuffIDs)
            categoryChanged = true
        end
        if NeedsCategoryWrite(layoutManager, refineLayout, hiddenAuraIDs, HIDDEN_AURA_CATEGORY) then
            layoutManager:WriteCooldownCategoryToLayout(refineLayout, HIDDEN_AURA_CATEGORY, hiddenAuraIDs)
            categoryChanged = true
        end
    end

    if categoryChanged and type(layoutManager.SetHasPendingChanges) == "function" then
        layoutManager:SetHasPendingChanges(true, true)
    end

    if type(dataProvider.MarkDirty) == "function" then
        dataProvider:MarkDirty()
    end

    if type(layoutManager.WriteCooldownOrderToActiveLayout) == "function" then
        local accessMode = Enum and Enum.CDMLayoutMode and Enum.CDMLayoutMode.AllowCreate or nil
        layoutManager:WriteCooldownOrderToActiveLayout(orderedCooldownIDs, accessMode)
    end

    if type(dataProvider.MarkDirty) == "function" then
        dataProvider:MarkDirty()
    end

    if type(layoutManager.UnlockNotifications) == "function" then
        layoutManager:UnlockNotifications(true)
    end

    if type(settingsFrame.SaveCurrentLayout) == "function" then
        settingsFrame:SaveCurrentLayout()
    elseif type(layoutManager.SaveLayouts) == "function" then
        layoutManager:SaveLayouts()
    end

    self.refineRuntimeTouchedBlizzard = true
    self.blizzardAssignmentSyncActive = true
    self.blizzardPrimaryAuraRuntimeActive = true
    local syncedLayoutKey = self.GetCurrentLayoutKey and self:GetCurrentLayoutKey() or nil
    local syncedSpecTag = GetCurrentSpecTag(layoutManager)

    local storedState = GetStoredSyncState()
    if storedState then
        storedState.layoutKey = syncedLayoutKey
        storedState.specTag = syncedSpecTag
    end

    self:ClearBlizzardAssignmentSyncDirty()
    return true
end

function CDM:NeedsBlizzardAssignmentSync()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return false
    end

    if self.blizzardAssignmentSyncDirty then
        return true
    end

    local _settingsFrame, layoutManager = GetLoadedSyncContext()
    if not self:IsStoredBlizzardAssignmentSyncCurrent(layoutManager) then
        return true
    end

    local refineLayoutID = self:EnsureRefineBlizzardLayout()
    local activeLayoutID = GetActiveLayoutID(layoutManager)
    return refineLayoutID ~= nil and activeLayoutID ~= refineLayoutID
end

function CDM:ApplyPendingBlizzardAssignmentSync()
    if not self:IsRefineRuntimeOwnerActive() then
        return false
    end

    if not self:NeedsBlizzardAssignmentSync() then
        return false
    end

    return self:SyncAssignmentsToBlizzardLayout()
end

function CDM:HandleAssignmentConfigurationChanged()
    self:MarkBlizzardAssignmentSyncDirty("assignments")

    if not self:IsRefineRuntimeOwnerActive() then
        return
    end

    if self.blizzardAssignmentSyncActive == true
        and self.MarkReloadRecommendationPending
        and self.ShowReloadRecommendationIfPending
    then
        self:MarkReloadRecommendationPending()
        self:ShowReloadRecommendationIfPending()
    end
end
