-- Two private catalog searches provide explicit collected/uncollected evidence.
-- Absence from either result set is unknown, never assumed to mean uncollected.
local _, RefineUI = ...
local Runtime = RefineUI.Opportunities
local function Accessible(value)
    return not (issecretvalue and issecretvalue(value)) and (not canaccessvalue or canaccessvalue(value))
end
local function Table(value)
    return Accessible(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end
local function Method(object, name, ...)
    if not object or type(object[name]) ~= "function" then return false end
    return pcall(object[name], object, ...)
end

function Runtime:StartHousing(refresh)
    if not self.visible or InCombatLockdown() or not self.engine then return end
    if not self.housingSearchers then
        local wanted = {}
        for _, reward in ipairs(self.engine.data.rewards) do
            if reward[1] == "decor" then wanted[reward[2]] = true end
        end
        if not next(wanted) or not C_HousingCatalog or not C_HousingCatalog.CreateCatalogSearcher then return end
        self.housingWanted, self.housingSearchers = wanted, {}
        for index = 1, 2 do
            local ok, searcher = pcall(C_HousingCatalog.CreateCatalogSearcher)
            if not ok or not searcher then self.housingUnavailable = true; return end
            self.housingSearchers[index] = searcher
            Method(searcher, "SetAutoUpdateOnParamChanges", false)
            if not Method(searcher, "SetCollected", index == 1)
                or not Method(searcher, "SetUncollected", index == 2) then self.housingUnavailable = true; return end
            Method(searcher, "SetStoredOnly", false)
            Method(searcher, "SetOwnedOnly", false) -- Older Retail name.
            Method(searcher, "SetFirstAcquisitionBonusOnly", false)
            Method(searcher, "SetSearchText", nil)
            if not Method(searcher, "SetResultsUpdatedCallback", function()
                self.housingPending = true; self:Schedule()
            end) then self.housingUnavailable = true; return end
        end
        refresh = true
    end
    if self.collectionActive == "decor" then
        local data = RefineUI.OpportunityCollectionData
        for _, id in ipairs(data and data.ids and data.ids.decor or {}) do self.housingWanted[id] = true end
    end
    if self.housingUnavailable then return end
    if refresh or self.housingDirty then
        self.housingGeneration = (self.housingGeneration or 0) + 1
        self.housingDirty = nil
        for _, searcher in ipairs(self.housingSearchers) do Method(searcher, "RunSearch") end
    end
end

function Runtime:CaptureHousing()
    if not self.housingSearchers or self.housingUnavailable then return end
    local known, conflicts = {}, {}
    local generation = self.housingGeneration
    local decorType = Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor
    for index, searcher in ipairs(self.housingSearchers) do
        if self.inWorker then coroutine.yield() end
        local ok, busy = Method(searcher, "IsSearchInProgress")
        if not ok or not Accessible(busy) or busy ~= false then return end
        local success, entries = Method(searcher, "GetCatalogSearchResults")
        if not success or not Table(entries) then return end
        for i, entry in ipairs(entries) do
            if i % 32 == 0 and self.inWorker then coroutine.yield() end
            if not Table(entry) or not Accessible(entry.recordID) or not Accessible(entry.entryType) then return end
            local id = entry.recordID
            if entry.entryType == decorType and self.housingWanted[id] then
                local owned = index == 1
                if known[id] ~= nil and known[id] ~= owned then conflicts[id] = true end
                known[id] = owned
            end
        end
    end
    for id in pairs(conflicts) do known[id] = nil end
    if generation ~= self.housingGeneration then return end
    self.decorOwnership = known
    self.engine:Invalidate("reward")
    local collectionState = self.collection and self.collection.decor
    if collectionState then
        collectionState.dirty, collectionState.status = true, "pending"
        self.collectionRequests = self.collectionRequests or {}
        self.collectionRequests.decor = true
    end
end
