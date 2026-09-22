-- Temporary, event-driven instance snapshot. No saved content database.
local _, RefineUI = ...
local Module = RefineUI:RegisterModule("LegacyCompletionist")
local BATCH_SIZE = 16
local MAX_DATA_RETRIES = 3
local DIFFICULTY_LABELS = {
    [1] = "5N", [2] = "5H", [3] = "10N", [4] = "25N", [5] = "10H", [6] = "25H",
    [7] = "25LFR", [8] = "5M+", [9] = "40N", [14] = "N", [15] = "H", [16] = "20M",
    [17] = "LFR", [23] = "5M", [24] = "5TW", [33] = "TW",
}

function Module:GetDifficultyLabel(difficultyID)
    if DIFFICULTY_LABELS[difficultyID] then return DIFFICULTY_LABELS[difficultyID] end
    local _, _, heroic, challenge, displayHeroic, mythic, _, lfr, minimum, maximum = GetDifficultyInfo(difficultyID)
    local size = minimum and maximum and minimum == maximum and maximum > 0 and tostring(maximum) or ""
    local mode = lfr and "LFR" or challenge and "M+" or mythic and "M" or (heroic or displayHeroic) and "H" or "N"
    return size .. mode
end
Module.KINDS = { "appearances", "mounts", "pets", "toys", "achievements" }
Module.LABELS = { appearances = "Appearances", mounts = "Mounts", pets = "Pets",
    toys = "Toys", achievements = "Achievements" }

function Module:GetSettings()
    local quests = RefineUI.Config.Quests
    quests.LegacyCompletionist = quests.LegacyCompletionist or {}
    return quests.LegacyCompletionist
end

function Module:GetContext()
    if not RefineUI.Config.Quests.Enable or self:GetSettings().Enable == false then return end
    local inside, kind = IsInInstance()
    if not inside or (kind ~= "party" and kind ~= "raid") then return end
    if not (C_Loot and C_Loot.IsLegacyLootModeEnabled and C_Loot.IsLegacyLootModeEnabled()) then return end
    local name, _, difficulty, difficultyName, _, _, _, mapID = GetInstanceInfo()
    if RefineUI:IsSecretValue(mapID) or RefineUI:IsSecretValue(difficulty) then return end
    local id = C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap
        and C_EncounterJournal.GetInstanceForGameMap(mapID)
    if not id or id <= 0 then return end
    return { id = id, difficulty = difficulty, name = name, difficultyName = difficultyName,
        isRaid = kind == "raid", key = id .. ":" .. difficulty }
end

function Module:CancelWork()
    if self.timer then self.timer:Cancel(); self.timer = nil end
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.ownershipTicker then self.ownershipTicker:Cancel(); self.ownershipTicker = nil end
    if self.worker then self.worker:ReleaseOwner(self) end
end

function Module:Clear()
    self:CancelWork()
    self.context, self.snapshot, self.worker, self.scan = nil, nil, nil, nil
    self.entries, self.bosses, self.achievementRows = {}, {}, nil
    self.rows, self.counts = {}, nil
    self.groups, self.groupOffsets, self.collapsedGroups, self.firstGroup = {}, {}, {}, 1
    self.defeated, self.ownershipAgain = {}, nil
    self.activeGroup, self.advanceAfterBoss, self.autoCollapseInitialized = nil, nil, nil
    self.achievementEntries, self.achievementEntryRows, self.achievementEntryBosses = nil, nil, nil
    self.dataRetries = 0
    self.status, self.rescan, self.deferred, self.ownershipDirty = nil, nil, nil, nil
    self.completionDirty = nil
    if self.frame then self.frame:Hide(); self.frame:MarkDirty() end
end

