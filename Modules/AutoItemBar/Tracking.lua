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
local type = type
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
--	Tracked Items
----------------------------------------------------------------------------------------

function AutoItemBar:RebuildTrackedLookup()
    local cfg = self:GetConfig()
    local source = cfg.TrackedItems
    local cleaned = {}
    local lookup = {}
    local orderLookup = {}

    for _, rawItemID in ipairs(source) do
        local itemID = tonumber(rawItemID)
        if itemID and itemID > 0 and not lookup[itemID] then
            lookup[itemID] = true
            tinsert(cleaned, itemID)
            orderLookup[itemID] = #cleaned
        end
    end

    cfg.TrackedItems = cleaned
    self.trackedItemsLookup = lookup
    self.trackedItemsOrderLookup = orderLookup
end

function AutoItemBar:IsItemManuallyTracked(itemID)
    if not self.trackedItemsLookup then
        self:RebuildTrackedLookup()
    end
    return self.trackedItemsLookup[itemID] == true
end

function AutoItemBar:GetTrackedItems()
    local cfg = self:GetConfig()
    if not self.trackedItemsLookup then
        self:RebuildTrackedLookup()
    end
    return cfg.TrackedItems
end

function AutoItemBar:GetTrackedSortIndex(itemID)
    if not self.trackedItemsOrderLookup then
        self:RebuildTrackedLookup()
    end
    return self.trackedItemsOrderLookup and self.trackedItemsOrderLookup[itemID] or nil
end

----------------------------------------------------------------------------------------
--	Hidden Items
----------------------------------------------------------------------------------------

function AutoItemBar:RebuildHiddenLookup()
    local cfg = self:GetConfig()
    local source = cfg.HiddenItems
    local cleaned = {}
    local lookup = {}

    for _, rawItemID in ipairs(source) do
        local itemID = tonumber(rawItemID)
        if itemID and itemID > 0 and not lookup[itemID] then
            lookup[itemID] = true
            tinsert(cleaned, itemID)
        end
    end

    cfg.HiddenItems = cleaned
    self.hiddenItemsLookup = lookup
end

function AutoItemBar:GetHiddenItems()
    local cfg = self:GetConfig()
    if not self.hiddenItemsLookup then
        self:RebuildHiddenLookup()
    end
    return cfg.HiddenItems
end

function AutoItemBar:IsItemHidden(itemID)
    if not self.hiddenItemsLookup then
        self:RebuildHiddenLookup()
    end
    return self.hiddenItemsLookup[itemID] == true
end

function AutoItemBar:AddHiddenItem(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end

    local cfg = self:GetConfig()
    if not self.hiddenItemsLookup then
        self:RebuildHiddenLookup()
    end

    local changed = false
    if not self.hiddenItemsLookup[itemID] then
        tinsert(cfg.HiddenItems, itemID)
        self.hiddenItemsLookup[itemID] = true
        changed = true
    end

    if self:RemoveTrackedItem(itemID, true) then
        changed = true
    end

    if changed then
        if InCombatLockdown() then
            self._pendingCombatRefresh = true
        end
        if self.RefreshCategoryManagerWindow then
            self:RefreshCategoryManagerWindow()
        end
        self:RequestUpdate()
    end

    return changed
end

function AutoItemBar:RemoveHiddenItem(itemID, skipUpdate)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end

    local cfg = self:GetConfig()
    local removed = false

    for i = #cfg.HiddenItems, 1, -1 do
        if tonumber(cfg.HiddenItems[i]) == itemID then
            tremove(cfg.HiddenItems, i)
            removed = true
        end
    end

    if not removed then
        return false
    end

    if self.hiddenItemsLookup then
        self.hiddenItemsLookup[itemID] = nil
    end

    if not skipUpdate then
        if InCombatLockdown() then
            self._pendingCombatRefresh = true
        end
        if self.RefreshCategoryManagerWindow then
            self:RefreshCategoryManagerWindow()
        end
        self:RequestUpdate()
    end

    return true
end

----------------------------------------------------------------------------------------
--	Tracked Item Mutators
----------------------------------------------------------------------------------------

function AutoItemBar:AddTrackedItem(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end

    local cfg = self:GetConfig()
    if not self.trackedItemsLookup then
        self:RebuildTrackedLookup()
    end

    local changed = false

    if self:RemoveHiddenItem(itemID, true) then
        changed = true
    end

    if self.trackedItemsLookup[itemID] then
        self:RebuildEnabledOrder()
        if changed then
            if InCombatLockdown() then
                self._pendingCombatRefresh = true
            end
            if self.RefreshCategoryManagerWindow then
                self:RefreshCategoryManagerWindow()
            end
            self:RequestUpdate()
        end
        return changed
    end

    tinsert(cfg.TrackedItems, itemID)
    self.trackedItemsLookup[itemID] = true
    self.trackedItemsOrderLookup = self.trackedItemsOrderLookup or {}
    self.trackedItemsOrderLookup[itemID] = #cfg.TrackedItems
    tinsert(cfg.EnabledOrder, self:GetItemToken(itemID))
    changed = true

    if changed then
        self:RebuildEnabledOrder()
        if InCombatLockdown() then
            self._pendingCombatRefresh = true
        end
        if self.RefreshCategoryManagerWindow then
            self:RefreshCategoryManagerWindow()
        end
        self:RequestUpdate()
    end

    return changed
end

function AutoItemBar:RemoveTrackedItem(itemID, skipUpdate)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end

    local cfg = self:GetConfig()
    local removed = false

    for i = #cfg.TrackedItems, 1, -1 do
        if tonumber(cfg.TrackedItems[i]) == itemID then
            tremove(cfg.TrackedItems, i)
            removed = true
        end
    end

    if not removed then
        return false
    end

    if removed then
        local token = self:GetItemToken(itemID)
        for i = #cfg.EnabledOrder, 1, -1 do
            if cfg.EnabledOrder[i] == token then
                tremove(cfg.EnabledOrder, i)
            end
        end
        self:RebuildTrackedLookup()
        self:RebuildEnabledOrder()
    end

    if not skipUpdate then
        if InCombatLockdown() then
            self._pendingCombatRefresh = true
        end
        if self.RefreshCategoryManagerWindow then
            self:RefreshCategoryManagerWindow()
        end
        self:RequestUpdate()
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
    local definitions = self:GetCategoryDefinitions()

    cfg.CategoryOrder = {}
    cfg.CategoryEnabled = {}
    for _, definition in ipairs(definitions) do
        tinsert(cfg.CategoryOrder, definition.key)
        cfg.CategoryEnabled[definition.key] = self:GetCategoryDefaultEnabled(definition)
    end
    cfg.CategorySchemaVersion = self.CATEGORY_SCHEMA_VERSION or cfg.CategorySchemaVersion or 1

    cfg.TrackedItems = {}
    cfg.HiddenItems = {}
    cfg.EnabledOrder = {}
    self.trackedItemsLookup = {}
    self.trackedItemsOrderLookup = {}
    self.hiddenItemsLookup = {}
    self.enabledOrderIndex = {}

    self._categoryConfigInitialized = true
    self:NormalizeCategoryOrder()
    self:RebuildEnabledOrder()

    if InCombatLockdown() then
        self._pendingCombatRefresh = true
    end
    if self.RefreshCategoryManagerWindow then
        self:RefreshCategoryManagerWindow()
    end
    self:RequestUpdate()
end
