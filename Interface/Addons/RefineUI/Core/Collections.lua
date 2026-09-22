-- Account collection facts shared by UI consumers. Ownership is queried on demand;
-- durable instance manifests and revision stamps live in JournalCache.
local _, RefineUI = ...
local Collections = { revision = 0, ownership = {}, listeners = {} }
RefineUI.Collections = Collections

local function ValidID(id) return type(id) == "number" and id > 0 end

function Collections:Subscribe(owner, callback)
    self.listeners[owner] = callback
end

function Collections:Invalidate(kind, persistent)
    if persistent ~= false and RefineUI.JournalCache then
        RefineUI.JournalCache:InvalidateOwnership(kind)
    end
    if not kind or kind == "appearances" then self.ownership = {} end
    self.revision = self.revision + 1
    for _, callback in pairs(self.listeners) do callback(kind) end
end

function Collections:IsAppearanceCollected(appearanceID, sourceID)
    local cached = self.ownership[appearanceID]
    if cached ~= nil then return cached end
    local api = C_TransmogCollection
    if not api then return nil end
    local owned
    if api.GetAllAppearanceSources and api.PlayerHasTransmogItemModifiedAppearance then
        if sourceID and api.PlayerHasTransmogItemModifiedAppearance(sourceID) == true then
            owned = true
        else
            local sources = api.GetAllAppearanceSources(appearanceID)
            if type(sources) == "table" and #sources > 0 then
                owned = false
                for _, id in ipairs(sources) do
                    local value = api.PlayerHasTransmogItemModifiedAppearance(id)
                    if value == true then owned = true; break end
                    if value == nil then owned = nil end
                end
            end
        end
    elseif sourceID and api.GetAppearanceInfoBySource then
        local info = api.GetAppearanceInfoBySource(sourceID)
        if info then owned = info.appearanceIsCollected end
    end
    -- Never turn unavailable data into a cached negative.
    if owned ~= nil then self.ownership[appearanceID] = owned end
    return owned
end

-- Ownership lookup for identities already resolved into the account manifest.
-- This avoids item-data loads and item-type detection on later sessions.
function Collections:IsCollected(kind, id)
    if not ValidID(id) then return nil end
    if kind == "appearances" then
        return self:IsAppearanceCollected(id)
    elseif kind == "mounts" then
        if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return nil end
        return select(11, C_MountJournal.GetMountInfoByID(id))
    elseif kind == "pets" then
        if not (C_PetJournal and C_PetJournal.GetNumCollectedInfo) then return nil end
        local count = C_PetJournal.GetNumCollectedInfo(id)
        if type(count) == "number" then return count > 0 end
        return nil
    elseif kind == "toys" then
        if not PlayerHasToy then return nil end
        return PlayerHasToy(id)
    end
end

-- Identity is independent of ownership. Preserve the full difficulty-specific link.
-- Returns kind, collection ID, owned (true/false/nil), pending item data.
function Collections:ResolveItem(item)
    local itemID, link = item.itemID, item.link
    if not ValidID(itemID) or type(link) ~= "string" or link == "" then return nil, nil, nil, true end
    if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        if C_Item.RequestLoadItemDataByID and not item.requested then
            item.requested = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil, nil, nil, true
    end
    if not (C_MountJournal and C_MountJournal.GetMountFromItem
        and C_PetJournal and C_PetJournal.GetPetInfoByItemID
        and C_ToyBox and C_ToyBox.GetToyInfo
        and C_TransmogCollection and C_TransmogCollection.GetItemInfo) then
        return nil, nil, nil, true
    end
    local mountID = C_MountJournal.GetMountFromItem(itemID)
    if ValidID(mountID) then
        local owned
        if C_MountJournal.GetMountInfoByID then owned = select(11, C_MountJournal.GetMountInfoByID(mountID)) end
        return "mounts", mountID, owned
    end
    local petName, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
    if petName then
        local owned
        if ValidID(speciesID) and C_PetJournal.GetNumCollectedInfo then
            local count = C_PetJournal.GetNumCollectedInfo(speciesID)
            if type(count) == "number" then owned = count > 0 end
        end
        return "pets", ValidID(speciesID) and speciesID or itemID, owned
    end
    local toyID = C_ToyBox.GetToyInfo(itemID)
    if ValidID(toyID) then
        local owned
        if PlayerHasToy then owned = PlayerHasToy(toyID) end
        return "toys", toyID, owned
    end
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(link)
    if ValidID(appearanceID) and ValidID(sourceID) then
        return "appearances", appearanceID, self:IsAppearanceCollected(appearanceID, sourceID)
    end
end

-- Tokens contribute their resulting visuals, not a second synthetic collectible.
function Collections:VisitRewards(item, visit)
    if RefineUI.GetTokenAppearanceData then
        local supported, data = RefineUI:GetTokenAppearanceData(item.link, item.itemID)
        if supported then
            if not data then return true end
            local seen = {}
            for _, appearances in pairs(data) do
                for _, id in ipairs(appearances) do
                    if not seen[id] then
                        seen[id] = true
                        visit("appearances", id, self:IsAppearanceCollected(id))
                    end
                end
            end
            return false
        end
    end
    local kind, id, owned, pending = self:ResolveItem(item)
    if kind then visit(kind, id, owned) end
    return pending
end

-- Broad list/update events also fire while Blizzard initializes collection
-- journals. Refresh visible consumers, but do not make a persisted snapshot
-- stale on every login/reload. The specific acquisition/removal events advance
-- the durable revision used by account-wide snapshots.
local EVENTS = {
    TRANSMOG_COLLECTION_UPDATED = { "appearances", false },
    PET_JOURNAL_LIST_UPDATE = { "pets", false },
    TRANSMOG_COLLECTION_SOURCE_ADDED = { "appearances", true },
    TRANSMOG_COLLECTION_SOURCE_REMOVED = { "appearances", true },
    NEW_MOUNT_ADDED = { "mounts", true },
    COMPANION_LEARNED = { "pets", true },
    NEW_PET_ADDED = { "pets", true },
    PET_JOURNAL_PET_DELETED = { "pets", true },
    PET_JOURNAL_PET_RESTORED = { "pets", true },
    PET_JOURNAL_PET_REVOKED = { "pets", true },
    NEW_TOY_ADDED = { "toys", true },
}
for event, info in pairs(EVENTS) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
        local kind, persistent = info[1], info[2]
        RefineUI:RegisterEventCallback(event, function()
            Collections:Invalidate(kind, persistent)
        end, "Collections:" .. event)
    end
end