function Module:Schedule(rescan, viewOnly)
    if RefineUI.InstanceCompletion.capturing or not self.context then return end
    self.rescan = self.rescan or rescan
    self.ownershipDirty = self.ownershipDirty or not viewOnly
    if self.timer then return end
    self.timer = C_Timer.NewTimer(0.2, function()
        self.timer = nil
        if not self.context then return end
        if InCombatLockdown() then self.deferred = true; return end
        local ownershipDirty = self.ownershipDirty
        self.ownershipDirty = nil
        if self.rescan then
            self.rescan = nil
            self:StartScan()
        else
            if self.completionDirty then self:RefreshBossCompletion() end
            if ownershipDirty then self:RefreshOwnership() else self:BuildView() end
        end
    end)
end

function Module:UpdateContext()
    local context = self:GetContext()
    if not context then
        if self.context then self:Clear() end
        return
    end
    if self.context and self.context.key == context.key then
        return
    end
    self:Clear()
    self.context = context
    self:EnsureFrame()
    self:Schedule(true)
    if RequestRaidInfo then RequestRaidInfo() end
end

function Module:RefreshBossCompletion()
    if not self.context or self.ticker or #self.bosses == 0 then return end
    -- Reuse the selection/filter transaction, without reading any loot.
    local batch = self:ReadBatch({ index = 1, bossIndex = 0, bosses = self.bosses, completionOnly = true })
    if batch then self.completionDirty = nil end
end

function Module:ResolveItem(item)
    return RefineUI.Collections:ResolveItem(item)
end
-- Journal state is global. The transaction is synchronous and restores every
-- selection/filter even after errors. Never scan while the user is browsing it.
function Module:ReadBatch(scan)
    local journal = _G.EncounterJournal
    if journal and journal:IsShown() then return nil, "journal" end
    local data = RefineUI.InstanceCompletion
    if scan.completionOnly then
        return data:WithJournal(self.context.id, self.context.difficulty, function(api)
            if api.IsEncounterComplete then
                for _, boss in ipairs(self.bosses) do
                    local completed = api.IsEncounterComplete(boss.id)
                    if not RefineUI:IsSecretValue(completed) and completed == true and boss.encounterID then
                        self:CompleteBoss(boss.encounterID)
                    end
                end
            end
            return {}
        end)
    end
    local batch, total = data:ReadLootBatch(self.context.id, self.context.difficulty, scan)
    if scan.bosses then self.bosses = scan.bosses end
    return batch, total
end

function Module:StartScan()
    if not self.context then return end
    if InCombatLockdown() then self.rescan, self.deferred = true, true; return end
    if not _G.EncounterJournal then
        if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_EncounterJournal") end
        if not _G.EncounterJournal then self.status = "Encounter Journal unavailable"; self:BuildView(); return end
    end
    self:EnsureFrame()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.ownershipTicker then self.ownershipTicker:Cancel(); self.ownershipTicker = nil end
    self.scan = { index = 1, bossIndex = 0, items = {}, byItem = {}, pending = {}, incomplete = false }
    self.status = "Loading journal loot..."
    self.bosses = {}
    if self:GetSettings().achievements ~= false and not self.achievementRows then
        self.worker = RefineUI.InstanceAchievements
        local context = self.context
        self.worker:RequestInstanceAchievementRows(context.id, context.isRaid, function(_, rows)
            if self.context ~= context then return end
            self.achievementRows = rows
            self:Schedule(nil, true)
        end, self)
    end
    self:BuildView()
    self.ticker = C_Timer.NewTicker(0.03, function() self:ScanTick() end)
end

