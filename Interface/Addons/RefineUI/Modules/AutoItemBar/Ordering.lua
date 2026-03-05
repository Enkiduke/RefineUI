----------------------------------------------------------------------------------------
-- AutoItemBar Component: Ordering
-- Description: Handles combined ordering logic for categories and custom items.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoItemBar = RefineUI:GetModule("AutoItemBar")
if not AutoItemBar then return end

local tinsert = table.insert
local tremove = table.remove
local tonumber = tonumber
local type = type
local ipairs = ipairs

----------------------------------------------------------------------------------------
--	Constants
----------------------------------------------------------------------------------------

local TOKEN_PREFIX_CATEGORY = "cat:"
local TOKEN_PREFIX_ITEM = "item:"
local ENTRY_TYPE_CATEGORY = "category"
local ENTRY_TYPE_ITEM = "item"

----------------------------------------------------------------------------------------
--	Tokenization
----------------------------------------------------------------------------------------

local function CategoryToken(key)
    return TOKEN_PREFIX_CATEGORY .. tostring(key or "")
end

local function ItemToken(itemID)
    return TOKEN_PREFIX_ITEM .. tostring(itemID or 0)
end

function AutoItemBar:GetCategoryToken(categoryKey)
    return CategoryToken(categoryKey)
end

function AutoItemBar:GetItemToken(itemID)
    return ItemToken(itemID)
end

function AutoItemBar:ParseEnabledToken(token)
    if type(token) ~= "string" then
        return nil, nil
    end

    local prefix, value = token:match("^(%a+)%:(.+)$")
    if prefix == "cat" and value and value ~= "" then
        return ENTRY_TYPE_CATEGORY, value
    end
    if prefix == "item" then
        local itemID = tonumber(value)
        if itemID and itemID > 0 then
            return ENTRY_TYPE_ITEM, itemID
        end
    end

    return nil, nil
end

----------------------------------------------------------------------------------------
--	Ordering Logic
----------------------------------------------------------------------------------------

function AutoItemBar:EnsureCategoryConfig()
    if self._categoryConfigInitialized and self.categoryOrderIndex then
        return
    end

    local cfg = self:GetConfig()
    local definitions = self:GetCategoryDefinitions()
    local schemaVersion = self.CATEGORY_SCHEMA_VERSION or 1
    local schemaChanged = cfg.CategorySchemaVersion ~= schemaVersion
    if schemaChanged then
        cfg.CategoryOrder = {}
        cfg.CategoryEnabled = {}
        cfg.CategorySchemaVersion = schemaVersion
    end

    local previousOrder = cfg.CategoryOrder
    local seen = {}
    local mergedOrder = {}

    for _, key in ipairs(previousOrder) do
        if type(key) == "string" and not seen[key] and self:GetCategoryByKey(key) then
            seen[key] = true
            tinsert(mergedOrder, key)
        end
    end

    for _, definition in ipairs(definitions) do
        local key = definition.key
        if not seen[key] then
            seen[key] = true
            tinsert(mergedOrder, key)
        end

        if cfg.CategoryEnabled[key] == nil then
            cfg.CategoryEnabled[key] = self:GetCategoryDefaultEnabled(definition)
        else
            cfg.CategoryEnabled[key] = cfg.CategoryEnabled[key] and true or false
        end
    end

    cfg.CategoryOrder = mergedOrder
    cfg.CategorySchemaVersion = schemaVersion
    self:NormalizeCategoryOrder()
    self:RebuildEnabledOrder()
    self._categoryConfigInitialized = true
end

function AutoItemBar:RebuildEnabledOrder()
    local cfg = self:GetConfig()
    local existing = cfg.EnabledOrder
    local trackedItems = cfg.TrackedItems
    local rebuilt = {}
    local seen = {}

    local trackedLookup = {}
    for _, rawItemID in ipairs(trackedItems) do
        local itemID = tonumber(rawItemID)
        if itemID and itemID > 0 then
            trackedLookup[itemID] = true
        end
    end

    for _, token in ipairs(existing) do
        local entryType, value = self:ParseEnabledToken(token)
        if entryType == ENTRY_TYPE_CATEGORY then
            if self:GetCategoryByKey(value) and cfg.CategoryEnabled[value] ~= false and not seen[token] then
                seen[token] = true
                tinsert(rebuilt, token)
            end
        elseif entryType == ENTRY_TYPE_ITEM then
            if trackedLookup[value] and not seen[token] then
                seen[token] = true
                tinsert(rebuilt, token)
            end
        end
    end

    for _, key in ipairs(cfg.CategoryOrder) do
        if cfg.CategoryEnabled[key] ~= false then
            local token = CategoryToken(key)
            if not seen[token] then
                seen[token] = true
                tinsert(rebuilt, token)
            end
        end
    end

    for _, rawItemID in ipairs(trackedItems) do
        local itemID = tonumber(rawItemID)
        if itemID and itemID > 0 then
            local token = ItemToken(itemID)
            if not seen[token] then
                seen[token] = true
                tinsert(rebuilt, token)
            end
        end
    end

    cfg.EnabledOrder = rebuilt
    self.enabledOrderIndex = {}
    for index, token in ipairs(rebuilt) do
        self.enabledOrderIndex[token] = index
    end
end

