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
local InCombatLockdown = InCombatLockdown
local Enum = Enum
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local REFINE_BLIZZARD_LAYOUT_NAME = "RefineUI CDM"
local DEFAULT_LAYOUT_ID = 0
local TRACKED_BUFF_CATEGORY = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff or nil

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
    return true
end

function CDM:CanUseStoredRefineBlizzardLayout()
    local _settingsFrame, layoutManager = GetLoadedSyncContext()
    if not layoutManager then
        return false
    end

    local specTag = GetCurrentSpecTag(layoutManager)
    local refineLayout = FindLayoutByName(layoutManager, REFINE_BLIZZARD_LAYOUT_NAME, specTag)
    local refineLayoutID = GetLayoutID(refineLayout)
    if type(refineLayoutID) ~= "number" or GetActiveLayoutID(layoutManager) ~= refineLayoutID then
        return false
    end

    -- Every valid aura stays tracked, so assignment changes never rewrite Blizzard's layout.
    if NeedsCategoryWrite(layoutManager, refineLayout, self:GetValidAuraCooldownIDs(true), TRACKED_BUFF_CATEGORY) then
        return false
    end

    self.refineBlizzardLayoutID = refineLayoutID
    self.refineBlizzardLayoutSpecTag = specTag
    return true
end

function CDM:NeedsBlizzardTrackerSetup()
    return self:IsRefineRuntimeOwnerActive()
        and self:GetAssignedCooldownSnapshot().hasAuraAssignments
        and GetLoadedSyncContext() ~= nil
        and not self:CanUseStoredRefineBlizzardLayout()
end

function CDM:RestorePreviousBlizzardLayout()
    local settingsFrame, layoutManager = GetLoadedSyncContext()
    if not settingsFrame or not layoutManager then
        return false
    end

    local specTag = GetCurrentSpecTag(layoutManager)
    self.blizzardAssignmentSyncActive = nil

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

-- Addon writes leave Blizzard's layout tables addon-modified, which breaks its secure
-- aura handling in combat. Only call this immediately before ReloadUI().
function CDM:SyncAssignmentsToBlizzardLayout()
    if not self:IsRefineRuntimeOwnerActive() or InCombatLockdown() then
        return false
    end
    if not self:SwitchToRefineBlizzardLayout() then
        return false
    end

    local settingsFrame, layoutManager, dataProvider = GetLoadedSyncContext()
    local refineLayout = layoutManager and layoutManager:GetLayout(self.refineBlizzardLayoutID)
    if not refineLayout then
        return false
    end

    local trackedCooldownIDs = self:GetValidAuraCooldownIDs(true)
    if NeedsCategoryWrite(layoutManager, refineLayout, trackedCooldownIDs, TRACKED_BUFF_CATEGORY) then
        layoutManager:LockNotifications()
        layoutManager:WriteCooldownCategoryToLayout(refineLayout, TRACKED_BUFF_CATEGORY, trackedCooldownIDs)
        layoutManager:SetHasPendingChanges(true, true)
        dataProvider:MarkDirty()
        layoutManager:UnlockNotifications(true)
    end

    settingsFrame:SaveCurrentLayout()
    self.blizzardAssignmentSyncActive = true
    return true
end
