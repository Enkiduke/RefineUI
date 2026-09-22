----------------------------------------------------------------------------------------
-- Boss / instance collection progress. Only the displayed instance and difficulty are
-- scanned. Journal selection and filters are restored before yielding to the next frame.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuideInstances")
if not Module then return end

local TICK_SECONDS = 0.03
local KEYS = RefineUI.InstanceCompletion.KEYS
Module.COMPLETION_KEYS = KEYS
local function NewCounts() return RefineUI.InstanceCompletion:NewCounts() end
local function AddCount(...) return RefineUI.InstanceCompletion:AddCount(...) end

local function ValidID(value)
    return type(value) == "number" and value > 0
end

function Module:IsCompletionVisible()
    local journal = _G.EncounterJournal
    return journal and journal:IsShown() and journal.encounter and journal.encounter:IsShown()
        and ValidID(journal.instanceID) and self:IsSupportedContentTab(journal.selectedTab)
end

function Module:CancelCompletionWork()
    if self._completionTicker then self._completionTicker:Cancel() end
    if self._completionRefreshTimer then self._completionRefreshTimer:Cancel() end
    self._completionTicker = nil
    self._completionRefreshTimer = nil
    self._completionAchievementRequest = nil
end

function Module:InvalidateCompletionData()
    self:CancelCompletionWork()
    self._completionLoot = nil
    self._completionSummary = nil
    self._completionAchievementMap = nil
end

function Module:ScheduleCompletionRefresh()
    if RefineUI.InstanceCompletion.capturing or not self:IsCompletionVisible() then return end
    if self._completionRefreshTimer then return end
    if C_Timer and C_Timer.NewTimer then
        self._completionRefreshTimer = C_Timer.NewTimer(0.15, function()
            self._completionRefreshTimer = nil
            if self:IsCompletionVisible() then self:RefreshCompletion() end
        end)
    end
end

function Module:IsAccountAppearanceCollected(appearanceID, sourceID)
    return RefineUI.Collections:IsAppearanceCollected(appearanceID, sourceID)
end
function Module:ResolveCompletionCollectible(item)
    return RefineUI.Collections:ResolveItem(item)
end

function Module:CreateCompletionLootState(instanceID, difficultyID)
    local saved = RefineUI.JournalCache and RefineUI.JournalCache:Get("details", instanceID .. ":" .. difficultyID)
    if saved then return saved end
    return {
        instanceID = instanceID, difficultyID = difficultyID, index = 1, bossIndex = 0,
        instance = NewCounts(), bosses = {}, missingItems = {}, incomplete = false,
    }
end

-- This transaction never spans frames and uses the C API, not display functions.
-- Other addons and Blizzard continue to see their original loot filters/selection.
function Module:ReadCompletionLootBatch(state)
    local scan = { index = state.index, bossIndex = state.bossIndex }
    local batch, total = RefineUI.InstanceCompletion:ReadLootBatch(state.instanceID, state.difficultyID, scan)
    state.journalBosses = scan.bosses
    return batch, total
end

function Module:ProcessCompletionLootTick()
    local state = self._completionLoot
    if not state or not self:IsCompletionVisible()
        or state.instanceID ~= self:GetCurrentJournalInstanceID()
        or state.difficultyID ~= EJ_GetDifficulty() then
        if self._completionTicker then self._completionTicker:Cancel() end
        self._completionTicker = nil
        return
    end

    local batch, total = self:ReadCompletionLootBatch(state)
    if not batch then
        state.incomplete, state.finished = true, true
        state.unavailable = true
        if total == "loading" then state.missingItems[0] = true end
    else
        for _, item in ipairs(batch) do
            local pending = RefineUI.Collections:VisitRewards(item, function(kind, id, earned)
                if earned == nil then
                    state.hasUnknown = true
                    state.missingItems[item.itemID or 0] = true
                end
                AddCount(state.instance, kind, id, earned, item)
                for bossID in pairs(item.bosses) do
                    local counts = state.bosses[bossID]
                    if not counts then counts = NewCounts(); state.bosses[bossID] = counts end
                    AddCount(counts, kind, id, earned, item)
                end
            end)
            if pending then
                state.incomplete = true
                state.missingItems[item.itemID or 0] = true
            end
        end
        state.index = state.index + #batch
        if state.index > total then
            if state.bossIndex < #(state.journalBosses or {}) then
                state.bossIndex, state.index = state.bossIndex + 1, 1
            else state.finished = true end
        end
    end

    if state.finished then
        if RefineUI.JournalCache and not state.incomplete and not state.hasUnknown and not state.needsRetry then
            RefineUI.JournalCache:Put("details", state.instanceID .. ":" .. state.difficultyID, state)
        end
        self._completionTicker:Cancel()
        self._completionTicker = nil
        self:UpdateCompletionSummary()
        self:RenderCompletionProgress()
        if state.needsRetry then
            self._completionLoot = nil
            self:ScheduleCompletionRefresh()
        end
    end
end

