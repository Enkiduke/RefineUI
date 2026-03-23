----------------------------------------------------------------------------------------
-- Bags Component: State Engine
-- Description: Inventory state tracking and snapshot management.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Bags = RefineUI:GetModule("Bags")
if not Bags then return end

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
local type = type
local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs
local pairs = pairs
local string = string
local table = table
local next = next

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------

local PREFETCH_DEBOUNCE_KEY = "Bags:MetadataPrefetch"
local MAIN_SECTION = {
    COMBINED_KEY = "main:__combined__:",
    COMBINED_CATEGORY = "__combined__",
    COMBINED_LABEL = "Combined",
    BAG_CATEGORY_PREFIX = "__bag__:",
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------

Bags.SlotStateByKey = Bags.SlotStateByKey or {}
Bags.SectionStateByKey = Bags.SectionStateByKey or { main = {}, reagent = {} }
Bags.PendingDelta = Bags.PendingDelta or {
    added = {},
    removed = {},
    changed = {},
    movedCategory = {},
    movedFrom = {},
    lockOnly = {},
    structural = true,
}
Bags.DirtySections = Bags.DirtySections or { main = {}, reagent = {} }
Bags.MainSectionList = Bags.MainSectionList or {}
Bags.ReagentSectionList = Bags.ReagentSectionList or {}
Bags._metadataPrefetchQueue = Bags._metadataPrefetchQueue or {}
Bags._metadataPrefetchInFlight = Bags._metadataPrefetchInFlight or false
Bags._snapshotRevision = Bags._snapshotRevision or 0

if Bags._snapshotDirty == nil then
    Bags._snapshotDirty = true
end

----------------------------------------------------------------------------------------
-- Key Helpers
----------------------------------------------------------------------------------------

local function ToSlotKey(bagID, slotIndex)
    return tostring(bagID) .. ":" .. tostring(slotIndex)
end

local function ParseItemID(value)
    if type(value) == "number" and value > 0 then
        return value
    end

    if type(value) == "string" then
        local linkID = tonumber(string.match(value, "item:(%d+)"))
        if linkID and linkID > 0 then
            return linkID
        end

        local rawID = tonumber(value)
        if rawID and rawID > 0 then
            return rawID
        end
    end

    return nil
end

function Bags.GetBagSlotKey(bagID, slotIndex)
    return ToSlotKey(bagID, slotIndex)
end

function Bags.ComputeVisualRevision(slotState)
    if not slotState or not slotState.itemID then
        return "empty"
    end

    return string.format(
        "%d|%d|%d|%s|%d|%d|%d",
        slotState.bagID or -1,
        slotState.slotIndex or -1,
        slotState.itemID or 0,
        tostring(slotState.hyperlink or ""),
        slotState.quality or -1,
        slotState.isBound and 1 or 0,
        slotState.stackCount or 1
    )
end

----------------------------------------------------------------------------------------
-- Refresh State
----------------------------------------------------------------------------------------

function Bags.MarkBagSnapshotDirty()
    Bags._snapshotDirty = true
end

function Bags.MarkSectionsDirty(sectionKeys, viewKey)
    if type(viewKey) ~= "string" then
        viewKey = "main"
    end

    Bags.DirtySections[viewKey] = Bags.DirtySections[viewKey] or {}
    local dirty = Bags.DirtySections[viewKey]

    if type(sectionKeys) == "table" then
        for key, value in pairs(sectionKeys) do
            local sectionKey = type(key) == "number" and value or key
            if type(sectionKey) == "string" and sectionKey ~= "" then
                dirty[sectionKey] = true
            end
        end
        return
    end

    if type(sectionKeys) == "string" and sectionKeys ~= "" then
        dirty[sectionKeys] = true
    end
end

----------------------------------------------------------------------------------------
-- Metadata Prefetch
----------------------------------------------------------------------------------------

local function ScheduleMetadataPrefetch()
    if RefineUI.Debounce then
        RefineUI:Debounce(PREFETCH_DEBOUNCE_KEY, 0.02, Bags.FlushItemMetadataPrefetch)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.02, function()
            Bags.FlushItemMetadataPrefetch()
        end)
    else
        Bags.FlushItemMetadataPrefetch()
    end
