local _, RefineUI = ...
local Planner, Data = RefineUI.AdventurePlanner, RefineUI.PlannerData
local Safe, WEIGHTS = Planner.Safe, Data.weights

-- Priority tiers: 1 collect, 2 pick up, 3 expiring, 4 weekly core, 5 useful, 6 optional.
local REASONS = { spark = "Spark Dust for crafted gear (season cap applies)", sparkCatchUp = "One-time Spark catch-up",
    worldBoss = "Weekly world boss loot", knowledge = "Profession Knowledge", assignment = "Special Assignment reward" }

local function Record(id, section, kind, title, category, icon)
    return { id = id, section = section, kind = kind, title = title, category = category, icon = icon or 134400, state = "available" }
end

local function Done(self, id) return self:Call(C_QuestLog, "IsQuestFlaggedCompleted", id) == true end

local function Count(self, ids)
    local count = 0
    for _, id in ipairs(ids or {}) do if Done(self, id) then count = count + 1 end end
    return count
end

local function AtMaxLevel(self)
    local level, maxLevel = self:Call(_G, "UnitLevel", "player"), self:Call(_G, "GetMaxLevelForPlayerExpansion")
    return level and maxLevel and level >= maxLevel
end

function Planner:QuestTitle(id)
    local title = self:Call(C_QuestLog, "GetTitleForQuestID", id) or self:Call(C_TaskQuest, "GetQuestInfoByQuestID", id)
    -- Request once per session: a failed load must not re-trigger refreshes.
    if not title and not self.requested["quest" .. id] then
        self.requested["quest" .. id] = true
        self:Call(C_QuestLog, "RequestLoadQuestByID", id)
    end
    return title
end

function Planner:RequestItem(itemID)
    if self.requested[itemID] then return end
    self.requested[itemID], self.pendingItems[itemID] = true, true
    self:Call(C_Item, "RequestLoadItemDataByID", itemID)
end

function Planner:GetMapTasks(mapID)
    local cache = self.mapTasks
    if cache and cache[mapID] then return cache[mapID] end
    local tasks = self:Call(C_TaskQuest, "GetQuestsOnMap", mapID) or {}
    if cache then cache[mapID] = tasks end
    return tasks
end

function Planner:CurrencyInfo(id)
    local info = self:Call(C_CurrencyInfo, "GetCurrencyInfo", id)
    if not info then return end
    return { name = Safe(info.name), quantity = Safe(info.quantity), icon = Safe(info.iconFileID),
        weeklyEarned = Safe(info.quantityEarnedThisWeek), weeklyCap = Safe(info.maxWeeklyQuantity),
        totalEarned = Safe(info.totalEarned), maxQuantity = Safe(info.maxQuantity), description = Safe(info.description),
        discovered = Safe(info.discovered), unused = Safe(info.isTypeUnused), accountWide = Safe(info.isAccountWide),
        useTotal = Safe(info.useTotalEarnedForMaxQty) }
end

