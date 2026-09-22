local _, RefineUI = ...
local Module = RefineUI:RegisterModule("AdventureGuideOpportunities")
local Runtime = { visible = false, revision = 0, labels = {}, achievementDirty = true, achievementQueue = {},
    pendingItems = {}, merchant = {}, stats = { reads = 0, slices = 0, maxSliceMS = 0 } }
RefineUI.Opportunities = Runtime
local function Accessible(v)
    return not (issecretvalue and issecretvalue(v)) and (not canaccessvalue or canaccessvalue(v))
end
local function Number(v) return Accessible(v) and type(v) == "number" and v == v and math.abs(v) < math.huge end
local fields = {
    GetCurrencyInfo = { "quantity", "name", "isAccountWide", "isAccountTransferable" },
    GetFactionDataByID = { "name", "currentStanding", "reaction", "isHeader", "isHeaderWithRep" },
    GetFriendshipReputation = { "friendshipFactionID" },
    GetFriendshipReputationRanks = { "currentLevel", "maxLevel" },
    GetMajorFactionData = { "renownLevel", "isUnlocked", "name" },
    GetItemInfo = { "price", "stackCount", "numAvailable", "isPurchasable", "hasExtendedCost" },
    GetAppearanceInfoBySource = { "appearanceID", "appearanceIsCollected" },
    GetSourceInfo = { "name", "icon" },
    GetCatalogEntryInfoByRecordID = { "name", "iconTexture" },
}

