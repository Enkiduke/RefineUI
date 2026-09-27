-- Shared journal catalogs. Callers own their cursors; identical batches are read once.
-- Every journal transaction finishes before returning/yielding. No idle ticker.
local _, RefineUI = ...
local Data = { catalogs = {}, clock = 0, revision = 0, capturing = false }
RefineUI.InstanceCompletion = Data
Data.KEYS = { "achievements", "appearances", "pets", "mounts", "toys" }
local LIMIT, BATCH = 32, 16
local function ValidID(id) return type(id) == "number" and id > 0 end

function Data:NewCounts()
    local counts = {}
    for _, key in ipairs(self.KEYS) do
        counts[key] = { earned = 0, total = 0, unknown = 0, seen = {}, missing = {} }
    end
    return counts
end

function Data:AddCount(counts, kind, id, earned, reward)
    local count = counts[kind]
    if count.seen[id] then return end
    count.seen[id] = true
    count.total = count.total + 1
    if earned == true then count.earned = count.earned + 1
    elseif earned == nil then count.unknown = count.unknown + 1
    elseif reward then count.missing[#count.missing + 1] = reward end
end

function Data:GetCatalog(instanceID, difficultyID)
    local key = instanceID .. ":" .. difficultyID
    self.clock = self.clock + 1
    local catalog = self.catalogs[key]
    if not catalog then
        local count, oldestKey, oldest = 0, nil, math.huge
        for id, entry in pairs(self.catalogs) do
            count = count + 1
            if entry.used < oldest then oldestKey, oldest = id, entry.used end
        end
        if count >= LIMIT then self.catalogs[oldestKey] = nil end
        catalog = RefineUI.JournalCache and RefineUI.JournalCache:Get("catalogs", key) or { batches = {} }
        self.catalogs[key] = catalog
    end
    catalog.used = self.clock
    return catalog
end

-- API selection is global, while EncounterJournal fields describe the visible UI.
function Data:WithJournal(instanceID, difficultyID, callback)
    if self.capturing then return nil, "busy" end
    local api, journal = C_EncounterJournal, _G.EncounterJournal
    if not (api and api.GetSlotFilter and api.SetSlotFilter and api.ResetSlotFilter
        and EJ_SelectInstance and EJ_SelectEncounter and EJ_GetDifficulty and EJ_SetDifficulty
        and EJ_GetLootFilter and EJ_SetLootFilter and EJ_IsValidInstanceDifficulty) then
        return nil, "unavailable"
    end
    local oldInstance = journal and journal.instanceID
    if not ValidID(oldInstance) and EJ_GetInstanceInfo and api.GetInstanceForGameMap then
        local mapID = select(10, EJ_GetInstanceInfo())
        if mapID then oldInstance = api.GetInstanceForGameMap(mapID) end
    end
    local oldEncounter = journal and journal.encounterID
    local oldDifficulty = EJ_GetDifficulty()
    local class, spec = EJ_GetLootFilter()
    local slot = api.GetSlotFilter()
    local tier = EJ_GetCurrentTier and EJ_GetCurrentTier()
    -- These are display events, not data dependencies. A temporary difficulty
    -- change makes Blizzard refresh/reopen its last instance, even on the cards.
    -- Suspend only this frame's registrations for the synchronous transaction.
    local suspended = {}
    if journal and journal.IsEventRegistered and journal.UnregisterEvent and journal.RegisterEvent then
        for _, event in ipairs({ "EJ_DIFFICULTY_UPDATE", "EJ_LOOT_DATA_RECIEVED" }) do
            if journal:IsEventRegistered(event) then
                suspended[#suspended + 1] = event
                journal:UnregisterEvent(event)
            end
        end
    end
    self.capturing = true
    local ok, result, extra = pcall(function()
        EJ_SelectInstance(instanceID)
        if difficultyID then
            if not EJ_IsValidInstanceDifficulty(difficultyID) then error("unsupported difficulty") end
            if EJ_GetDifficulty() ~= difficultyID then EJ_SetDifficulty(difficultyID) end
        end
        EJ_SetLootFilter(0, 0)
        api.ResetSlotFilter()
        return callback(api)
    end)
    local restored = true
    local function Restore(fn, ...)
        local success = pcall(fn, ...)
        restored = success and restored
    end
    if tier and EJ_SelectTier and EJ_GetCurrentTier() ~= tier then Restore(EJ_SelectTier, tier) end
    if ValidID(oldInstance) then Restore(EJ_SelectInstance, oldInstance) end
    if EJ_GetDifficulty() ~= oldDifficulty then Restore(EJ_SetDifficulty, oldDifficulty) end
    if ValidID(oldEncounter) then Restore(EJ_SelectEncounter, oldEncounter) end
    Restore(EJ_SetLootFilter, class, spec)
    Restore(api.SetSlotFilter, slot)
    self.capturing = false
    for _, event in ipairs(suspended) do Restore(journal.RegisterEvent, journal, event) end
    if not ok or not restored then return nil, ok and "restore failed" or result end
    return result, extra
end

function Data:GetDifficulties(instanceID)
    return self:WithJournal(instanceID, nil, function()
        local ids, seen = {}, {}
        -- Match the Guide's supported modes; new client IDs are included dynamically.
        local candidates = DifficultyUtil and DifficultyUtil.ID
            or { 1, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 23, 24, 33 }
        for _, id in pairs(candidates) do
            if ValidID(id) and not seen[id] and EJ_IsValidInstanceDifficulty(id) then
                seen[id] = true; ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        return ids
    end)
end

-- scan.index is local to a pass. scan.bossIndex=0 reads the instance list;
-- positive values read explicit bosses, covering missing/shared journal attribution.
function Data:ReadLootBatch(instanceID, difficultyID, scan)
    local catalog = self:GetCatalog(instanceID, difficultyID)
    local pass = scan.bossIndex or 0
    local key = pass .. ":" .. scan.index
    local cached = catalog.batches[key]
    if cached then scan.bosses = catalog.bosses; return cached.items, cached.total end
    local items, total = self:WithJournal(instanceID, difficultyID, function(api)
        if not catalog.bosses then
            catalog.bosses = {}
            for index = 1, 100 do
                local name, _, id, _, _, _, encounterID = EJ_GetEncounterInfoByIndex(index, instanceID)
                if not ValidID(id) then break end
                catalog.bosses[#catalog.bosses + 1] = {
                    id = id, name = name, encounterID = encounterID,
                    icon = EJ_GetCreatureInfo and select(5, EJ_GetCreatureInfo(1, id)),
                }
            end
        end
        scan.bosses = catalog.bosses
        local boss = scan.bosses[pass]
        if boss then EJ_SelectEncounter(boss.id) end
        -- GetNumLoot rebuilds the list after selection/filter changes. Checking
        -- IsLootListOutOfDate first leaves every fresh scan permanently waiting.
        local rows, count = {}, EJ_GetNumLoot()
        if EJ_IsLootListOutOfDate and EJ_IsLootListOutOfDate() then return nil, "loading" end
        for index = scan.index, math.min(count, scan.index + BATCH - 1) do
            local info = api.GetLootInfoByIndex(index, 1)
            local item = { bosses = {} }
            if boss then item.bosses[boss.id] = true end
            if info then
                item.itemID, item.link, item.name, item.icon = info.itemID, info.link, info.name, info.icon
                if ValidID(info.encounterID) then item.bosses[info.encounterID] = true end
                local shared = not boss and EJ_GetNumEncountersForLootByIndex and EJ_GetNumEncountersForLootByIndex(index) or 1
                for otherIndex = 2, shared do
                    local other = api.GetLootInfoByIndex(index, otherIndex)
                    if other and ValidID(other.encounterID) then item.bosses[other.encounterID] = true end
                end
            end
            rows[#rows + 1] = item
        end
        return rows, count
    end)
    if items then
        -- Cache only resolved journal rows. Item ownership may still be unknown.
        local ready = true
        for _, item in ipairs(items) do if not item.itemID or not item.link then ready = false end end
        if ready then
            catalog.batches[key] = { items = items, total = total }
            -- Persist once the final boss pass is read, then only for late-resolved gaps,
            -- instead of re-copying the growing catalog after every batch.
            if not catalog.complete and scan.index + #items > total and pass >= #catalog.bosses then
                catalog.complete = true
            end
            if catalog.complete and RefineUI.JournalCache then
                RefineUI.JournalCache:Put("catalogs", instanceID .. ":" .. difficultyID, catalog)
            end
        end
    end
    return items, total
end

function Data:InvalidateCatalog(instanceID, difficultyID)
    self.catalogs[instanceID .. ":" .. difficultyID] = nil
    if RefineUI.JournalCache then
        RefineUI.JournalCache:Remove("catalogs", instanceID .. ":" .. difficultyID)
    end
end

RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
    Data:StartSummaryWorker()
end, "InstanceCompletion:World")

-- Expansion cards subscribe only while visible. One bounded worker handles all cards.
Data.summaries, Data.summaryQueue = {}, {}
-- Owners that only keep summaries warm (sorting/filtering); visible cards go first.
Data.backgroundOwners = setmetatable({}, { __mode = "k" })
local TICK_BUDGET_MS = 3
-- Missing data is retried a bounded number of times, then settles as partial.
local RETRY_DELAYS = { 1, 2, 4, 8 }

function Data:SaveSummaryManifest(state, resolved)
    if not state.discovered or state.incomplete or not RefineUI.JournalCache then return end
    if state.manifestSaved and (not resolved or state.manifestResolvedSaved) then return end
    local items = {}
    for _, item in ipairs(state.items) do
        if ValidID(item.itemID) and type(item.link) == "string" and item.link ~= "" then
            -- Completion needs the difficulty-specific link for transmog identity,
            -- but not the larger boss/name/icon payload held by detail catalogs.
            items[#items + 1] = { itemID = item.itemID, link = item.link }
        end
    end
    RefineUI.JournalCache:Put("manifests", state.id, {
        items = items,
        difficulties = state.difficulties,
        rewards = resolved and state.rewards or nil,
        rewardsResolved = resolved or nil,
    })
    state.manifestSaved = true
    state.manifestResolvedSaved = resolved or nil
end

function Data:RememberSummaryReward(state, kind, id, itemIndex)
    if kind == "achievements" or not state.summary.instance[kind] or not ValidID(id) then return end
    local key = kind .. ":" .. id
    state.rewardKeys = state.rewardKeys or {}
    if state.rewardKeys[key] then return end
    state.rewardKeys[key] = true
    state.rewards = state.rewards or {}
    state.rewards[#state.rewards + 1] = { kind = kind, id = id, itemIndex = itemIndex }
end

function Data:PublishSummary(state)
    if RefineUI.JournalCache and state.summary.lootReady and state.summary.achievementsReady
        and not state.summary.unavailable and not state.summary.partial then
        local ready = true
        for _, count in pairs(state.summary.instance) do
            if count.unknown > 0 then ready = false end
        end
        if ready then
            RefineUI.JournalCache:Put("summaries", state.id, {
                summary = state.summary,
                ownershipRevisions = RefineUI.JournalCache:GetOwnershipRevisions(),
            })
        end
    end
    for _, callback in pairs(state.owners) do callback(state.summary) end
end

function Data:ResetSummaryOwnership(state)
    state.resolveIndex, state.rewardIndex = 1, 1
    state.pending, state.identityPending, state.retryRequested = nil, nil, nil
    state.summary = { instanceID = state.id, instance = self:NewCounts(),
        lootReady = false, achievementsReady = false, allDifficulties = true }
    state.ownershipRevision = RefineUI.Collections.revision
    state.achievementRevision = self.achievementRevision
    state.missingItems = {}
    -- Item loads can be dropped under server throttling; a new pass may ask again.
    for _, item in ipairs(state.items) do item.requested = nil end
end

function Data:TrimSummaryCache(limit)
    while true do
        local count, oldestKey, oldest = 0, nil, math.huge
        for id, state in pairs(self.summaries) do
            count = count + 1
            if not next(state.owners) and (state.used or 0) < oldest then
                oldestKey, oldest = id, state.used or 0
            end
        end
        if count <= limit or not oldestKey then return end
        local old = self.summaries[oldestKey]
        RefineUI.InstanceAchievements:ReleaseOwner(old)
        for index = #self.summaryQueue, 1, -1 do
            if self.summaryQueue[index] == old then table.remove(self.summaryQueue, index) end
        end
        self.summaries[oldestKey] = nil
    end
end

function Data:RequestSummary(instanceID, owner, callback, background)
    local currentTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local state = self.summaries[instanceID]
    if not state then
        -- Active views may temporarily exceed this bound. Once released, their
        -- durable manifests/snapshots let us return to a small session cache.
        self:TrimSummaryCache(15)
        state = { id = instanceID, owners = {}, items = {}, links = {},
            scan = { index = 1, bossIndex = 0 }, difficultyIndex = 1 }
        self.summaries[instanceID] = state
        self.summaryQueue[#self.summaryQueue + 1] = state
        self:ResetSummaryOwnership(state)
        local manifest = RefineUI.JournalCache and RefineUI.JournalCache:Get("manifests", instanceID)
        local saved = RefineUI.JournalCache and RefineUI.JournalCache:Get("summaries", instanceID)
        if manifest then
            state.items, state.difficulties = manifest.items or {}, manifest.difficulties
            state.rewards, state.rewardsResolved = manifest.rewards, manifest.rewardsResolved
            state.discovered, state.manifestSaved = true, true
            state.manifestResolvedSaved = state.rewardsResolved
            if state.rewards then
                state.rewardKeys = {}
                for _, reward in ipairs(state.rewards) do
                    state.rewardKeys[reward.kind .. ":" .. reward.id] = true
                end
            end
        elseif saved and saved.items then
            -- Migrate version-one summaries without discarding their expensive
            -- discovery work. The next save removes this duplication.
            state.items, state.difficulties = saved.items, saved.difficulties
            state.discovered = true
            self:SaveSummaryManifest(state)
        end
        for _, item in ipairs(state.items) do state.links[item.link] = true end
        if saved then
            state.summary, state.resolveIndex = saved.summary, #state.items + 1
            state.rewardIndex = #(state.rewards or {}) + 1
            if not RefineUI.JournalCache:OwnershipMatches(saved.ownershipRevisions) then
                self:ResetSummaryOwnership(state)
            end
        end
    end
    self.clock = self.clock + 1
    state.used = self.clock
    -- Keep the browsed expansion warm even when its native cards are recycled.
    -- Older expansions remain eligible for the session-cache eviction policy.
    state.tier = currentTier
    -- A new visit retries data that was unavailable or settled as partial.
    if not next(state.owners) and (state.summary.unavailable or state.summary.partial) then
        if state.incomplete or not state.discovered then
            state.discovered, state.incomplete = nil, nil
            state.scan, state.difficultyIndex = { index = 1, bossIndex = 0 }, 1
            if state.difficulties and #state.difficulties == 0 then state.difficulties = nil end
        end
        state.pending, state.retryAttempts = nil, nil
        self:ResetSummaryOwnership(state)
    end
    state.owners[owner] = callback
    self.backgroundOwners[owner] = background or nil
    self:SetItemEventsActive(true)
    if state.ownershipRevision ~= RefineUI.Collections.revision or state.achievementRevision ~= self.achievementRevision then
        self:ResetSummaryOwnership(state)
    end
    callback(state.summary)
    self:StartSummaryWorker()
end

function Data:ReleaseSummary(owner)
    local owned = false
    for _, state in pairs(self.summaries) do
        state.owners[owner] = nil
        if not next(state.owners) then
            RefineUI.InstanceAchievements:ReleaseOwner(state)
            state.achievementRequest = nil
        else
            owned = true
        end
    end
    if not owned then self:SetItemEventsActive(false) end
    self:TrimSummaryCache(16)
    if not self:HasSummaryWork() and self.summaryTicker then
        self.summaryTicker:Cancel(); self.summaryTicker = nil
    end
end

local function HasWork(state)
    if not next(state.owners) then return false end
    local summary = state.summary
    if summary.unavailable then return state.retryRequested == true end
    local rewardsPending = state.rewardsResolved
        and state.rewardIndex <= #(state.rewards or {})
        or not state.rewardsResolved and state.resolveIndex <= #state.items
    return not state.discovered or rewardsPending or not summary.lootReady
        or (not summary.achievementsReady and not state.achievementRequest)
end

function Data:HasSummaryWork()
    for _, state in ipairs(self.summaryQueue) do
        if HasWork(state) then return true end
    end
    return false
end

-- Queue order is request order, so visible cards fill in from the top of the list.
function Data:NextSummaryState()
    local background
    for _, state in ipairs(self.summaryQueue) do
        if HasWork(state) then
            for owner in pairs(state.owners) do
                if not self.backgroundOwners[owner] then return state end
            end
            background = background or state
        end
    end
    return background
end

function Data:StartSummaryWorker()
    if self.summaryTicker or not self:HasSummaryWork() or (InCombatLockdown and InCombatLockdown()) then return end
    self.summaryTicker = C_Timer.NewTicker(0, function() self:SummaryTick() end)
end

-- Item and journal events can be dropped or never fire for data that stays unresolved.
-- Returns false once the retry budget is spent; the caller then settles the summary.
function Data:ScheduleSummaryRetry(state)
    local attempt = (state.retryAttempts or 0) + 1
    local delay = RETRY_DELAYS[attempt]
    if not delay then return false end
    state.retryAttempts = attempt
    C_Timer.After(delay, function()
        if self.summaries[state.id] == state and next(state.owners) and state.summary.unavailable then
            state.retryRequested = true
            self:StartSummaryWorker()
        end
    end)
    return true
end

-- The journal could not be read. Retry, or keep the loot found so far as partial.
function Data:FailSummaryDiscovery(state, loading)
    if loading then
        state.summary.partial = true
        state.missingItems[0] = true
    end
    if self:ScheduleSummaryRetry(state) then
        state.summary.unavailable = true
    else
        state.incomplete, state.discovered = true, true
    end
    self:PublishSummary(state)
end

function Data:ProcessSummaryState(state)
    if state.summary.unavailable then
        -- Coalesce arrivals until the current pass finishes. Never rewind an
        -- active scan for each item event.
        state.retryRequested = nil
        if state.incomplete then
            state.discovered, state.incomplete = nil, nil
            state.difficultyIndex, state.scan = 1, { index = 1, bossIndex = 0 }
        end
        if state.difficulties and #state.difficulties == 0 then state.difficulties = nil end
        state.pending, state.identityPending = nil, nil
        self:ResetSummaryOwnership(state)
        self:PublishSummary(state)
        return
    end
    if not state.discovered then
        if not state.difficulties then
            state.difficulties = self:GetDifficulties(state.id)
            if not state.difficulties or #state.difficulties == 0 then
                self:FailSummaryDiscovery(state, true)
                return
            end
        end
        local scan, difficulty = state.scan, state.difficulties[state.difficultyIndex]
        local batch, total = self:ReadLootBatch(state.id, difficulty, scan)
        if not batch then
            self:FailSummaryDiscovery(state, total == "loading")
            return
        end
        for _, item in ipairs(batch) do
            if not item.link or not item.itemID then
                state.incomplete = true
                state.missingItems[item.itemID or 0] = true
            elseif not state.links[item.link] then
                state.links[item.link] = true
                state.items[#state.items + 1] = item
            end
        end
        scan.index = scan.index + #batch
        if scan.index > total then
            if scan.bossIndex < #scan.bosses then
                scan.bossIndex, scan.index = scan.bossIndex + 1, 1
            else
                state.difficultyIndex = state.difficultyIndex + 1
                state.scan = { index = 1, bossIndex = 0 }
                state.discovered = state.difficultyIndex > #state.difficulties
                if state.discovered then self:SaveSummaryManifest(state) end
            end
        end
        return
    end
    if not state.summary.lootReady then
        if state.rewardsResolved then
            for _ = 1, BATCH do
                local reward = state.rewards and state.rewards[state.rewardIndex]
                if not reward then break end
                state.rewardIndex = state.rewardIndex + 1
                local item = state.items[reward.itemIndex]
                local owned = RefineUI.Collections:IsCollected(reward.kind, reward.id)
                self:AddCount(state.summary.instance, reward.kind, reward.id, owned, item)
                if owned == nil then
                    state.pending = true
                    state.missingItems[item and item.itemID or 0] = true
                end
            end
        else
            for _ = 1, BATCH do
                local itemIndex, item = state.resolveIndex, state.items[state.resolveIndex]
                if not item then break end
                state.resolveIndex = state.resolveIndex + 1
                local pending = RefineUI.Collections:VisitRewards(item, function(kind, id, owned)
                    self:RememberSummaryReward(state, kind, id, itemIndex)
                    self:AddCount(state.summary.instance, kind, id, owned, item)
                    if owned == nil then
                        state.pending = true
                        state.missingItems[item.itemID or 0] = true
                    end
                end)
                if pending then
                    state.pending, state.identityPending = true, true
                    state.missingItems[item.itemID or 0] = true
                end
            end
        end
        local resolvedAll = state.rewardsResolved
            and state.rewardIndex > #(state.rewards or {})
            or not state.rewardsResolved and state.resolveIndex > #state.items
        if resolvedAll then
            if not state.rewardsResolved and not state.identityPending then
                state.rewardsResolved = true
                state.rewardIndex = #(state.rewards or {}) + 1
                self:SaveSummaryManifest(state, true)
            end
            -- A partial catalog shows its known counts but never a completion
            -- percentage, and is never persisted.
            local complete = not state.incomplete and not state.pending
            if complete or not self:ScheduleSummaryRetry(state) then
                state.summary.lootReady = true
                state.summary.partial = not complete or nil
                if complete then state.retryRequested, state.retryAttempts = nil, nil end
            else
                state.summary.partial, state.summary.unavailable = true, true
            end
            self:PublishSummary(state)
        end
        return
    end
    if not state.summary.achievementsReady and not state.achievementRequest then
        state.achievementRequest = true
        local isRaid = select(12, EJ_GetInstanceInfo(state.id))
        RefineUI.InstanceAchievements:RequestInstanceAchievementRows(state.id, isRaid, function(_, rows)
            state.achievementRequest = nil
            for _, row in ipairs(rows) do
                local _, _, _, owned = GetAchievementInfo(row.achievementID)
                self:AddCount(state.summary.instance, "achievements", row.achievementID, owned, row)
            end
            state.summary.achievementsReady = true
            self:PublishSummary(state)
        end, state)
    end
end

-- Work runs every frame within a small time budget instead of one step per tick.
function Data:SummaryTick()
    if InCombatLockdown and InCombatLockdown() then
        self.summaryTicker:Cancel(); self.summaryTicker = nil; return
    end
    local deadline = debugprofilestop() + TICK_BUDGET_MS
    local state = self:NextSummaryState()
    while state do
        self:ProcessSummaryState(state)
        if debugprofilestop() >= deadline then break end
        if not HasWork(state) then state = self:NextSummaryState() end
    end
    if not self:HasSummaryWork() and self.summaryTicker then
        self.summaryTicker:Cancel(); self.summaryTicker = nil
    end
end

RefineUI.Collections:Subscribe("InstanceCompletion", function()
    for _, state in pairs(Data.summaries) do
        if next(state.owners) then
            state.pending = nil
            Data:ResetSummaryOwnership(state)
            Data:PublishSummary(state)
        end
    end
    Data:StartSummaryWorker()
end)
RefineUI:RegisterEventCallback("ACHIEVEMENT_EARNED", function()
    if RefineUI.JournalCache then RefineUI.JournalCache:InvalidateOwnership("achievements") end
    Data.achievementRevision = (Data.achievementRevision or 0) + 1
    for _, state in pairs(Data.summaries) do
        state.achievementRevision = Data.achievementRevision
        state.summary.achievementsReady = false
        state.summary.instance.achievements = Data:NewCounts().achievements
    end
    Data:StartSummaryWorker()
end, "InstanceCompletion:Achievements")
RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function() Data:StartSummaryWorker() end, "InstanceCompletion:Combat")

-- Item data events are frequent; listen only while a summary has owners.
local ITEM_EVENTS = { "EJ_LOOT_DATA_RECIEVED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }
local function OnItemData(_, itemID, success)
    if Data.capturing or RefineUI:IsSecretValue(itemID) or success == false then return end
    for _, state in pairs(Data.summaries) do
        if next(state.owners)
            and (state.summary.partial or next(state.missingItems))
            and (not itemID or state.missingItems[itemID] or state.missingItems[0]) then
            state.retryRequested = true
        end
    end
    Data:StartSummaryWorker()
end

function Data:SetItemEventsActive(active)
    if self.itemEventsActive == active then return end
    self.itemEventsActive = active
    for _, event in ipairs(ITEM_EVENTS) do
        if active then
            RefineUI:RegisterEventCallback(event, OnItemData, "InstanceCompletion:" .. event)
        else
            RefineUI:OffEvent(event, "InstanceCompletion:" .. event)
        end
    end
end
