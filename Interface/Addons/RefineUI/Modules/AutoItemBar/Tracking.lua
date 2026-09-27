----------------------------------------------------------------------------------------
-- AutoItemBar Component: Tracking
-- Description: Manages the custom tracked and hidden item lists.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoItemBar = RefineUI:GetModule("AutoItemBar")
if not AutoItemBar then return end

local tinsert = table.insert
local tremove = table.remove
local tonumber = tonumber
local ipairs = ipairs

----------------------------------------------------------------------------------------
--	Lookups
----------------------------------------------------------------------------------------

local function BuildCleanLookup(source)
    local cleaned = {}
    local lookup = {}

    for _, rawItemID in ipairs(source) do
        local itemID = tonumber(rawItemID)
        if itemID and itemID > 0 and not lookup[itemID] then
            lookup[itemID] = true
            tinsert(cleaned, itemID)
        end
    end

    return cleaned, lookup
end

local function RemoveItemID(list, itemID)
    local removed = false
    for i = #list, 1, -1 do
        if tonumber(list[i]) == itemID then
            tremove(list, i)
            removed = true
        end
    end
    return removed
end

function AutoItemBar:RebuildTrackedLookup()
    local cfg = self:GetConfig()
    cfg.TrackedItems, self.trackedItemsLookup = BuildCleanLookup(cfg.TrackedItems)
end

function AutoItemBar:RebuildHiddenLookup()
    local cfg = self:GetConfig()
    cfg.HiddenItems, self.hiddenItemsLookup = BuildCleanLookup(cfg.HiddenItems)
end

function AutoItemBar:IsItemManuallyTracked(itemID)
    return self.trackedItemsLookup[itemID] == true
end

function AutoItemBar:IsItemHidden(itemID)
    return self.hiddenItemsLookup[itemID] == true
end

----------------------------------------------------------------------------------------
--	Mutators
----------------------------------------------------------------------------------------

function AutoItemBar:AddHiddenItem(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end

    local changed = false
    if not self.hiddenItemsLookup[itemID] then
        tinsert(self:GetConfig().HiddenItems, itemID)
        self.hiddenItemsLookup[itemID] = true
        changed = true
    end

    if self:RemoveTrackedItem(itemID, true) then
        changed = true
    end

    if changed then
        self:OnEntriesChanged()
    end
    return changed
end

function AutoItemBar:RemoveHiddenItem(itemID, skipUpdate)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end

    if not RemoveItemID(self:GetConfig().HiddenItems, itemID) then
        return false
    end
    self.hiddenItemsLookup[itemID] = nil

    if not skipUpdate then
        self:OnEntriesChanged()
    end
    return true
end

function AutoItemBar:AddTrackedItem(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end

    local changed = self:RemoveHiddenItem(itemID, true)

    if not self.trackedItemsLookup[itemID] then
        tinsert(self:GetConfig().TrackedItems, itemID)
        self.trackedItemsLookup[itemID] = true
        self:RebuildEnabledOrder()
        changed = true
    end

    if changed then
        self:OnEntriesChanged()
    end
    return changed
end

function AutoItemBar:RemoveTrackedItem(itemID, skipUpdate)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end

    local cfg = self:GetConfig()
    if not RemoveItemID(cfg.TrackedItems, itemID) then
        return false
    end

    self.trackedItemsLookup[itemID] = nil
    self:RebuildEnabledOrder()

    if not skipUpdate then
        self:OnEntriesChanged()
    end
    return true
end

function AutoItemBar:MoveTrackedItemToIndex(itemID, targetIndex)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end
    return self:MoveEnabledTokenToIndex(self:GetItemToken(itemID), targetIndex)
end

----------------------------------------------------------------------------------------
--	State Reconstruction
----------------------------------------------------------------------------------------

function AutoItemBar:ResetCategoryManagerDefaults()
    local cfg = self:GetConfig()

    cfg.CategoryOrder = {}
    cfg.CategoryEnabled = {}
    for _, definition in ipairs(self:GetCategoryDefinitions()) do
        tinsert(cfg.CategoryOrder, definition.key)
        cfg.CategoryEnabled[definition.key] = self:GetCategoryDefaultEnabled(definition)
    end
    cfg.CategorySchemaVersion = self.CATEGORY_SCHEMA_VERSION

    cfg.TrackedItems = {}
    cfg.HiddenItems = {}
    cfg.EnabledOrder = {}
    self.trackedItemsLookup = {}
    self.hiddenItemsLookup = {}

    self._categoryConfigInitialized = true
    self:NormalizeCategoryOrder()
    self:RebuildEnabledOrder()
    self:OnEntriesChanged()
end