end

function Bags.QueueItemMetadataPrefetch(itemIDsOrLinks)
    if itemIDsOrLinks == nil then return end

    local queue = Bags._metadataPrefetchQueue
    local function QueueOne(value)
        local itemID = ParseItemID(value)
        if not itemID then return end
        if Bags.GetItemMetadata and Bags.GetItemMetadata(itemID, itemID) then
            return
        end
        queue[itemID] = true
    end

    if type(itemIDsOrLinks) == "table" then
        for key, value in pairs(itemIDsOrLinks) do
            QueueOne(type(key) == "number" and value or key)
        end
    else
        QueueOne(itemIDsOrLinks)
    end

    if next(queue) then
        ScheduleMetadataPrefetch()
    end
end

function Bags.FlushItemMetadataPrefetch()
    if Bags._metadataPrefetchInFlight then return end

    local queue = Bags._metadataPrefetchQueue
    local pending = {}
    for itemID in pairs(queue) do
        if not (Bags.GetItemMetadata and Bags.GetItemMetadata(itemID, itemID)) then
            table.insert(pending, itemID)
        else
            queue[itemID] = nil
        end
    end

    if #pending == 0 then return end

    if not (ContinuableContainer and ContinuableContainer.Create and Item and Item.CreateFromItemID) then
        if C_Item and C_Item.RequestLoadItemDataByID then
            for _, itemID in ipairs(pending) do
                C_Item.RequestLoadItemDataByID(itemID)
                queue[itemID] = nil
            end
        else
            for _, itemID in ipairs(pending) do
                queue[itemID] = nil
            end
        end
        return
    end

    Bags._metadataPrefetchInFlight = true
    local container = ContinuableContainer:Create()
    local staged = 0

    for _, itemID in ipairs(pending) do
        local item = Item:CreateFromItemID(itemID)
        if item then
            container:AddContinuable(item)
            staged = staged + 1
        end
    end

    if staged == 0 then
        Bags._metadataPrefetchInFlight = false
        return
    end

    container:ContinueOnLoad(function()
        Bags._metadataPrefetchInFlight = false
        for _, itemID in ipairs(pending) do
            queue[itemID] = nil
        end

        Bags._snapshotDirty = true
        if Bags.RequestUpdate then
            Bags.RequestUpdate()
        end

        if next(queue) then
            ScheduleMetadataPrefetch()
        end
    end)
end

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

local function MarkSectionDirty(dirtyMain, dirtyReagent, viewKey, sectionKey)
    if not sectionKey then return end
    if viewKey == "reagent" then
        dirtyReagent[sectionKey] = true
    else
        dirtyMain[sectionKey] = true
    end
end

local function BuildCategoryOrderIndex()
    local order = (Bags.GetEnabledCategoryOrder and Bags.GetEnabledCategoryOrder()) or Bags.CATEGORY_ORDER or {}
    local index = {}
    for i, key in ipairs(order) do
        index[key] = i
    end
    return index
end

local function CompareTextAsc(a, b)
    a = tostring(a or "")
    b = tostring(b or "")
    if a == b then
        return nil
    end
    if a == "" then
        return false
    end
    if b == "" then
        return true
    end
    return a < b
end

local function CompareNumberAsc(a, b)
    a = tonumber(a) or 0
    b = tonumber(b) or 0
    if a == b then
        return nil
    end
    return a < b
end

local function CompareNumberDesc(a, b)
    a = tonumber(a) or -1
    b = tonumber(b) or -1
    if a == b then
        return nil
    end
    return a > b
end

local function CompareBlizzardSlotOrder(sa, sb)
    local result = CompareNumberAsc(sa and sa.bagID, sb and sb.bagID)
    if result ~= nil then
        return result
    end
    return (tonumber(sa and sa.slotIndex) or 0) < (tonumber(sb and sb.slotIndex) or 0)