-- Never put Blizzard-owned tables or secret values into engine caches. Yield before
-- each read, outside pcall: Lua 5.1 cannot yield across a protected-call boundary.
function Runtime:Call(namespace, name, ...)
    if self.inWorker then coroutine.yield() end
    local fn = namespace and namespace[name]
    if type(fn) ~= "function" then self.readFailure = name .. ": API unavailable"; return nil end
    for i = 1, select("#", ...) do if not Accessible(select(i, ...)) then return nil end end
    self.stats.reads = self.stats.reads + 1
    local function Pack(...) return { n = select("#", ...), ... } end
    local values = Pack(pcall(fn, ...))
    if not values[1] then self.readFailure = name .. ": API call failed"; return nil end
    for i = 2, values.n do
        local v = values[i]
        if not Accessible(v) then self.readFailure = name .. ": restricted result"; return nil end
        if type(v) == "table" then
            if canaccesstable and not canaccesstable(v) then self.readFailure = name .. ": restricted table"; return nil end
            local clean = {}
            if fields[name] then
                for _, field in ipairs(fields[name]) do
                    local value = v[field]
                    if not Accessible(value) then self.readFailure = name .. ": restricted " .. field; return nil end
                    if type(value) == "string" or type(value) == "boolean" or Number(value) then clean[field] = value end
                end
            elseif name == "GetCategoryList" or name == "GetMountIDs" then
                for _, value in ipairs(v) do if not Number(value) then return nil end; clean[#clean + 1] = value end
            else return nil end
            values[i] = clean
        elseif type(v) == "number" and not Number(v) then return nil
        elseif type(v) ~= "string" and type(v) ~= "boolean" and v ~= nil and type(v) ~= "number" then return nil end
    end
    return unpack(values, 2, values.n)
end

function Runtime:Preferences()
    if not RefineDB then return { hidden = {}, focus = {} } end
    RefineDB.Opportunities = RefineDB.Opportunities or { version = 1, hidden = {}, focus = {} }
    local db = RefineDB.Opportunities
    db.hidden, db.focus = db.hidden or {}, db.focus or {}
    return db
end

function Runtime:Dependency(req)
    local kind, id = req[1], req[2]
    if kind == "questReward" then
        local done = self:Call(C_QuestLog, "IsQuestFlaggedCompleted", id)
        if done == true then return 0 elseif done ~= false then return nil end
        local active = self:Call(C_QuestLog, "IsOnQuest", id)
        -- Not in the log is a planning lead, not proof the quest is unavailable.
        if active == false then return 3 elseif active ~= true then return nil end
        local ready = self:Call(C_QuestLog, "ReadyForTurnIn", id)
        if type(ready) ~= "boolean" then return nil end
        return ready and 2 or 1
    end
    if kind == "achievementReward" then
        local _, name, _, completed, _, _, _, _, _, _, _, guild, _, _, statistic = self:Call(_G,"GetAchievementInfo",id)
        if not name or type(completed) ~= "boolean" then return nil, self.readFailure or "Achievement completion unavailable" end
        if completed or guild or statistic then return 0 end
        local count=self:Call(_G,"GetAchievementNumCriteria",id)
        if not Number(count) or count < 1 then return nil,"Achievement criteria unavailable" end
        local missing=0
        for index=1,count do
            local _,_,done=self:Call(_G,"GetAchievementCriteriaInfo",id,index)
            if type(done) ~= "boolean" then return nil,"Achievement criterion completion unavailable" end
            if not done then missing=missing+1 end
        end
        self.rewardProgress=self.rewardProgress or {}
        self.rewardProgress[id]={completed=count-missing,total=count,missing=missing}
        return missing > 0 and 1 or 0
    end
    if kind == "capture" then
        local _, _, _, _, _, _, wild, _, _, _, obtainable = self:Call(C_PetJournal, "GetPetInfoBySpeciesID", id)
        if wild ~= true or obtainable ~= true then return nil end
        return 1
    end
    if kind == "gold" then return self:Call(_G, "GetMoney") end
    if kind == "level" then return self:Call(_G, "UnitLevel", "player") end
    if kind == "faction" then
        local faction = self:Call(_G, "UnitFactionGroup", "player")
        return faction == "Horde" and 1 or faction == "Alliance" and 2 or nil
    end
    if kind == "class" then return select(3, self:Call(_G, "UnitClass", "player")) end
    if kind == "race" then return select(3, self:Call(_G, "UnitRace", "player")) end
    if kind == "quest" then
        return self:Call(C_QuestLog, req[4] == "account" and "IsQuestFlaggedCompletedOnAccount" or "IsQuestFlaggedCompleted", id)
    end
    if kind == "achievement" then return select(4, self:Call(_G, "GetAchievementInfo", id)) end
    if kind == "currency" then
        local info = self:Call(C_CurrencyInfo, "GetCurrencyInfo", id)
        self.labels[kind .. ":" .. id] = info and info.name
        return info and info.quantity
    end
    if kind == "renown" then
        local data = self:Call(C_MajorFactions, "GetMajorFactionData", id)
        self.labels[kind .. ":" .. id] = data and data.name
        return data and data.isUnlocked == true and data.renownLevel or nil
    end
    if kind == "reputation" then
        -- ATT thresholds for friendship/renown cannot be compared with ordinary standing.
        local friendship = self:Call(C_GossipInfo, "GetFriendshipReputation", id)
        if not friendship or not Number(friendship.friendshipFactionID) then return nil end
        if friendship.friendshipFactionID > 0 then
            local ranks=self:Call(C_GossipInfo,"GetFriendshipReputationRanks",id)
            return ranks and ranks.currentLevel, not ranks and "Friendship ranks unavailable" or nil, "rank"
        end
        local major = self:Call(C_MajorFactions, "GetMajorFactionData", id)
        if major then
            self.labels[kind..":"..id]=(major.name or "Faction").." renown"
            return major.isUnlocked == true and major.renownLevel or nil,
                major.isUnlocked ~= true and "Major faction not unlocked" or nil, "rank"
        end
        local data = self:Call(C_Reputation, "GetFactionDataByID", id)
        self.labels[kind .. ":" .. id] = data and data.name
        return data and data.currentStanding
    end
end

function Runtime:Ownership(reward)
    local kind, id, itemID = unpack(reward)
    if kind == "mountSpell" then
        id = self:Call(C_MountJournal, "GetMountFromSpell", id)
        if not Number(id) or id <= 0 then return { reason = self.readFailure or "GetMountFromSpell: no journal ID for ATT spell " .. reward[2] } end
        kind = "mount"
    end
    if kind == "mount" then
        local name, _, icon, _, _, _, _, _, _, _, owned = self:Call(C_MountJournal, "GetMountInfoByID", id)
        return { name = name, icon = icon, owned = owned, reason = owned == nil and (self.readFailure or "GetMountInfoByID: ownership unavailable for journal ID " .. id) or nil }
    elseif kind == "pet" then
        local count = self:Call(C_PetJournal, "GetNumCollectedInfo", id)
        local name, icon = self:Call(C_PetJournal, "GetPetInfoBySpeciesID", id)
        local owned
        if Number(count) then owned = count > 0 end
        return { name = name, icon = icon, owned = owned }
    elseif kind == "appearance" then
        local info = self:Call(C_TransmogCollection, "GetAppearanceInfoBySource", id)
        local source = self:Call(C_TransmogCollection, "GetSourceInfo", id)
        local hasData, canCollect = self:Call(C_TransmogCollection, "AccountCanCollectSource", id)
        if not source or not source.name or hasData ~= true then self:RequestItem(itemID) end
        local eligible
        if hasData == true then eligible = canCollect end
        return { name = source and source.name, icon = source and source.icon,
            owned = info and info.appearanceIsCollected, eligible = eligible,
            eligibilityRequired = true, appearanceID = info and info.appearanceID }
    elseif kind == "decor" then
        local decorType = Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor
        local info = decorType and self:Call(C_HousingCatalog, "GetCatalogEntryInfoByRecordID", decorType, id)
        return { name = info and info.name, icon = info and info.iconTexture,
            owned = self.decorOwnership and self.decorOwnership[id] }
    elseif kind == "toy" then
        local _, name, icon = self:Call(C_ToyBox, "GetToyInfo", id)
        local owned = self:Call(_G, "PlayerHasToy", id)
        if not name then self:RequestItem(itemID) end
        return { name = name, icon = icon, owned = owned }
    end
    return {}
end

function Runtime:RequestItem(itemID)
    self.requestedItems = self.requestedItems or {}
    if not self.requestedItems[itemID] then
        self.requestedItems[itemID] = true
        self.pendingItems[itemID] = true
        self:Call(C_Item, "RequestLoadItemDataByID", itemID)
    end
end

function Runtime:MerchantReady(itemID, npcID)
    return self.merchantNPC == npcID and self.merchant[itemID] == true
end

function Runtime:CaptureMerchant()
    local generation = self.merchantGeneration
    local guid = self:Call(_G, "UnitGUID", "npc")
    local npcID = type(guid) == "string" and tonumber(guid:match("^[^-]+%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-"))
    local verified = {}
    if npcID and self.merchantOpen then
        local count = self:Call(_G, "GetMerchantNumItems")
        for index = 1, math.min(Number(count) and count or 0, 500) do
            local link = self:Call(_G, "GetMerchantItemLink", index)
            local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
            local info = self:Call(C_MerchantFrame, "GetItemInfo", index)
            if id and info and info.isPurchasable == true and Number(info.numAvailable)
                and (info.numAvailable == -1 or info.numAvailable > 0) and Number(info.stackCount) and info.stackCount > 0
                and Number(info.price) and info.price >= 0 then
                local money = self:Call(_G, "GetMoney")
                local ready = Number(money) and money >= info.price
                if info.hasExtendedCost == true then
                    local costs = self:Call(_G, "GetMerchantItemCostInfo", index)
                    if not Number(costs) or costs <= 0 then ready = false end
                    local totals = {}
                    for cost = 1, math.min(Number(costs) and costs or 0, 50) do
                        local _, amount, costLink = self:Call(_G, "GetMerchantItemCostItem", index, cost)
                        local currencyID = type(costLink) == "string" and tonumber(costLink:match("currency:(%d+)"))
                        if not currencyID or not Number(amount) or amount <= 0 then ready = false
                        else totals[currencyID] = (totals[currencyID] or 0) + amount end
                    end
                    for currencyID, amount in pairs(totals) do
                        local currency = self:Call(C_CurrencyInfo, "GetCurrencyInfo", currencyID)
                        if not currency or not Number(currency.quantity) or currency.quantity < amount then ready = false end
                    end
                elseif info.hasExtendedCost ~= false then ready = false end
                verified[id] = ready == true
            end
        end
    end
    if generation == self.merchantGeneration and self.merchantOpen then
        self.merchant, self.merchantNPC = verified, npcID
        -- No permanent inventory observations, even while the dashboard stays open.
        self.engine:Invalidate("gold", 0)
        self.engine:Invalidate("currency")
    end
end

function Runtime:ReadAchievement(id, destination)
    local epoch = self.achievementEpoch or 0
    if self:Call(C_AchievementInfo, "IsValidAchievement", id) ~= true then
        (destination or self.engine.achievements)[id] = nil; return
    end
    local _, name, _, completed, _, _, _, _, _, icon, _, guild, _, _, statistic = self:Call(_G, "GetAchievementInfo", id)
    local result
    if completed == false and name and not guild and not statistic then
        local count = self:Call(_G, "GetAchievementNumCriteria", id)
        local missing, last, unknown, remainingQuantity, remainingRequired = 0, nil, false
        if Number(count) and count > 1 then
            for index = 1, count do
                local text, _, done, quantity, required = self:Call(_G, "GetAchievementCriteriaInfo", id, index)
                if type(done) ~= "boolean" then unknown = true; break end
                if not done then
                    missing = missing + 1; last = text
                    remainingQuantity, remainingRequired = quantity, required
                end
                if missing > 1 then break end
            end
            if not unknown and missing == 1 then
                result = { id = "achievement:" .. id, achievementID = id, title = name, icon = icon,
                    tier = 4, label = "One criterion left", criteriaCompleted = count - 1, criteriaTotal = count,
                    remainingCriterion = last, quantity = remainingQuantity, required = remainingRequired,
                    detail = string.format("%d/%d criteria complete • %s", count - 1, count, last or "Open achievement for details") }
            end
        end
    end
    if epoch == (self.achievementEpoch or 0) then (destination or self.engine.achievements)[id] = result end
end

function Runtime:DiscoverAchievements()
    local categories = self:Call(_G, "GetCategoryList")
    if not categories then self.discoveryUnavailable = true; return end
    self.discoveryUnavailable = nil
    local seen, snapshot = {}, {}
    local sizes = {}
    self.scanProgress = { checked = 0, total = 0 }
    for _, category in ipairs(categories) do
        local count = self:Call(_G, "GetCategoryNumAchievements", category)
        sizes[category] = Number(count) and count or 0
        self.scanProgress.total = self.scanProgress.total + sizes[category]
    end
    for _, category in ipairs(categories) do
        for index = 1, sizes[category] do
            local id, _, _, completed, _, _, _, _, _, _, _, guild, _, _, statistic = self:Call(_G, "GetAchievementInfo", category, index)
            if Number(id) and not seen[id] then
                seen[id] = true
                -- The enumeration already supplies completion; avoid re-reading
                -- valid/criteria metadata for the majority that are completed.
                if completed == false and not guild and not statistic then self:ReadAchievement(id, snapshot) end
            end
            self.scanProgress.checked = self.scanProgress.checked + 1
        end
    end
    self.engine.achievements = snapshot
    self.verifiedAt = GetTime()
end

function Runtime:Run()
    while true do
        local collectionKind = self.collectionRequests and next(self.collectionRequests)
        if collectionKind and self.DiscoverCollection then
            self.collectionRequests[collectionKind] = nil; self:DiscoverCollection(collectionKind)
        elseif self.housingPending and self.CaptureHousing then self.housingPending = nil; self:CaptureHousing()
        elseif self.merchantPending then self.merchantPending = nil; self:CaptureMerchant()
        elseif next(self.achievementQueue) then
            local id = next(self.achievementQueue); self.achievementQueue[id] = nil; self:ReadAchievement(id)
        elseif self.engine:WorkOne() then
            coroutine.yield()
        elseif self.discoveryRequested then
            self.discoveryRequested, self.discovering = nil, true
            self:Publish() -- Make collectible results available before the catalog scan.
            self:DiscoverAchievements(); self.discovering = nil
        else return end
    end
end

function Runtime:Publish()
    self.revision = self.revision + 1
    if self.visible and Module.Render then Module:Render() end
end

function Runtime:RequestPublish()
    if not self.visible or self.publishTimer then return end
    self.publishTimer = C_Timer.NewTimer(0.1, function()
        self.publishTimer = nil; self:Publish()
    end)
end

function Runtime:Schedule()
    if self.timer or not self.visible or InCombatLockdown() then return end
    self.timer = C_Timer.NewTimer(0, function()
        self.timer = nil
        if not self.visible or InCombatLockdown() then return end
        self.worker = self.worker or coroutine.create(function() self:Run() end)
        local start = debugprofilestop()
        self.inWorker = true
        for _ = 1, 200 do
            local ok, err = coroutine.resume(self.worker)
            if not ok then
                self.error = "Opportunity data unavailable • Try Refresh"; self.workerError = tostring(err)
                self.worker, self.discovering, self.discoveryRequested = nil, nil, nil; break
            end
            if coroutine.status(self.worker) == "dead" then self.worker = nil; break end
            if debugprofilestop() - start >= 1 then break end
        end
        self.inWorker = false
        local elapsed = debugprofilestop() - start
        self.stats.slices = self.stats.slices + 1; self.stats.maxSliceMS = math.max(self.stats.maxSliceMS, elapsed)
        local now = GetTime()
        if self.worker and Module.UpdateStatus and (not self.lastStatusUpdate or now - self.lastStatusUpdate >= 0.25) then
            self.lastStatusUpdate = now; Module:UpdateStatus()
        end
        -- Publish complete batches, never a partially rebuilt list every slice.
        if not self.worker then self:Publish() end
        if self.worker then self:Schedule() end
    end)
end

function Runtime:SetVisible(visible)
    self.visible = visible
    if not visible then
        if self.timer then self.timer:Cancel(); self.timer = nil end
        if self.publishTimer then self.publishTimer:Cancel(); self.publishTimer = nil end
        return
    end
    if not self.engine then
        local data = RefineUI.OpportunityData
        if not data or data.schema ~= 1 then self.error = "Opportunity data unavailable"; self:Publish(); return end
        self.engine = RefineUI.OpportunityEngine.New(data, self); self.engine:Reset()
    end
    self.mapID = self:Call(C_Map, "GetBestMapForUnit", "player")
    if self.StartHousing then self:StartHousing() end
    if self.achievementDirty and not self.discovering and not self.discoveryRequested then
        self.discoveryRequested = true; self.achievementDirty = nil
    end
    self:Publish(); self:Schedule()
end

function Runtime:Refresh()
    if not self.engine then return end
    self.worker = nil; self.discovering = nil; self.scanProgress = nil
    self.requestedItems = {}
    self.engine:Reset()
    if self.InvalidateCollection then self:InvalidateCollection(nil, true) end
    self.discoveryRequested = true
    self.achievementDirty = nil
    if self.StartHousing then self:StartHousing(true) end
    self.error = nil; self:Publish(); self:Schedule()
end

function Runtime:GetPage(offset, limit, category)
    if not self.engine then return {}, 0, {} end
    return self.engine:GetPage(self:Preferences(), self.mapID, offset, limit, category)
end

function Runtime:Event(event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if Accessible(name) and name == "Blizzard_EncounterJournal" then Module:Install() end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        if self.timer then self.timer:Cancel(); self.timer = nil end
        self:Publish(); return
    end
    if event == "PLAYER_REGEN_ENABLED" and self.StartHousing then self:StartHousing() end
    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" or event == "MERCHANT_CLOSED" then
        self.merchantGeneration = (self.merchantGeneration or 0) + 1
        self.merchantOpen = event ~= "MERCHANT_CLOSED"
        self.merchant, self.merchantNPC = {}, nil
        self.merchantPending = self.merchantOpen
    end
    local engine = self.engine
    if not engine then return end
    local id = ...; if not Number(id) then id = nil end
    if event == "CURRENCY_DISPLAY_UPDATE" then engine:Invalidate("currency", id)
    elseif event == "PLAYER_MONEY" or event:find("MERCHANT_", 1, true) == 1 then
        engine:Invalidate("gold", 0); engine:Invalidate("currency")
    elseif event == "UPDATE_FACTION" then engine:Invalidate("reputation"); engine:Invalidate("renown")
    elseif event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" or event == "MAJOR_FACTION_UNLOCKED" then engine:Invalidate("renown", id)
    elseif event == "QUEST_TURNED_IN" then engine:Invalidate("quest", id); engine:Invalidate("questReward", id)
    elseif event == "QUEST_LOG_UPDATE" then engine:Invalidate("quest"); engine:Invalidate("questReward")
    elseif event == "ACHIEVEMENT_EARNED" or event == "CRITERIA_EARNED" or event == "TRACKED_ACHIEVEMENT_UPDATE" then
        self.achievementEpoch = (self.achievementEpoch or 0) + 1
        if id then self.achievementQueue[id] = true; engine.achievements[id] = nil; engine:Invalidate("achievement", id) end
        engine:Invalidate("achievementReward", id)
        if event == "ACHIEVEMENT_EARNED" and self.InvalidateCollection then self:InvalidateCollection("achievements") end
    elseif event == "CRITERIA_UPDATE" then
        -- Broad events are frequent; retain the verified snapshot until Refresh
        -- or reopening instead of repeatedly clearing/rebuilding every candidate.
        self.achievementDirty = true
        self:RequestPublish(); return
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        if self.visible then self.mapID = self:Call(C_Map, "GetBestMapForUnit", "player") end
    elseif event == "NEW_TOY_ADDED" or event == "TOYS_UPDATED" or event == "NEW_MOUNT_ADDED" or event == "COMPANION_LEARNED" or event == "PET_JOURNAL_LIST_UPDATE" then
        engine:Invalidate("reward")
        if self.InvalidateCollection then
            if event == "NEW_MOUNT_ADDED" then self:InvalidateCollection("mount")
            elseif event == "NEW_TOY_ADDED" or event == "TOYS_UPDATED" then self:InvalidateCollection("toy")
            else self:InvalidateCollection("pet") end
        end
    elseif event == "TRANSMOG_COLLECTION_UPDATED" or event == "TRANSMOG_SOURCE_ADDED" or event == "TRANSMOG_SOURCE_REMOVED" then
        engine:Invalidate("reward")
        if self.InvalidateCollection then self:InvalidateCollection("appearance") end
    elseif event == "HOUSING_STORAGE_UPDATED" or event == "HOUSING_STORAGE_ENTRY_UPDATED" or event == "HOUSE_DECOR_ADDED_TO_CHEST" then
        self.decorOwnership = nil; engine:Invalidate("reward")
        self.housingDirty = true
        if self.visible and self.StartHousing then self:StartHousing(true) end
    elseif event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
        if id and self.pendingItems[id] then
            self.pendingItems[id] = nil; engine:Invalidate("item", id)
            if self.InvalidateCollection then self:InvalidateCollection("toy") end
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LEVEL_UP" or event == "ADDON_RESTRICTION_STATE_CHANGED" then
        self.worker = nil; self.discovering = nil; self.achievementEpoch = (self.achievementEpoch or 0) + 1
        engine:Reset(); engine.achievements = {}; self.achievementDirty = true
        self.decorOwnership = nil; self.housingDirty = true
        if self.InvalidateCollection then self:InvalidateCollection(nil, true) end
        if self.visible and self.StartHousing then self:StartHousing(true) end
        if self.visible then self.discoveryRequested = true; self.achievementDirty = nil end
    end
    -- A live offer can become unaffordable without a merchant inventory event.
    if self.merchantOpen and (event == "PLAYER_MONEY" or event == "CURRENCY_DISPLAY_UPDATE") then
        self.merchantGeneration = (self.merchantGeneration or 0) + 1; self.merchant = {}; self.merchantPending = true
    end
    self:Schedule()
end

function Module:OnEnable()
    if self.registered then return end
    self.registered = true
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_MONEY",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED",
        "CURRENCY_DISPLAY_UPDATE", "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED",
        "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "ACHIEVEMENT_EARNED", "CRITERIA_EARNED", "CRITERIA_UPDATE",
        "TRACKED_ACHIEVEMENT_UPDATE", "NEW_TOY_ADDED", "TOYS_UPDATED", "NEW_MOUNT_ADDED", "COMPANION_LEARNED", "PET_JOURNAL_LIST_UPDATE",
        "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED",
        "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_SOURCE_ADDED", "TRANSMOG_SOURCE_REMOVED",
        "HOUSING_STORAGE_UPDATED", "HOUSING_STORAGE_ENTRY_UPDATED", "HOUSE_DECOR_ADDED_TO_CHEST",
        "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }) do
        if not C_EventUtils or C_EventUtils.IsEventValid(event) then
            RefineUI:RegisterEventCallback(event, function(_, ...) Runtime:Event(event, ...) end, "Opportunities:" .. event)
        end
    end
    if EncounterJournal then self:Install() end
end
