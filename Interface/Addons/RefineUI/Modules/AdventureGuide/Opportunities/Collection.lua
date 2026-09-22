-- Native collection catalog. ATT routes annotate entries but never define totals.
local _, RefineUI = ...
local Runtime = RefineUI.Opportunities

local mountSources = {
    [0] = "Unknown source", [1] = "Drop", [2] = "Quest", [3] = "Vendor",
    [4] = "Profession", [5] = "Achievement", [6] = "World event",
    [7] = "Promotion", [8] = "Store", [9] = "Trading Post", [10] = "PvP",
}

local function State(runtime, kind)
    runtime.collection = runtime.collection or {}
    runtime.collection[kind] = runtime.collection[kind] or { status = "idle", rows = {}, counts = {} }
    return runtime.collection[kind]
end

local function Supported(kind)
    return kind == "mount" or kind == "pet" or kind == "toy" or kind == "appearance"
        or kind == "decor" or kind == "achievements"
end

function Runtime:RequestCollection(kind)
    if not Supported(kind) then return end
    local state = State(self, kind)
    self.collectionActive = kind
    if state.status == "ready" and not state.dirty then return end
    if state.status == "pending" or state.status == "scanning" then return end
    if kind == "decor" and self.StartHousing then self:StartHousing(true) end
    state.status = "pending"
    self.collectionRequests = self.collectionRequests or {}
    self.collectionRequests[kind] = true
    if not self.inWorker then self:Schedule() end
end

function Runtime:InvalidateCollection(kind, force)
    if not self.collection then return end
    for key, state in pairs(self.collection) do
        if not kind or key == kind then
            state.dirty = true
            if force then state.status = "idle" end
            if self.visible and self.collectionActive == key then
                state.status = "idle"; self:RequestCollection(key)
            end
        end
    end
end