end

local function GetSlotSortMeta(slotState, categoryOrderIndex)
    local meta = Bags.GetItemMetadata and Bags.GetItemMetadata(slotState.itemID, slotState.hyperlink) or nil
    return {
        categoryIndex = categoryOrderIndex[slotState.categoryKey] or 9999,
        subCategory = tostring(slotState.subCategoryKey or ""),
        itemType = tostring((meta and meta.itemType) or slotState.categoryKey or ""),
        itemSubType = tostring((meta and meta.itemSubType) or slotState.subCategoryKey or ""),
        quality = tonumber((meta and meta.quality) or slotState.quality) or -1,
        name = tostring((meta and meta.nameLower) or ""),
    }
end

local function CompareSectionSlots(sa, sb, sortMode, categoryOrderIndex)
    if sortMode == Bags.SORT_MODE.TYPE then
        local sortA = GetSlotSortMeta(sa, categoryOrderIndex)
        local sortB = GetSlotSortMeta(sb, categoryOrderIndex)

        local result = CompareNumberAsc(sortA.categoryIndex, sortB.categoryIndex)
        if result ~= nil then return result end

        result = CompareTextAsc(sortA.subCategory, sortB.subCategory)
        if result ~= nil then return result end

        result = CompareTextAsc(sortA.itemType, sortB.itemType)
        if result ~= nil then return result end

        result = CompareTextAsc(sortA.itemSubType, sortB.itemSubType)
        if result ~= nil then return result end

        result = CompareNumberDesc(sortA.quality, sortB.quality)
        if result ~= nil then return result end

        result = CompareTextAsc(sortA.name, sortB.name)
        if result ~= nil then return result end
    elseif sortMode == Bags.SORT_MODE.QUALITY then
        local sortA = GetSlotSortMeta(sa, categoryOrderIndex)
        local sortB = GetSlotSortMeta(sb, categoryOrderIndex)

        local result = CompareNumberDesc(sortA.quality, sortB.quality)
        if result ~= nil then return result end

        result = CompareNumberAsc(sortA.categoryIndex, sortB.categoryIndex)
        if result ~= nil then return result end

        result = CompareTextAsc(sortA.subCategory, sortB.subCategory)
        if result ~= nil then return result end

        result = CompareTextAsc(sortA.name, sortB.name)
        if result ~= nil then return result end
    elseif sortMode == Bags.SORT_MODE.NAME then
        local sortA = GetSlotSortMeta(sa, categoryOrderIndex)
        local sortB = GetSlotSortMeta(sb, categoryOrderIndex)

        local result = CompareTextAsc(sortA.name, sortB.name)
        if result ~= nil then return result end

        result = CompareNumberDesc(sortA.quality, sortB.quality)
        if result ~= nil then return result end

        result = CompareNumberAsc(sortA.categoryIndex, sortB.categoryIndex)
        if result ~= nil then return result end
    end

    return CompareBlizzardSlotOrder(sa, sb)
end

local function GetMainBagLabel(bagID)
    if bagID == (BACKPACK_CONTAINER or 0) then
        return BAG_NAME_BACKPACK or "Backpack"
    end

    if C_Container and C_Container.GetBagName then
        local bagName = C_Container.GetBagName(bagID)
        if type(bagName) == "string" and bagName ~= "" then
            return bagName
        end
    end

    return string.format("Bag %d", tonumber(bagID) or 0)
end

local function BuildBagSectionCache()
    local cache = {}
    local maxBagSlots = NUM_BAG_SLOTS or 4

    for bagID = 0, maxBagSlots do
        if bagID ~= 5 then
            cache[bagID] = {
                categoryKey = MAIN_SECTION.BAG_CATEGORY_PREFIX .. tostring(bagID),
                key = "main:" .. MAIN_SECTION.BAG_CATEGORY_PREFIX .. tostring(bagID) .. ":",
                label = GetMainBagLabel(bagID),
                order = bagID + 1,
            }
        end
    end

    return cache
