local _, RefineUI = ...
local Planner = RefineUI.AdventurePlanner
local Registry, Model = RefineUI.PlannerRegistry, RefineUI.PlannerModel
local Number = RefineUI.PlannerEvidence.Number
local function Base(self, id, provider, kind, title, category, bucket, order)
    return { id = id, provider = provider, kind = kind, title = title, category = category, bucket = bucket,
        cadence = bucket, registryOrder = order, scope = "character", ownerKey = self.owner,
        observedAt = self:Now(), verification = "live", source = provider, state = "available" }
end

-- Expansion is relevance metadata, never availability evidence. The optional
-- global getter is not part of C_QuestLog; unavailable metadata stays unknown.
function Planner:ClassifyQuest(record, observed)
    local expansion
    if type(GetQuestExpansion) == "function" then expansion = self:Call(_G, "GetQuestExpansion", record.questID) end
    if not Number(expansion) or expansion < 0 or expansion % 1 ~= 0 then expansion = nil end
    if expansion == nil and observed then expansion = observed.expansionID end
    local metadata = Registry.quests[record.questID]
    if expansion == nil and metadata then expansion = metadata.expansion end
    local current = LE_EXPANSION_LEVEL_CURRENT
    record.expansionID = expansion
    if Number(current) and Number(expansion) and expansion <= current then
        record.contentEra = expansion < current and "legacy" or "current"
        local name = _G["EXPANSION_NAME" .. expansion]
        if RefineUI.PlannerEvidence.Accessible(name) and type(name) == "string" then record.expansionName = name end
        if observed then observed.expansionID = expansion end
    else record.contentEra = "unknown" end
    if record.contentEra ~= "current" then record.importance = "optional" end
end

function Planner:ObserveQuests()
    local periods = { daily = self:Period("daily"), weekly = self:Period("weekly") }
    local logged = {}
    local read = self:Read(C_QuestLog, "GetNumQuestLogEntries")
    local count = read.values and read.values[1]
    self.questCoverage = read.status == "known" and Number(count)
    count = Number(count) and count or 0
    for index = 1, count do
        local info = self:Call(C_QuestLog, "GetInfo", index)
        if not info or info._restricted then self.questCoverage = false end
        if info and Number(info.questID) and not info.isHeader then
            logged[info.questID] = true
            local cadence = info.frequency == Enum.QuestFrequency.Daily and "daily"
                or info.frequency == Enum.QuestFrequency.Weekly and "weekly"
                or Registry.quests[info.questID] and (Registry.quests[info.questID].cadence
                    or Registry.quests[info.questID].observationCadence)
            local scope = self:Call(C_QuestLog, "IsAccountQuest", info.questID) == true and "account" or "character"
            local period = cadence and (scope == "account" and self:Period(cadence, scope) or periods[cadence])
            if period then
                local entry = period.quests[info.questID] or {}
                entry.title, entry.observedAt = info.title, self:Now()
                entry.scope = scope
                entry.cadenceVerified = info.frequency == Enum.QuestFrequency.Daily or info.frequency == Enum.QuestFrequency.Weekly
                period.quests[info.questID] = entry
            end
        end
    end
    return logged
end

function Planner:ObserveTurnIn(questID)
    if not Number(questID) then return end
    for _, scope in ipairs({ "character", "account" }) do
    for _, cadence in ipairs({ "daily", "weekly" }) do
        local period = self:Period(cadence, scope)
        local entry = period and period.quests[questID]
        if entry then entry.completed = true; entry.completedAt = self:Now(); entry.observedAt = self:Now() end
    end
    end
end