function Runtime:DiscoverCollection(kind)
    if not Supported(kind) then return end
    local state = State(self, kind)
    state.status = "scanning"
    local ids
    if kind == "mount" then ids = self:Call(C_MountJournal, "GetMountIDs")
    elseif kind == "appearance" then
        ids = {}
        local types = Enum and Enum.TransmogCollectionType
        local seenTypes = {}
        for _, categoryID in pairs(type(types) == "table" and types or {}) do
            if type(categoryID) == "number" and categoryID > 0 and not seenTypes[categoryID] then
                seenTypes[categoryID] = true
                ids[#ids + 1] = categoryID
            end
        end
        table.sort(ids)
    elseif kind == "achievements" then
        ids = {}
        local categories = self:Call(_G, "GetCategoryList")
        for categoryOrder, categoryID in ipairs(categories or {}) do
            local categoryName = self:Call(_G, "GetCategoryInfo", categoryID)
            local count = self:Call(_G, "GetCategoryNumAchievements", categoryID)
            for index = 1, type(count) == "number" and count or 0 do
                ids[#ids + 1] = {categoryID, index, categoryName, categoryOrder}
            end
        end
    else
        local data = RefineUI.OpportunityCollectionData
        ids = data and data.schema == 1 and data.ids and data.ids[kind]
    end
    if type(ids) ~= "table" or #ids == 0 then
        state.status, state.error = "unavailable", self.readFailure or "Collection identity catalog returned no entries"
        return
    end
    local rows, counts = {}, { total = 0, owned = 0, missing = 0, unknown = 0, unavailable = 0,
        candidates = #ids, rejected = 0 }
    self.collectionProgress = { kind = kind, checked = 0, total = #ids }
    local seen = {}
    for _, candidate in ipairs(ids) do
        local id = candidate
        local row, skip
        if kind == "mount" then
            local name, spellID, icon, _, _, sourceType, _, _, _, shouldHideOnChar, isCollected =
                self:Call(C_MountJournal, "GetMountInfoByID", id)
            if type(name) == "string" and type(spellID) == "number" and spellID > 0 then
                local owned
                if type(isCollected) == "boolean" then owned = isCollected end
                row = { id = "collection:mount:" .. id, collectionRow = true, collectionKind = "mount",
                    mountID = id, collectionKey = "mountSpell:" .. spellID, spellID = spellID,
                    title = name, icon = icon, owned = owned, unavailable = shouldHideOnChar == true,
                    sourceType = sourceType, sourceLabel = mountSources[sourceType] or "Other source",
                    groupLabel = mountSources[sourceType] or "Other source", groupOrder = (sourceType or 99) + 1 }
            end
        elseif kind == "pet" then
            local name, icon, _, _, sourceText, _, _, _, _, _, obtainable = self:Call(C_PetJournal, "GetPetInfoBySpeciesID", id)
            if type(name) == "string" then
                local ownedCount = self:Call(C_PetJournal, "GetNumCollectedInfo", id)
                local owned
                if type(ownedCount) == "number" then owned = ownedCount > 0 end
                row = { id = "collection:pet:" .. id, collectionRow = true, collectionKind = "pet",
                    speciesID = id, collectionKey = "pet:" .. id, title = name, icon = icon, owned = owned,
                    unavailable = obtainable == false, sourceLabel = type(sourceText) == "string" and sourceText or "Pet Journal",
                    groupLabel = "Battle Pets", groupOrder = 1 }
            end
        elseif kind == "toy" then
            local toyID, name, icon = self:Call(C_ToyBox, "GetToyInfo", id)
            if type(toyID) == "number" and toyID > 0 then
                local owned = self:Call(_G, "PlayerHasToy", id)
                if type(owned) ~= "boolean" then owned = nil end
                if type(name) ~= "string" then
                    name = "Toy " .. id
                    if self.RequestItem then self:RequestItem(id) end
                end
                row = { id = "collection:toy:" .. id, collectionRow = true, collectionKind = "toy",
                    itemID = id, collectionKey = "toy:" .. id, title = name, icon = icon, owned = owned,
                    sourceLabel = "Toy Box", groupLabel = "Toys", groupOrder = 1 }
            end
        elseif kind == "appearance" then
            local name, isWeapon = self:Call(C_TransmogCollection, "GetCategoryInfo", id)
            local total = self:Call(C_TransmogCollection, "GetCategoryTotal", id)
            local collected = self:Call(C_TransmogCollection, "GetCategoryCollectedCount", id)
            if type(name) == "string" and type(total) == "number" and total > 0
                and type(collected) == "number" and collected >= 0 then
                collected = math.min(collected, total)
                row = { id = "collection:appearance-category:" .. id, collectionRow = true,
                    collectionGroup = true, collectionKind = "appearance", categoryID = id,
                    title = name, icon = 136516, owned = collected >= total,
                    collectedCount = collected, totalCount = total, sourceLabel = "Appearance collection",
                    groupLabel = isWeapon and "Weapons" or "Armor", groupOrder = isWeapon and 1 or 2 }
            end
        elseif kind == "decor" then
            local decorType = Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor
            local info = decorType and self:Call(C_HousingCatalog, "GetCatalogEntryInfoByRecordID", decorType, id)
            if info and type(info.name) == "string" then
                row = { id = "collection:decor:" .. id, collectionRow = true, collectionKind = "decor",
                    recordID = id, collectionKey = "decor:" .. id, title = info.name, icon = info.iconTexture,
                    owned = self.decorOwnership and self.decorOwnership[id], sourceLabel = "Housing Decor",
                    groupLabel = "Housing Decor", groupOrder = 1 }
            end
        else
            local achievementID, name, _, completed, _, _, _, _, _, icon, _, guild, _, _, statistic =
                self:Call(_G, "GetAchievementInfo", candidate[1], candidate[2])
            id = achievementID
            if type(id) == "number" and seen[id] then skip = true
            elseif type(id) == "number" and type(name) == "string" and not guild and not statistic then
                seen[id] = true
                local owned
                if type(completed) == "boolean" then owned = completed end
                row = { id = "collection:achievement:" .. id, collectionRow = true, collectionKind = "achievements",
                    achievementID = id, title = name, icon = icon, owned = owned, sourceLabel = "Achievement",
                    groupLabel = type(candidate[3]) == "string" and candidate[3] or "Achievements",
                    groupOrder = candidate[4] or 999 }
            end
        end
        if row then
            local owned, unavailable = row.owned, row.unavailable
            rows[#rows + 1] = row
            local amount = row.collectionGroup and row.totalCount or 1
            local collected = row.collectionGroup and row.collectedCount or nil
            counts.total = counts.total + amount
            if collected then
                counts.owned = counts.owned + collected
                counts.missing = counts.missing + amount - collected
            elseif owned == true then counts.owned = counts.owned + 1
            elseif owned == false then counts.missing = counts.missing + 1
            else counts.unknown = counts.unknown + 1 end
            if unavailable then counts.unavailable = counts.unavailable + 1 end
        elseif not skip and kind ~= "appearance" then counts.rejected = counts.rejected + 1 end
        self.collectionProgress.checked = self.collectionProgress.checked + 1
    end
    table.sort(rows, function(a, b)
        local an, bn = a.title:lower(), b.title:lower()
        return an == bn and a.id < b.id or an < bn
    end)
    state.rows, state.counts, state.status, state.error, state.dirty = rows, counts, "ready", nil, nil
    self.collectionProgress = nil
end

function Runtime:GetCollectionStatus(kind)
    return State(self, kind)
end

function Runtime:GetCollectionView(kind, ownership)
    local state = State(self, kind)
    if state.status ~= "ready" then return {}, 0, state.counts, state.status end
    local prefs = self:Preferences()
    local search = (prefs.collectionSearch or ""):lower()
    local groups, byLabel, total = {}, {}, 0
    for _, row in ipairs(state.rows) do
        local matchesOwnership = ownership == "all" or ownership == "owned" and row.owned == true
            or ownership == "missing" and row.owned == false
        if matchesOwnership and not prefs.hidden[row.id]
            and (search == "" or row.title:lower():find(search, 1, true)) then
            local label = row.groupLabel or "Collection"
            local group = byLabel[label]
            if not group then
                group = { label = label, order = row.groupOrder or 999, items = {} }
                byLabel[label], groups[#groups + 1] = group, group
            end
            group.items[#group.items + 1] = row
            total = total + 1
        end
    end
    table.sort(groups, function(a, b)
        return a.order == b.order and a.label < b.label or a.order < b.order
    end)
    return groups, total, state.counts, state.status
end

function Runtime:DecorateCollectionRow(source)
    if not source then return nil end
    local prefs = self:Preferences()
    local recommendations = self.engine and self.engine:GetRecommendationIndex(prefs, self.mapID) or {}
    local recommendation = source.collectionKind == "achievements" and self.engine and self.engine.achievements[source.achievementID]
        or recommendations[source.collectionKey]
    local row = {}
    for key, value in pairs(source) do row[key] = value end
    row.recommendation = recommendation
    if row.collectionGroup then
        row.label = row.owned and "Category complete" or "Category incomplete"
        row.detail = string.format("%d / %d appearances collected", row.collectedCount, row.totalCount)
    elseif row.owned == true then
        row.label, row.detail = "Collected", row.sourceLabel
    elseif row.owned == nil then
        row.label, row.detail = "Ownership unknown", row.sourceLabel
    elseif row.unavailable then
        row.label, row.detail = "Missing • Unavailable to this character", row.sourceLabel
    elseif recommendation then
        row.label = "Missing • " .. recommendation.label
        row.detail = recommendation.detail or recommendation.label
    else
        row.label, row.detail = "Missing", row.sourceLabel .. " • No verified recommendation"
    end
    return row
end

-- Compatibility for diagnostics/tests and any future non-grid consumer.
function Runtime:GetCollectionPage(offset, limit, kind, ownership)
    local groups, total, counts, status = self:GetCollectionView(kind, ownership)
    if status ~= "ready" then return {}, total, counts, status end
    local first, last = (offset or 0) + 1, (offset or 0) + (limit or 20)
    local page, cursor = {}, 0
    for _, group in ipairs(groups) do
        for _, source in ipairs(group.items) do
            cursor = cursor + 1
            if cursor >= first and cursor <= last then page[#page + 1] = self:DecorateCollectionRow(source) end
            if cursor >= last then return page, total, counts, status end
        end
    end
    return page, total, counts, status
end