end

----------------------------------------------------------------------------------------
-- Search logic
----------------------------------------------------------------------------------------

function Bags.ResolveSearchMatch(itemID, bagID, slotIndex, info)
    local searchText = Bags.searchText or ""
    if type(searchText) ~= "string" or searchText == "" then
        return true
    end
    searchText = string.match(searchText, "^%s*(.-)%s*$") or ""
    if searchText == "" then
        return true
    end
    searchText = string.lower(searchText)

    local searchInfo = info
    if (not searchInfo or searchInfo.isFiltered == nil)
        and C_Container
        and C_Container.GetContainerItemInfo
        and type(bagID) == "number"
        and type(slotIndex) == "number"
    then
        searchInfo = C_Container.GetContainerItemInfo(bagID, slotIndex)
    end

    if searchInfo and searchInfo.isFiltered ~= nil then
        return not searchInfo.isFiltered
    end

    local hyperlink = searchInfo and searchInfo.hyperlink
    if (not hyperlink or hyperlink == "")
        and C_Container
        and C_Container.GetContainerItemLink
        and type(bagID) == "number"
        and type(slotIndex) == "number"
    then
        hyperlink = C_Container.GetContainerItemLink(bagID, slotIndex)
    end

    local itemName
    if hyperlink and GetItemInfo then
        itemName = GetItemInfo(hyperlink)
    end

    if (not itemName or itemName == "") and C_Item and C_Item.GetItemNameByID and type(itemID) == "number" then
        itemName = C_Item.GetItemNameByID(itemID)
    end

    if type(itemName) == "string" and itemName ~= "" then
        return string.lower(itemName):find(searchText, 1, true) ~= nil
    end

    if Bags.MatchesSearch then
        return Bags.MatchesSearch(itemID)
    end

    return true
end

----------------------------------------------------------------------------------------
-- Slot State
----------------------------------------------------------------------------------------