local function QuestObjectives(self, id)
    local objectives = self:Call(C_QuestLog, "GetQuestObjectives", id) or {}
    local lines, current, target = {}, 0, 0
    local actions, known, unfinishedText = 0, #objectives > 0 and not objectives._incomplete, nil
    for _, objective in ipairs(objectives) do
        if objective.text then lines[#lines + 1] = objective.text end
        if Number(objective.numFulfilled) and Number(objective.numRequired) then
            current = current + math.min(objective.numFulfilled, objective.numRequired)
            target = target + objective.numRequired
        end
        if objective._restricted then known = false end
        if not objective.finished then
            -- Kill/object interactions count discrete actions. Item/currency,
            -- percentage and opaque progress objectives do not: one missing
            -- item or percentage point is not necessarily one gameplay action.
            local discrete = objective.type == "monster" or objective.type == "object"
            if discrete and Number(objective.numFulfilled) and Number(objective.numRequired)
                and objective.numRequired > objective.numFulfilled then
                actions = actions + objective.numRequired - objective.numFulfilled
                unfinishedText = objective.text
            else known = false end
        end
    end
    if #objectives == 0 or objectives._incomplete then current, target = nil, nil end
    return lines, current, target, known and actions > 0 and actions or nil, unfinishedText
end

local function NeedsDiscovery(self, questIDs, offered, logged, oneTime)
    -- A missing log entry is not evidence of an available quest. This only
    -- decides whether a labelled check-the-giver lead is still useful.
    if not self.questCoverage then return false end
    for _, id in ipairs(questIDs) do
        -- A one-time catch-up lead needs an explicit lifetime-incomplete answer.
        -- Nil/restricted data must not resurface it every weekly reset.
        if oneTime and self:Call(C_QuestLog, "IsQuestFlaggedCompleted", id) ~= false then return false end
        if offered[id] or logged[id] or self:Call(C_QuestLog, "IsOnQuest", id) == true then return false end
        for _, scope in ipairs({ "character", "account" }) do
            local period = self:Period("weekly", scope)
            local observed = period and period.quests[id]
            if observed and observed.completed then return false end
        end
    end
    return true
end

local function Discovery(self, definition, title, detail, icon)
    local r = Base(self, "discovery:" .. definition.key, "quests", "Discovery", title,
        definition.category, "weekly", 500)
    r.state, r.verification = "candidate", "registry"
    if definition.oneTime then r.cadence, r.oneTime = "none", true end
    r.questIDs, r.minLevel = definition.questIDs, definition.minLevel
    local period = self:Period("weekly")
    r.resetKey, r.validUntil = period and period.reset, period and period.reset
    r.icon, r.recommendationWeight = icon or 134400, definition.weight
    r.destination = { type = "map", id = definition.mapID, position = definition.position,
        label = definition.position and "Pin quest giver" or "Open zone map" }
    r.detail = detail .. (definition.accessNote and " • " .. definition.accessNote or "")
    r.source = definition.source or "MidnightHelper ResetRoutine catalogue"
    return r
end

Planner.providers.quests = function(self)
    local logged = self:ObserveQuests()
    local offered = {}
    for _, mapID in ipairs({ 2393, 2395, 2437, 2413, 2405, 2509, 2512 }) do
        local quests = self:Call(C_QuestLine, "GetAvailableQuestLines", mapID)
        if type(quests) == "table" and not (HasSecretValues and HasSecretValues(quests)) then
            for _, info in ipairs(quests) do
                local id = info.questID
                local metadata = Number(id) and Registry.quests[id]
                if metadata and (metadata.weeklyQuest or metadata.oneTime) and not info._restricted and not info.isHidden then
                    local scope = self:Call(C_QuestLog, "IsAccountQuest", id) == true and "account" or "character"
                    local period = self:Period("weekly", scope)
                    local title = self:Call(C_QuestLog, "GetTitleForQuestID", id)
                    if period and title then
                        offered[id] = mapID
                        period.quests[id] = period.quests[id] or { title = title,
                            scope = scope, observedAt = self:Now() }
                    end
                end
            end
        end
    end
    -- A small registered world-quest set can be offered before acceptance, but
    -- only when the client's visible map tasks also include it. Global rotation
    -- alone does not establish availability for this character.
    local worldActive, mapTasks = {}, {}
    for id, metadata in pairs(Registry.quests) do
        if metadata.activeWorldQuest and self:Call(C_TaskQuest, "IsActive", id) == true then
            local mapID = metadata.mapID
            if mapID and not mapTasks[mapID] then
                local visible = {}
                for _, poi in ipairs(self:GetMapTasks(mapID) or {}) do
                    if poi.questID and not poi._restricted and not poi.isHidden then visible[poi.questID] = true end
                end
                mapTasks[mapID] = visible
            end
            local minutes = self:Call(C_TaskQuest, "GetQuestTimeLeftSeconds", id)
            local title = self:Call(C_TaskQuest, "GetQuestInfoByQuestID", id)
            local period = self:Period(metadata.cadence)
            if mapID and mapTasks[mapID][id] and period and title and Number(minutes) and minutes > 0 then
                worldActive[id] = { title = title, expiresAt = self:Now() + minutes }
                period.quests[id] = period.quests[id] or { title = title, scope = "character", observedAt = self:Now() }
            end
        end
    end
    local records = {}
    local keyQuests = {}
    for _, mapID in ipairs({ 2395, 2437, 2413, 2405, 2509, 2512 }) do
        local tasks = self:GetMapTasks(mapID)
        if type(tasks) == "table" and not (HasSecretValues and HasSecretValues(tasks)) then
            for _, poi in ipairs(tasks) do
                local id = poi.questID
                if Number(id) and not keyQuests[id] and not poi._restricted and not poi.isHidden and self:Call(C_TaskQuest, "IsActive", id) == true then
                    self:Call(C_TaskQuest, "RequestPreloadRewardData", id)
                    local rewards = self:Call(C_QuestLog, "GetQuestRewardCurrencies", id) or {}
                    for _, reward in ipairs(rewards) do
                        if Number(reward.currencyID) and (reward.currencyID == 3028 or reward.currencyID == 3310) then
                            local minutes = self:Call(C_TaskQuest, "GetQuestTimeLeftSeconds", id)
                            local title = self:Call(C_TaskQuest, "GetQuestInfoByQuestID", id)
                            if title and Number(minutes) and minutes > 0 then
                                local r = Base(self, "quest:" .. id, "quests", "Activity", title, "Delves", "weekly", 205)
                                r.cadence, r.questID, r.icon = "explicit-expiry", id, 134241
                                r.expiryVerified = true
                                r.expiresAt = self:Now() + minutes
                                r.validUntil, r.rewardAvailable = r.expiresAt, true
                                r.detail = reward.currencyID == 3028 and "Rewards a Restored Coffer Key" or "Rewards Coffer Key Shards"
                                r.rewardReason = r.detail
                                r.destination = { type = "map", id = mapID, label = "Track quest" }
                                r.recommendable, r.recommendationWeight, r.rewardClass = true, 72, "cofferKey"
                                keyQuests[id] = r
                            end
                        end
                    end
                end
            end
        end
    end
    local activePrey = self:Call(C_QuestLog, "GetActivePreyQuest")
    for _, scope in ipairs({ "account", "character" }) do
    for _, cadence in ipairs({ "daily", "weekly" }) do
        local period = self:Period(cadence, scope)
        for id, observed in pairs(period and period.quests or {}) do
            local metadata = Registry.quests[id]
            local onQuest = self:Call(C_QuestLog, "IsOnQuest", id)
            local r = Base(self, "quest:" .. id, "quests", "Activity", observed.title or ("Quest " .. id),
                metadata and metadata.category or "Quests", cadence, 200)
            r.scope, r.questID, r.icon = observed.scope or "character", id, metadata and metadata.icon or 134400
            r.ownerKey = scope == "account" and "account" or self.owner
            r.rewardClass = metadata and metadata.rewardClass
            r.oneTime = metadata and metadata.oneTime
            r.importance = metadata and metadata.optional and "optional" or nil
            r.professionSkillLineID = metadata and metadata.professionSkillLineID
            if id == activePrey then r.category, r.contentType = "Prey", "prey" end
            r.validUntil, r.resetKey = period.reset, period.reset
            r.cadence = not (metadata and metadata.oneTime) and observed.cadenceVerified and cadence or "none"
            r.weeklyQuest = not (metadata and metadata.oneTime) and observed.cadenceVerified
                and cadence == "weekly" and not (metadata and metadata.activeWorldQuest)
            r.destination = onQuest and { type = "quest", id = id, label = "Track quest" } or nil
            r.rewardReason = observed.cadenceVerified and (cadence == "daily" and "Daily quest reward" or "Weekly quest reward") or "Quest reward"
            if metadata and metadata.rewardClass == "spark" then
                r.rewardReason = "Potential Spark Dust • season cap applies"
            elseif metadata and metadata.oneTime then
                r.rewardReason = "One-time Spark catch-up • season cap applies"
            end
            r.source = "C_QuestLog.IsOnQuest / ReadyForTurnIn"
            r.rewardAvailable = onQuest == true
            local completion, verification = Model.Resolve({
                { ownerKey = r.ownerKey, resetKey = r.resetKey, validUntil = r.validUntil,
                    completed = nil, verification = "live", source = "C_QuestLog.IsOnQuest" },
                { ownerKey = r.ownerKey, resetKey = r.resetKey, validUntil = r.validUntil,
                    completed = observed.completed, verification = "observed", source = "QUEST_TURNED_IN" },
            }, "completed", r.ownerKey, r.resetKey, self:Now())
            if metadata and metadata.oneTime and self:Call(C_QuestLog, "IsQuestFlaggedCompleted", id) == true then
                completion, verification = true, "live"
            end
            if completion then
                r.state, r.verification, r.detail = "complete", verification,
                    metadata and metadata.oneTime and "Completed" or "Completed this reset"
                r.source, r.observedAt = metadata and metadata.oneTime and verification == "live"
                    and "C_QuestLog.IsQuestFlaggedCompleted" or "QUEST_TURNED_IN", observed.completedAt or observed.observedAt
                r.destination = nil
            elseif onQuest or worldActive[id] then
                local ready = self:QuestReady(id)
                r.state = ready == true and "ready" or ready == false and "inProgress" or "unknown"
                local objectiveText
                r.objectives, r.current, r.target, r.remainingActions, objectiveText = QuestObjectives(self, id)
                r.detail = r.state == "ready" and "Reward ready • Turn in this quest" or table.concat(r.objectives, " • ")
                if r.detail == "" then r.detail = "In progress" end
                local total, elapsed = self:Call(C_QuestLog, "GetTimeAllowed", id)
                if Number(total) and Number(elapsed) and total > elapsed then r.expiresAt = self:Now() + total - elapsed; r.expiryVerified = true end
                r.actionTitle = r.state == "ready" and ("Turn in " .. r.title) or r.title
                if r.state ~= "ready" and r.remainingActions == 1 and objectiveText then
                    r.rewardReason = "One action remaining • " .. objectiveText
                end
                if ready == nil then
                    r.verification, r.detail, r.remainingActions = "unknown", "Progress unavailable", nil
                end
                if worldActive[id] then
                    r.expiryVerified = true
                    r.expiresAt = worldActive[id].expiresAt
                    r.destination = { type = "map", id = metadata.mapID, label = "Track quest" }
                    if ready == false and not onQuest then r.state = "available" end
                    r.rewardAvailable = ready ~= nil
                end
            elseif offered[id] then
                r.state, r.verification, r.detail = "available", "live", "Available • Pick up this quest"
                r.source = "C_QuestLine.GetAvailableQuestLines"
                r.rewardAvailable = true
                r.actionTitle = "Pick up " .. r.title
                local pickup = Registry.pickupByQuestID and Registry.pickupByQuestID[id]
                r.destination = { type = "map", id = offered[id],
                    position = pickup and pickup.mapID == offered[id] and pickup.position or nil,
                    label = pickup and pickup.mapID == offered[id] and "Pin quest giver" or "Open zone map" }
            else
                r.state, r.verification, r.detail = "unknown", "unknown", "Not in quest log"
                if metadata and metadata.mapID then r.destination = { type = "map", id = metadata.mapID, label = "Map" } end
            end
            if keyQuests[id] then
                r.rewardReason = keyQuests[id].rewardReason
                r.rewardClass, r.recommendationWeight = "cofferKey", 72
                keyQuests[id] = nil
            end
            local tag = self:Call(C_QuestLog, "GetQuestTagInfo", id)
            if tag and Number(tag.tradeskillLineID) and tag.tradeskillLineID > 0 then
                r.category, r.professionSkillLineID = "Professions", tag.tradeskillLineID
            end
            r.factionRewards = self:Call(C_QuestLog, "GetQuestLogMajorFactionReputationRewards", id) or {}
            self:ClassifyQuest(r, observed)
            -- Recommendation eligibility is explicit. A live accepted quest, a
            -- character-specific world task, or a presently offered registered
            -- weekly can be acted on; an old observation cannot.
            r.recommendable = (onQuest == true or worldActive[id] ~= nil or offered[id] ~= nil)
                and r.state ~= "unknown" and r.state ~= "complete"
            r.recommendationWeight = r.recommendationWeight
                or r.rewardClass == "spark" and 90
                or r.rewardClass == "sparkCatchUp" and 80
                or r.rewardClass == "professionKnowledge" and 78
                or metadata and metadata.activeWorldQuest and 74
                or (r.weeklyQuest or (metadata and metadata.weeklyQuest)) and 58
                or cadence == "daily" and 42
                or 35
            records[#records + 1] = r
        end
    end
    end
    for _, r in pairs(keyQuests) do self:ClassifyQuest(r); records[#records + 1] = r end
    local level = self:Call(_G, "UnitLevel", "player")
    if Number(level) then
        for _, definition in ipairs(Registry.discovery or {}) do
            if level >= definition.minLevel and NeedsDiscovery(self, definition.questIDs, offered, logged, definition.oneTime) then
                records[#records + 1] = Discovery(self, definition,
                    "Check " .. definition.giver, definition.reward, definition.icon)
            end
        end
        if level >= 90 and type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
            local first, second = self:Call(_G, "GetProfessions")
            local seen = {}
            for _, slot in ipairs({ first, second }) do
                if Number(slot) then
                    local name, icon, skill, _, _, _, skillLine = self:Call(_G, "GetProfessionInfo", slot)
                    local ids = Number(skillLine) and Registry.professionWeeklies[skillLine]
                    local service = Registry.professionServices[skillLine]
                    if ids and not seen[skillLine] and (service or Number(skill) and skill >= 25)
                        and NeedsDiscovery(self, ids, offered, logged) then
                        seen[skillLine] = true
                        local definition = { key = "profession:" .. skillLine, questIDs = ids, mapID = 2393,
                            position = Registry.professionPickupPoints[skillLine],
                            category = "Professions", minLevel = 90, weight = 78 }
                        records[#records + 1] = Discovery(self, definition,
                            "Check " .. (name or "profession") .. " weekly",
                            "Potential Knowledge • " .. (service and "Work Order station" or "profession trainer"), icon)
                    end
                end
            end
        end
    end
    if not self.questCoverage then
        local r = Base(self, "quests:coverage", "quests", "Progress", "Quest log coverage", "Quests", "weekly", 0)
        r.state, r.verification, r.coverageRequired = "unknown", "unknown", true
        r.detail = "Quest log partly unavailable • Existing observations are retained"
        records[#records + 1] = r
    end
    return records
end

Planner.providers.vault = function(self)
    local records, types = {}, Enum.WeeklyRewardChestThresholdType
    local vaultActions = {}
    local reset = self:ResetTime("weekly")
    local waiting = self:Call(C_WeeklyRewards, "HasAvailableRewards")
    local currentPeriod = self:Call(C_WeeklyRewards, "AreRewardsForCurrentRewardPeriod")
    local tracks = { { types.Raid, "Raids", "raid bosses", 236423 },
        { types.Activities, "Dungeons", "dungeons", 463829 }, { types.World, "World & delves", "world activities or delves", 6025441 } }
    for index, track in ipairs(tracks) do
        local progress = Base(self, "vault:track:" .. index, "vault", "Progress", track[2], "Great Vault", "weekly", 10 + index * 2)
        progress.destination = { type = "vault", label = "Vault" }; progress.icon = track[4]
        progress.validUntil = reset; progress.milestones = {}; progress.unit = track[3]
        local activities = self:Call(C_WeeklyRewards, "GetActivities", track[1])
        local sorted = {}
        for _, activity in ipairs(activities or {}) do
            if Number(activity.threshold) and Number(activity.progress) and activity.threshold > 0 then sorted[#sorted + 1] = activity end
        end
        table.sort(sorted, function(a, b) return a.threshold < b.threshold end)
        local nextActivity, unlocked = nil, 0
        for _, activity in ipairs(sorted) do
            local reached = activity.progress >= activity.threshold
            local link, upgradeLink = self:Call(C_WeeklyRewards, "GetExampleRewardItemHyperlinks", activity.id)
            local itemLevel = link and self:Call(C_Item, "GetDetailedItemLevelInfo", link)
            if link and not itemLevel then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID then self.pendingItems[itemID] = true; self:Call(C_Item, "RequestLoadItemDataByID", itemID) end
            end
            progress.milestones[#progress.milestones + 1] = { current = activity.progress, target = activity.threshold,
                reached = reached, itemLevel = itemLevel, link = link, upgradeLink = upgradeLink, level = activity.level, activityTierID = activity.activityTierID }
            if reached then unlocked = unlocked + 1 elseif not nextActivity then nextActivity = activity end
        end
        progress.current, progress.target = unlocked, #sorted
        progress.state = #sorted > 0 and not activities._incomplete and "available" or "unknown"
        if waiting ~= false and currentPeriod ~= true then progress.state = "unknown" end
        if progress.state == "unknown" then progress.verification = "unknown" end
        progress.coverageRequired = true
        progress.detail = #sorted > 0 and (unlocked .. " / " .. #sorted .. " options unlocked") or "Progress unavailable"
        if progress.state == "unknown" then progress.detail = "Vault progress unavailable" end
        progress.rewardReason = "Unlock reward choices for your next Great Vault"
        progress.source = "C_WeeklyRewards.GetActivities"
        records[#records + 1] = progress
        if #sorted > 0 and not activities._incomplete and reset and (waiting == false or currentPeriod == true) then
            local task = Model.Copy(progress)
            task.id, task.kind, task.registryOrder = "vault:next:" .. index, "Progress", progress.registryOrder + 1
            task.goalType, task.outcomeID = "vault", task.id
            task.milestones = nil; task.title = track[2] .. " • Great Vault"
            task.icon, task.expiresAt = track[4], reset
            if nextActivity then
                task.current, task.target = nextActivity.progress, nextActivity.threshold
                task.remainingProgress = nextActivity.threshold - nextActivity.progress
                task.state = task.current > 0 and "inProgress" or "available"
                task.activityTierID, task.activityID = nextActivity.activityTierID, nextActivity.id
                task.goalType, task.outcomeID = "vault", task.id
                task.actionable = false
                task.detail = task.current .. " / " .. task.target .. " • Unlocks next reward slot"
                local remaining = task.target - task.current
                if remaining > 0 then
                    local singular, plural = index == 1 and "qualifying raid boss" or index == 2 and "qualifying dungeon" or "qualifying world activity or delve",
                        index == 1 and "qualifying raid bosses" or index == 2 and "qualifying dungeons" or "qualifying world activities or delves"
                    local action = Model.Copy(task)
                    action.id, action.kind, action.goalID = "vault:action:" .. index, "Activity", task.id
                    action.title = "Unlock the next " .. track[2] .. " Vault choice"
                    action.actionTitle = "Complete " .. remaining .. " more " .. (remaining == 1 and singular or plural)
                    action.state, action.actionable, action.recommendable =
                        task.current > 0 and "inProgress" or "available", true, true
                    action.destination = { type = "vault", label = "Vault" }
                    action.rewardReason = "Unlocks your next Great Vault reward choice"
                    action.recommendationWeight, action.rewardClass = 82, "vaultMilestone"
                    action.remainingActions = remaining
                    action.effort = { unit = track[3], count = remaining }
                    action.facts = Model.Copy(task.facts or {})
                    vaultActions[#vaultActions + 1] = action
                end
            else
                task.state, task.detail = "complete", "All reward options unlocked"
            end
            records[#records + 1] = task
        end
    end
    local reward = waiting
    if reward then
        local claim = Base(self, "vault:claim", "vault", "Activity", "Collect your Great Vault reward", "Great Vault", "weekly", 1)
        claim.state = "claimable"; claim.icon = 1518642; claim.destination = { type = "vault", label = "Vault" }
        claim.recommendable, claim.recommendationWeight, claim.rewardClass = true, 100, "vaultClaim"
        claim.hasInteraction = self:Call(C_WeeklyRewards, "HasInteraction")
        claim.canClaim = self:Call(C_WeeklyRewards, "CanClaimRewards")
        claim.detail = claim.hasInteraction == true and claim.canClaim == true and "Reward ready • Choose at the Vault" or "Reward waiting • Visit the Great Vault to collect; remote preview may be read-only"
        claim.rewardReason = "A Great Vault reward is waiting to be collected"
        local E = RefineUI.PlannerEvidence
        claim.source = "C_WeeklyRewards.HasAvailableRewards"
        claim.facts = { rewardWaiting = E.Fact(claim, "rewardWaiting", reward),
            interaction = E.Fact(claim, "interaction", claim.hasInteraction, "C_WeeklyRewards.HasInteraction"),
            claimReady = E.Fact(claim, "claimReady", claim.canClaim, "C_WeeklyRewards.CanClaimRewards") }
        records[#records + 1] = claim
    end
    -- One Vault action is enough for the weekly headline. Prefer the closest
    -- measured milestone, then the stable track order. The remaining tracks stay
    -- visible as progress without monopolizing all recommendation slots.
    table.sort(vaultActions, function(a, b)
        if a.remainingActions ~= b.remainingActions then return a.remainingActions < b.remainingActions end
        return a.id < b.id
    end)
    if vaultActions[1] then records[#records + 1] = vaultActions[1] end
    return records
end

Planner.providers.instances = function(self)
    if not self.instanceReady then
        return { { id = "instances:status", provider = "instances", kind = "Progress", category = "Lockouts", bucket = "weekly",
            title = "Instance lockouts", state = self.instanceRequest and "loading" or "unknown", verification = "unknown",
            detail = self.instanceRequest and "Checking progress…" or "Progress unavailable", registryOrder = 99 } }
    end
    local records, daily = {}, self:ResetTime("daily")
    for index = 1, self:Call(_G, "GetNumSavedInstances") or 0 do
        local name, lockID, seconds, difficultyID, locked, extended, _, raid, _, difficulty, total, killed, _, mapID = self:Call(_G, "GetSavedInstanceInfo", index)
        if Number(difficultyID) and (Number(mapID) or Number(lockID)) and type(name) == "string" and Number(seconds) and (locked or extended) and (seconds > 0 or extended) then
            local expiry = seconds > 0 and self:Now() + seconds or nil
            local bucket = expiry and daily and expiry <= daily + 2 and "daily" or "weekly"
            local r = Base(self, "instance:" .. tostring(mapID or lockID) .. ":" .. difficultyID, "instances",
                "Progress", name, "Lockouts", bucket, 100)
            r.cadence, r.current, r.target = "explicit-expiry", killed or 0, total or 0
            r.expiresAt, r.validUntil, r.icon = expiry, expiry, 236423
            r.state = r.target > 0 and (r.current >= r.target and "complete" or "inProgress") or "unknown"
            r.detail = string.format("%s • %d / %d bosses%s", difficulty or "", r.current, r.target, extended and " • Extended save" or "")
            r.rewardReason = extended and "Extended lockout; not a record of this week's kills" or "Saved instance progress by difficulty"
            -- Lockout state alone does not prove per-boss personal loot eligibility.
            r.rewardAvailable = false; r.bosses = {}
            for boss = 1, r.target do
                local bossName, _, defeated = self:Call(_G, "GetSavedInstanceEncounterInfo", index, boss)
                if bossName then r.bosses[#r.bosses + 1] = { title = bossName, complete = defeated } end
            end
            local journalID = mapID and self:Call(C_EncounterJournal, "GetInstanceForGameMap", mapID)
            if journalID then r.destination = { type = "instance", id = journalID, difficulty = difficultyID, raid = raid, label = "Guide" } end
            records[#records + 1] = r
        end
    end
    return records
end

function Planner:CurrencyRecord(id, info, metadata)
    if not info or not info.name or info.isTypeUnused or not info.discovered then return end
    local r = Base(self, "currency:" .. id, "resources", "Resource", info.name,
        metadata and metadata.category or "Currencies", "weekly", 400)
    r.currencyID, r.quantity, r.icon = id, info.quantity, info.iconFileID
    r.scope = info.isAccountWide and "account" or "character"
    r.ownerKey = r.scope == "account" and "account" or self.owner
    r.source = "C_CurrencyInfo.GetCurrencyInfo"
    local E = RefineUI.PlannerEvidence
    r.facts = { holdings = E.Field(r, info, "quantity"), weeklyEarned = E.Field(r, info, "quantityEarnedThisWeek"),
        weeklyCap = E.Field(r, info, "maxWeeklyQuantity"), totalEarned = E.Field(r, info, "totalEarned"),
        capacity = E.Field(r, info, "maxQuantity") }
    r.destination = { type = "currency", id = id, label = "Details" }
    r.rewardReason = info.description
    local parts = {}
    if metadata and metadata.category == "Sparks" then
        r.quantity = nil -- the counter is not an inventory balance
        r.heldItemID = metadata.heldItemID
        local itemName = self:Call(C_Item, "GetItemNameByID", metadata.heldItemID)
        if itemName then r.title = itemName else self.pendingItems[metadata.heldItemID] = true end
        local held = self:Call(C_Item, "GetItemCount", metadata.heldItemID, true, false, true, true)
        if Number(held) then r.held = held end
        r.facts.holdings = E.Fact(r, "holdings", r.held, "C_Item.GetItemCount (bags and banks)", "live")
        if info.useTotalEarnedForMaxQty and Number(info.totalEarned) and Number(info.maxQuantity) and info.maxQuantity > 0 then
            r.seasonEarned, r.seasonCap = info.totalEarned, info.maxQuantity
            r.catchUpRemaining = math.max(0, r.seasonCap - r.seasonEarned)
            r.detail = string.format("%d / %d earned this season • %s", r.seasonEarned, r.seasonCap,
                r.catchUpRemaining == 0 and "Caught up" or (r.catchUpRemaining .. " behind current cap"))
            if r.held then r.detail = r.detail .. " • " .. r.held .. " across bags and banks (including account bank)" end
            r.validUntil = self:ResetTime("weekly")
        else
            r.state, r.verification, r.detail = "unknown", "unknown", "Spark acquisition progress unavailable"
        end
        return r
    end
    if Number(info.maxWeeklyQuantity) and info.maxWeeklyQuantity > 0 and Number(info.quantityEarnedThisWeek) then
        r.weeklyEarned, r.weeklyCap = info.quantityEarnedThisWeek, info.maxWeeklyQuantity
        parts[#parts + 1] = r.weeklyEarned .. " / " .. r.weeklyCap .. " earned this week"
        r.validUntil = self:ResetTime("weekly")
    end
    if info.useTotalEarnedForMaxQty and Number(info.maxQuantity) and info.maxQuantity > 0 and Number(info.totalEarned) then
        r.seasonEarned, r.seasonCap = info.totalEarned, info.maxQuantity
        parts[#parts + 1] = r.seasonEarned .. " / " .. r.seasonCap .. " total earned"
    end
    if metadata and metadata.category == "Catalyst" then
        r.charges, r.maxCharges = info.quantity, info.maxQuantity
        parts[#parts + 1] = Number(info.quantity) and (info.quantity .. " Catalyst charges") or "Charges unavailable"
        -- ItemInteraction charge data belongs to the active conversion system.
        -- Never apply another interaction's recharge timer to this currency.
        local interaction = self:Call(C_ItemInteraction, "GetItemInteractionInfo")
        if interaction and interaction.currencyTypeId == id then
            local charge = self:Call(C_ItemInteraction, "GetChargeInfo")
            if charge and Number(charge.timeToNextCharge) and charge.timeToNextCharge > 0 then
                r.nextRechargeAt = self:Now() + charge.timeToNextCharge
                r.rechargeRate = Number(charge.rechargeRate) and charge.rechargeRate or nil
                r.newChargeAmount = Number(charge.newChargeAmount) and charge.newChargeAmount or nil
                parts[#parts + 1] = "Next charge in " .. math.ceil(charge.timeToNextCharge / 3600) .. "h"
            end
        end
    else parts[#parts + 1] = Number(info.quantity) and (info.quantity .. " held") or "Quantity unavailable" end
    if not Number(info.quantity) then
        r.quantity, r.charges = nil, nil
        r.state, r.verification = "unknown", "unknown"
    end
    r.detail = table.concat(parts, " • ")
    return r
end

Planner.providers.resources = function(self)
    local _, _, _, build = self:Call(_G, "GetBuildInfo")
    local candidates = Registry.ResourceIDs(tonumber(build) or 0)
    -- Read visible currency rows without expanding headers or changing the
    -- player's currency-list filters. Seasonal candidates cover collapsed rows.
    for index = 1, self:Call(C_CurrencyInfo, "GetCurrencyListSize") or 0 do
        local info = self:Call(C_CurrencyInfo, "GetCurrencyListInfo", index)
        if info and not info.isHeader then
            local link = self:Call(C_CurrencyInfo, "GetCurrencyListLink", index)
            local id = link and self:Call(C_CurrencyInfo, "GetCurrencyIDFromLink", link)
            if id and Number(info.maxWeeklyQuantity) and info.maxWeeklyQuantity > 0 then candidates[id] = candidates[id] or {} end
        end
    end
    local db = self:Database()
    for key in pairs(db and db.preferences.pins or {}) do
        local id = tonumber(key:match("^currency:(%d+)$"))
        if id then candidates[id] = candidates[id] or {} end
    end
    local records = {}
    for id, metadata in pairs(candidates) do
        local r = self:CurrencyRecord(id, self:Call(C_CurrencyInfo, "GetCurrencyInfo", id), metadata)
        if r then records[#records + 1] = r end
    end
    return records
end