local function Objectives(self, r)
    local objectives = self:Call(C_QuestLog, "GetQuestObjectives", r.questID) or {}
    r.lines = {}
    for _, objective in ipairs(objectives) do
        local text, have, need = Safe(objective.text), Safe(objective.numFulfilled), Safe(objective.numRequired)
        if text then r.lines[#r.lines + 1] = text end
        if not Safe(objective.finished) and text and not r.detail then r.detail = text end
        if #objectives == 1 and type(have) == "number" and type(need) == "number" and need > 1 then
            r.current, r.target = math.min(have, need), need
        end
    end
end

-- Expansion identity decides relevance only; registry entries are Midnight quests.
local function Classify(self, r, meta)
    local expansion = type(GetQuestExpansion) == "function" and self:Call(_G, "GetQuestExpansion", r.questID) or nil
    if expansion == nil and meta then expansion = 11 end
    local current = LE_EXPANSION_LEVEL_CURRENT
    if type(expansion) ~= "number" or type(current) ~= "number" then r.era = "unknown"
    elseif expansion < current then
        r.era = "legacy"
        local name = Safe(_G["EXPANSION_NAME" .. expansion])
        if type(name) == "string" then r.expansionName = name end
    else r.era = "current" end
    if r.era ~= "current" or (meta and meta.optional) then r.section, r.tier, r.optional = "optional", 6, true end
end

local function FactionReason(self, r)
    for _, reward in ipairs(self:Call(C_QuestLog, "GetQuestLogMajorFactionReputationRewards", r.questID) or {}) do
        local factionID, amount = Safe(reward.factionID), Safe(reward.rewardAmount)
        local info = factionID and amount and amount > 0 and self:Call(C_MajorFactions, "GetMajorFactionData", factionID)
        local name = info and Safe(info.name)
        if name then r.lines = r.lines or {}; r.lines[#r.lines + 1] = "Rewards " .. amount .. " " .. name .. " reputation"; return end
    end
end

-- status: "log" (accepted), "offered", "task" (visible world quest), "complete" or "missing".
local function QuestRecord(self, id, title, meta, cadence, status, mapID, expiresAt)
    local category = meta and meta.category or (cadence == "daily" and "Daily quests" or "Weekly quests")
    local r = Record("quest:" .. id, "weekly", "task", title or ("Quest " .. id), category, meta and meta.icon)
    local reward = meta and meta.reward
    r.questID, r.cadence, r.expiresAt = id, meta and meta.oneTime and "once" or cadence, expiresAt
    r.weight = WEIGHTS[reward] or cadence == "daily" and WEIGHTS.daily or cadence == "weekly" and WEIGHTS.weekly or WEIGHTS.quest
    r.reason = REASONS[reward] or (cadence == "daily" and "Daily quest" or "Weekly quest")
    if status == "complete" then
        r.state, r.detail = "complete", meta and meta.oneTime and "Completed" or "Completed this reset"
    elseif status == "log" then
        r.destination = { type = "quest", id = id, label = "Track quest" }
        if self:Call(C_QuestLog, "ReadyForTurnIn", id) then
            r.state, r.tier, r.weight = "ready", 1, WEIGHTS.turnIn
            r.actionTitle, r.detail = "Turn in " .. r.title, "Ready to turn in"
        else
            r.state, r.tier = "active", cadence == "daily" and 5 or 4
            Objectives(self, r)
            local total, elapsed = self:Call(C_QuestLog, "GetTimeAllowed", id)
            if type(total) == "number" and type(elapsed) == "number" and total > elapsed then r.expiresAt = self:Now() + total - elapsed end
        end
    elseif status == "offered" then
        local giver = Data.pickupByQuestID[id]
        local position = giver and giver.mapID == mapID and giver.position or nil
        r.state, r.tier, r.actionTitle = "available", 2, "Pick up " .. r.title
        r.detail = "Available now" .. (giver and " from " .. giver.giver or "") .. " • pick up before playing so progress counts"
        r.destination = { type = "map", id = mapID, position = position, label = position and "Pin quest giver" or "Open map" }
    elseif status == "task" then
        r.state, r.tier = "available", 4
        r.destination = { type = "map", id = mapID, label = "Track quest" }
    else
        r.state, r.detail = "missing", "Not in quest log"
        if meta and meta.mapID then r.destination = { type = "map", id = meta.mapID, label = "Open map" } end
    end
    r.recommend = r.state == "ready" or r.state == "active" or r.state == "available"
    Classify(self, r, meta)
    if r.state ~= "complete" then FactionReason(self, r) end
    return r
end

function Planner:ObserveQuest(id, info)
    if not id then return end
    if not info then
        local index = self:Call(C_QuestLog, "GetLogIndexForQuestID", id)
        info = index and self:Call(C_QuestLog, "GetInfo", index)
        if not info then return end
    end
    local frequency, meta = Safe(info.frequency), Data.quests[id]
    local cadence = frequency == Enum.QuestFrequency.Daily and "daily" or frequency == Enum.QuestFrequency.Weekly and "weekly"
        or meta and meta.weekly and "weekly"
    if not cadence then return end
    local scope = self:Call(C_QuestLog, "IsAccountQuest", id) == true and "account" or "character"
    local period = self:Period(cadence, scope)
    if period then
        local entry = period.quests[id] or {}
        entry.title, entry.scope, entry.observedAt = Safe(info.title) or entry.title, scope, self:Now()
        entry.completed, entry.completedAt = nil, nil
        period.quests[id] = entry
    end
    return cadence
end

function Planner:ObserveTurnIn(id)
    if not id then return end
    for _, scope in ipairs({ "character", "account" }) do
        for _, cadence in ipairs({ "daily", "weekly" }) do
            local period = self:Period(cadence, scope)
            local entry = period and period.quests[id]
            if entry then entry.completed, entry.completedAt = true, self:Now() end
        end
    end
end

Planner.providers.quests = function(self)
    local records, handled = {}, {}
    local activePrey = self:Call(C_QuestLog, "GetActivePreyQuest")
    local function Add(r) records[#records + 1] = r; handled[r.questID] = true end
    for index = 1, self:Call(C_QuestLog, "GetNumQuestLogEntries") or 0 do
        local info = self:Call(C_QuestLog, "GetInfo", index)
        local id = info and Safe(info.questID)
        if id and not Safe(info.isHeader) and not Safe(info.isHidden) and id ~= activePrey then
            local cadence = self:ObserveQuest(id, info)
            if cadence or Data.quests[id] then Add(QuestRecord(self, id, Safe(info.title), Data.quests[id], cadence, "log")) end
        end
    end
    local maxed = AtMaxLevel(self)
    for _, mapID in ipairs(Data.maps) do
        for _, line in ipairs(self:Call(C_QuestLine, "GetAvailableQuestLines", mapID) or {}) do
            local id = Safe(line.questID)
            local meta = id and Data.quests[id]
            if meta and (meta.weekly or meta.oneTime) and not handled[id] and not Safe(line.isHidden) and not Done(self, id) then
                Add(QuestRecord(self, id, self:QuestTitle(id), meta, "weekly", "offered", mapID))
            end
        end
    end
    -- Registered world quests count only while visible to this character.
    local visible = {}
    for id, meta in pairs(Data.quests) do
        if meta.worldQuest and not handled[id] and meta.mapID and self:Call(C_TaskQuest, "IsActive", id) == true then
            if not visible[meta.mapID] then
                visible[meta.mapID] = {}
                for _, poi in ipairs(self:GetMapTasks(meta.mapID)) do
                    local questID = Safe(poi.questID)
                    if questID and not Safe(poi.isHidden) then visible[meta.mapID][questID] = true end
                end
            end
            local seconds = self:Call(C_TaskQuest, "GetQuestTimeLeftSeconds", id)
            if visible[meta.mapID][id] and seconds and seconds > 0 and not Done(self, id) then
                Add(QuestRecord(self, id, self:QuestTitle(id), meta, "weekly", "task", meta.mapID, self:Now() + seconds))
            end
        end
    end
    -- Coffer Key world quests are only worth doing while shards are uncapped.
    local shards = self:CurrencyInfo(Data.coffer.shards)
    local shardsCapped = shards and shards.weeklyCap and shards.weeklyCap > 0 and shards.weeklyEarned
        and shards.weeklyEarned >= shards.weeklyCap
    for _, mapID in ipairs(Data.maps) do
        for _, poi in ipairs(mapID ~= 2393 and self:GetMapTasks(mapID) or {}) do
            local id = Safe(poi.questID)
            if id and not handled[id] and not Safe(poi.isHidden) and self:Call(C_TaskQuest, "IsActive", id) == true then
                if not self.requested["reward" .. id] then
                    self.requested["reward" .. id] = true
                    self:Call(C_TaskQuest, "RequestPreloadRewardData", id)
                end
                for _, reward in ipairs(self:Call(C_QuestLog, "GetQuestRewardCurrencies", id) or {}) do
                    local currencyID = Safe(reward.currencyID)
                    local seconds = self:Call(C_TaskQuest, "GetQuestTimeLeftSeconds", id)
                    local title = self:QuestTitle(id)
                    if (currencyID == Data.coffer.key or (currencyID == Data.coffer.shards and not shardsCapped))
                        and title and seconds and seconds > 0 and not handled[id] then
                        local r = QuestRecord(self, id, title, { category = "Coffer Keys", icon = 134241 }, "weekly", "task", mapID, self:Now() + seconds)
                        r.section, r.weight = "delves", WEIGHTS.cofferKey
                        r.reason = currencyID == Data.coffer.key and "Rewards a Restored Coffer Key" or "Rewards Coffer Key Shards"
                        r.detail = r.reason
                        Add(r)
                    end
                end
            end
        end
    end
    -- Earlier observations recover abandoned or turned-in quests; registry flags
    -- recover completions that happened before the Planner saw them.
    for _, scope in ipairs({ "character", "account" }) do
        for _, cadence in ipairs({ "daily", "weekly" }) do
            local period = self:Period(cadence, scope)
            for id, observed in pairs(period and period.quests or {}) do
                if not handled[id] and id ~= activePrey then
                    local complete = observed.completed or Done(self, id)
                    Add(QuestRecord(self, id, observed.title, Data.quests[id], cadence, complete and "complete" or "missing"))
                end
            end
        end
    end
    for id, meta in pairs(Data.quests) do
        if not handled[id] and not meta.profession and (meta.weekly or meta.oneTime) and Done(self, id) then
            Add(QuestRecord(self, id, self:QuestTitle(id), meta, "weekly", "complete"))
        end
    end
    if maxed then
        local warMode = self:Call(C_PvP, "IsWarModeDesired") == true
        for _, giver in ipairs(Data.givers) do
            local open = true
            for _, id in ipairs(giver.questIDs) do
                if handled[id] or Done(self, id) then open = false; break end
            end
            if open then
                local r = Record("discovery:" .. giver.key, "weekly", "lead", "Check " .. giver.giver, giver.category)
                r.actionTitle, r.tier, r.weight = "Visit " .. giver.giver, 2, giver.weight - 15
                r.reason = giver.reward .. (giver.note and " • " .. giver.note or "")
                r.detail = "Weekly quest giver • pick up if offered this week"
                local period = self:Period("weekly")
                r.resetKey = period and period.reset
                r.destination = { type = "map", id = giver.mapID, position = giver.position,
                    label = giver.position and "Pin quest giver" or "Open map" }
                r.recommend = not giver.optional or warMode
                records[#records + 1] = r
            end
        end
    end
    return records
end

local TRACKS = {
    { key = "Raid", title = RAIDS, unit = "raid boss", units = "raid bosses", icon = 236423 },
    { key = "Activities", title = DUNGEONS, unit = "dungeon", units = "dungeons", icon = 463829 },
    { key = "World", title = WORLD or "World", unit = "Delve or world activity", units = "Delves or world activities", icon = 6025441 },
}

local function ItemLevel(self, link)
    if not link then return end
    local level = self:Call(C_Item, "GetDetailedItemLevelInfo", link)
    if not level then
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID then self:RequestItem(itemID) end
    end
    return level
end

-- Uses Blizzard's own Vault upgrade rules and strings, so advice matches the Vault tooltip.
local function Improvement(self, track, activity)
    local link, upgradeLink = self:Call(C_WeeklyRewards, "GetExampleRewardItemHyperlinks", activity.id)
    local current = ItemLevel(self, link)
    if track.key == "Raid" then
        local upgrade = ItemLevel(self, upgradeLink)
        local nextDifficulty = DifficultyUtil and DifficultyUtil.GetNextPrimaryRaidDifficultyID(activity.level)
        local name = nextDifficulty and DifficultyUtil.GetDifficultyName(nextDifficulty)
        if current and upgrade and upgrade > current and name then
            return current, upgrade, WEEKLY_REWARDS_COMPLETE_RAID and WEEKLY_REWARDS_COMPLETE_RAID:format(name)
        end
        return current
    end
    local hasData, _, nextLevel, upgrade = self:Call(C_WeeklyRewards, "GetNextActivitiesIncrease", activity.tierID, activity.level)
    if not (hasData and nextLevel and upgrade and current and upgrade > current) then return current end
    local text = track.key == "World" and WEEKLY_REWARDS_COMPLETE_WORLD and WEEKLY_REWARDS_COMPLETE_WORLD:format(nextLevel)
        or activity.threshold > 1 and WEEKLY_REWARDS_COMPLETE_MYTHIC and WEEKLY_REWARDS_COMPLETE_MYTHIC:format(nextLevel, activity.threshold)
        or WEEKLY_REWARDS_COMPLETE_MYTHIC_SHORT and WEEKLY_REWARDS_COMPLETE_MYTHIC_SHORT:format(nextLevel)
    return current, upgrade, text
end

Planner.providers.vault = function(self)
    local records = {}
    local waiting = self:Call(C_WeeklyRewards, "HasAvailableRewards") == true
    local stale = waiting and self:Call(C_WeeklyRewards, "AreRewardsForCurrentRewardPeriod") ~= true
    if waiting then
        local r = Record("vault:claim", "vault", "task", "Choose your Great Vault reward", "Great Vault", 1518642)
        r.state, r.tier, r.weight, r.recommend = "ready", 1, WEIGHTS.vaultClaim, true
        r.reason = "Choose it before spending Crests or Catalyst charges"
        r.detail = "Reward waiting at the Great Vault"
        r.destination = { type = "vault", label = "Open Great Vault" }
        records[#records + 1] = r
    end
    for index, track in ipairs(TRACKS) do
        local r = Record("vault:track:" .. index, "vault", "vault", track.title, "Great Vault", track.icon)
        r.destination, r.slots = { type = "vault", label = "Open Great Vault" }, {}
        local activities = {}
        for _, activity in ipairs(self:Call(C_WeeklyRewards, "GetActivities", Enum.WeeklyRewardChestThresholdType[track.key]) or {}) do
            local threshold, progress = Safe(activity.threshold), Safe(activity.progress)
            if threshold and progress and threshold > 0 then
                activities[#activities + 1] = { id = Safe(activity.id), threshold = threshold, progress = progress,
                    level = Safe(activity.level) or 0, tierID = Safe(activity.activityTierID) }
            end
        end
        table.sort(activities, function(a, b) return a.threshold < b.threshold end)
        local unlocked, nextActivity, lowest = 0, nil, nil
        for _, activity in ipairs(activities) do
            local slot = { threshold = activity.threshold, progress = activity.progress, reached = activity.progress >= activity.threshold }
            if slot.reached then
                unlocked = unlocked + 1
                slot.itemLevel, slot.upgrade, slot.upgradeText = Improvement(self, track, activity)
                if slot.itemLevel and (not lowest or slot.itemLevel < lowest.itemLevel) then lowest = slot end
            elseif not nextActivity then nextActivity = activity end
            r.slots[#r.slots + 1] = slot
        end
        r.current, r.target = unlocked, #activities
        if #activities == 0 or stale then
            r.state, r.detail = "unknown", stale and "Collect last week's reward first" or "Progress unavailable"
        else
            r.state = unlocked == #activities and "complete" or unlocked > 0 and "active" or "available"
            r.detail = unlocked .. " / " .. #activities .. (lowest and (" • ilvl " .. lowest.itemLevel) or "")
        end
        -- The ring fills toward the final threshold; each activity reports the same total.
        local final = activities[#activities]
        r.fraction = final and math.min(1, final.progress / final.threshold)
        records[#records + 1] = r
        if r.state ~= "unknown" and nextActivity then
            local remaining = nextActivity.threshold - nextActivity.progress
            local task = Record("vault:next:" .. index, "vault", "task", track.title .. " Vault choice " .. (unlocked + 1), "Great Vault", track.icon)
            task.actionTitle = "Complete " .. remaining .. " more " .. (remaining == 1 and track.unit or track.units)
            task.reason = "Unlocks Great Vault choice " .. (unlocked + 1) .. " of " .. #activities
            task.detail = track.title .. " • " .. nextActivity.progress .. " / " .. nextActivity.threshold
            task.current, task.target = nextActivity.progress, nextActivity.threshold
            task.state = nextActivity.progress > 0 and "active" or "available"
            task.tier, task.weight, task.recommend = 4, WEIGHTS.vault - math.min(remaining, 10), true
            task.destination = r.destination
            records[#records + 1] = task
        elseif r.state == "complete" and lowest and lowest.upgrade then
            local task = Record("vault:improve:" .. index, "vault", "task", "Improve your " .. track.title .. " Vault reward", "Great Vault", track.icon)
            task.actionTitle = "Raise a " .. track.title .. " Vault choice to ilvl " .. lowest.upgrade
            task.reason = lowest.upgradeText or "Higher difficulty improves this Vault choice"
            task.detail = "Currently ilvl " .. lowest.itemLevel
            task.tier, task.weight, task.recommend = 5, WEIGHTS.vault - 14, true
            task.destination = r.destination
            records[#records + 1] = task
        end
    end
    return records
end

Planner.providers.prey = function(self)
    local records, prey = {}, Data.prey
    local done = Count(self, prey.ids)
    local r = Record("prey:weekly", "delves", "progress", "Prey hunts", "Prey", "Interface\\Icons\\Ability_Hunter_MarkedForDeath")
    r.current, r.target = done, prey.target
    r.state = done >= prey.target and "complete" or done > 0 and "active" or "available"
    r.detail = done .. " / " .. prey.target .. " this week"
    r.lines = { "Season 2 guides recommend four hunts each week.", "Later hunts give sharply reduced progress." }
    records[#records + 1] = r
    local id = self:Call(C_QuestLog, "GetActivePreyQuest")
    if id and id > 0 and self:Call(C_QuestLog, "IsOnQuest", id) == true then
        local hunt = QuestRecord(self, id, self:QuestTitle(id) or "Active Prey hunt", { category = "Prey" }, "weekly", "log")
        hunt.section, hunt.weight = "delves", WEIGHTS.prey
        hunt.reason = "Finish your active hunt • Great Vault World progress"
        records[#records + 1] = hunt
    elseif done < prey.target and AtMaxLevel(self) then
        local task = Record("prey:start", "delves", "task", "Start a Prey hunt", "Prey", "Interface\\Icons\\Ability_Hunter_MarkedForDeath")
        task.actionTitle = "Start a Prey hunt with " .. prey.giver
        task.reason = "Hunt " .. (done + 1) .. " of " .. prey.target .. " • Great Vault World progress"
        task.detail = "Silvermoon City"
        task.tier, task.weight, task.recommend = 4, WEIGHTS.prey - done, true
        task.destination = { type = "map", id = prey.mapID, label = "Open map" }
        records[#records + 1] = task
    end
    return records
end

Planner.providers.delves = function(self)
    local records, bountiful = {}, {}
    local here = self:Call(C_Map, "GetBestMapForUnit", "player")
    for mapID, pois in pairs(Data.bountifulDelves) do
        for _, poiID in ipairs(pois) do
            local info = self:Call(C_AreaPoiInfo, "GetAreaPOIInfo", mapID, poiID)
            local name = info and Safe(info.name)
            if name then
                local map = self:Call(C_Map, "GetMapInfo", mapID)
                local position, x, y = info and Safe(info.position)
                if position then x, y = self:Call(position, "GetXY", position) end
                local r = Record("delve:" .. poiID, "delves", "context", name, "Bountiful Delves", 6025441)
                r.detail = "Bountiful • " .. (map and Safe(map.name) or "")
                r.destination = { type = "map", id = mapID, position = x and y and { x = x, y = y },
                    label = x and "Pin Delve" or "Open map" }
                if mapID == here then table.insert(bountiful, 1, r) else bountiful[#bountiful + 1] = r end
                records[#records + 1] = r
            end
        end
    end
    local keys = self:CurrencyInfo(Data.coffer.key)
    local count = keys and keys.quantity or 0
    if count > 0 and bountiful[1] then
        local task = Record("delves:bountiful", "delves", "task", "Run a Bountiful Delve", "Delves", 6025441)
        task.actionTitle = "Run a Bountiful Delve at Tier " .. Data.coffer.tier .. "+"
        task.reason = count .. " Restored Coffer Key" .. (count == 1 and "" or "s") .. " • best used on Tier " .. Data.coffer.tier .. " or higher"
        task.detail = bountiful[1].title .. " • " .. bountiful[1].detail:gsub("^Bountiful • ", "")
        task.tier, task.weight, task.recommend = 4, WEIGHTS.bountiful + math.min(count, 6), true
        task.destination = bountiful[1].destination
        records[#records + 1] = task
    end
    if self:Call(C_DelvesUI, "HasActiveDelve") == true then
        local eligible = self:Call(C_DelvesUI, "IsEligibleForActiveDelveRewards", "player")
        local r = Record("delves:active", "nearby", "context", "Active Delve", "Delves", 6025441)
        r.detail = "Rewards: " .. (eligible == true and "Available" or eligible == false and "Unavailable" or "Not shown")
        records[#records + 1] = r
    end
    return records
end

local function KnowledgeLine(label, done, kp)
    return (done and "|A:common-icon-checkmark:12:12|a " or "|A:common-icon-redx:12:12|a ") .. label .. " • " .. kp .. " Knowledge"
end

Planner.providers.professions = function(self, db)
    local records, maxed, listed = {}, AtMaxLevel(self), {}
    -- Accepted or offered profession quests already appear in the quests provider.
    for _, r in ipairs(self.cache.quests or {}) do
        if r.questID and r.state ~= "missing" then listed[r.questID] = true end
    end
    local first, second = self:Call(_G, "GetProfessions")
    for _, slot in ipairs({ first, second }) do
        local name, icon, skill, _, _, _, skillLine = self:Call(_G, "GetProfessionInfo", slot)
        local source = skillLine and Data.professions[skillLine]
        if source and name then
            local r = Record("profession:" .. skillLine, "professions", "progress", name .. " weekly Knowledge", "Professions", icon)
            r.lines = {}
            local earned, total = 0, 0
            local function Source(label, done, kp, got)
                total, earned = total + kp, earned + (got or done and kp or 0)
                r.lines[#r.lines + 1] = KnowledgeLine(label, done, kp)
            end
            local questDone = Count(self, source.quest) > 0
            Source("Weekly quest", questDone, source.questKP)
            local treatiseDone = Done(self, source.treatise)
            Source("Thalassian Treatise", treatiseDone, 1)
            if source.drops then
                local drops = Count(self, source.drops)
                Source("Crafting drops " .. drops .. " / " .. #source.drops, drops == #source.drops,
                    #source.drops * source.dropKP, drops * source.dropKP)
            end
            if source.gather then
                local gathered = Count(self, source.gather)
                Source("Gathering finds " .. gathered .. " / " .. #source.gather, gathered == #source.gather,
                    #source.gather * source.gatherKP, gathered * source.gatherKP)
                Source("Bonus find", Done(self, source.bonus), source.bonusKP)
            end
            r.current, r.target = earned, total
            r.state = earned >= total and "complete" or earned > 0 and "active" or "available"
            r.detail = earned .. " / " .. total .. " Knowledge this week"
            records[#records + 1] = r
            local gatherer = source.gather ~= nil
            local pending = false
            for _, id in ipairs(source.quest) do
                if listed[id] or self:Call(C_QuestLog, "IsOnQuest", id) == true then pending = true end
            end
            if maxed and not questDone and not pending and (not gatherer or (skill and skill >= 25)) then
                local task = Record("discovery:profession:" .. skillLine, "professions", "task", name .. " weekly quest", "Professions", icon)
                task.actionTitle = "Pick up your " .. name .. " weekly"
                task.reason = "+" .. source.questKP .. " Knowledge • " .. (gatherer and "profession trainer" or "Work Order station")
                task.detail = "Silvermoon City"
                task.tier, task.weight, task.recommend = 5, WEIGHTS.knowledge, true
                task.destination = { type = "map", id = 2393, position = source.point, label = "Pin pickup" }
                records[#records + 1] = task
            end
            local held = self:Call(C_Item, "GetItemCount", source.treatiseItem, true, false, true, true)
            if not treatiseDone and held and held > 0 then
                local task = Record("profession:treatise:" .. skillLine, "professions", "task", "Use your " .. name .. " Treatise", "Professions", icon)
                task.actionTitle, task.itemID = "Use your " .. name .. " Treatise", source.treatiseItem
                task.reason, task.detail = "+1 Knowledge • already in your bags", "Use it from your bags"
                task.tier, task.weight, task.recommend = 4, WEIGHTS.knowledge + 2, true
                records[#records + 1] = task
            end
        end
    end
    for key, entry in pairs(db.snapshots.orders) do
        if entry.expiresAt <= self:Now() then db.snapshots.orders[key] = nil
        else
            local r = Record("order:" .. key, "professions", "context", "Patron order #" .. entry.order.orderID, "Patron Orders", "Interface\\Icons\\INV_Misc_Note_01")
            r.observedAt, r.expiresAt, r.expirationMeaning = entry.observedAt, entry.expiresAt, "Order expires"
            r.detail, r.lines = "Seen at the crafting orders table", {}
            for _, reward in ipairs(entry.order.npcOrderRewards or {}) do
                local label = reward.itemLink or (reward.currencyType and ("Currency #" .. reward.currencyType))
                if label then r.lines[#r.lines + 1] = "Reward: " .. (reward.count or "?") .. " × " .. label end
            end
            records[#records + 1] = r
        end
    end
    return records
end

-- Patron orders are passive snapshots of successful NPC order searches.
function Planner:ObserveOrders(page, result, orderType)
    if Safe(result) ~= Enum.CraftingOrderResult.Ok or Safe(orderType) ~= Enum.CraftingOrderType.Npc then return end
    local info = Safe(page.professionInfo)
    local profession = info and Safe(info.professionID)
    local db = self:Database()
    if not profession or not db then return end
    for _, order in ipairs(self:Call(C_CraftingOrders, "GetCrafterOrders") or {}) do
        local orderID, expiresAt = Safe(order.orderID), Safe(order.expirationTime)
        if orderID and expiresAt and Safe(order.orderType) == orderType then
            local rewards = {}
            for _, reward in ipairs(Safe(order.npcOrderRewards) or {}) do
                rewards[#rewards + 1] = { itemLink = Safe(reward.itemLink), currencyType = Safe(reward.currencyType), count = Safe(reward.count) }
            end
            db.snapshots.orders[profession .. ":" .. orderID] = { order = { orderID = orderID, npcOrderRewards = rewards },
                profession = profession, observedAt = self:Now(), expiresAt = expiresAt }
        end
    end
    self:Invalidate("professions")
end

function Planner:InstallOrderHooks()
    local page = ProfessionsFrame and ProfessionsFrame.OrdersPage
    if not page or self.orderHookPage == page or type(page.OrderRequestCallback) ~= "function" then return end
    self.orderHookPage = page
    hooksecurefunc(page, "OrderRequestCallback", function(...) pcall(self.ObserveOrders, self, ...) end)
end

function Planner:ObserveOrderFulfilled(result, orderID)
    result, orderID = Safe(result), Safe(orderID)
    local db = self:Database()
    if result ~= Enum.CraftingOrderResult.Ok or not orderID or not db then return end
    for key, entry in pairs(db.snapshots.orders) do
        if entry.order.orderID == orderID then db.snapshots.orders[key] = nil end
    end
    self:Invalidate("professions")
end

function Planner:InvalidateOrderReward(_, orderID)
    orderID = Safe(orderID)
    local db = self:Database()
    if not orderID or not db then return end
    for _, entry in pairs(db.snapshots.orders) do
        if entry.order.orderID == orderID then entry.order.npcOrderRewards = nil end
    end
    self:Invalidate("professions")
end

function Planner:CurrencyRecord(id, metadata)
    local info = self:CurrencyInfo(id)
    if not info or not info.name or info.unused or not info.discovered then return end
    local r = Record("currency:" .. id, "resources", "resource", info.name, metadata and metadata.category or "Currencies", info.icon)
    r.currencyID, r.amount, r.description = id, info.quantity, info.description
    r.destination = { type = "currency", id = id, label = "Details" }
    r.lines = {}
    if metadata and metadata.heldItemID then
        -- The Spark counter tracks seasonal acquisition; the held item is spendable.
        local itemName = self:Call(C_Item, "GetItemNameByID", metadata.heldItemID)
        if itemName then r.title = itemName else self:RequestItem(metadata.heldItemID) end
        r.amount = self:Call(C_Item, "GetItemCount", metadata.heldItemID, true, false, true, true)
        if info.useTotal and info.totalEarned and info.maxQuantity and info.maxQuantity > 0 then
            r.lines[#r.lines + 1] = info.totalEarned .. " / " .. info.maxQuantity .. " earned this season"
            if info.totalEarned < info.maxQuantity then r.lines[#r.lines + 1] = (info.maxQuantity - info.totalEarned) .. " still available" end
        end
        return r
    end
    if info.weeklyCap and info.weeklyCap > 0 and info.weeklyEarned then
        r.lines[#r.lines + 1] = info.weeklyEarned .. " / " .. info.weeklyCap .. " earned this week"
    end
    if info.useTotal and info.maxQuantity and info.maxQuantity > 0 and info.totalEarned then
        r.lines[#r.lines + 1] = info.totalEarned .. " / " .. info.maxQuantity .. " earned this season"
    end
    if metadata and metadata.category == "Catalyst" then
        r.lines[#r.lines + 1] = (info.quantity or "?") .. " Catalyst charges"
        local interaction = self:Call(C_ItemInteraction, "GetItemInteractionInfo")
        if interaction and Safe(interaction.currencyTypeId) == id then
            local charge = self:Call(C_ItemInteraction, "GetChargeInfo")
            local seconds = charge and Safe(charge.timeToNextCharge)
            if seconds and seconds > 0 then r.expiresAt, r.expirationMeaning = self:Now() + seconds, "Next charge" end
        end
    end
    return r
end

Planner.providers.resources = function(self, db)
    local _, _, _, build = self:Call(_G, "GetBuildInfo")
    local candidates = Data.ResourceIDs(tonumber(build) or 0)
    for key in pairs(db.preferences.pins) do
        local id = tonumber(key:match("^currency:(%d+)$"))
        if id then candidates[id] = candidates[id] or {} end
    end
    local records = {}
    for id, metadata in pairs(candidates) do
        local r = self:CurrencyRecord(id, metadata)
        if r then
            records[#records + 1] = r
            if metadata.category == "Catalyst" and r.amount and r.amount > 0 then
                local task = Record("catalyst:charge", "weekly", "task", "Catalyst charge available", "Catalyst", r.icon)
                task.actionTitle = "Convert a piece at the Catalyst"
                task.reason = r.amount .. " charge" .. (r.amount == 1 and "" or "s") .. " • convert after choosing your Vault reward"
                task.tier, task.weight, task.recommend = 5, 55, true
                records[#records + 1] = task
            end
        end
    end
    table.sort(records, function(a, b) return a.id < b.id end)
    return records
end

Planner.providers.lockouts = function(self)
    local records, dailyReset = {}, self:ResetTime("daily")
    for index = 1, self:Call(_G, "GetNumSavedInstances") or 0 do
        local name, lockID, seconds, difficultyID, locked, extended, _, raid, _, difficulty, total, killed, _, mapID =
            self:Call(_G, "GetSavedInstanceInfo", index)
        if name and difficultyID and seconds and (locked or extended) and (seconds > 0 or extended) and total and total > 0 then
            local r = Record("instance:" .. tostring(mapID or lockID) .. ":" .. difficultyID, "lockouts", "lockout", name, "Lockouts", raid and 236423 or 463829)
            r.current, r.target = killed or 0, total
            r.expiresAt = seconds > 0 and self:Now() + seconds or nil
            r.cadence = r.expiresAt and dailyReset and r.expiresAt <= dailyReset + 2 and "daily" or "weekly"
            r.state = r.current >= r.target and "complete" or "active"
            r.detail = (difficulty or "") .. " • " .. r.current .. " / " .. r.target .. " bosses" .. (extended and " • Extended" or "")
            r.lines = {}
            for boss = 1, total do
                local bossName, _, defeated = self:Call(_G, "GetSavedInstanceEncounterInfo", index, boss)
                if bossName then r.lines[#r.lines + 1] = (defeated and "|A:common-icon-checkmark:12:12|a " or "") .. bossName end
            end
            local journalID = mapID and self:Call(C_EncounterJournal, "GetInstanceForGameMap", mapID)
            if journalID then r.destination = { type = "instance", id = journalID, difficulty = difficultyID, label = "Open in Guide" } end
            records[#records + 1] = r
        end
    end
    return records
end

Planner.providers.journeys = function(self)
    local records = {}
    for _, id in ipairs(self:Call(C_MajorFactions, "GetMajorFactionIDs", LE_EXPANSION_LEVEL_CURRENT) or {}) do
        id = Safe(id)
        if id and self:Call(C_MajorFactions, "IsMajorFactionHiddenFromExpansionPage", id) == false
            and self:Call(C_MajorFactions, "ShouldDisplayMajorFactionAsJourney", id) == true then
            local info = self:Call(C_MajorFactions, "GetMajorFactionData", id)
            local name = info and Safe(info.name)
            if name and Safe(info.isUnlocked) == true then
                local r = Record("journey:" .. id, "progress", "progress", name, "Journeys", "Interface\\Icons\\Achievement_Reputation_01")
                r.factionID = id
                r.current, r.target = Safe(info.renownReputationEarned), Safe(info.renownLevelThreshold)
                local maximum = self:Call(C_MajorFactions, "HasMaximumRenown", id) == true
                local capped = self:Call(C_MajorFactions, "IsWeeklyRenownCapped", id) == true
                r.state = maximum and "complete" or "active"
                r.detail = "Renown " .. (Safe(info.renownLevel) or "?") .. (capped and " • Weekly cap reached" or "")
                r.destination = { type = "journeys", id = id, label = "Open Journey" }
                records[#records + 1] = r
            end
        end
    end
    return records
end

-- Map events near the player: the current map and its parents only.
Planner.providers.events = function(self)
    local records, seen = {}, {}
    local mapID = self:Call(C_Map, "GetBestMapForUnit", "player")
    for _ = 1, 8 do
        if not mapID or mapID <= 0 or seen[mapID] then break end
        seen[mapID] = true
        for _, id in ipairs(self:Call(C_AreaPoiInfo, "GetEventsForMap", mapID) or {}) do
            id = Safe(id)
            local info = id and not seen["poi" .. id] and self:Call(C_AreaPoiInfo, "GetAreaPOIInfo", mapID, id)
            local name = info and Safe(info.name)
            if name and Safe(info.isLocked) ~= true then
                seen["poi" .. id] = true
                local r = Record("events:" .. id, "nearby", "context", name, "World events", "Interface\\Icons\\INV_Misc_Map_01")
                local position, x, y = Safe(info.position)
                if position then x, y = self:Call(position, "GetXY", position) end
                r.detail = Safe(info.isCurrentEvent) == true and "Happening now" or "On your map"
                r.destination = { type = "map", id = mapID, position = x and y and { x = x, y = y }, label = x and "Pin location" or "Open map" }
                local timed, hidden = self:Call(C_AreaPoiInfo, "IsAreaPOITimed", id)
                local seconds = timed == true and hidden == false and self:Call(C_AreaPoiInfo, "GetAreaPOISecondsLeft", id)
                if seconds and seconds > 0 then r.expiresAt, r.expirationMeaning = self:Now() + seconds, "Ends" end
                records[#records + 1] = r
            end
        end
        local info = self:Call(C_Map, "GetMapInfo", mapID)
        mapID = info and Safe(info.parentMapID)
    end
    return records
end