local function BuildSlotState(bagID, slotIndex, info, categoryOrderIndex, unresolvedMeta, bagSectionCache)
    if not info or not info.itemID then return nil end

    local itemID = info.itemID
    local meta = Bags.GetItemMetadata and Bags.GetItemMetadata(itemID, info.hyperlink) or nil
    if not meta then
        unresolvedMeta[itemID] = true
    end

    local stackCount = info.stackCount or 1
    local quality = info.quality
    local isBound = info.isBound and true or false
    local isLocked = info.isLocked and true or false
    local isNewItem = C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bagID, slotIndex) and true or false

    local viewKey
    local categoryKey
    local subCategoryKey
    local sectionKey
    local sectionLabel
    local sectionOrder
    local sectionSubOrder = 0
    local sectionCategoryKey
    local sectionSubCategoryKey
    local sectionTargetBagID

    if bagID == 5 then
        viewKey = "reagent"
        local reagentKey, reagentLabel, reagentSort
        if Bags.GetReagentSlotCategory then
            reagentKey, reagentLabel, reagentSort = Bags.GetReagentSlotCategory(itemID, info.hyperlink)
        end
        categoryKey = reagentKey or "OTHER"
        sectionLabel = reagentLabel or categoryKey or (OTHER or "Other")
        sectionOrder = reagentSort or 9999
        sectionKey = "reagent:" .. tostring(categoryKey)
        sectionCategoryKey = categoryKey
        sectionSubCategoryKey = nil
        sectionTargetBagID = nil
    else
        viewKey = "main"
        if Bags.GetItemCategory then
            categoryKey, subCategoryKey = Bags.GetItemCategory(bagID, slotIndex, info)
        end
        categoryKey = categoryKey or "Other"
        if Bags.IsCombinedViewEnabled and Bags.IsCombinedViewEnabled() then
            sectionCategoryKey = MAIN_SECTION.COMBINED_CATEGORY
            sectionSubCategoryKey = nil
            sectionLabel = MAIN_SECTION.COMBINED_LABEL
            sectionOrder = 1
            sectionSubOrder = 0
            sectionKey = MAIN_SECTION.COMBINED_KEY
            sectionTargetBagID = nil
        elseif Bags.IsBagViewEnabled and Bags.IsBagViewEnabled() then
            local bagSection = bagSectionCache and bagSectionCache[bagID]
            sectionCategoryKey = (bagSection and bagSection.categoryKey) or (MAIN_SECTION.BAG_CATEGORY_PREFIX .. tostring(bagID))
            sectionSubCategoryKey = nil
            sectionLabel = (bagSection and bagSection.label) or GetMainBagLabel(bagID)
            sectionOrder = (bagSection and bagSection.order) or (bagID + 1)
            sectionSubOrder = 0
            sectionKey = (bagSection and bagSection.key) or ("main:" .. MAIN_SECTION.BAG_CATEGORY_PREFIX .. tostring(bagID) .. ":")
            sectionTargetBagID = bagID
        else
            sectionCategoryKey = categoryKey
            sectionSubCategoryKey = subCategoryKey
            sectionLabel = subCategoryKey or (Bags.GetCategoryLabel and Bags.GetCategoryLabel(categoryKey)) or categoryKey
            sectionOrder = categoryOrderIndex[categoryKey] or 9999
            sectionSubOrder = subCategoryKey and 1 or 0
            sectionKey = "main:" .. tostring(categoryKey) .. ":" .. tostring(subCategoryKey or "")
            sectionTargetBagID = nil
        end
    end

    local state = {
        slotKey = ToSlotKey(bagID, slotIndex),
        bagID = bagID,
        slotIndex = slotIndex,
        itemID = itemID,
        hyperlink = info.hyperlink,
        iconFileID = info.iconFileID,
        stackCount = stackCount,
        quality = quality,
        isBound = isBound,
        isLocked = isLocked,
        isNewItem = isNewItem,
        categoryKey = categoryKey,
        subCategoryKey = subCategoryKey,
        sectionCategoryKey = sectionCategoryKey,
        sectionSubCategoryKey = sectionSubCategoryKey,
        sectionTargetBagID = sectionTargetBagID,
        sectionKey = sectionKey,
        sectionLabel = sectionLabel,
        sectionOrder = sectionOrder,
        sectionSubOrder = sectionSubOrder,
        viewKey = viewKey,
    }

    if Bags.ResolveSearchMatch then
        state.searchMatch = Bags.ResolveSearchMatch(itemID, bagID, slotIndex, info)
    else
        state.searchMatch = (Bags.MatchesSearch and Bags.MatchesSearch(itemID)) or true
    end

    state.visualRevision = Bags.ComputeVisualRevision(state)
    return state
end

----------------------------------------------------------------------------------------
-- Section Management
----------------------------------------------------------------------------------------

local function AddToSection(sectionMap, sectionList, slotState)
    local section = sectionMap[slotState.sectionKey]
    if not section then
        section = {
            key = slotState.sectionKey,
            viewKey = slotState.viewKey,
            categoryKey = (slotState.sectionCategoryKey ~= nil) and slotState.sectionCategoryKey or slotState.categoryKey,
            subCategoryKey = (slotState.sectionCategoryKey ~= nil) and slotState.sectionSubCategoryKey or slotState.subCategoryKey,
            label = slotState.sectionLabel,
            sortOrder = slotState.sectionOrder or 9999,
            subOrder = slotState.sectionSubOrder or 0,
            targetBagID = slotState.sectionTargetBagID,
            slotKeys = {},
        }
        sectionMap[slotState.sectionKey] = section
        table.insert(sectionList, section)
    end
    table.insert(section.slotKeys, slotState.slotKey)
end