function Module:BuildCompletionAchievementMap(rows, instanceID)
    local cached = self._completionAchievementMap
    if cached and cached.rows == rows and cached.instanceID == instanceID then return cached end
    local map = { rows = rows, instanceID = instanceID, bosses = {}, unmatched = 0 }
    local index = 1
    while true do
        local name, _, bossID = EJ_GetEncounterInfoByIndex(index, instanceID)
        if not ValidID(bossID) then break end
        local option = { encounterID = bossID, token = self:NormalizeCompletionToken(name) }
        map.bosses[bossID] = { option = option, rows = {} }
        index = index + 1
    end
    for _, row in ipairs(rows) do
        local matched = false
        for _, boss in pairs(map.bosses) do
            if self:RowMatchesBossFilter(row, boss.option) then
                boss.rows[#boss.rows + 1] = row
                matched = true
            end
        end
        if not matched then map.unmatched = map.unmatched + 1 end
    end
    self._completionAchievementMap = map
    return map
end

function Module:UpdateCompletionSummary()
    local state = self._completionLoot
    if not state then return end
    local rows = self:GetCachedInstanceAchievementRows(state.instanceID)
    local previous = self._completionSummary
    if previous and previous.lootState == state and previous.sourceRows == rows
        and previous.lootFinished == state.finished
        and previous.achievementRevision == self._completionAchievementRevision then
        return
    end
    local summary = {
        instanceID = state.instanceID, difficultyID = state.difficultyID,
        instance = NewCounts(), bosses = {}, achievementsReady = rows ~= nil,
        lootReady = state.finished and not state.incomplete,
        unavailable = state.unavailable,
        lootState = state, sourceRows = rows, lootFinished = state.finished,
        achievementRevision = self._completionAchievementRevision,
    }
    for _, key in ipairs(KEYS) do
        if key ~= "achievements" then summary.instance[key] = state.instance[key] end
    end
    if rows then
        local map = self:BuildCompletionAchievementMap(rows, state.instanceID)
        summary.unmatched = map.unmatched
        local ownership = {}
        for _, row in ipairs(rows) do
            local _, _, _, completed = GetAchievementInfo(row.achievementID)
            ownership[row.achievementID] = completed
            AddCount(summary.instance, "achievements", row.achievementID, completed, row)
        end
        for bossID, boss in pairs(map.bosses) do
            local counts = NewCounts()
            local loot = state.bosses[bossID]
            for _, key in ipairs(KEYS) do
                if key ~= "achievements" and loot then counts[key] = loot[key] end
            end
            for _, row in ipairs(boss.rows) do
                AddCount(counts, "achievements", row.achievementID, ownership[row.achievementID], row)
            end
            summary.bosses[bossID] = counts
        end
    end
    -- Loot counts remain visible while achievement scanning is still in progress.
    for bossID, counts in pairs(state.bosses) do
        if not summary.bosses[bossID] then summary.bosses[bossID] = counts end
    end
    self._completionSummary = summary
end

function Module:RefreshCompletion()
    if not self:IsCompletionVisible() then return end
    local instanceID = self:GetCurrentJournalInstanceID()
    local difficultyID = EJ_GetDifficulty()
    local state = self._completionLoot
    if not state or state.instanceID ~= instanceID or state.difficultyID ~= difficultyID then
        self:CancelCompletionWork()
        state = self:CreateCompletionLootState(instanceID, difficultyID)
        self._completionLoot = state
    end
    local rows = self:GetCachedInstanceAchievementRows(instanceID)
    if not rows and self._completionAchievementRequest ~= instanceID then
        self._completionAchievementRequest = instanceID
        local isRaid = select(12, EJ_GetInstanceInfo(instanceID))
        self:RequestInstanceAchievementRows(instanceID, isRaid, function(doneID)
            if self._completionAchievementRequest == doneID then self._completionAchievementRequest = nil end
            self:ScheduleCompletionRefresh()
        end)
    end
    if not state.finished and not self._completionTicker and C_Timer and C_Timer.NewTicker then
        self._completionTicker = C_Timer.NewTicker(TICK_SECONDS, function() self:ProcessCompletionLootTick() end)
    end
    self:UpdateCompletionSummary()
    self:RenderCompletionProgress()
end

function Module:RegisterCompletionEvents()
    if self._completionEventsRegistered then return end
    self._completionEventsRegistered = true
    RefineUI.Collections:Subscribe(self, function()
        self:CancelCompletionWork()
        self._completionLoot = nil
        self:ScheduleCompletionRefresh()
    end)
    for _, event in ipairs({ "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE" }) do
        RefineUI:RegisterEventCallback(event, function()
            self._completionAchievementRevision = (self._completionAchievementRevision or 0) + 1
            self:ScheduleCompletionRefresh()
        end, self:BuildKey("Completion", event))
    end
    for _, event in ipairs({ "EJ_LOOT_DATA_RECIEVED", "GET_ITEM_INFO_RECEIVED" }) do
        RefineUI:RegisterEventCallback(event, function(_, itemID)
            if RefineUI.InstanceCompletion.capturing or RefineUI:IsSecretValue(itemID) then return end
            local state = self._completionLoot
            if state and (state.incomplete or state.hasUnknown) and (not itemID or state.missingItems[itemID] or state.missingItems[0]) then
                if state.finished then
                    self:CancelCompletionWork()
                    self._completionLoot = nil
                    self:ScheduleCompletionRefresh()
                else
                    state.needsRetry = true
                end
            end
        end, self:BuildKey("Completion", event))
    end
end
