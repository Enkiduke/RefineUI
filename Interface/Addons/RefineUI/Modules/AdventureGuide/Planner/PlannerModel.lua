-- Pure projection rules: no API reads, persistence, or UI mutations here.
local _, RefineUI = ...
local Model = {}
RefineUI.PlannerModel = Model
local actionable = { claimable = true, ready = true, available = true, inProgress = true }
local authority = { live = 4, observed = 3, snapshot = 2, registry = 1, unknown = 0 }

function Model.Copy(record)
    local result = {}
    for key, value in pairs(record) do result[key] = value end
    return result
end

-- Evidence is explicit: false is a value, nil is no answer. Callers must not
-- treat an absent quest-log entry as a live completion=false observation.
function Model.Resolve(evidence, field, owner, resetKey, now)
    local best, rank
    for _, item in ipairs(evidence) do
        local value = item[field]
        local valid = item.ownerKey == owner and item.resetKey == resetKey
            and (not item.validUntil or item.validUntil > now)
        local score = authority[item.verification] or 0
        if valid and value ~= nil and (not rank or (item.observedAt or 0) > (best.observedAt or 0) or ((item.observedAt or 0) == (best.observedAt or 0) and score > rank)) then
            best, rank = item, score
        end
    end
    if best then return best[field], best.verification, best.source end
    return nil, "unknown"
end

function Model.IsVerified(record, now)
    return (record.verification == "live" or record.verification == "observed")
        and (not record.validUntil or record.validUntil > now)
        and (not record.expiresAt or record.expiresAt > now)
end