function Module:ScanTick()
    if not self.context or not self.scan then return end
    if InCombatLockdown() then
        self.ticker:Cancel(); self.ticker = nil
        self.rescan, self.deferred = true, true
        return
    end
    local scan = self.scan
    local batch, total = self:ReadBatch(scan)
    if not batch then
        self.ticker:Cancel(); self.ticker = nil
        self.status = total == "journal" and "Close Adventure Guide to refresh loot" or "Journal data unavailable for this difficulty"
        self.rescan = total == "journal"
        self:BuildView()
        return
    end
    for _, source in ipairs(batch) do
        -- Catalog rows are shared; only the tracker snapshot may be merged/mutated.
        local item = { itemID = source.itemID, link = source.link, name = source.name,
            icon = source.icon, bosses = {} }
        for boss in pairs(source.bosses) do item.bosses[boss] = true end
        -- Merge instance/boss passes by difficulty-specific link, preserving all
        -- shared boss associations without resolving the same item repeatedly.
        local key = item.link or item.itemID
        local existing = key and scan.byItem[key]
        if existing then
            for bossID in pairs(item.bosses) do existing.bosses[bossID] = true end
        else
            scan.items[#scan.items + 1] = item
            if key then scan.byItem[key] = item end
        end
        if not item.itemID or not item.link then
            scan.incomplete = true
            scan.pending[item.itemID or 0] = true
        end
    end
    scan.index = scan.index + #batch
    if scan.index > total then
        if scan.bossIndex < #scan.bosses then
            scan.bossIndex = scan.bossIndex + 1
            scan.index = 1
            return
        end
        self.ticker:Cancel(); self.ticker = nil
        scan.byItem = nil
        self.snapshot = scan
        self.scan = nil
        self.status = nil
        self:RefreshBossCompletion()
        self:RefreshOwnership()
        if scan.retry then self:Schedule(true) end
    end
end

function Module:RefreshOwnership()
    if not self.context then return end
    -- The scan resolves the fresh snapshot when it finishes; do not also resolve
    -- the previous snapshot in response to bag/collection events mid-scan.
    if self.scan and self.ticker then return end
    if self.ownershipTicker then self.ownershipAgain = true; return end
    local snapshot = self.snapshot
    local entries = {}
    if snapshot then
        local seen, index = {}, 1
        snapshot.unknownData = snapshot.incomplete
        snapshot.pending = {}
        local function Tick()
          if InCombatLockdown() then
            self.ownershipTicker:Cancel(); self.ownershipTicker = nil
            self.deferred = true
            return
          end
          for _ = 1, BATCH_SIZE do
            local item = snapshot.items[index]
            if not item then break end
            index = index + 1
            local pending = RefineUI.Collections:VisitRewards(item, function(kind, id, owned)
                local key = kind .. ":" .. id
                local entry = seen[key]
                if not entry then
                    entry = { key = key, kind = kind, id = id, owned = owned, item = item, bosses = {} }
                    seen[key] = entry
                    entries[#entries + 1] = entry
                elseif owned == true or entry.owned == nil then entry.owned = owned end
                for boss in pairs(item.bosses) do entry.bosses[boss] = true end
            end)
            if pending then
                snapshot.unknownData = true
                snapshot.pending[item.itemID or 0] = true
            end
          end
          if index > #snapshot.items then
            self.ownershipTicker:Cancel(); self.ownershipTicker = nil
            self.entries = entries
            self:BuildView()
            if self.ownershipAgain then self.ownershipAgain = nil; self:Schedule() end
          end
        end
        self.ownershipTicker = C_Timer.NewTicker(0.03, Tick)
        return
    end
    self.entries = entries
    self:BuildView()
end

function Module:GetAchievementEntries()
    if self.achievementEntries and self.achievementEntryRows == self.achievementRows
        and self.achievementEntryBosses == self.bosses then
        return self.achievementEntries
    end
    local entries = {}
    local provider = RefineUI.InstanceAchievements
    local options = {}
    for _, boss in ipairs(self.bosses or {}) do
        options[#options + 1] = { encounterID = boss.id, token = provider:NormalizeCompletionToken(boss.name) }
    end
    for _, row in ipairs(self.achievementRows or {}) do
        local _, name, _, owned = GetAchievementInfo(row.achievementID)
        local entry = { key = "achievement:" .. row.achievementID, id = row.achievementID,
            kind = "achievements", name = name or row.name, icon = row.icon, owned = owned, bosses = {} }
        -- Use the same cached name/description/category matching as the Guide.
        -- Shared achievements may belong to multiple bosses; instance totals still
        -- count the achievement once. Criteria remain an attribution-only fallback.
        local matchedDescription = false
        for _, option in ipairs(options) do
            if provider:RowMatchesBossFilter(row, option) then
                entry.bosses[option.encounterID] = true
                matchedDescription = true
            end
        end
        local criteriaCount = not matchedDescription and GetAchievementNumCriteria(row.achievementID) or 0
        for index = 1, criteriaCount do
            local text = GetAchievementCriteriaInfo(row.achievementID, index)
            local matched
            for _, boss in ipairs(self.bosses) do
                if text == boss.name then
                    if matched then matched = nil; break end
                    matched = boss.id
                end
            end
            if matched then entry.bosses[matched] = true end
        end
        entries[#entries + 1] = entry
    end
    self.achievementEntries = entries
    self.achievementEntryRows, self.achievementEntryBosses = self.achievementRows, self.bosses
    return entries
end

function Module:CompleteBoss(encounterID)
    if self.defeated[encounterID] then return false end
    self.defeated[encounterID] = true
    for _, boss in ipairs(self.bosses or {}) do
        if boss.encounterID == encounterID then
            self.collapsedGroups[boss.id] = true
            self.advanceAfterBoss = boss.id
            return true
        end
    end
    return false
end

function Module:OnInitialize()
    if not RefineUI.Config.Quests.Enable then return end
    self.entries, self.bosses = {}, {}
    RefineUI:OnEvents({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_DIFFICULTY_CHANGED",
        "UPDATE_INSTANCE_INFO", "PLAYER_LEVEL_UP" }, function(event)
        self:UpdateContext()
        if event == "UPDATE_INSTANCE_INFO" and self.context then
            self.completionDirty = true
            self:Schedule(nil, true)
        end
        if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(1, function() self:UpdateContext() end) end
    end, "LegacyCompletionist:Context")
    -- Criteria are not displayed and do not change static boss attribution.
    RefineUI:OnEvents({ "ACHIEVEMENT_EARNED" }, function()
        self.achievementEntries = nil
        self:Schedule(nil, true)
    end, "LegacyCompletionist:Achievements")
    RefineUI.Collections:Subscribe(self, function() self:Schedule() end)
    RefineUI:RegisterEventCallback("BAG_UPDATE_DELAYED", function() self:Schedule() end, "LegacyCompletionist:Ownership")
    RefineUI:RegisterEventCallback("ENCOUNTER_END", function(_, encounterID, _, _, _, success)
        if not self.context or RefineUI:IsSecretValue(encounterID) or RefineUI:IsSecretValue(success) then return end
        if success == 1 and self:CompleteBoss(encounterID) then self:Schedule(nil, true) end
    end, "LegacyCompletionist:Encounter")
    RefineUI:RegisterEventCallback("BOSS_KILL", function(_, encounterID)
        if not self.context or RefineUI:IsSecretValue(encounterID) then return end
        if self:CompleteBoss(encounterID) then self:Schedule(nil, true) end
    end, "LegacyCompletionist:Boss")
    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if self.deferred then self.deferred = nil; self:Schedule() end
    end, "LegacyCompletionist:Combat")
    RefineUI:OnEvents({ "EJ_LOOT_DATA_RECIEVED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }, function(_, itemID)
        if RefineUI.InstanceCompletion.capturing or not self.context or RefineUI:IsSecretValue(itemID) then return end
        local scan = self.scan or self.snapshot
        if scan and (not itemID or scan.pending[itemID] or scan.pending[0]) then
            -- Some unavailable journal entries keep emitting data notifications.
            -- Bound retries per visit; a manual refresh can explicitly try again.
            if self.dataRetries >= MAX_DATA_RETRIES or scan.retry or self.rescan then return end
            self.dataRetries = self.dataRetries + 1
            if self.scan then scan.retry = true else self:Schedule(true) end
        end
    end, "LegacyCompletionist:ItemData")
    self:UpdateContext()
end