local function SortSectionSlots(section, slotStateByKey, sortMode, categoryOrderIndex)
    table.sort(section.slotKeys, function(a, b)
        local sa = slotStateByKey[a]
        local sb = slotStateByKey[b]
        if not sa or not sb then
            return tostring(a) < tostring(b)
        end
        return CompareSectionSlots(sa, sb, sortMode, categoryOrderIndex or {})
    end)
end

----------------------------------------------------------------------------------------
-- Delta Helpers
----------------------------------------------------------------------------------------

local function BuildSectionSignature(sectionList)
    local tokens = {}
    for i, section in ipairs(sectionList) do
        tokens[i] = section.key .. ":" .. tostring(#(section.slotKeys or {}))
    end
    return table.concat(tokens, "|")
end

local function IsLockOnlyChange(oldState, newState)
    return oldState.sectionKey == newState.sectionKey
        and oldState.visualRevision == newState.visualRevision
        and oldState.searchMatch == newState.searchMatch
        and oldState.isLocked ~= newState.isLocked
end

local function IsRenderableChange(oldState, newState)
    return oldState.visualRevision ~= newState.visualRevision
        or oldState.searchMatch ~= newState.searchMatch
        or oldState.isLocked ~= newState.isLocked
        or oldState.bagID ~= newState.bagID
        or oldState.slotIndex ~= newState.slotIndex
end

----------------------------------------------------------------------------------------
-- Snapshot building
----------------------------------------------------------------------------------------

function Bags.RefreshBagState(opts)
    opts = opts or {}

    if opts.equipmentSetsChanged and Bags.RebuildEquipmentSetLookup then
        Bags.RebuildEquipmentSetLookup()
    elseif not Bags._equipmentSetLookup and Bags.RebuildEquipmentSetLookup then
        Bags.RebuildEquipmentSetLookup()
    end

    local categoryOrderIndex = BuildCategoryOrderIndex()
    local bagSectionCache = BuildBagSectionCache()
    local prevSlotStateByKey = Bags.SlotStateByKey or {}
    local nextSlotStateByKey = {}
    local unresolvedMeta = {}

    local mainSectionsByKey = {}
    local reagentSectionsByKey = {}
    local mainSectionList = {}
    local reagentSectionList = {}

    local freeSlotsBag = 0
    local freeSlotsReagent = 0
    local normalTotal = 0
    local reagentTotal = 0

    local maxBagSlots = NUM_BAG_SLOTS or 4
    for bagID = 0, maxBagSlots do
        if bagID ~= 5 then
            local bagSlots = C_Container.GetContainerNumSlots(bagID) or 0
            normalTotal = normalTotal + bagSlots
            for slotIndex = 1, bagSlots do
                local info = C_Container.GetContainerItemInfo(bagID, slotIndex)
                if not info or not info.itemID then
                    freeSlotsBag = freeSlotsBag + 1
                else
                    local slotState = BuildSlotState(bagID, slotIndex, info, categoryOrderIndex, unresolvedMeta, bagSectionCache)
                    if slotState then
                        nextSlotStateByKey[slotState.slotKey] = slotState
                        AddToSection(mainSectionsByKey, mainSectionList, slotState)
                    end
                end
            end
        end
    end

    local reagentSlots = C_Container.GetContainerNumSlots(5) or 0
    reagentTotal = reagentSlots
    for slotIndex = 1, reagentSlots do
        local info = C_Container.GetContainerItemInfo(5, slotIndex)
        if not info or not info.itemID then
            freeSlotsReagent = freeSlotsReagent + 1
        else
            local slotState = BuildSlotState(5, slotIndex, info, categoryOrderIndex, unresolvedMeta, bagSectionCache)
            if slotState then
                nextSlotStateByKey[slotState.slotKey] = slotState
                AddToSection(reagentSectionsByKey, reagentSectionList, slotState)
            end
        end
    end

    local enabledOrder = (Bags.GetEnabledCategoryOrder and Bags.GetEnabledCategoryOrder()) or Bags.CATEGORY_ORDER or {}
    local combinedViewEnabled = Bags.IsCombinedViewEnabled and Bags.IsCombinedViewEnabled()
    local bagViewEnabled = Bags.IsBagViewEnabled and Bags.IsBagViewEnabled()
    local mainSortMode = (Bags.SORT_MODE and Bags.SORT_MODE.BLIZZARD) or "Blizzard"
    if not bagViewEnabled then
        mainSortMode = (Bags.GetActiveSortMode and Bags.GetActiveSortMode()) or mainSortMode
    end
    if bagViewEnabled then
        for bagID, bagSection in pairs(bagSectionCache) do
            if type(bagID) == "number" and bagID ~= 5 and bagSection and not mainSectionsByKey[bagSection.key] then
                local section = {
                    key = bagSection.key,
                    viewKey = "main",
                    categoryKey = bagSection.categoryKey,
                    subCategoryKey = nil,
                    label = bagSection.label,
                    sortOrder = bagSection.order or (bagID + 1),
                    subOrder = 0,
                    targetBagID = bagID,
                    slotKeys = {},
                }
                mainSectionsByKey[bagSection.key] = section
                table.insert(mainSectionList, section)
            end
        end
    end

    if not combinedViewEnabled and not bagViewEnabled and Bags.IsCustomCategoryKey then
        for _, categoryKey in ipairs(enabledOrder) do
            if Bags.IsCustomCategoryKey(categoryKey) then
                local sectionKey = "main:" .. tostring(categoryKey) .. ":"
                if not mainSectionsByKey[sectionKey] then
                    local section = {
                        key = sectionKey,
                        viewKey = "main",
                        categoryKey = categoryKey,
                        subCategoryKey = nil,
                        label = (Bags.GetCategoryLabel and Bags.GetCategoryLabel(categoryKey)) or categoryKey,
                        sortOrder = categoryOrderIndex[categoryKey] or 9999,
                        subOrder = 0,
                        slotKeys = {},
                    }
                    mainSectionsByKey[sectionKey] = section
                    table.insert(mainSectionList, section)
                end
            end
        end
    end

    for _, section in ipairs(mainSectionList) do
        SortSectionSlots(section, nextSlotStateByKey, mainSortMode, categoryOrderIndex)
    end
    for _, section in ipairs(reagentSectionList) do
        SortSectionSlots(section, nextSlotStateByKey, (Bags.SORT_MODE and Bags.SORT_MODE.BLIZZARD) or "Blizzard", categoryOrderIndex)
    end

    table.sort(mainSectionList, function(a, b)
        if a.sortOrder ~= b.sortOrder then
            return a.sortOrder < b.sortOrder
        end
        if a.subOrder ~= b.subOrder then
            return a.subOrder < b.subOrder
        end
        return tostring(a.label or a.key) < tostring(b.label or b.key)
    end)

    table.sort(reagentSectionList, function(a, b)
        if a.sortOrder ~= b.sortOrder then
            return a.sortOrder < b.sortOrder
        end
        return tostring(a.label or a.key) < tostring(b.label or b.key)
    end)

    local delta = {
        added = {},
        removed = {},
        changed = {},
        movedCategory = {},
        movedFrom = {},
        lockOnly = {},
        structural = false,
    }

    local dirtyMain = {}
    local dirtyReagent = {}

    for slotKey, oldState in pairs(prevSlotStateByKey) do
        local newState = nextSlotStateByKey[slotKey]
        if not newState then
            delta.removed[slotKey] = oldState
            MarkSectionDirty(dirtyMain, dirtyReagent, oldState.viewKey, oldState.sectionKey)
        elseif oldState.sectionKey ~= newState.sectionKey or oldState.viewKey ~= newState.viewKey then
            delta.movedCategory[slotKey] = newState
            delta.movedFrom[slotKey] = oldState
            MarkSectionDirty(dirtyMain, dirtyReagent, oldState.viewKey, oldState.sectionKey)
            MarkSectionDirty(dirtyMain, dirtyReagent, newState.viewKey, newState.sectionKey)
            delta.structural = true
        elseif IsLockOnlyChange(oldState, newState) then
            delta.lockOnly[slotKey] = newState
            MarkSectionDirty(dirtyMain, dirtyReagent, newState.viewKey, newState.sectionKey)
        elseif IsRenderableChange(oldState, newState) then
            delta.changed[slotKey] = newState
            MarkSectionDirty(dirtyMain, dirtyReagent, newState.viewKey, newState.sectionKey)
        end
    end

    for slotKey, newState in pairs(nextSlotStateByKey) do
        if not prevSlotStateByKey[slotKey] then
            delta.added[slotKey] = newState
            MarkSectionDirty(dirtyMain, dirtyReagent, newState.viewKey, newState.sectionKey)
            delta.structural = true
        end
    end

    local prevSections = Bags.SectionStateByKey or { main = {}, reagent = {} }
    for sectionKey, _ in pairs(prevSections.main or {}) do
        if not mainSectionsByKey[sectionKey] then
            dirtyMain[sectionKey] = true
            delta.structural = true
        end
    end
    for sectionKey, section in pairs(mainSectionsByKey) do
        local prevSection = prevSections.main and prevSections.main[sectionKey]
        if not prevSection or #(prevSection.slotKeys or {}) ~= #(section.slotKeys or {}) then
            dirtyMain[sectionKey] = true
            delta.structural = true
        end
    end

    for sectionKey, _ in pairs(prevSections.reagent or {}) do
        if not reagentSectionsByKey[sectionKey] then
            dirtyReagent[sectionKey] = true
            delta.structural = true
        end
    end
    for sectionKey, section in pairs(reagentSectionsByKey) do
        local prevSection = prevSections.reagent and prevSections.reagent[sectionKey]
        if not prevSection or #(prevSection.slotKeys or {}) ~= #(section.slotKeys or {}) then
            dirtyReagent[sectionKey] = true
            delta.structural = true
        end
    end

    local mainSignature = BuildSectionSignature(mainSectionList)
    local reagentSignature = BuildSectionSignature(reagentSectionList)
    if mainSignature ~= Bags._mainSectionSignature or reagentSignature ~= Bags._reagentSectionSignature then
        delta.structural = true
    end
    Bags._mainSectionSignature = mainSignature
    Bags._reagentSectionSignature = reagentSignature

    Bags.DirtySections.main = dirtyMain
    Bags.DirtySections.reagent = dirtyReagent
    Bags.SlotStateByKey = nextSlotStateByKey
    Bags.SectionStateByKey = {
        main = mainSectionsByKey,
        reagent = reagentSectionsByKey,
    }
    Bags.MainSectionList = mainSectionList
    Bags.ReagentSectionList = reagentSectionList
    Bags.PendingDelta = delta

    Bags._snapshotRevision = (Bags._snapshotRevision or 0) + 1
    Bags._snapshot = {
        revision = Bags._snapshotRevision,
        freeSlotsBag = freeSlotsBag,
        freeSlotsReagent = freeSlotsReagent,
        normalTotal = normalTotal,
        reagentTotal = reagentTotal,
        mainSections = mainSectionList,
        reagentSections = reagentSectionList,
        slotStateByKey = nextSlotStateByKey,
        delta = delta,
    }

    Bags._snapshotDirty = false
    if next(unresolvedMeta) then
        Bags.QueueItemMetadataPrefetch(unresolvedMeta)
    end

    return Bags._snapshot
end

function Bags.RefreshSnapshot(opts)
    local snapshot = Bags.RefreshBagState(opts)
    if opts and opts.render and Bags.RenderBagSnapshot then
        Bags.RenderBagSnapshot(Bags.Frame, snapshot, opts)
    end
    return snapshot
end

function Bags.GetSnapshot()
    if Bags._snapshotDirty or not Bags._snapshot then
        return Bags.RefreshBagState()
    end
    return Bags._snapshot
end