-- Provider records contain only accessible fields. Facts are independently
-- overridden by adapters whenever availability and progress have different sources.
function Model.Prepare(source)
    local r, E = Model.Copy(source), RefineUI.PlannerEvidence
    r.facts = Model.Copy(source.facts or {})
    if not r.facts.progress then
        local known = r.state ~= "unknown" and r.state ~= "loading" and r.state ~= "locked"
        r.facts.progress = E.Fact(r, "progress", known and r.state or nil)
    end
    if not r.facts.availability then
        r.facts.availability = E.Fact(r, "availability", actionable[r.state] == true and r.destination ~= nil and r.actionable ~= false)
    end
    r.factionRewards = {}
    for _, original in ipairs(source.factionRewards or {}) do
        local reward = Model.Copy(original)
        r.factionRewards[#r.factionRewards + 1] = reward
        reward.evidence = reward.evidence or E.Fact(r, "factionReward", reward.rewardAmount, "C_QuestLog.GetQuestLogMajorFactionReputationRewards")
    end
    return r
end

local function Stable(a, b)
    if (a.customOrder or 9999) ~= (b.customOrder or 9999) then return (a.customOrder or 9999) < (b.customOrder or 9999) end
    if (a.registryOrder or 9999) ~= (b.registryOrder or 9999) then
        return (a.registryOrder or 9999) < (b.registryOrder or 9999)
    end
    return a.id < b.id
end

function Model.Build(records, preferences, now, dailyReset)
    preferences = preferences or {}
    local view = { daily = {}, weekly = {}, resources = {}, discoveries = {}, context = {}, snapshots = {}, completed = {}, nextUp = {}, overflow = {},
        counts = { daily = 0, weekly = 0, ready = 0, completed = 0, pinnedCompleted = 0, legacy = 0, optional = 0 }, byID = {} }
    local candidates, seen, prepared = {}, {}, {}
    local preparedIDs = {}
    for _, source in ipairs(records) do
        if not preparedIDs[source.id] then prepared[#prepared + 1] = Model.Prepare(source); preparedIDs[source.id] = true end
    end
    view.goals, view.goalsByID = RefineUI.PlannerGoals.Build(prepared, now)
    local opportunities, opportunitiesByID = RefineUI.PlannerOpportunities.Build(prepared, view.goalsByID, preferences, now, dailyReset)
    view.opportunities = opportunities
    view.coverage = { unknown = 0, incomplete = 0, complete = 0 }
    local priorityGoals = 0
    for _, goal in ipairs(view.goals) do
        if goal.importance ~= "optional" or (preferences.focus and preferences.focus[goal.recordID]) then
            priorityGoals = priorityGoals + 1
            view.coverage[goal.state] = view.coverage[goal.state] + 1
        end
    end
    for _, r in ipairs(prepared) do
        if r.coverageRequired and not Model.IsVerified(r, now) then view.coverage.unknown = view.coverage.unknown + 1 end
    end
    view.caughtUp = priorityGoals > 0 and view.coverage.unknown == 0 and view.coverage.complete == priorityGoals
    view.emptyMessage = view.caughtUp and "Caught up on tracked priority goals" or "No clear next step right now"
    for _, source in ipairs(prepared) do
        if not seen[source.id] then
            seen[source.id] = true
            local r = Model.Copy(source)
            r.customOrder = preferences.order and preferences.order[r.id]
            r.focused = preferences.focus and preferences.focus[r.id] or false
            r.pinned = preferences.pins and preferences.pins[r.id] or false
            r.hidden = (preferences.hidden and preferences.hidden[r.id])
                or (preferences.categories and preferences.categories[r.category]) or false
            if r.kind == "Discovery" and r.resetKey and preferences.dismissedLeads
                and preferences.dismissedLeads[r.id] == r.resetKey then r.hidden = true end
            local filters = preferences.filters or {}
            local mode = filters.mode
            if filters.hideResources and r.kind == "Resource" then r.hidden = true end
            local verified = Model.IsVerified(r, now)
            if mode == "pinned" and not r.pinned then r.hidden = true end
            if mode == "actionable" and not (r.kind == "Activity" and actionable[r.state] and verified) then r.hidden = true end
            if mode == "ready" and not (verified and (r.state == "ready" or r.state == "claimable")) then r.hidden = true end
            if mode == "expiring" and not (r.kind == "Activity" and actionable[r.state] and verified and r.expiryVerified and r.expiresAt and dailyReset and r.expiresAt <= dailyReset) then r.hidden = true end
            if filters.hideUnavailable and (not verified or r.state == "unknown" or r.state == "loading" or r.state == "locked") then r.hidden = true end
            if filters.search and filters.search ~= "" and not ((r.title or "") .. " " .. (r.category or "")):lower():find(filters.search:lower(), 1, true) then r.hidden = true end
            if not r.hidden and r.state ~= "inactive" and (r.state ~= "locked" or r.pinned or r.kind == "Context") then
                if r.kind ~= "Discovery" and not Model.IsVerified(r, now) and r.state ~= "loading" and r.state ~= "locked"
                    and (r.verification ~= "snapshot" or (r.validUntil and r.validUntil <= now)) then
                    r.state = "unknown"
                end
                view.byID[r.id] = r
                if r.kind == "Resource" then
                    view.resources[#view.resources + 1] = r
                elseif r.kind == "Discovery" then
                    view.discoveries[#view.discoveries + 1] = r
                elseif r.kind == "Context" then
                    view.context[#view.context + 1] = r
                elseif r.kind == "Snapshot" then
                    view.snapshots[#view.snapshots + 1] = r
                elseif r.kind == "Activity" and r.state == "complete" then
                    view.counts.completed = view.counts.completed + 1
                    if r.pinned then
                        view.counts.pinnedCompleted = view.counts.pinnedCompleted + 1
                        table.insert(view[r.bucket or "weekly"], r)
                    else table.insert(view.completed, r) end
                else
                    table.insert(view[r.bucket or "weekly"], r)
                    if r.kind == "Activity" and actionable[r.state] and Model.IsVerified(r, now) then
                        local bucket = r.bucket or "weekly"
                        if r.importance == "optional" and not r.focused then bucket = r.contentEra == "legacy" and "legacy" or "optional" end
                        view.counts[bucket] = view.counts[bucket] + 1
                        if bucket ~= "legacy" and bucket ~= "optional" and (r.state == "claimable" or r.state == "ready") then view.counts.ready = view.counts.ready + 1 end
                        local opportunity = opportunitiesByID[r.id]
                        if opportunity then candidates[#candidates + 1] = opportunity end
                    end
                end
            end
        end
    end
    for _, key in ipairs({ "daily", "weekly", "resources", "context", "snapshots", "completed" }) do table.sort(view[key], Stable) end
    table.sort(view.discoveries, function(a, b)
        if a.pinned ~= b.pinned then return a.pinned == true end
        if a.focused ~= b.focused then return a.focused == true end
        if a.recommendationWeight ~= b.recommendationWeight then return a.recommendationWeight > b.recommendationWeight end
        return Stable(a, b)
    end)
    local rank = {}; for i, r in ipairs(opportunities) do rank[r.id] = i end
    table.sort(candidates, function(a, b) return rank[a.id] < rank[b.id] end)
    for index = 1, math.min(3, #candidates) do view.nextUp[index] = candidates[index] end
    if #view.nextUp == 0 and #view.discoveries > 0 then
        view.emptyMessage = "No immediate task found"
        view.emptyDetail = "Check Worth Starting for ideas."
    end
    local cutoff = view.nextUp[3] and view.nextUp[3].priorityTier
    local groups = {}
    for index = 4, #candidates do
        local r = candidates[index]
        if r.priorityTier <= cutoff then
            local key = r.priorityTier .. ":" .. r.bucket
            if not groups[key] then
                groups[key] = { reason = r.recommendationReason, tier = r.priorityTier, bucket = r.bucket, id = r.id, count = 0 }
                view.overflow[#view.overflow + 1] = groups[key]
            end
            groups[key].count = groups[key].count + 1
        end
    end
    view.primary = view.nextUp[1]
    view.today, view.thisWeek, view.progress, view.optional, view.legacy = {}, {}, {}, {}, {}
    for _, bucket in ipairs({ "daily", "weekly" }) do
        for _, r in ipairs(view[bucket]) do
            local target = r.contentEra == "legacy" and view.legacy or r.importance == "optional" and view.optional or r.kind == "Progress" and view.progress
                or (r.bucket == "daily" or (r.expiryVerified and r.expiresAt and dailyReset and r.expiresAt <= dailyReset)) and view.today or view.thisWeek
            target[#target + 1] = r
        end
    end
    return view
end