function AutoItemBar:GetEnabledEntries()
    self:EnsureCategoryConfig()
    local cfg = self:GetConfig()
    local entries = {}

    for _, token in ipairs(cfg.EnabledOrder) do
        local entryType, value = self:ParseEnabledToken(token)
        if entryType == ENTRY_TYPE_CATEGORY then
            local def = self:GetCategoryByKey(value)
            if def and cfg.CategoryEnabled[value] ~= false then
                tinsert(entries, {
                    type = ENTRY_TYPE_CATEGORY,
                    key = value,
                    label = def.label,
                    token = token,
                })
            end
        elseif entryType == ENTRY_TYPE_ITEM then
            if self:IsItemManuallyTracked(value) then
                tinsert(entries, {
                    type = ENTRY_TYPE_ITEM,
                    itemID = value,
                    token = token,
                })
            end
        end
    end

    return entries
end

function AutoItemBar:GetEnabledSortIndexForCategory(categoryKey)
    if not categoryKey then return 99999 end
    self:EnsureCategoryConfig()
    local token = CategoryToken(categoryKey)
    return self.enabledOrderIndex and self.enabledOrderIndex[token] or 99999
end

function AutoItemBar:GetEnabledSortIndexForItem(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return 99999 end
    self:EnsureCategoryConfig()
    local token = ItemToken(itemID)
    return self.enabledOrderIndex and self.enabledOrderIndex[token] or 99999
end

function AutoItemBar:MoveEnabledTokenToIndex(token, targetIndex)
    if type(token) ~= "string" or token == "" then return false end

    local cfg = self:GetConfig()
    local source = cfg.EnabledOrder
    local currentIndex
    for index, entry in ipairs(source) do
        if entry == token then
            currentIndex = index
            break
        end
    end
    if not currentIndex then
        return false
    end

    local count = #source
    if type(targetIndex) ~= "number" then
        targetIndex = count
    end
    if targetIndex < 1 then
        targetIndex = 1
    elseif targetIndex > count then
        targetIndex = count
    end
    if targetIndex == currentIndex then
        return false
    end

    tremove(source, currentIndex)
    tinsert(source, targetIndex, token)
    self:RebuildEnabledOrder()
    self:RebuildTrackedLookup()

    if InCombatLockdown() then
        self._pendingCombatRefresh = true
    end
    if self.RefreshCategoryManagerWindow then
        self:RefreshCategoryManagerWindow()
    end
    self:RequestUpdate()
    return true
end

function AutoItemBar:NormalizeCategoryOrder()
    local cfg = self:GetConfig()
    local enabled = {}
    local disabled = {}

    for _, key in ipairs(cfg.CategoryOrder) do
        local isEnabled = cfg.CategoryEnabled[key] ~= false
        if isEnabled then
            tinsert(enabled, key)
        else
            tinsert(disabled, key)
        end
    end

    cfg.CategoryOrder = {}
    for _, key in ipairs(enabled) do
        tinsert(cfg.CategoryOrder, key)
    end
    for _, key in ipairs(disabled) do
        tinsert(cfg.CategoryOrder, key)
    end

    self.categoryOrderIndex = {}
    for index, key in ipairs(cfg.CategoryOrder) do
        self.categoryOrderIndex[key] = index
    end
end

function AutoItemBar:GetOrderedCategories(includeDisabled)
    self:EnsureCategoryConfig()

    local cfg = self:GetConfig()
    local ordered = {}
    for _, key in ipairs(cfg.CategoryOrder) do
        local def = self:GetCategoryByKey(key)
        if def then
            local enabled = cfg.CategoryEnabled[key] ~= false
            if includeDisabled or enabled then
                ordered[#ordered + 1] = {
                    key = key,
                    label = def.label,
                    enabled = enabled,
                    definition = def,
                }
            end
        end
    end

    return ordered
end

function AutoItemBar:IsTrackingCategoryEnabled(categoryKey)
    if not categoryKey then return false end
    self:EnsureCategoryConfig()
    local cfg = self:GetConfig()
    return cfg.CategoryEnabled[categoryKey] ~= false
end

function AutoItemBar:SetTrackingCategoryEnabled(categoryKey, enabled)
    if not categoryKey or not self:GetCategoryByKey(categoryKey) then return end

    local cfg = self:GetConfig()
    cfg.CategoryEnabled[categoryKey] = enabled and true or false
    self:NormalizeCategoryOrder()
    self:RebuildEnabledOrder()

    if self.RefreshCategoryManagerWindow then
        self:RefreshCategoryManagerWindow()
    end
    self:RequestUpdate()
end

function AutoItemBar:MoveCategoryBefore(dragKey, targetKey)
    if not dragKey or not targetKey or dragKey == targetKey then return false end

    local cfg = self:GetConfig()
    if cfg.CategoryEnabled[dragKey] == false or cfg.CategoryEnabled[targetKey] == false then
        return false
    end

    local dragIndex, targetIndex
    for i, key in ipairs(cfg.CategoryOrder) do
        if key == dragKey then
            dragIndex = i
        elseif key == targetKey then
            targetIndex = i
        end
    end

    if not dragIndex or not targetIndex then
        return false
    end

    tremove(cfg.CategoryOrder, dragIndex)
    if dragIndex < targetIndex then
        targetIndex = targetIndex - 1
    end
    tinsert(cfg.CategoryOrder, targetIndex, dragKey)

    self:NormalizeCategoryOrder()
    if self.RefreshCategoryManagerWindow then
        self:RefreshCategoryManagerWindow()
    end
    self:RequestUpdate()
    return true
end

function AutoItemBar:MoveCategoryToEnabledIndex(dragKey, enabledIndex)
    if not dragKey then return false end
    return self:MoveEnabledTokenToIndex(CategoryToken(dragKey), enabledIndex)
end

function AutoItemBar:GetCategorySortIndex(categoryKey)
    if not categoryKey then return 99999 end
    self:EnsureCategoryConfig()
    return self.categoryOrderIndex and self.categoryOrderIndex[categoryKey] or 99999
end
